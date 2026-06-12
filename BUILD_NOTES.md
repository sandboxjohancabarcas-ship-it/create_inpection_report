# Build-Architektur & Hinweise zur Fehlerbehebung

## Details zur Umgebung
- **Flutter SDK**: ^3.0.0
- **Java-Version**: 17 (Erforderlich für modernes AGP)
- **Kotlin-Version**: 2.0+ (Erfordert `compilerOptions` DSL im Root)
- **Android Gradle Plugin**: 8.x

## Kritische Konfigurationsanpassungen
1. **Umleitung des Build-Verzeichnisses**: 
   Die `android/build.gradle.kts` ist so konfiguriert, dass alle Ausgaben in den Root-Ordner `/build` umgeleitet werden. Dies ist entscheidend, damit das Flutter-Tool unter Windows die generierte APK findet.
2. **Globale Java/Kotlin-Erzwingung**: 
   Der `subprojects`-Block in der Root-Datei `build.gradle.kts` zwingt alle Plugins (viele davon standardmäßig auf Java 8), Java 17 zu verwenden. 
   - **Warnung**: Verwenden Sie NICHT `options.release.set(17)` im Root-Skript, da dies das Android-API-Linking unterbricht. Verwenden Sie stattdessen `sourceCompatibility` und `targetCompatibility`.
3. **Kotlin DSL**: 
   Da Kotlin 2.0 verwendet wird, ist `kotlinOptions` veraltet. Verwenden Sie immer `compilerOptions` mit `jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)`.
4. **Abhängigkeit der Ressourcen-Verkleinerung**:
   Das Android Gradle Plugin (AGP) 8.x erfordert `minifyEnabled true`, wenn `shrinkResources true` verwendet wird. Dies liegt daran, dass der Resource-Shrinker auf den Code-Analyzer (R8) angewiesen ist, um festzustellen, welche Ressourcen tatsächlich im Code referenziert werden.

## Wiederherstellungsverfahren (Der "Radikale Reset")
Wenn der Build fehlschlägt oder einen veralteten App-Status anzeigt:
1. Run `./android/gradlew --stop`
2. **Hintergrundprozesse beenden**: Öffnen Sie den Task-Manager und stellen Sie sicher, dass `WartungsTool.exe` nicht läuft.
3. **Tiefenreinigung**: 
   - Löschen Sie den Root-Ordner `build/`.
   - Löschen Sie den Ordner `windows/flutter/ephemeral/`.
3. Run `flutter clean`
4. Run `flutter pub get`
5. Run `flutter build apk --release`
6. Run `flutter build windows --release`

## Vorbereitung für das Windows-Deployment
1. **Anforderung an die Toolchain**: Installieren Sie Visual Studio 2022. 
   - Workload: "Desktopentwicklung mit C++"
   - Einzelkomponente: "MSVC v143 - VS 2022 C++ x64/x86 Buildtools"
2. **SQLite (FFI) Konfiguration**: 
   - Verwenden Sie `sqflite_common_ffi` für Windows.
   - Rufen Sie in der Datenbankinitialisierung `if (Platform.isWindows)` auf, um `sqfliteFfiInit()` auszuführen und `databaseFactory = databaseFactoryFfi` zu setzen.
   - Stellen Sie sicher, dass `path_provider` für die plattformübergreifende Pfadauflösung verwendet wird.
3. **Build Command**: 
   - `flutter build windows --release`
4. **Paketierung**: Die Ausgabe befindet sich in `build\windows\runner\Release`. Um einen Installer zu erstellen, verwenden Sie das Pub-Paket `msix` oder ein externes Tool wie Inno Setup.

## Verifizierungsschritte (Release-Build)
- Zeitstempel der Datei prüfen: `build\windows\runner\Release\WartungsTool.exe` muss der aktuellen Zeit entsprechen.
- Wenn der Zeitstempel alt ist, löschen Sie `build\windows` manuell und führen Sie `flutter build windows --release -v` aus, um detaillierte Protokolle zu sehen.