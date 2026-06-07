# Build Architecture & Troubleshooting Notes

## Environment Details
- **Flutter SDK**: ^3.0.0
- **Java Version**: 17 (Required for modern AGP)
- **Kotlin Version**: 2.0+ (Requires `compilerOptions` DSL in root)
- **Android Gradle Plugin**: 8.x

## Critical Configuration Fixes
1. **Build Directory Redirection**: 
   The `android/build.gradle.kts` is configured to redirect all outputs to the root `/build` folder. This is critical for the Flutter tool on Windows to find the generated APK.
2. **Global Java/Kotlin Enforcement**: 
   The `subprojects` block in the root `build.gradle.kts` forces all plugins (many of which default to Java 8) to use Java 17. 
   - **Warning**: Do NOT use `options.release.set(17)` in the root script as it breaks Android API linking. Use `sourceCompatibility` and `targetCompatibility` instead.
3. **Kotlin DSL**: 
   Since Kotlin 2.0 is used, `kotlinOptions` is deprecated. Always use `compilerOptions` with `jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)`.

## Recovery Procedure (The "Scorched Earth" Reset)
If the build fails with "Finalized" or "Unresolved Reference" errors after configuration changes:
1. Run `./android/gradlew --stop`
2. Delete `android/.gradle`, `android/.kotlin`, and the root `build/` folder.
3. Run `flutter clean`
4. Run `flutter pub get`
5. Run `flutter build apk --release`