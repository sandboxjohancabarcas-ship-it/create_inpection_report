import 'dart:convert';
import 'dart:io';

Future<void> main(List<String> rawArgs) async {
  // Credentials (defaults configured for WartungsTool)
  final apiKey = Platform.environment['CRAFTNOTE_API_KEY'] ?? '64045d24-397a-407b-b4ae-2ceef59018dd';
  final clientId = Platform.environment['CRAFTNOTE_CLIENT_ID'] ?? 'd04f732b-6c89-4804-97d8-63a0ea7c1199';
  final baseUrl = (Platform.environment['CRAFTNOTE_BASE_URL'] ?? 'https://europe-west1-craftnote-live.cloudfunctions.net/api/v1')
      .replaceAll(RegExp(r'/+$'), '');

  stdout.writeln('========================================================================================================');
  stdout.writeln('  CRAFTNOTE - PROJEKTE & PARAMETER-ANALYSE');
  stdout.writeln('========================================================================================================');
  stdout.writeln('API Base URL:  $baseUrl');
  stdout.writeln('Client-ID:     $clientId');
  stdout.writeln('API-Key:       ${apiKey.substring(0, 4)}...${apiKey.substring(apiKey.length - 4)}');
  stdout.writeln('--------------------------------------------------------------------------------------------------------\n');

  final cacheFile = File('craftnote_projects_cache.json');
  final bool forceRefresh = rawArgs.contains('--refresh') || !cacheFile.existsSync();
  final bool showJson = rawArgs.contains('--json');
  final bool showFirstOnly = rawArgs.contains('--first');
  final bool forceDetails = rawArgs.contains('--details') || rawArgs.contains('-d') || rawArgs.contains('--all');

  int? limitDetailCount;
  for (final arg in rawArgs) {
    if (arg.startsWith('--limit=')) {
      limitDetailCount = int.tryParse(arg.substring('--limit='.length));
    }
  }

  final cleanArgs = rawArgs.where((a) =>
      a != '--refresh' &&
      a != '--details' &&
      a != '-d' &&
      a != '--all' &&
      a != '--json' &&
      a != '--first' &&
      !a.startsWith('--limit=')).toList();

  final allProjects = <Map<String, dynamic>>[];

  if (!forceRefresh && cacheFile.existsSync()) {
    stdout.writeln('Lade Projekte aus lokalem Cache (Verwende --refresh für Live-Aktualisierung)...');
    try {
      final cachedJson = jsonDecode(await cacheFile.readAsString());
      if (cachedJson is List) {
        for (final item in cachedJson) {
          if (item is Map<String, dynamic>) allProjects.add(item);
        }
      }
      stdout.writeln('Erfolgreich ${allProjects.length} Projekte aus Cache geladen.\n');
    } catch (e) {
      stdout.writeln('Cache fehlerhaft, lade live aus Craftnote...');
    }
  }

  if (allProjects.isEmpty) {
    final client = HttpClient();
    int offset = 0;
    const limit = 100;
    int page = 1;

    stdout.write('Lade Projekte live aus Craftnote');

    try {
      while (true) {
        stdout.write('.');
        final uri = Uri.parse('$baseUrl/projects?limit=$limit&offset=$offset');
        final request = await client.getUrl(uri);
        request.headers.set('X-CN-API-KEY', apiKey);
        request.headers.set('X-CN-CLIENT-ID', clientId);
        request.headers.set('Accept', 'application/json');

        final response = await request.close();
        final body = await response.transform(utf8.decoder).join();

        if (response.statusCode != 200) {
          stdout.writeln('\n❌ Fehler beim Abrufen (Seite $page, Status ${response.statusCode}): $body');
          break;
        }

        final dynamic decoded = jsonDecode(body);
        List<dynamic> items = [];
        if (decoded is List) {
          items = decoded;
        } else if (decoded is Map<String, dynamic> && decoded['projects'] is List) {
          items = decoded['projects'] as List<dynamic>;
        } else if (decoded is Map<String, dynamic> && decoded['data'] is List) {
          items = decoded['data'] as List<dynamic>;
        }

        if (items.isEmpty) {
          break;
        }

        for (final item in items) {
          if (item is Map<String, dynamic>) {
            allProjects.add(item);
          }
        }

        if (items.length < limit) {
          break; // Letzte Seite erreicht
        }

        offset += limit;
        page++;
      }

      stdout.writeln(' Fertig!\n');
      stdout.writeln('Gefundene Projekte insgesamt: ${allProjects.length}\n');

      // Save to cache
      await cacheFile.writeAsString(jsonEncode(allProjects));
    } finally {
      client.close();
    }
  }

  if (allProjects.isEmpty) {
    stdout.writeln('Keine Projekte in Craftnote gefunden.');
    return;
  }

  // Sortierung: Zuerst nach Angebots-/Auftragsnummer (orderNumber), dann Projektname
  allProjects.sort((a, b) {
    final ordA = (a['orderNumber'] ?? '').toString();
    final ordB = (b['orderNumber'] ?? '').toString();
    if (ordA.isNotEmpty && ordB.isNotEmpty) {
      final cmp = ordA.compareTo(ordB);
      if (cmp != 0) return cmp;
    } else if (ordA.isNotEmpty) {
      return -1;
    } else if (ordB.isNotEmpty) {
      return 1;
    }
    final nameA = (a['name'] ?? '').toString();
    final nameB = (b['name'] ?? '').toString();
    return nameA.toLowerCase().compareTo(nameB.toLowerCase());
  });

  String clean(dynamic val) => (val ?? '').toString().replaceAll('\n', ' ').replaceAll('\r', '').trim();

  // Optionaler Suchfilter über CLI-Parameter (z. B. `dart run tool/list_craftnote_projects.dart 26-00251-AN`)
  final filterQuery = cleanArgs.join(' ').trim().toLowerCase();
  List<Map<String, dynamic>> displayProjects;

  if (showFirstOnly) {
    displayProjects = [allProjects.first];
  } else if (filterQuery.isNotEmpty) {
    displayProjects = allProjects.where((p) {
      final ord = clean(p['orderNumber']).toLowerCase();
      final name = clean(p['name']).toLowerCase();
      final id = clean(p['id']).toLowerCase();
      final street = clean(p['street']).toLowerCase();
      final city = clean(p['city']).toLowerCase();
      final zip = clean(p['zipcode']).toLowerCase();
      final billingName = clean(p['billingName']).toLowerCase();
      final note = clean(p['noteContent']).toLowerCase();
      return ord.contains(filterQuery) ||
          name.contains(filterQuery) ||
          id.contains(filterQuery) ||
          street.contains(filterQuery) ||
          city.contains(filterQuery) ||
          zip.contains(filterQuery) ||
          billingName.contains(filterQuery) ||
          note.contains(filterQuery);
    }).toList();
  } else {
    displayProjects = allProjects;
  }

  if (filterQuery.isNotEmpty) {
    stdout.writeln('Suchfilter aktiv: "$filterQuery" -> ${displayProjects.length} Treffer von ${allProjects.length} Projekten.\n');
  }

  // --- TABELLE ZEIGEN WENN NICHT NUR EINZELNES JSON ANGEFORDERT IST ---
  if (!showJson) {
    String pad(String text, int width) {
      if (text.length > width) {
        return '${text.substring(0, width - 3)}...';
      }
      return text.padRight(width);
    }

    // Column widths:
    const colNr = 4;
    const colOrder = 18;
    const colName = 42;
    const colId = 38;
    const colStreet = 30;
    const colCity = 18;

    final header = '| ${pad('Nr.', colNr)} '
        '| ${pad('Order Number', colOrder)} '
        '| ${pad('Project Name', colName)} '
        '| ${pad('Craftnote ID (UUID)', colId)} '
        '| ${pad('Street / Address', colStreet)} '
        '| ${pad('City', colCity)} |';

    final separator = '+-${'-' * colNr}-'
        '+-${'-' * colOrder}-'
        '+-${'-' * colName}-'
        '+-${'-' * colId}-'
        '+-${'-' * colStreet}-'
        '+-${'-' * colCity}-+';

    stdout.writeln(separator);
    stdout.writeln(header);
    stdout.writeln(separator);

    final maxTableRows = (filterQuery.isEmpty && !forceDetails && displayProjects.length > 50)
        ? 50
        : displayProjects.length;

    int index = 1;
    for (int i = 0; i < maxTableRows; i++) {
      final p = displayProjects[i];
      final orderNr = clean(p['orderNumber']);
      final name = clean(p['name']);
      final id = clean(p['id']);
      final street = clean(p['street']);
      final city = clean(p['city']);

      final row = '| ${pad(index.toString(), colNr)} '
          '| ${pad(orderNr.isEmpty ? '-' : orderNr, colOrder)} '
          '| ${pad(name, colName)} '
          '| ${pad(id, colId)} '
          '| ${pad(street.isEmpty ? '-' : street, colStreet)} '
          '| ${pad(city.isEmpty ? '-' : city, colCity)} |';
      stdout.writeln(row);
      index++;
    }

    stdout.writeln(separator);
    if (displayProjects.length > maxTableRows) {
      stdout.writeln('(Zeige die ersten $maxTableRows von ${displayProjects.length} Projekten in der Kurzübersicht.)\n');
    } else {
      stdout.writeln('Gesamt: ${displayProjects.length} Projekte aufgelistet.\n');
    }
  }

  // --- ENTSCHEIDUNG ZUR DETAILANZEIGE ALLER PARAMETER ---
  // Parameter werden angezeigt wenn:
  // - `--details` / `-d` / `--all`
  // - `--first`
  // - `--json`
  // - Oder ein Suchfilter angegeben wurde und <= 10 Treffer liefert (Standard-Detailansicht beim Suchen)
  final bool shouldShowDetails = forceDetails ||
      showFirstOnly ||
      showJson ||
      (filterQuery.isNotEmpty && displayProjects.isNotEmpty && displayProjects.length <= (limitDetailCount ?? 10));

  final int detailLimit = limitDetailCount ??
      (forceDetails ? displayProjects.length : (showFirstOnly ? 1 : 10));

  final projectsForDetail = displayProjects.take(detailLimit).toList();

  if (shouldShowDetails && projectsForDetail.isNotEmpty) {
    stdout.writeln('========================================================================================================');
    stdout.writeln('  VOLLSTÄNDIGE PARAMETER-ANTWORT DER PROJEKTE (${projectsForDetail.length} Projekt(e))');
    stdout.writeln('========================================================================================================\n');

    for (int i = 0; i < projectsForDetail.length; i++) {
      final project = projectsForDetail[i];
      if (showJson) {
        final encoder = const JsonEncoder.withIndent('  ');
        stdout.writeln('// -------------------------------------------------------------');
        stdout.writeln('// PROJEKT #${i + 1}: ${project['name'] ?? project['id']}');
        stdout.writeln('// -------------------------------------------------------------');
        stdout.writeln(encoder.convert(project));
        stdout.writeln();
      } else {
        printComprehensiveProjectParameters(i + 1, project);
      }
    }
  } else if (filterQuery.isNotEmpty && displayProjects.length > (limitDetailCount ?? 10) && !forceDetails) {
    stdout.writeln('💡 Hinweis: $displayProjects.length Projekte gefunden. Um alle Parameter-Antworten anzuzeigen, füge "--details" oder z. B. "--limit=5" hinzu.');
    stdout.writeln('   Beispiel: dart run tool/list_craftnote_projects.dart "$filterQuery" --details\n');
  } else if (!forceDetails && !showFirstOnly) {
    stdout.writeln('💡 Tipp: Um alle API-Parameter eines bestimmten Projektes anzuzeigen:');
    stdout.writeln('   dart run tool/list_craftnote_projects.dart <Auftragsnummer_oder_Name>');
    stdout.writeln('   Beispiel: dart run tool/list_craftnote_projects.dart --first');
    stdout.writeln('   JSON-Export: dart run tool/list_craftnote_projects.dart <Suchbegriff> --json\n');
  }

  // --- MARKDOWN EXPORT GENERIEREN ---
  final sbMarkdown = StringBuffer();
  sbMarkdown.writeln('# Craftnote Projektliste & Parameter-Übersicht\n');
  sbMarkdown.writeln('Abgerufen am: ${DateTime.now().toIso8601String()}\n');
  sbMarkdown.writeln('Gesamtzahl Projekte im Workspace: **${allProjects.length}**\n');
  if (filterQuery.isNotEmpty) {
    sbMarkdown.writeln('Suchfilter: `${filterQuery}` (**${displayProjects.length} Treffer**)\n');
  }

  sbMarkdown.writeln('## Übersichtstabelle\n');
  sbMarkdown.writeln('| Nr. | Order Number (Angebotsnr) | Project Name | Craftnote ID (UUID) | Street / Address | City | Customer |');
  sbMarkdown.writeln('|---:|:---|:---|:---|:---|:---|:---|');

  int mdIndex = 1;
  final mdTableLimit = displayProjects.length > 300 ? 300 : displayProjects.length;
  for (int i = 0; i < mdTableLimit; i++) {
    final p = displayProjects[i];
    final orderNr = clean(p['orderNumber']);
    final name = clean(p['name']);
    final id = clean(p['id']);
    final street = clean(p['street']);
    final city = clean(p['city']);
    final clientName = clean(p['clientName']);

    sbMarkdown.writeln('| $mdIndex | ${orderNr.isEmpty ? '-' : orderNr} | $name | `$id` | ${street.isEmpty ? '-' : street} | ${city.isEmpty ? '-' : city} | ${clientName.isEmpty ? '-' : clientName} |');
    mdIndex++;
  }

  if (displayProjects.length > mdTableLimit) {
    sbMarkdown.writeln('\n*(Tabelle auf erste $mdTableLimit Einträge begrenzt. Nutze CLI-Filter für spezifische Projekte)*\n');
  }

  // Wenn Details vorhanden sind, auch in Markdown aufnehmen
  if (shouldShowDetails && projectsForDetail.isNotEmpty) {
    sbMarkdown.writeln('\n## Detaillierte Parameter-Antworten der Projekte\n');
    for (int i = 0; i < projectsForDetail.length; i++) {
      final p = projectsForDetail[i];
      sbMarkdown.writeln('### #${i + 1}: ${p['name'] ?? p['id']}\n');
      sbMarkdown.writeln('```json');
      sbMarkdown.writeln(const JsonEncoder.withIndent('  ').convert(p));
      sbMarkdown.writeln('```\n');
    }
  }

  final mdFile = File('craftnote_projects_overview.md');
  await mdFile.writeAsString(sbMarkdown.toString());
  stdout.writeln('Übersicht & Parameter als Markdown-Datei gespeichert: ${mdFile.absolute.path}\n');
}

/// Formatiert Unix-Timestamps (Sekunden oder Millisekunden) lesbar.
String formatTimestamp(dynamic val) {
  if (val == null) return '-';
  if (val is int) {
    final ms = val > 100000000000 ? val : val * 1000;
    try {
      final dt = DateTime.fromMillisecondsSinceEpoch(ms).toLocal();
      return '$dt (Unix: $val)';
    } catch (_) {
      return val.toString();
    }
  }
  return val.toString();
}

/// Gibt alle Parameter eines Projekts gegliedert und vollständig aus.
void printComprehensiveProjectParameters(int index, Map<String, dynamic> p) {
  stdout.writeln('┌───────────────────────────────────────────────────────────────────────────────────────────────────────');
  stdout.writeln('│ PROJEKT #$index: ${(p['name'] ?? 'Ohne Namen')}');
  stdout.writeln('│ ID (UUID): ${p['id']}');
  stdout.writeln('├───────────────────────────────────────────────────────────────────────────────────────────────────────');

  void printField(String label, dynamic value, [String? extra]) {
    final valStr = (value == null || value.toString().trim().isEmpty) ? '-' : value.toString().trim();
    final extraStr = extra != null ? ' ($extra)' : '';
    stdout.writeln('│  • ${label.padRight(28)}: $valStr$extraStr');
  }

  // 1. Basis-Identifikatoren
  stdout.writeln('│ [1] BASIS-PARAMETER & TYP');
  printField('id (UUID)', p['id']);
  printField('name', p['name']);
  printField('orderNumber (Auftrag/Angebot)', p['orderNumber']);
  printField('projectType', p['projectType']);
  printField('archived', p['archived'], p['archived'] == true ? 'ARCHIVIERT' : 'AKTIV');
  printField('statusId', p['statusId']);
  printField('parentProject', p['parentProject']);
  printField('creator', p['creator']);

  // 2. Zeitstempel
  stdout.writeln('│\n│ [2] ZEITSTEMPEL & AUDIT');
  printField('creationDate', formatTimestamp(p['creationDate']));
  printField('lastEditedDate', formatTimestamp(p['lastEditedDate']));
  printField('lastOpenedDate', formatTimestamp(p['lastOpenedDate']));
  if (p.containsKey('unreadCountsLastEditedDate')) {
    printField('unreadCountsLastEditedDate', formatTimestamp(p['unreadCountsLastEditedDate']));
  }

  // 3. Standortadresse
  stdout.writeln('│\n│ [3] PROJEKT-STANDORT (ADRESSE)');
  printField('street', p['street']);
  printField('zipcode', p['zipcode']);
  printField('city', p['city']);
  printField('country', p['country']);

  // 4. Rechnungsdaten
  stdout.writeln('│\n│ [4] RECHNUNGSEMPFÄNGER (BILLING)');
  printField('billingName', p['billingName']);
  printField('billingStreet', p['billingStreet']);
  printField('billingZipcode', p['billingZipcode']);
  printField('billingCity', p['billingCity']);
  printField('billingCountry', p['billingCountry']);
  printField('billingEmail', p['billingEmail']);

  // 5. Kundendaten (falls separat)
  if (p.containsKey('clientName') || p.containsKey('clientEmail') || p.containsKey('clientPhone')) {
    stdout.writeln('│\n│ [5] KUNDE / CLIENT DIRECT');
    printField('clientName', p['clientName']);
    printField('clientEmail', p['clientEmail']);
    printField('clientPhone', p['clientPhone']);
  }

  // 6. Kontakte
  final contacts = p['contacts'];
  stdout.writeln('│\n│ [6] KONTAKTE (CONTACTS)');
  if (contacts is List && contacts.isNotEmpty) {
    stdout.writeln('│    Anzahl Kontakte: ${contacts.length}');
    for (int cIdx = 0; cIdx < contacts.length; cIdx++) {
      final c = contacts[cIdx];
      if (c is Map) {
        final cName = c['name'] ?? '-';
        final emails = (c['emails'] is List) ? (c['emails'] as List).join(', ') : '-';
        final phones = (c['phones'] is List) ? (c['phones'] as List).join(', ') : '-';
        stdout.writeln('│    [$cIdx] Name: $cName | E-Mails: [${emails.isEmpty ? '-' : emails}] | Tel: [${phones.isEmpty ? '-' : phones}]');
      } else {
        stdout.writeln('│    [$cIdx] $c');
      }
    }
  } else {
    stdout.writeln('│    Keine Kontakte hinterlegt.');
  }

  // 7. Notizen / Beschreibung
  stdout.writeln('│\n│ [7] NOTIZ / AUFTRAGSTEXT (noteContent)');
  final note = p['noteContent']?.toString() ?? '';
  if (note.trim().isEmpty) {
    stdout.writeln('│    - Keine Notiz hinterlegt -');
  } else {
    for (final line in note.split('\n')) {
      stdout.writeln('│    $line');
    }
  }

  // 8. Unterprojekte / Dateien / Speicher
  stdout.writeln('│\n│ [8] SYSTEM, SPEICHER & UNTERPROJEKTE');
  if (p.containsKey('storageBytes')) {
    final bytes = p['storageBytes'];
    if (bytes is num) {
      final kb = (bytes / 1024).toStringAsFixed(1);
      final mb = (bytes / (1024 * 1024)).toStringAsFixed(2);
      printField('storageBytes', '$bytes Bytes ($kb KB / $mb MB)');
    } else {
      printField('storageBytes', bytes);
    }
  }
  final subProjects = p['projects'];
  if (subProjects is List) {
    printField('projects (Sub-Projects)', '${subProjects.length} Unterprojekte ${subProjects.isNotEmpty ? subProjects : ""}');
  }

  // 9. Vollständige Rohparameter-Übersicht (Garantie: JEDER Parameter wird aufgeführt)
  stdout.writeln('│\n│ [9] ALLE PARAMETER-SCHLÜSSEL & TYPEN IM RESPONSE (Vollständigkeitsliste)');
  final sortedKeys = p.keys.toList()..sort();
  for (final key in sortedKeys) {
    final val = p[key];
    String summary;
    if (val == null) {
      summary = 'null';
    } else if (val is String) {
      summary = val.length > 50 ? '"${val.substring(0, 47)}..." (String, len=${val.length})' : '"$val" (String)';
    } else if (val is List) {
      summary = 'List with ${val.length} items';
    } else if (val is Map) {
      summary = 'Map with ${val.length} keys';
    } else {
      summary = '$val (${val.runtimeType})';
    }
    stdout.writeln('│    • ${key.padRight(28)} : $summary');
  }

  stdout.writeln('└───────────────────────────────────────────────────────────────────────────────────────────────────────\n');
}
