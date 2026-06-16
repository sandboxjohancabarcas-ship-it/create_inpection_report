import 'dart:io';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import '../models/door.dart';

class GaebExportService {
  final String customer;
  final String projectName;
  final String jobNumber;

  GaebExportService({
    required this.customer,
    required this.projectName,
    required this.jobNumber,
  });

  /// Generates the .x83 XML file with hierarchical mapping (Door -> Errors)
  /// High-level method to export and save XML
  Future<File> exportToXml(List<Map<String, dynamic>> exportData) async {
    final now = DateTime.now();
    final String content = generateXmlString(exportData);
    final String sanitizedCustomer = _sanitizeXmlId(customer);
    final String dateTimeString = DateFormat('yyyyMMdd_HHmmss').format(now);
    final String fileName = "${sanitizedCustomer}_Wartung_$dateTimeString.x83";
    return _saveFile(content, fileName);
  }

  /// Generates the .x83 XML string content (Pure logic, easy to unit test)
  String generateXmlString(List<Map<String, dynamic>> exportData) {
    final now = DateTime.now();
    final dateStr = DateFormat('yyyy-MM-dd').format(now);
    final timeStr = DateFormat('HH:mm:ss').format(now);

    // Sanitize job number: numbers only
    final String cleanJobNo = jobNumber.replaceAll(RegExp(r'[^0-9]'), '');
    final String validJobNo = cleanJobNo.isEmpty ? "100" : cleanJobNo;

    final String sanitizedProjectId = _sanitizeXmlId('$customer-$projectName');

    StringBuffer buf = StringBuffer();
    buf.writeln('<?xml version="1.0" encoding="UTF-8"?>');
    buf.writeln('<GAEB xmlns="http://www.gaeb.de/GAEB_DA_XML/DA83/3.2">');
    buf.writeln('  <GAEBInfo>');
    buf.writeln('    <Version>3.2</Version>');
    buf.writeln('    <VersDate>2013-10</VersDate>');
    buf.writeln('    <Date>$dateStr</Date>');
    buf.writeln('    <Time>$timeStr</Time>');
    buf.writeln('    <ProgSystem>/ GXML Toolbox V3.3 R20200224</ProgSystem>');
    buf.writeln('    <ProgName>WartungsTool</ProgName>');
    buf.writeln('  </GAEBInfo>');
    buf.writeln('  <PrjInfo>');
    buf.writeln('    <NamePrj>$validJobNo</NamePrj>');
    buf.writeln('    <LblPrj>$customer - $projectName</LblPrj>');
    buf.writeln('    <Cur>EUR</Cur>');
    buf.writeln('    <CurLbl>Euro</CurLbl>');
    buf.writeln('  </PrjInfo>');
    buf.writeln('  <Award>');
    buf.writeln('    <DP>83</DP>');
    buf.writeln('    <BoQ ID="id$validJobNo">');
    buf.writeln('      <BoQInfo>');
    buf.writeln('        <Name>$validJobNo</Name>');
    buf.writeln('        <LblBoQ>Türwartung Export</LblBoQ>');
    buf.writeln('        <OutlCompl>AllTxt</OutlCompl>');
    buf.writeln('        <BoQBkdn>');
    buf.writeln('          <Type>BoQLevel</Type>');
    buf.writeln('          <LblBoQBkdn>Titel</LblBoQBkdn>');
    buf.writeln('          <Length>4</Length>');
    buf.writeln('          <Num>No</Num>');
    buf.writeln('        </BoQBkdn>');
    buf.writeln('        <BoQBkdn>');
    buf.writeln('          <Type>BoQLevel</Type>');
    buf.writeln('          <LblBoQBkdn>Tür</LblBoQBkdn>');
        buf.writeln('          <Length>10</Length>');
    buf.writeln('          <Num>No</Num>');
    buf.writeln('        </BoQBkdn>');
    buf.writeln('        <BoQBkdn>');
    buf.writeln('          <Type>Item</Type>');
    buf.writeln('          <Length>10</Length>');
    buf.writeln('          <Num>No</Num>');
    buf.writeln('        </BoQBkdn>');
    buf.writeln('        <NoUPComps>4</NoUPComps>');
    buf.writeln('        <LblUPComp1 Type="Wages">Lohn</LblUPComp1>');
    buf.writeln('        <LblUPComp2 Type="Materials">Material</LblUPComp2>');
    buf.writeln('        <LblUPComp3 Type="Plant">Gerät</LblUPComp3>');
    buf.writeln('        <LblUPComp4 Type="Miscellaneous">Sonstiges</LblUPComp4>');
    buf.writeln('        <LblTime>Stunden</LblTime>');
    buf.writeln('      </BoQInfo>');
    buf.writeln('      <BoQBody>');

    int doorIdx = 1;
    for (var entry in exportData) {
      final dynamic doorRaw = entry['door'];
      if (doorRaw == null || doorRaw is! Door) continue;
      final Door door = doorRaw;

      final List<dynamic> errorsRaw = entry['errors'] ?? [];

      // Requirement: Omit doors with no errors
      if (errorsRaw.isEmpty) continue;

      // Level 2: Door as Category
      final sanitizedId = _sanitizeXmlId(door.doorAlias ?? '');
      final sanitizedRNo = _sanitizeRNoPart(door.doorNumber ?? '');
      buf.writeln('        <BoQCtgy ID="$sanitizedId" RNoPart="$sanitizedRNo">');
      buf.writeln('          <LblTx>');
      buf.writeln('            <p><span style="font-weight:bold;">Tür: ${door.doorNumber ?? ''}</span></p>');
      buf.writeln('          </LblTx>');
      buf.writeln('          <BoQBody>');
      buf.writeln('            <Itemlist>');

      // Level 3: Individual Errors as Items
      for (int i = 0; i < errorsRaw.length; i++) {
        final err = errorsRaw[i];
        final String code = err['code']?.toString() ?? '';
        final String sanitizedCode = _sanitizeRNoPart(code);
        final String desc = err['description']?.toString() ?? '';
        final String qty = err['quantity']?.toString() ?? '1.000';

        buf.writeln('              <Item ID="${sanitizedProjectId}_$sanitizedCode" RNoPart="$sanitizedCode">');
        buf.writeln('                <Qty>$qty</Qty>');
        buf.writeln('                <QU>Stck</QU>');
        buf.writeln('                <Description>');
        buf.writeln('                  <CompleteText>');
        buf.writeln('                    <DetailTxt>');
        buf.writeln('                      <Text>');
        buf.writeln('                        <p><span style="font-weight:bold;">$desc</span></p>');
        buf.writeln('                      </Text>');
        buf.writeln('                    </DetailTxt>');
        buf.writeln('                    <OutlineText>');
        buf.writeln('                      <OutlTxt><TextOutlTxt><p><span>$desc</span></p></TextOutlTxt></OutlTxt>');
        buf.writeln('                    </OutlineText>');
        buf.writeln('                  </CompleteText>');
        buf.writeln('                </Description>');
        buf.writeln('              </Item>');
      }

      buf.writeln('            </Itemlist>');
      buf.writeln('          </BoQBody>');
      buf.writeln('        </BoQCtgy>');
      doorIdx++;
    }

    buf.writeln('      </BoQBody>');
    buf.writeln('    </BoQ>');
    buf.writeln('  </Award>');
    buf.writeln('</GAEB>');
    return buf.toString();
  }

  /// High-level method to export and save D83 (GAEB 90)
  Future<File> exportToD83(List<Map<String, dynamic>> exportData) async {
    final String content = generateD83String(exportData);
    final String cleanJobNo = jobNumber.replaceAll(RegExp(r'[^0-9]'), '');
    final String fileName = cleanJobNo.isEmpty ? "100.d83" : "$cleanJobNo.d83";
    return _saveFile(content, fileName);
  }

  String generateD83String(List<Map<String, dynamic>> exportData) {
    StringBuffer buf = StringBuffer();
    int lineCount = 1;

    final String cleanJobNo = jobNumber.replaceAll(RegExp(r'[^0-9]'), '');
    final String validJobNo = cleanJobNo.isEmpty ? "100" : cleanJobNo;

    buf.writeln(_fmtD83('00', validJobNo, lineCount++));
    buf.writeln(_fmtD83('01', '$customer - $projectName', lineCount++));

    for (var entry in exportData) {
      final dynamic doorRaw = entry['door'];
      if (doorRaw == null || doorRaw is! Door) continue;
      final Door door = doorRaw;
      
      final List<dynamic> errorsRaw = entry['errors'] ?? [];
      
      // Omit mangelfrei doors
      if (errorsRaw.isEmpty) continue;

      buf.writeln(_fmtD83('21', door.doorNumber, lineCount++));
      buf.writeln(_fmtD83('25', door.doorNumber, lineCount++));

      List<String> textLines = [
        '---------------------------------------',
      ];

      for (var err in errorsRaw) {
        final String desc = err['description']?.toString() ?? '';
        if (desc.isNotEmpty) textLines.add(desc);
      }

      for (var s in textLines) {
        buf.writeln(_fmtD83('26', _truncate(s, 70), lineCount++));
      }
    }

    buf.writeln(_fmtD83('99', 'END', lineCount++));
    return buf.toString();
  }

  String _fmtD83(String type, String content, int count) {
    String countStr = count.toString().padLeft(6, '0');
    String paddedContent = content.padRight(72, ' ');
    return '$type${_truncate(paddedContent, 72)}$countStr';
  }

  String _truncate(String text, int max) {
    if (text.length <= max) return text;
    return '${text.substring(0, max - 3)}...';
  }

  Future<File> _saveFile(String content, String fileName) async {
    final directory = await getApplicationDocumentsDirectory();
    final exportDirPath = p.join(directory.path, 'WartungsTool', 'Exports');
    final file = File(p.join(exportDirPath, fileName));
    await file.create(recursive: true);
    return file.writeAsString(content);
  }

  // Helper to sanitize strings for XML ID attributes (must be NCName compliant)
  String _sanitizeXmlId(String input) {
    // Replace invalid characters with underscore, ensure it starts with a letter or underscore
    return input.replaceAll(RegExp(r'[^a-zA-Z0-9_\-.]'), '_');
  }

  // Helper to sanitize strings for RNoPart (typically alphanumeric or numeric only)
  String _sanitizeRNoPart(String input) {
    return input.replaceAll(RegExp(r'[^0-9]'), ''); // Only numbers
  }
}
