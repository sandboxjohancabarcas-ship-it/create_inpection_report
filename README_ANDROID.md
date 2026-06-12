# WartungsTool - Android (Inspektor-Tablet)

## Überblick
Die Android-Version des **WartungsTools** ist für Außendienst-Inspektoren konzipiert, um Türwartungen durchzuführen, Mängel zu erfassen und Daten über eine `working.db`-Datei zu synchronisieren.

## Build-Voraussetzungen (Für Entwickler)
Um die Anwendung zu kompilieren, muss Ihre Entwicklungsumgebung folgende Anforderungen erfüllen:
- **Flutter SDK**: `^3.0.0`
- **Java Development Kit (JDK)**: Version 17 (Erforderlich für das Android Gradle Plugin 8.x).
- **Android Studio**: Installiert mit dem neuesten Android SDK und den Command-line Tools.
- **Kotlin**: Unterstützung für Version 2.0+.

## Erstellung der APK
Wir stellen ein automatisiertes Skript zur Verfügung, das das Prozessmanagement und das Löschen des Caches übernimmt, um einen sauberen Build zu gewährleisten.

1. Öffnen Sie ein PowerShell-Terminal im Projektverzeichnis.
2. Führen Sie das Rebuild-Skript aus:
   ```powershell
   ./rebuild.ps1
   ```
3. Nach Abschluss befindet sich die Installationsdatei unter:
   `build\app\outputs\flutter-apk\app-release.apk`

## Installation auf dem Tablet
Da diese Anwendung als eigenständiges Tool für spezifische Hardware bereitgestellt wird (kein Play Store):

1. **Unbekannte Quellen zulassen**: Gehen Sie auf dem Android-Tablet zu *Einstellungen > Sicherheit* und aktivieren Sie "Unbekannte Apps installieren".
2. **APK übertragen**: Kopieren Sie die `app-release.apk` per USB oder über einen freigegebenen Netzwerkordner auf das Tablet.
3. **Ausführen**: Öffnen Sie den Dateimanager auf dem Tablet, suchen Sie die APK und tippen Sie darauf, um sie zu installieren.

## Dateneinrichtung
- Beim ersten Start initialisiert die App die `working.db`.
- Verwenden Sie das "Manager-Terminal" (Windows), um ein **Job-Paket** zu exportieren, und importieren Sie dieses Paket dann auf das Tablet, um mit den Inspektionen zu beginnen.

## Fehlerbehebung
- **Build schlägt fehl**: Führen Sie `flutter clean` aus und stellen Sie sicher, dass keine anderen Gradle-Prozesse den `build`-Ordner sperren.
- **Datenbankfehler**: Stellen Sie sicher, dass die Speicherberechtigungen für die Anwendung auf dem Tablet aktiviert sind.