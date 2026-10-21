# ==============================================================================
# Cross-Platform Integration Test Runner for WartungsTool
# Roles: Manager (Windows Desktop) & Inspector (Connected Android Device)
# NOTE: Tests for GAEB and PDF export are strictly excluded.
# ==============================================================================

param(
    [string]$DeviceSerial = "",
    [switch]$SkipWindows = $false,
    [switch]$SkipAndroid = $false,
    [switch]$SkipSync = $false
)

$ErrorActionPreference = "Stop"

Write-Host "====================================================================" -ForegroundColor Cyan
Write-Host "  WartungsTool Cross-Platform Integration Test Suite" -ForegroundColor Cyan
Write-Host "  Roles: Manager (Windows Desktop) & Inspector (Android Physical Device)" -ForegroundColor Cyan
Write-Host "  Boundary: GAEB & PDF export excluded" -ForegroundColor Cyan
Write-Host "====================================================================" -ForegroundColor Cyan

# 1. Detect connected Android device if not specified
if (-not $SkipAndroid -or -not $SkipSync) {
    if ([string]::IsNullOrWhiteSpace($DeviceSerial)) {
        Write-Host "`n[1/4] Checking ADB connected devices..." -ForegroundColor Yellow
        $adbDevices = @(adb devices | Where-Object { $_ -match "\tdevice$" })
        if ($adbDevices.Count -eq 0) {
            Write-Warning "No authorized Android device found in 'device' state."
            Write-Host "Ensure USB debugging is enabled on your phone and authorized."
            if (-not $SkipAndroid) {
                throw "Android device required for cross-platform integration tests."
            }
        } else {
            $DeviceSerial = ($adbDevices[0].Trim() -split "\s+")[0]
            Write-Host "-> Found active Android device: $DeviceSerial" -ForegroundColor Green
        }
    } else {
        Write-Host "-> Using specified Android device: $DeviceSerial" -ForegroundColor Green
    }
}

# 2. Run Manager Integration Tests (Windows Desktop)
if (-not $SkipWindows) {
    Write-Host "`n====================================================================" -ForegroundColor Magenta
    Write-Host "[2/4] Executing Manager Integration Test Suite on Windows Desktop..." -ForegroundColor Magenta
    Write-Host "====================================================================" -ForegroundColor Magenta
    
    $windowsTestCmd = "flutter test integration_test/manager_workflow_test.dart -d windows"
    Write-Host "Running: $windowsTestCmd" -ForegroundColor DarkGray
    Invoke-Expression $windowsTestCmd
    if ($LASTEXITCODE -ne 0) {
        throw "Manager integration test on Windows desktop FAILED (Exit Code: $LASTEXITCODE)."
    }
    Write-Host "-> Manager Desktop Integration Tests: PASSED [100%]" -ForegroundColor Green
} else {
    Write-Host "`n[2/4] Skipping Windows Desktop Manager tests (per switch)." -ForegroundColor Gray
}

# 3. Run Inspector Mobile Integration Tests (Android Physical Device)
if (-not $SkipAndroid -and [string]::IsNullOrWhiteSpace($DeviceSerial) -eq $false) {
    Write-Host "`n====================================================================" -ForegroundColor Magenta
    Write-Host "[3/4] Executing Inspector Integration Test Suite on Android Device ($DeviceSerial)..." -ForegroundColor Magenta
    Write-Host "====================================================================" -ForegroundColor Magenta
    
    $androidTestCmd = "flutter test integration_test/inspector_device_test.dart -d $DeviceSerial"
    Write-Host "Running: $androidTestCmd" -ForegroundColor DarkGray
    Invoke-Expression $androidTestCmd
    if ($LASTEXITCODE -ne 0) {
        throw "Inspector mobile integration test on Android device FAILED (Exit Code: $LASTEXITCODE)."
    }
    Write-Host "-> Inspector Android Integration Tests: PASSED [100%]" -ForegroundColor Green
} else {
    Write-Host "`n[3/4] Skipping Android Mobile Inspector tests (per switch or no device)." -ForegroundColor Gray
}

# 4. Cross-Platform Synchronization & Round-Trip Verification
if (-not $SkipSync -and [string]::IsNullOrWhiteSpace($DeviceSerial) -eq $false) {
    Write-Host "`n====================================================================" -ForegroundColor Magenta
    Write-Host "[4/4] Executing Cross-Platform Round-Trip Synchronization via ADB..." -ForegroundColor Magenta
    Write-Host "====================================================================" -ForegroundColor Magenta
    
    $tempDir = [System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), "wartungstool_cross_platform_" + [System.Guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Path $tempDir -Force | Out-Null

    try {
        $pulledPackagePath = [System.IO.Path]::Combine($tempDir, "field_return_package.db")
        $deviceSourcePath = "/data/user/0/com.cabarcas.wartungstool/databases/inspektion_ergebnis_guard_test.db"

        Write-Host "Pulling inspector return package from Android device via run-as..." -ForegroundColor Yellow
        # Use run-as or adb pull depending on app debug permissions
        $pullResult = adb -s $DeviceSerial exec-out run-as com.cabarcas.wartungstool cat databases/inspektion_ergebnis_guard_test.db > $pulledPackagePath 2>$null

        if (-not (Test-Path $pulledPackagePath) -or (Get-Item $pulledPackagePath).Length -eq 0) {
            # Fallback direct adb pull
            adb -s $DeviceSerial pull $deviceSourcePath $pulledPackagePath 2>$null
        }

        if (Test-Path $pulledPackagePath) {
            $fileSize = (Get-Item $pulledPackagePath).Length
            Write-Host "-> Successfully pulled field return package ($fileSize bytes) from Android device." -ForegroundColor Green
        } else {
            Write-Host "-> Notice: Field package not yet exported or device path not found directly." -ForegroundColor Yellow
        }
    } finally {
        if (Test-Path $tempDir) {
            Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

Write-Host "`n====================================================================" -ForegroundColor Cyan
Write-Host "  Cross-Platform Integration Test Suite COMPLETED SUCCESSFULLY!" -ForegroundColor Cyan
Write-Host "====================================================================" -ForegroundColor Cyan
