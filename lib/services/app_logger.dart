import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../utils/file_export_helper.dart';

enum LogLevel { info, warn, error, debug }

class LogEntry {
  final DateTime timestamp;
  final LogLevel level;
  final String tag;
  final String message;
  final String? errorDetails;

  const LogEntry({
    required this.timestamp,
    required this.level,
    required this.tag,
    required this.message,
    this.errorDetails,
  });

  String get levelString {
    switch (level) {
      case LogLevel.info:
        return 'INFO';
      case LogLevel.warn:
        return 'WARN';
      case LogLevel.error:
        return 'ERROR';
      case LogLevel.debug:
        return 'DEBUG';
    }
  }

  String format() {
    final timeStr = DateFormat('yyyy-MM-dd HH:mm:ss.SSS').format(timestamp);
    final base = '$timeStr [$levelString] [$tag] $message';
    if (errorDetails != null && errorDetails!.isNotEmpty) {
      return '$base\n  $errorDetails';
    }
    return base;
  }
}

/// Central application logger providing persistent, rolling file logging
/// on both Android and Windows with export/download capabilities.
class AppLogger {
  AppLogger._internal();
  static final AppLogger instance = AppLogger._internal();

  static const String logFileName = 'app_usage.log';
  static const int maxFileSizeBytes = 5 * 1024 * 1024; // 5 MB rotation limit
  static const int maxInMemoryEntries = 500;

  final List<LogEntry> _recentEntries = [];
  File? _activeLogFile;
  bool _isInitializing = false;
  Completer<void>? _initCompleter;
  Future<void> _writeQueue = Future.value();
  final StreamController<LogEntry> _entryStreamController =
      StreamController<LogEntry>.broadcast();

  Stream<LogEntry> get onLogEntry => _entryStreamController.stream;
  List<LogEntry> get recentEntries => List.unmodifiable(_recentEntries);

  /// Initializes the file logger for the current platform (Android / Windows / etc.)
  Future<void> init() async {
    if (_activeLogFile != null) return;
    if (_isInitializing) return _initCompleter?.future;

    _isInitializing = true;
    _initCompleter = Completer<void>();

    try {
      Directory? baseDir;

      // On Android: prioritize external app storage which is directly accessible
      // via USB cable on a PC and in standard file manager apps.
      if (!kIsWeb && Platform.isAndroid) {
        try {
          baseDir = await getExternalStorageDirectory();
        } catch (_) {}
      }

      // Fallback for Windows, tests or if external storage is unavailable
      if (baseDir == null) {
        try {
          baseDir = await getApplicationSupportDirectory();
        } catch (_) {
          try {
            baseDir = await getApplicationDocumentsDirectory();
          } catch (_) {
            baseDir = Directory.systemTemp;
          }
        }
      }

      final logsDir = Directory(p.join(baseDir.path, 'logs'));
      if (!logsDir.existsSync()) {
        logsDir.createSync(recursive: true);
      }

      _activeLogFile = File(p.join(logsDir.path, logFileName));
      if (!_activeLogFile!.existsSync()) {
        _activeLogFile!.createSync(recursive: true);

        // If an old log existed in internal application support directory, migrate it
        try {
          final oldSupport = await getApplicationSupportDirectory();
          final oldLog = File(p.join(oldSupport.path, 'logs', logFileName));
          if (oldLog.existsSync() && oldLog.path != _activeLogFile!.path) {
            final oldContent = await oldLog.readAsString();
            if (oldContent.isNotEmpty) {
              await _activeLogFile!.writeAsString(oldContent);
            }
          }
        } catch (_) {}
      }

      _initCompleter?.complete();
    } catch (e) {
      debugPrint('[AppLogger] Initialization notice: $e');
      _initCompleter?.complete();
    } finally {
      _isInitializing = false;
    }
  }

  /// Logs an INFO level message.
  static void info(String tag, String message) {
    instance.log(LogLevel.info, tag, message);
  }

  /// Logs a WARN level message.
  static void warn(String tag, String message, [Object? error, StackTrace? stack]) {
    String? details;
    if (error != null) {
      details = 'Fehler: $error';
      if (stack != null) details += '\n$stack';
    }
    instance.log(LogLevel.warn, tag, message, details);
  }

  /// Logs an ERROR level message.
  static void error(String tag, String message, [Object? error, StackTrace? stack]) {
    String? details;
    if (error != null) {
      details = 'Fehler: $error';
      if (stack != null) details += '\n$stack';
    }
    instance.log(LogLevel.error, tag, message, details);
  }

  /// Logs a DEBUG level message.
  static void debug(String tag, String message) {
    instance.log(LogLevel.debug, tag, message);
  }

  /// Internal log dispatcher.
  void log(LogLevel level, String tag, String message, [String? errorDetails]) {
    final entry = LogEntry(
      timestamp: DateTime.now(),
      level: level,
      tag: tag,
      message: message,
      errorDetails: errorDetails,
    );

    // Keep in-memory ring buffer
    _recentEntries.add(entry);
    if (_recentEntries.length > maxInMemoryEntries) {
      _recentEntries.removeAt(0);
    }
    _entryStreamController.add(entry);

    // Terminal / console output in debug runs
    if (kDebugMode) {
      debugPrint(entry.format());
    }

    // Persist to file through sequential queue to prevent concurrent race conditions
    _writeQueue = _writeQueue.then((_) => _appendToFile(entry)).catchError((e) {
      debugPrint('[AppLogger] File write error: $e');
    });
  }

  Future<void> _appendToFile(LogEntry entry) async {
    try {
      if (_activeLogFile == null) {
        await init();
      }
      if (_activeLogFile == null) return;

      // Check size rotation
      if (await _activeLogFile!.exists()) {
        final length = await _activeLogFile!.length();
        if (length > maxFileSizeBytes) {
          final backup = File('${_activeLogFile!.path}.1');
          if (await backup.exists()) await backup.delete();
          await _activeLogFile!.rename(backup.path);
          _activeLogFile = File(_activeLogFile!.path);
          await _activeLogFile!.create();
        }
      }

      final line = '${entry.format()}\n';
      await _activeLogFile!.writeAsString(line, mode: FileMode.append, flush: true);
    } catch (e) {
      debugPrint('[AppLogger] File write notice: $e');
    }
  }

  /// Reads the entire active log file text.
  Future<String> readAllLogs() async {
    // Wait for any pending write operations to flush
    await _writeQueue;
    try {
      if (_activeLogFile == null) await init();
      if (_activeLogFile != null && await _activeLogFile!.exists()) {
        return await _activeLogFile!.readAsString();
      }
    } catch (e) {
      debugPrint('[AppLogger] Error reading log file: $e');
    }
    // Fallback to recent in-memory entries
    return _recentEntries.map((e) => e.format()).join('\n');
  }

  /// Returns the absolute path of the current log file.
  Future<String?> getLogFilePath() async {
    if (_activeLogFile == null) await init();
    return _activeLogFile?.path;
  }

  /// Returns the current log file size in bytes.
  Future<int> getLogFileSize() async {
    await _writeQueue;
    try {
      if (_activeLogFile == null) await init();
      if (_activeLogFile != null && await _activeLogFile!.exists()) {
        return await _activeLogFile!.length();
      }
    } catch (_) {}
    return 0;
  }

  /// Clears the active log file and in-memory buffer.
  Future<void> clearLogs() async {
    await _writeQueue;
    _recentEntries.clear();
    try {
      if (_activeLogFile == null) await init();
      if (_activeLogFile != null && await _activeLogFile!.exists()) {
        await _activeLogFile!.writeAsString('', mode: FileMode.write, flush: true);
      }
      info('AppLogger', 'Anwendungsprotokoll wurde manuell geleert.');
    } catch (e) {
      debugPrint('[AppLogger] Error clearing logs: $e');
    }
  }

  /// Allows the user to download / export the log file on Android or Windows.
  Future<String?> exportLogsSafely() async {
    final nowStr = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
    final defaultFileName = 'WartungsTool_Log_$nowStr.txt';
    final content = await readAllLogs();
    final bytes = Uint8List.fromList(utf8.encode(content));

    return await FileExportHelper.saveFileSafely(
      defaultFileName: defaultFileName,
      dialogTitle: 'Anwendungsprotokoll (Log) herunterladen',
      fileBytes: bytes,
      allowedExtensions: ['txt', 'log'],
    );
  }

  /// 1-Click direct export: On Android, attempts to copy the log file directly
  /// into the public 'Download/WartungsTool' or 'Download' folder.
  /// If direct filesystem access is restricted by scoped storage, falls back to the system save dialog.
  Future<String?> exportToDownloadsOrPrompt() async {
    final nowStr = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
    final defaultFileName = 'WartungsTool_Log_$nowStr.txt';
    final content = await readAllLogs();
    final bytes = Uint8List.fromList(utf8.encode(content));

    if (!kIsWeb && Platform.isAndroid) {
      for (final downloadPath in [
        '/storage/emulated/0/Download/WartungsTool',
        '/storage/emulated/0/Download',
      ]) {
        try {
          final dir = Directory(downloadPath);
          if (!dir.existsSync()) {
            dir.createSync(recursive: true);
          }
          final target = File(p.join(dir.path, defaultFileName));
          await target.writeAsBytes(bytes, flush: true);

          // Keep a convenience file always pointing to latest log
          try {
            final latest = File(p.join(dir.path, 'WartungsTool_Log_Aktuell.txt'));
            await latest.writeAsBytes(bytes, flush: true);
          } catch (_) {}

          return target.path;
        } catch (e) {
          debugPrint('[AppLogger] Direct download note ($downloadPath): $e');
        }
      }
    }

    return await exportLogsSafely();
  }
}
