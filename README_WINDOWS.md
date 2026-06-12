# WartungsTool - Windows (Manager-Terminal)

## Überblick
Die Windows-Version des **WartungsTools** dient als "Source of Truth" (zentrale Datenquelle). Sie verwaltet die Master-Datenbank, die Zuweisung von Aufträgen, das Zusammenführen von Inspektorendaten und die Erstellung von GAEB-konformen Berichten.

## Build-Voraussetzungen (Für Entwickler)
Das Erstellen der Windows-Version erfordert die C++ Desktop-Toolchain:
- **Flutter SDK**: `^3.0.0`
- **Visual Studio 2022**: 
  - Workload: "Desktopentwicklung mit C++"
  - Komponente: "MSVC v143 - VS 2022 C++ x64/x86 Buildtools"
- **SQLite FFI**: Der Build enthält automatisch die `sqlite3.dll` über die Abhängigkeit `sqlite3_flutter_libs`.

## Erstellung der ausführbaren Datei
Bei Windows-Builds treten häufig Dateisperren auf, wenn die App bereits im Hintergrund läuft. Verwenden Sie das spezielle Windows-Rebuild-Skript:

1. Öffnen Sie ein PowerShell-Terminal im Projektverzeichnis.
2. Führen Sie das Windows-spezifische Rebuild-Skript aus:
   ```powershell
   ./rebuild_windows.ps1
   ```
3. Das Build-Ergebnis befindet sich unter:
   `build\windows\runner\Release\`

## Installation & Verteilung
Die Anwendung ist derzeit portabel. Um sie auf dem Rechner eines Managers zu "installieren":

1. **Release-Ordner kopieren**: Kopieren Sie den *gesamten* `Release`-Ordner (nicht nur die .exe) an den Zielort (z.B. `C:\Programme\WartungsTool`).
   - **Wichtig**: Die `.exe` ist von den `.dll`-Dateien (wie `sqlite3.dll` und `flutter_windows.dll`) im selben Verzeichnis abhängig.
2. **Verknüpfung erstellen**: Rechtsklick auf `WartungsTool.exe`, "Verknüpfung erstellen" wählen und diese auf den Desktop verschieben.

## Datenbank-Speicherort
Unter Windows speichert die Anwendung ihre Datenbanken im Dokumente-Ordner des Benutzers:
- `Dokumente\WartungsTool\door_inspection.db` (Master-Datenbank)
- `Dokumente\WartungsTool\working.db` (Lokale Arbeitskopie)

## Rollentrennung
Die Anwendung erkennt automatisch die Windows-Umgebung und startet das **Manager-Dashboard**, das Zugriff auf GAEB-Exporte und die Verwaltung der Master-Datenbank bietet.

## Fehlerbehebung
- **Fehlende DLLs**: Wenn die App nicht startet, stellen Sie sicher, dass alle Dateien aus dem Ordner `build\windows\runner\Release` zusammen kopiert wurden.
- **Zugriff verweigert**: Wenn das Build-Skript fehlschlägt, stellen Sie sicher, dass `WartungsTool.exe` im Task-Manager geschlossen ist.