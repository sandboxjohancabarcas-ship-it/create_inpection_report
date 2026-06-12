import 'dart:io';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import '../models/door.dart';
import '../models/inspection_door_error.dart';
import '../models/error_catalog.dart';

class GaebExportService {
  final String customer;
  final String projectName;
  final String jobNumber;

  GaebExportService({
    required this.customer,
    required this.projectName,
    required this.jobNumber,
  });

  /// Generates the .x83 XML file with rich text formatting
  Future<File> exportToXml(List<Map<String, dynamic>> exportData) async {
    final now = DateTime.now();
    final dateStr = DateFormat('yyyy-MM-dd').format(now); 
    final timeStr = DateFormat('HH:mm:ss').format(now);
    
    // Sanitize job number: numbers only as requested
    final String cleanJobNo = jobNumber.replaceAll(RegExp(r'[^0-9]'), '');
    final String validJobNo = cleanJobNo.isEmpty ? "100" : cleanJobNo;

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
    buf.writeln('          <Length>2</Length>');
    buf.writeln('          <Num>Yes</Num>');
    buf.writeln('        </BoQBkdn>');
    buf.writeln('        <BoQBkdn>');
    buf.writeln('          <Type>BoQLevel</Type>');
    buf.writeln('          <LblBoQBkdn>Bereich</LblBoQBkdn>');
    buf.writeln('          <Length>2</Length>');
    buf.writeln('          <Num>Yes</Num>');
    buf.writeln('        </BoQBkdn>');
    buf.writeln('        <BoQBkdn>');
    buf.writeln('          <Type>Item</Type>');
    buf.writeln('          <Length>3</Length>');
    buf.writeln('          <Num>Yes</Num>');
    buf.writeln('        </BoQBkdn>');
    buf.writeln('        <NoUPComps>4</NoUPComps>');
    buf.writeln('        <LblUPComp1 Type="Wages">Lohn</LblUPComp1>');
    buf.writeln('        <LblUPComp2 Type="Materials">Material</LblUPComp2>');
    buf.writeln('        <LblUPComp3 Type="Plant">Gerät</LblUPComp3>');
    buf.writeln('        <LblUPComp4 Type="Miscellaneous">Sonstiges</LblUPComp4>');
    buf.writeln('        <LblTime>Stunden</LblTime>');
    buf.writeln('      </BoQInfo>');
    buf.writeln('      <BoQBody>');
    buf.writeln('        <BoQCtgy ID="cat1" RNoPart="01">');
    buf.writeln('          <LblTx><p><span>Wartungspositionen</span></p></LblTx>');
    buf.writeln('          <BoQBody>');
    buf.writeln('            <Itemlist>');

    int itemIdx = 1;
    for (var entry in exportData) {
      // Defensive check to avoid the "Null is not a subtype of Door" error
      final dynamic doorRaw = entry['door'];
      if (doorRaw == null || doorRaw is! Door) continue;
      final Door door = doorRaw;

      final List<dynamic> errorsRaw = entry['errors'] ?? [];

      final String posNo = (itemIdx * 10).toString().padLeft(3, '0');
      buf.writeln('              <Item ID="door$itemIdx" RNoPart="$posNo">');
      buf.writeln('          <Qty>1.000</Qty>');
      buf.writeln('          <QU>Stck</QU>');
      buf.writeln('          <Description>');
      buf.writeln('            <CompleteText>');
      buf.writeln('              <DetailTxt>');
      buf.writeln('                <Text>');
      buf.writeln('                  <p><span><span style="font-weight:bold;">Tür-Nr: ${door.doorNumber}</span> (${door.roomDesignation})</span></p>');
      buf.writeln('                  <p><span>Material: ${door.material} | Hersteller: ${door.manufacturer}</span></p>');
      buf.writeln('                  <p><span>Ort: Etage ${door.floor}, Raum ${door.roomNumber}</span></p>');
      
      if (errorsRaw.isNotEmpty) {
        buf.writeln('                  <p><span><span style="text-decoration:underline;">Mängelbericht:</span></span></p>');
        for (var err in errorsRaw) {
          final String code = err['code'] ?? 'ERR';
          final String desc = err['description'] ?? 'Mangel';
          final String note = err['notes'] ?? '';
          
          buf.writeln('                  <p><span><span style="color:#FF0000;">[$code] - $desc</span></span></p>');
          if (note.isNotEmpty) {
            buf.writeln('                  <p><span><span style="font-style:italic;">Hinweis: $note</span></span></p>');
          }
        }
      } else {
        buf.writeln('                  <p><span>Status: Keine Mängel festgestellt.</span></p>');
      }

      buf.writeln('                </Text>');
      buf.writeln('              </DetailTxt>');
      buf.writeln('              <OutlineText>');
      buf.writeln('                <OutlTxt><TextOutlTxt><p><span>Tür ${door.doorNumber}</span></p></TextOutlTxt></OutlTxt>');
      buf.writeln('              </OutlineText>');
      buf.writeln('            </CompleteText>');
      buf.writeln('          </Description>');
      buf.writeln('              </Item>');
      itemIdx++;
    }

    buf.writeln('            </Itemlist>');
    buf.writeln('          </BoQBody>');
    buf.writeln('        </BoQCtgy>');
    buf.writeln('      </BoQBody>');
    buf.writeln('    </BoQ>');
    buf.writeln('  </Award>');
    buf.writeln('</GAEB>');

    return _saveFile(buf.toString(), '$validJobNo.x83');
  }

  /// Generates the .d83 (GAEB 90) file with truncated lines
  Future<File> exportToD83(List<Map<String, dynamic>> exportData) async {
    StringBuffer buf = StringBuffer();
    int lineCount = 1;

    buf.writeln(_fmtD83('00', jobNumber, lineCount++));
    buf.writeln(_fmtD83('01', '$customer - $projectName', lineCount++));

    for (var entry in exportData) {
      final dynamic doorRaw = entry['door'];
      if (doorRaw == null || doorRaw is! Door) continue;
      final Door door = doorRaw;
      
      final List<dynamic> errorsRaw = entry['errors'] ?? [];

      buf.writeln(_fmtD83('21', 'Tür ${door.doorNumber}', lineCount++));
      buf.writeln(_fmtD83('25', 'Tür: ${door.doorNumber} / ${door.roomDesignation}', lineCount++));

      List<String> textLines = [
        'Material: ${door.material}',
        'Hersteller: ${door.manufacturer}',
        'Ort: Etage ${door.floor} | Raum ${door.roomNumber}',
        '---------------------------------------',
      ];

      if (errorsRaw.isNotEmpty) {
        textLines.add('MAENGELBERICHT:');
        for (var err in errorsRaw) {
          final String code = err['code'] ?? 'ERR';
          final String desc = err['description'] ?? '';
          final String note = err['notes'] ?? '';
          textLines.add('[$code] $desc');
          if (note.isNotEmpty) textLines.add(' -> Hinweis: $note');
        }
      } else {
        textLines.add('Status: Mangelfrei');
      }

      for (var s in textLines) {
        buf.writeln(_fmtD83('26', _truncate(s, 70), lineCount++));
      }
    }

    buf.writeln(_fmtD83('99', 'END', lineCount++));
    return _saveFile(buf.toString(), '$jobNumber.d83');
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
    final path = '${directory.path}/WartungsTool/Exports/$fileName';
    final file = File(path);
    await file.create(recursive: true);
    return file.writeAsString(content);
  }
}