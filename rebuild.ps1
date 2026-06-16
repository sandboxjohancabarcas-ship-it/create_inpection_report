# WartungsTool - Android Build Script
Set-Location $PSScriptRoot

Write-Host "Starting Android build sequence..." -ForegroundColor Cyan

# 1. Kill Background Processes (Ensures Java/Gradle doesn't lock folders)
Write-Host "[1/4] Stopping Gradle Daemons and checking for Java locks..." -ForegroundColor Gray
& .\android\gradlew.bat --stop
Get-Process "java" -ErrorAction SilentlyContinue | Stop-Process -Force

# 2. Deep Clean
Write-Host "[2/4] Clearing stale caches and build artifacts..." -ForegroundColor Gray
# Explicitly remove the target APK so we don't see an old version if the build fails
$apkPath = "build\app\outputs\flutter-apk\app-release.apk"
if (Test-Path $apkPath) { Remove-Item -Force $apkPath }

if (Test-Path "android/.gradle") { Remove-Item -Recurse -Force "android/.gradle" }
if (Test-Path "android/.kotlin") { Remove-Item -Recurse -Force "android/.kotlin" }
if (Test-Path "build") { Remove-Item -Recurse -Force "build" }

# 3. Environment Refresh
Write-Host "[3/4] Running flutter clean and fetching dependencies..." -ForegroundColor Gray
flutter clean
flutter pub get

# 4. Android Build
Write-Host "[4/4] Building Android APK (Release)..." -ForegroundColor Cyan
flutter build apk --release --obfuscate --split-debug-info=build/app/outputs/symbols

if ($LASTEXITCODE -eq 0) {
    Write-Host "Android build completed successfully." -ForegroundColor Green
    Write-Host "APK is located in: build\app\outputs\flutter-apk\app-release.apk" -ForegroundColor Gray
} else {
    Write-Host "Build failed. Check the logs above for Gradle or ProGuard errors." -ForegroundColor Red
}