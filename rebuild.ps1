# WartungsTool - Android Build Script
Set-Location $PSScriptRoot

Write-Host "Starting Android build sequence..." -ForegroundColor Cyan

# 1. Environment Pre-checks
Write-Host "[1/5] Validating environment (Java 17 & Flutter)..." -ForegroundColor Gray
try {
    $javaVersion = java -version 2>&1 | Out-String
    if ($javaVersion -notmatch '17') {
        Write-Host "Warning: JDK 17 is required for AGP 8.x. Detected version:`n$javaVersion" -ForegroundColor Yellow
    }
} catch {
    Write-Host "Error: Java not found. Please install JDK 17." -ForegroundColor Red
    exit 1
}

# 2. Kill Background Processes (Ensures Java/Gradle doesn't lock folders)
Write-Host "[2/5] Stopping Gradle Daemons and checking for Java locks..." -ForegroundColor Gray
if (Test-Path "android/gradlew.bat") {
    & .\android\gradlew.bat --stop
}
Get-Process "java", "javac" -ErrorAction SilentlyContinue | Stop-Process -Force

# 3. Deep Clean
Write-Host "[3/5] Clearing stale caches..." -ForegroundColor Gray
if (Test-Path "android/.gradle") { Remove-Item -Recurse -Force "android/.gradle" }
if (Test-Path "android/.kotlin") { Remove-Item -Recurse -Force "android/.kotlin" }

# 4. Environment Refresh
Write-Host "[4/5] Running flutter clean and fetching dependencies..." -ForegroundColor Gray
flutter clean
flutter pub get

# 5. Android Build
Write-Host "[5/5] Building Android APK (Release)..." -ForegroundColor Cyan
# Obfuscation is enabled; split-debug-info is required for symbolication maps
flutter build apk --release --obfuscate --split-debug-info=build/app/outputs/symbols

if ($LASTEXITCODE -eq 0) {
    Write-Host "Android build completed successfully." -ForegroundColor Green
    Write-Host "APK is located in: build\app\outputs\flutter-apk\app-release.apk" -ForegroundColor Gray
} else {
    Write-Host "Build failed. Check the logs above for Gradle or ProGuard errors." -ForegroundColor Red
}