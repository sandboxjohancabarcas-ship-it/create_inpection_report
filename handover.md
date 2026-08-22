# Handover: Setting Up on a New Machine

This guide provides step-by-step instructions for setting up the **WartungsTool** development environment on a new machine that has only the Antigravity IDE installed.

---

## 1. Repository & Branch
- **Branch**: `feature/multi-user` (must check out this branch to preserve all metadata, database migrations, cloud integrations, and import fixes).
- **Command**:
  ```bash
  git checkout feature/multi-user
  ```

---

## 2. Prerequisites Setup (Environment & Dependencies)

### A. Java Development Kit (JDK) 17
*Mandatory for compatibility with Android Gradle Plugin 8.x.*
1. Download and install **JDK 17** (MSI/EXE installer for Windows).
2. Set the following environment variables:
   - `JAVA_HOME` = `C:\Program Files\Java\jdk-17` (or your JDK installation path).
   - Append `%JAVA_HOME%\bin` to your System `PATH`.

### B. Flutter SDK
1. Download the **Flutter SDK** (version `^3.0.0` or latest stable).
2. Unzip it to a stable location, e.g., `C:\flutter` or `C:\Users\<username>\flutter`.
3. Set the following environment variables:
   - Append `C:\flutter\bin` to your System `PATH`.
4. Run `flutter doctor` in a new terminal to verify.

### C. Android Studio & Android SDK
1. Install **Android Studio**.
2. Open Android Studio, navigate to the SDK Manager, and install:
   - Android SDK (latest version).
   - **Android SDK Command-line Tools (latest)** (required for Flutter build).
3. Set the following environment variables:
   - `ANDROID_HOME` = `C:\Users\<Username>\AppData\Local\Android\Sdk` (update with your Windows username).
   - Append `%ANDROID_HOME%\cmdline-tools\latest\bin` and `%ANDROID_HOME%\platform-tools` to your System `PATH`.
4. Run:
   ```bash
   flutter doctor --android-licenses
   ```
   Accept all licenses by pressing `y`.

---

## 3. Project Initialization

1. Open a terminal in the project root folder.
2. Download all package dependencies:
   ```bash
   flutter pub get
   ```
3. Run `flutter doctor` to ensure the diagnostic check is fully green.

---

## 4. Database Setup & Seeding

The databases include the new schema updates (Master DB version **19**, Local DB version **9**) containing `projectNumber`. 

To initialize and seed both database files:
1. Run the master data seeding test script:
   ```bash
   flutter test test/seed_master_data_test.dart
   ```
2. This creates the databases and seeds them with mock inspection data.

---

## 5. Build, Test, and Execution Commands

### Run the App on Windows
To launch the Windows desktop version in debug mode:
```bash
flutter run -d windows
```

### Run Unit and Integration Tests
To verify everything compiles and passes:
- Run individual/sequential test suites:
  ```bash
  flutter test test/inspection_metadata_update_test.dart
  flutter test test/excel_import_test.dart
  ```
- Run the full suite:
  ```bash
  flutter test
  ```

### Build Android APK
To compile the release version for Android tablets:
1. Open a PowerShell terminal.
2. Run the automated clean-and-rebuild script (which handles file locking and Gradle cache transform cleanups):
   ```powershell
   ./rebuild.ps1
   ```
3. The built APK will be located at:
   `build\app\outputs\flutter-apk\app-release.apk`
