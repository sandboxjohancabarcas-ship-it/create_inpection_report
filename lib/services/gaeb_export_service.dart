import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:intl/intl.dart';

class GaebExportService {
  /// Exports multiple inspections to GAEB 90 (D83) format.
  static Future<File?> exportToGaeb90(List<Map<String, dynamic>> jobs, String exportName) async {
    final directory = await getApplicationDocumentsDirectory();
    final file = File('${directory.path}/${exportName}_export.d83');
    
    StringBuffer sb = StringBuffer();
    int lineCounter = 1;

    String formatLine(String za, String content) {
      String line = za + content.padRight(72).substring(0, 72) + lineCounter.toString().padLeft(6, '0');
      lineCounter++;
      return '$line\r\n';
    }                                                                                                          

    // ZA 00: Eröffnungssatz (Page 15)        
    sb.write(formatLine('00', ' 83L 1122PPPPI90'));

    for (var job in jobs) {
      final meta = job['metadata'];
      sb.write(formatLine('01', 'Kunde: ${meta['clientName']} | Job: ${meta['auftragsnummer']}'));

      for (var door in job['doors']) {
        String oz = (door['doorNumber']?.toString() ?? '0').padLeft(9, '0');
        sb.write(formatLine('21', '$oz NNN 00000001000Stck'));
        sb.write(formatLine('25', door['material'] ?? 'Material?'));
        sb.write(formatLine('26', 'Etage: ${door['floor']} | Raum: ${door['roomNumber']}'));
        sb.write(formatLine('26', door['doorFunctionOK'] == true ? 'Status: OK' : 'Status: Defekt'));
        for (var error in (door['errors'] as List)) {
          sb.write(formatLine('26', '- $error'));
        }
      }
    }

    // ZA 99: Abschlusssatz
    sb.write(formatLine('99', ''));

    return await file.writeAsString(sb.toString());
  }

  /// Exports multiple inspections to GAEB DA XML (X83) format.
  static Future<File?> exportToGaebXml(List<Map<String, dynamic>> jobs, String exportName) async {
    final directory = await getApplicationDocumentsDirectory();
    final file = File('${directory.path}/${exportName}_export.x83');
    final now = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final time = DateFormat('HH:mm:ss').format(DateTime.now());

    StringBuffer xml = StringBuffer();
    xml.writeln('<?xml version="1.0" encoding="UTF-8"?>');
    xml.writeln('<GAEB xmlns="http://www.gaeb.de/GAEB_DA_XML/200407">');
    xml.writeln('  <GAEBInfo>');
    xml.writeln('    <Version>3.2</Version>');
    xml.writeln('    <Date>$now</Date>');
    xml.writeln('    <Time>$time</Time>');
    xml.writeln('  </GAEBInfo>');
    xml.writeln('  <Award>');
    xml.writeln('    <DP>83</DP>');
    xml.writeln('    <BoQ ID="id1">');
    xml.writeln('      <BoQBody>');

    for (var job in jobs) {
      final meta = job['metadata'];
      xml.writeln('        <Section ID="job_${meta['inspectionId']}">');
      xml.writeln('          <LblText>${meta['clientName']} - ${meta['auftragsnummer']}</LblText>');
      xml.writeln('          <Itemlist>');
      
      for (var door in job['doors']) {
        String status = door['doorFunctionOK'] == true ? 'OK' : 'Defekt';
        xml.writeln('            <Item RNoPart="${door['doorNumber']}">');
        xml.writeln('              <Qty>1.000</Qty>');
        xml.writeln('              <QU>Stck</QU>');
        xml.writeln('              <Description>');
        xml.writeln('                <CompleteText><DetailTxt><Text>');
        xml.writeln('                  <span>Etage: ${door['floor']} / Raum: ${door['roomNumber']}</span><br/>');
        xml.writeln('                  <span>Material: ${door['material']}</span><br/>');
        xml.writeln('                  <span>Status: $status</span><br/>');
        if ((door['errors'] as List).isNotEmpty) {
          xml.writeln('                  <span>Mängel: ${(door['errors'] as List).join(', ')}</span>');
        }
        xml.writeln('                </Text></DetailTxt></CompleteText>');
        xml.writeln('              </Description>');
        xml.writeln('            </Item>');
      }
      xml.writeln('          </Itemlist>');
      xml.writeln('        </Section>');
    }

    xml.writeln('      </BoQBody>');
    xml.writeln('    </BoQ>');
    xml.writeln('  </Award>');
    xml.writeln('</GAEB>');

    return await file.writeAsString(xml.toString());
  }
}
