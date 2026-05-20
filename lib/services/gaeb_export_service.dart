import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:intl/intl.dart';

class GaebExportService {
  /// Exports multiple inspections to GAEB 90 (D83) format.
  static Future<File?> exportToGaeb90(List<Map<String, dynamic>> jobs, String exportName) async {
    final directory = await getApplicationDocumentsDirectory();
    final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
    final file = File('${directory.path}/${exportName}_$timestamp.d83');
    
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
      sb.write(formatLine('01', 'PROJEKT: ${meta['clientName']} - ${meta['auftragsnummer']}'));

      for (var door in job['doors']) {
        // OZ in GAEB 90 must be digits only. Removing non-numeric characters for strict compatibility.
        String oz = (door['doorNumber']?.toString() ?? '0').replaceAll(RegExp(r'[^0-9]'), '').padLeft(9, '0');
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

  /// Escapes special XML characters to prevent syntax errors.
  static String _escapeXml(String input) {
    return input
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&apos;');
  }

  /// Exports multiple inspections to GAEB DA XML (X83) format.
  static Future<File?> exportToGaebXml(List<Map<String, dynamic>> jobs, String exportName) async {
    final directory = await getApplicationDocumentsDirectory();
    final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
    final file = File('${directory.path}/${exportName}_$timestamp.x83');
    final now = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final time = DateFormat('HH:mm:ss').format(DateTime.now());

    StringBuffer xml = StringBuffer();
    xml.writeln('<?xml version="1.0" encoding="UTF-8"?>');
    xml.writeln('<GAEB xmlns="http://www.gaeb.de/GAEB_DA_XML/DA83/3.2">');
    xml.writeln('  <GAEBInfo>');
    xml.writeln('    <Version>3.2</Version>');
    xml.writeln('    <VersDate>2013-10</VersDate>');
    xml.writeln('    <Date>$now</Date>');
    xml.writeln('    <Time>$time</Time>');
    xml.writeln('    <ProgSystem>Mobile Inspector Service</ProgSystem>');
    xml.writeln('  </GAEBInfo>');
    xml.writeln('  <PrjInfo>');
    xml.writeln('    <NamePrj>${_escapeXml(exportName)}</NamePrj>');
    xml.writeln('    <LblPrj>Wartungs-Export</LblPrj>');
    xml.writeln('    <Cur>EUR</Cur>');
    xml.writeln('    <CurLbl>Euro</CurLbl>');
    xml.writeln('  </PrjInfo>');
    xml.writeln('  <Award>');
    xml.writeln('    <DP>83</DP>');
    xml.writeln('    <AwardInfo>');
    xml.writeln('      <Cat>SelectCall</Cat>');
    xml.writeln('      <Cur>EUR</Cur>');
    xml.writeln('      <CurLbl>Euro</CurLbl>');
    xml.writeln('    </AwardInfo>');
    xml.writeln('    <BoQ ID="id1">');
    xml.writeln('      <BoQInfo>');
    xml.writeln('        <Name>Wartung</Name>');
    xml.writeln('        <LblBoQ>${_escapeXml(exportName)}</LblBoQ>');
    xml.writeln('        <OutlCompl>AllTxt</OutlCompl>');
    xml.writeln('        <BoQBkdn>');
    xml.writeln('          <Type>BoQLevel</Type>');
    xml.writeln('          <LblBoQBkdn>Titel</LblBoQBkdn>');
    xml.writeln('          <Length>2</Length>');
    xml.writeln('          <Num>Yes</Num>');
    xml.writeln('        </BoQBkdn>');
    xml.writeln('      </BoQInfo>');
    xml.writeln('      <BoQBody>');

    for (var job in jobs) {
      final meta = job['metadata'];
      final jobId = meta['inspectionId'];

      // Using BoQCtgy for grouping as seen in the reference template
      xml.writeln('        <BoQCtgy ID="job_$jobId" RNoPart="${jobId.toString().padLeft(2, '0')}">');
      xml.writeln('          <LblTx><p><span>${_escapeXml(meta['clientName'])} - ${_escapeXml(meta['auftragsnummer'])}</span></p></LblTx>');
      xml.writeln('          <BoQBody>');
      xml.writeln('            <Itemlist>');
      
      int itemCounter = 1;
      for (var door in job['doors']) {
        String status = door['doorFunctionOK'] == true ? 'OK' : 'Defekt';
        String rNo = (door['doorNumber']?.toString() ?? '0').replaceAll(RegExp(r'[^0-9]'), '');
        if (rNo.isEmpty) rNo = itemCounter.toString();
        
        // Every Item requires a unique ID attribute for XML schema validation
        xml.writeln('              <Item ID="item_${jobId}_$itemCounter" RNoPart="$rNo">');
        xml.writeln('                <Qty>1.000</Qty>');
        xml.writeln('                <QU>Stck</QU>');
        xml.writeln('                <Description>');
        xml.writeln('                  <CompleteText>');
        xml.writeln('                    <DetailTxt>');
        
        // Constructing an XHTML compliant description block as required by GAEB 3.2
        xml.writeln('                      <Text>');
        xml.writeln('                        <p><span>Etage: ${_escapeXml(door['floor'] ?? '')} / Raum: ${_escapeXml(door['roomNumber'] ?? '')}</span><br/>');
        xml.writeln('                        <span>Material: ${_escapeXml(door['material'] ?? '')}</span><br/>');
        xml.writeln('                        <span>Status: $status</span></p>');
        
        final errors = door['errors'] as List;
        if (errors.isNotEmpty) {
          xml.writeln('                        <p><span>Mängel: ${_escapeXml(errors.join(', '))}</span></p>');
        }
        xml.writeln('                      </Text>');
        xml.writeln('                    </DetailTxt>');
        xml.writeln('                  </CompleteText>');
        xml.writeln('                </Description>');
        xml.writeln('              </Item>');
        itemCounter++;
      }
      xml.writeln('            </Itemlist>');
      xml.writeln('          </BoQBody>');
      xml.writeln('        </BoQCtgy>');
    }

    xml.writeln('      </BoQBody>');
    xml.writeln('    </BoQ>');
    xml.writeln('  </Award>');
    xml.writeln('</GAEB>');

    return await file.writeAsString(xml.toString());
  }
}
