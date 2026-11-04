import 'dart:convert';
import 'dart:io';

Future<void> main(List<String> args) async {
  // Credentials (defaults configured for WartungsTool)
  final apiKey = Platform.environment['CRAFTNOTE_API_KEY'] ?? '64045d24-397a-407b-b4ae-2ceef59018dd';
  final clientId = Platform.environment['CRAFTNOTE_CLIENT_ID'] ?? 'd04f732b-6c89-4804-97d8-63a0ea7c1199';
  final baseUrl = (Platform.environment['CRAFTNOTE_BASE_URL'] ?? 'https://europe-west1-craftnote-live.cloudfunctions.net/api/v1')
      .replaceAll(RegExp(r'/+$'), '');

  stdout.writeln('========================================================================================================');
  stdout.writeln('  CRAFTNOTE - ALLE PROJEKTE TABELLARISCH ABRUFEN');
  stdout.writeln('========================================================================================================');
  stdout.writeln('API Base URL:  $baseUrl');
  stdout.writeln('Client-ID:     $clientId');
  stdout.writeln('API-Key:       ${apiKey.substring(0, 4)}...${apiKey.substring(apiKey.length - 4)}');
  stdout.writeln('--------------------------------------------------------------------------------------------------------\n');

  final cacheFile = File('craftnote_projects_cache.json');
  final bool forceRefresh = args.contains('--refresh') || !cacheFile.existsSync();
  final cleanArgs = args.where((a) => a != '--refresh').toList();

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
    final displayProjects = filterQuery.isEmpty
        ? allProjects
        : allProjects.where((p) {
            final ord = clean(p['orderNumber']).toLowerCase();
            final name = clean(p['name']).toLowerCase();
            final id = clean(p['id']).toLowerCase();
            final street = clean(p['street']).toLowerCase();
            final city = clean(p['city']).toLowerCase();
            return ord.contains(filterQuery) ||
                name.contains(filterQuery) ||
                id.contains(filterQuery) ||
                street.contains(filterQuery) ||
                city.contains(filterQuery);
          }).toList();

    if (filterQuery.isNotEmpty) {
      stdout.writeln('Suchfilter aktiv: "$filterQuery" -> ${displayProjects.length} Treffer von ${allProjects.length} Projekten.\n');
    }

    String pad(String text, int width) {
      if (text.length > width) {
        return '${text.substring(0, width - 3)}...';
      }
      return text.padRight(width);
    }

    // Column widths:
    const colNr = 4;
    const colOrder = 18;
    const colName = 44;
    const colId = 38;
    const colStreet = 32;
    const colCity = 20;

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

    final sbMarkdown = StringBuffer();
    sbMarkdown.writeln('# Craftnote Projektliste\n');
    sbMarkdown.writeln('Abgerufen am: ${DateTime.now().toIso8601String()}\n');
    sbMarkdown.writeln('Gesamtzahl Projekte: **${allProjects.length}**\n');
    sbMarkdown.writeln('| Nr. | Order Number (Angebotsnr) | Project Name | Craftnote ID (UUID) | Street / Address | City | Customer |');
    sbMarkdown.writeln('|---:|:---|:---|:---|:---|:---|:---|');

    int index = 1;
    for (final p in displayProjects) {
      final orderNr = clean(p['orderNumber']);
      final name = clean(p['name']);
      final id = clean(p['id']);
      final street = clean(p['street']);
      final city = clean(p['city']);
      final clientName = clean(p['clientName']);

      final row = '| ${pad(index.toString(), colNr)} '
          '| ${pad(orderNr.isEmpty ? '-' : orderNr, colOrder)} '
          '| ${pad(name, colName)} '
          '| ${pad(id, colId)} '
          '| ${pad(street.isEmpty ? '-' : street, colStreet)} '
          '| ${pad(city.isEmpty ? '-' : city, colCity)} |';
      stdout.writeln(row);

      sbMarkdown.writeln('| $index | ${orderNr.isEmpty ? '-' : orderNr} | $name | `$id` | ${street.isEmpty ? '-' : street} | ${city.isEmpty ? '-' : city} | ${clientName.isEmpty ? '-' : clientName} |');

      index++;
    }

    stdout.writeln(separator);
    stdout.writeln('\nGesamt: ${allProjects.length} Projekte aufgelistet.');

    // Save as markdown file for easy viewing
    final mdFile = File('craftnote_projects_overview.md');
    await mdFile.writeAsString(sbMarkdown.toString());
    stdout.writeln('Übersicht ebenfalls als Markdown-Datei gespeichert: ${mdFile.absolute.path}\n');
}
