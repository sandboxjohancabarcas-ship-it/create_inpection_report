# WartungsTool - Windows Build Script
# Focused exclusively on the Windows Manager Terminal build.

Write-Host "Starting Windows build sequence..." -ForegroundColor Cyan

# 1. Kill Background Processes (Essential for Windows build to overwrite .exe)
Write-Host "[1/4] Checking for running instances of WartungsTool..." -ForegroundColor Gray
Get-Process "WartungsTool" -ErrorAction SilentlyContinue | Stop-Process -Force

# 2. Deep Clean (Remove root build folder and ephemeral Windows artifacts)
Write-Host "[2/4] Clearing build artifacts and CMake caches..." -ForegroundColor Gray
if (Test-Path "build") { Remove-Item -Recurse -Force "build" }
if (Test-Path "windows/flutter/ephemeral") { Remove-Item -Recurse -Force "windows/flutter/ephemeral" }

# 3. Environment Refresh
Write-Host "[3/4] Running flutter clean and fetching dependencies..." -ForegroundColor Gray
flutter clean
flutter pub get

# 4. Windows Build
Write-Host "[4/4] Building Windows Package (Release)..." -ForegroundColor Cyan
flutter build windows --release

if ($LASTEXITCODE -eq 0) {
    Write-Host "Windows build completed successfully." -ForegroundColor Green
    Write-Host "Executable and dependencies are in: build\windows\runner\Release" -ForegroundColor Gray
} else {
    Write-Host "Build failed. Check the logs above for C++ compiler or Flutter errors." -ForegroundColor Red
}