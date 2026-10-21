# WartungsTool - Windows Build Script with Automated Pre-Build Integration Test Gate
param(
    [switch]$SkipTests = $false
)

Set-Location $PSScriptRoot

Write-Host "====================================================================" -ForegroundColor Cyan
Write-Host "  WartungsTool - Windows Release Build Sequence" -ForegroundColor Cyan
Write-Host "====================================================================" -ForegroundColor Cyan

# 1. Kill Background Processes
# This prevents "File in use" errors during compilation (MSB3374)
Write-Host "[1/5] Stopping existing app instances and build tools..." -ForegroundColor Gray
Get-Process "WartungsTool" -ErrorAction SilentlyContinue | Stop-Process -Force
Get-Process "MSBuild" -ErrorAction SilentlyContinue | Stop-Process -Force

# 2. Synchronize Version & Build Date
Write-Host "[2/5] Updating version and build date timestamp..." -ForegroundColor Gray
& "$PSScriptRoot\scripts\update_version.ps1"

# 3. Environment Refresh
Write-Host "[3/5] Fetching dependencies..." -ForegroundColor Gray
flutter pub get

# 4. Asset Verification
if (!(Test-Path "error_catalog.json")) {
    Write-Host "Warning: error_catalog.json not found in root. Windows build may fail to bundle assets." -ForegroundColor Yellow
}

# 5. Automated Pre-Build Integration Test Gatekeeper
if (-not $SkipTests) {
    Write-Host "`n[4/5] Executing Pre-Build Integration Test Routine Gatekeeper..." -ForegroundColor Cyan
    & "$PSScriptRoot\scripts\run_test_routine.ps1" -PreBuild
    if ($LASTEXITCODE -ne 0) {
        Write-Host "`nABORT: Pre-Build Integration Tests FAILED. Windows build terminated." -ForegroundColor Red
        exit 1
    }
    Write-Host "-> Pre-Build Quality Gate: PASSED. Proceeding to compilation." -ForegroundColor Green
} else {
    Write-Host "`n[4/5] Skipping test routine (-SkipTests specified)." -ForegroundColor Yellow
}

# 6. Run Application in Release Mode
Write-Host "`n[5/5] Launching Windows application in Release Mode..." -ForegroundColor Cyan
flutter run --release -d windows

if ($LASTEXITCODE -ne 0) {
    Write-Host "Build failed. If you see path errors, verify that lib/pages/inspection_summary_card.dart exists." -ForegroundColor Red
    exit 1
}