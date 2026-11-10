import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wartungstool/services/app_logger.dart';
import 'package:wartungstool/widgets/app_log_dialog.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AppLogger tests', () {
    test('LogEntry formats correctly', () {
      final now = DateTime(2026, 11, 10, 10, 15, 30, 123);
      final entry = LogEntry(
        timestamp: now,
        level: LogLevel.info,
        tag: 'TestTag',
        message: 'Hello World',
      );

      final formatted = entry.format();
      expect(formatted, contains('[INFO]'));
      expect(formatted, contains('[TestTag]'));
      expect(formatted, contains('Hello World'));
      expect(formatted, contains('2026-11-10 10:15:30.123'));
    });

    test('LogEntry with error details formats stack/details', () {
      final entry = LogEntry(
        timestamp: DateTime.now(),
        level: LogLevel.error,
        tag: 'Network',
        message: 'Request failed',
        errorDetails: 'SocketException: connection refused',
      );

      final formatted = entry.format();
      expect(formatted, contains('[ERROR]'));
      expect(formatted, contains('SocketException: connection refused'));
    });

    test('AppLogger records in-memory entries and broadcasts stream', () async {
      final logger = AppLogger.instance;
      final expectedMessages = <String>[];

      final subscription = logger.onLogEntry.listen((entry) {
        expectedMessages.add(entry.message);
      });

      AppLogger.info('UnitTest', 'Test message 1');
      AppLogger.warn('UnitTest', 'Test warning 2');
      AppLogger.error('UnitTest', 'Test error 3');

      // Allow microtask / event loop tick
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(expectedMessages, contains('Test message 1'));
      expect(expectedMessages, contains('Test warning 2'));
      expect(expectedMessages, contains('Test error 3'));

      expect(logger.recentEntries.any((e) => e.message == 'Test message 1'), isTrue);
      expect(logger.recentEntries.any((e) => e.level == LogLevel.warn), isTrue);
      expect(logger.recentEntries.any((e) => e.level == LogLevel.error), isTrue);

      await subscription.cancel();
    });

    test('AppLogger clearLogs removes in-memory items', () async {
      final logger = AppLogger.instance;
      AppLogger.info('UnitTest', 'Should be cleared');

      await logger.clearLogs();
      // After clear, only the "log cleared" notice is in memory
      expect(logger.recentEntries.length, 1);
      expect(logger.recentEntries.first.message, contains('manuell geleert'));
    });
  });

  group('AppLogDialog widget test', () {
    testWidgets('Renders AppLogDialog and displays log entries', (tester) async {
      AppLogger.info('UI', 'App initialized');
      AppLogger.warn('UI', 'Low battery detected');

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AppLogDialog(),
          ),
        ),
      );

      // Allow async _loadLogs to complete
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Anwendungsprotokoll (Log-Datei)'), findsOneWidget);
      expect(find.text('In Downloads ablegen'), findsOneWidget);
      expect(find.text('Speichern unter...'), findsOneWidget);
      expect(find.text('Protokoll leeren'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget); // Search bar
    });
  });
}

