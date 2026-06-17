# WartungsTool - Windows Build Script
Set-Location $PSScriptRoot

Write-Host "Starting Windows build sequence..." -ForegroundColor Cyan

# 1. Kill Background Processes
# This prevents "File in use" errors during compilation (MSB3374)
Write-Host "[1/4] Stopping existing app instances and build tools..." -ForegroundColor Gray
Get-Process "WartungsTool" -ErrorAction SilentlyContinue | Stop-Process -Force
Get-Process "MSBuild" -ErrorAction SilentlyContinue | Stop-Process -Force

# 2. Environment Refresh
Write-Host "[2/4] Fetching dependencies..." -ForegroundColor Gray
flutter pub get

# 3. Asset Verification
if (!(Test-Path "error_catalog.csv")) {
    Write-Host "Warning: error_catalog.csv not found in root. Windows build may fail to bundle assets." -ForegroundColor Yellow
}

# 4. Run Application
Write-Host "[3/4] Launching Windows application..." -ForegroundColor Cyan
flutter run -d windows

if ($LASTEXITCODE -ne 0) {
    Write-Host "Build failed. If you see path errors, verify that lib/pages/inspection_summary_card.dart exists." -ForegroundColor Red
    exit 1
}