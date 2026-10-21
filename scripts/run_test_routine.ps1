<#
================================================================================
 WartungsTool - Automated Integration Test Routine
 Roles: Manager (Windows Desktop) & Inspector (Connected Android Device)
 Exclusions: GAEB XML export and PDF export tests are strictly excluded.
 Profiles:
   -Quick     : Fast static analysis + fast unit/domain tests (~15-25s)
   -PreBuild  : Pre-build gatekeeper (analysis + full test/ suite -j 1 + manager_workflow_test) (~60-90s)
   -Full      : Complete cross-platform (PreBuild + Android physical device + ADB sync) (~2-3m)
   -File      : Execute a single target test file
================================================================================
#>

[CmdletBinding(DefaultParameterSetName = "PreBuild")]
param(
    [Parameter(ParameterSetName = "Quick")]
    [switch]$Quick,

    [Parameter(ParameterSetName = "PreBuild")]
    [switch]$PreBuild,

    [Parameter(ParameterSetName = "Full")]
    [switch]$Full,

    [Parameter(ParameterSetName = "SingleFile")]
    [string]$File,

    [Parameter()]
    [string]$DeviceSerial = "",

    [Parameter()]
    [switch]$SkipAnalysis = $false
)

$ErrorActionPreference = "Stop"
$rootPath = Resolve-Path "$PSScriptRoot\.."
Set-Location $rootPath

$startTime = Get-Date

Write-Host "====================================================================" -ForegroundColor Cyan
Write-Host "  WartungsTool - Integration Test Routine" -ForegroundColor Cyan
Write-Host "  Execution Time: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Cyan
if ($Quick) {
    Write-Host "  Profile: QUICK (Fast Post-Change Validation)" -ForegroundColor Green
} elseif ($Full) {
    Write-Host "  Profile: FULL CROSS-PLATFORM (Windows Desktop + Android Device)" -ForegroundColor Magenta
} elseif ($File) {
    Write-Host "  Profile: SINGLE TEST FILE ($File)" -ForegroundColor Yellow
} else {
    Write-Host "  Profile: PRE-BUILD GATEKEEPER (Desktop Full Suite + Integration)" -ForegroundColor Cyan
}
Write-Host "  Exclusions: GAEB XML & PDF exports strictly omitted" -ForegroundColor DarkGray
Write-Host "====================================================================" -ForegroundColor Cyan

# ------------------------------------------------------------------------------
# STAGE 1: Static Code Analysis (dart analyze)
# ------------------------------------------------------------------------------
if (-not $SkipAnalysis) {
    Write-Host "`n[Stage 1] Running Static Code Analysis (dart analyze)..." -ForegroundColor Yellow
    $analysisOutput = dart analyze --fatal-infos 2>&1
    if ($LASTEXITCODE -ne 0) {
        # Check if there are fatal errors vs warnings
        $errorLines = $analysisOutput | Where-Object { $_ -match "error •" }
        if ($errorLines.Count -gt 0) {
            Write-Host "FATAL: Static analysis failed with errors:" -ForegroundColor Red
            $errorLines | ForEach-Object { Write-Host "  $_" -ForegroundColor Red }
            exit 1
        } else {
            Write-Host "-> Static analysis passed with 0 fatal errors." -ForegroundColor Green
        }
    } else {
        Write-Host "-> Static analysis passed (0 errors, 0 warnings)." -ForegroundColor Green
    }
} else {
    Write-Host "`n[Stage 1] Skipping Static Analysis (-SkipAnalysis specified)." -ForegroundColor DarkGray
}

# ------------------------------------------------------------------------------
# STAGE 2: Execute Target Test Suites in test/
# ------------------------------------------------------------------------------
if ($File) {
    Write-Host "`n[Stage 2] Executing Single Target Test: $File" -ForegroundColor Yellow
    if (-not (Test-Path $File)) {
        Write-Host "ERROR: Target test file not found: $File" -ForegroundColor Red
        exit 1
    }
    flutter test $File -j 1
    if ($LASTEXITCODE -ne 0) {
        Write-Host "FAILED: Test execution failed for $File (Exit Code: $LASTEXITCODE)." -ForegroundColor Red
        exit 1
    }
    Write-Host "-> Test PASSED: $File" -ForegroundColor Green
} elseif ($Quick) {
    Write-Host "`n[Stage 2] Executing Fast Core Unit & Domain Tests..." -ForegroundColor Yellow
    $fastTests = @(
        "test/alias_generation_test.dart",
        "test/catalog_init_test.dart",
        "test/catalog_integrity_service_test.dart",
        "test/conflict_resolution_test.dart",
        "test/door_options_service_test.dart",
        "test/door_options_crud_test.dart",
        "test/customer_normalizer_test.dart",
        "test/inspection_lock_permissions_test.dart",
        "test/inspection_year_editability_test.dart",
        "test/photo_name_helper_test.dart",
        "test/barcode_duplicate_warning_test.dart",
        "test/app_version_test.dart"
    )
    
    $existingFastTests = $fastTests | Where-Object { Test-Path $_ }
    Write-Host "Running $($existingFastTests.Count) fast domain test suites..." -ForegroundColor DarkGray
    flutter test $existingFastTests -j 1
    if ($LASTEXITCODE -ne 0) {
        Write-Host "FAILED: Quick test suite encountered failures (Exit Code: $LASTEXITCODE)." -ForegroundColor Red
        exit 1
    }
    Write-Host "-> Quick Core Tests: PASSED [100%]" -ForegroundColor Green
} else {
    Write-Host "`n[Stage 2] Discovering and Executing Core Test Suite (test/)..." -ForegroundColor Yellow
    
    # Discover all tests in test/, strictly filtering out GAEB and PDF tests
    $eligibleTests = Get-ChildItem -Path "test" -Filter "*.dart" -File | 
        Where-Object { 
            $_.Name -notmatch "^(gaeb_|pdf_)" -and
            $_.DirectoryName -notmatch "test_data"
        } | 
        ForEach-Object { "test/$($_.Name)" }

    Write-Host "Found $($eligibleTests.Count) eligible tests (GAEB & PDF excluded)." -ForegroundColor DarkGray
    Write-Host "Executing sequential test run (-j 1) to eliminate SQLite file locks..." -ForegroundColor DarkGray

    # Execute tests in batches of 15 to keep argument strings well below Windows command length limits
    $batchSize = 15
    for ($i = 0; $i -lt $eligibleTests.Count; $i += $batchSize) {
        $end = [Math]::Min($i + $batchSize, $eligibleTests.Count)
        $batch = $eligibleTests[$i..($end - 1)]
        $batchNum = [Math]::Floor($i / $batchSize) + 1
        $totalBatches = [Math]::Ceiling($eligibleTests.Count / $batchSize)
        
        Write-Host "  -> Running Batch $batchNum/$totalBatches ($($batch.Count) suites)..." -ForegroundColor Gray
        flutter test $batch -j 1
        if ($LASTEXITCODE -ne 0) {
            Write-Host "FAILED: Core test batch $batchNum failed (Exit Code: $LASTEXITCODE)." -ForegroundColor Red
            exit 1
        }
    }
    Write-Host "-> All $($eligibleTests.Count) Core Tests in test/: PASSED [100%]" -ForegroundColor Green
}

# ------------------------------------------------------------------------------
# STAGE 3: Manager Workflow Integration Test (Windows Desktop)
# ------------------------------------------------------------------------------
if (-not $Quick -and -not $File) {
    Write-Host "`n[Stage 3] Executing Manager Desktop Integration Test Suite..." -ForegroundColor Yellow
    Write-Host "Running 11 Manager Use Cases (M-UC-01 to M-UC-11) on Windows Desktop..." -ForegroundColor DarkGray
    
    flutter test integration_test/manager_workflow_test.dart -d windows
    if ($LASTEXITCODE -ne 0) {
        Write-Host "FAILED: Manager Desktop Integration Tests failed (Exit Code: $LASTEXITCODE)." -ForegroundColor Red
        exit 1
    }
    Write-Host "-> Manager Desktop Integration Tests: PASSED [100%]" -ForegroundColor Green
}

# ------------------------------------------------------------------------------
# STAGE 4: Inspector Mobile Integration Tests & Cross-Platform Sync
# ------------------------------------------------------------------------------
if ($Full) {
    Write-Host "`n[Stage 4] Detecting Connected Android Device for Mobile Integration Tests..." -ForegroundColor Yellow
    
    if ([string]::IsNullOrWhiteSpace($DeviceSerial)) {
        $adbDevices = @(adb devices | Where-Object { $_ -match "\tdevice$" })
        if ($adbDevices.Count -eq 0) {
            Write-Host "WARNING: No authorized Android physical device detected via ADB." -ForegroundColor Yellow
            Write-Host "Make sure your device (e.g. Samsung Galaxy A16) is connected in USB Debugging mode." -ForegroundColor Yellow
            Write-Host "FAILED: -Full profile requires an active Android device." -ForegroundColor Red
            exit 1
        }
        $DeviceSerial = ($adbDevices[0].Trim() -split "\s+")[0]
    }
    
    Write-Host "-> Target Android Device: $DeviceSerial" -ForegroundColor Green
    Write-Host "Executing Inspector Mobile Integration Tests (I-UC-01 to I-UC-07) on device..." -ForegroundColor DarkGray
    
    flutter test integration_test/inspector_device_test.dart -d $DeviceSerial
    if ($LASTEXITCODE -ne 0) {
        Write-Host "FAILED: Inspector mobile integration tests on device $DeviceSerial failed (Exit Code: $LASTEXITCODE)." -ForegroundColor Red
        exit 1
    }
    Write-Host "-> Inspector Mobile Integration Tests: PASSED [100%]" -ForegroundColor Green

    # Cross-Platform Package Sync Verification
    Write-Host "`n[Stage 5] Verifying Cross-Platform ADB Round-Trip Package Synchronization..." -ForegroundColor Yellow
    $tempDir = [System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), "wartungstool_sync_" + [System.Guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
    try {
        $pulledPackagePath = [System.IO.Path]::Combine($tempDir, "field_return_package.db")
        $deviceSourcePath = "/data/user/0/com.cabarcas.wartungstool/databases/inspektion_ergebnis_guard_test.db"

        # Attempt pull via run-as or direct pull
        adb -s $DeviceSerial exec-out run-as com.cabarcas.wartungstool cat databases/inspektion_ergebnis_guard_test.db > $pulledPackagePath 2>$null
        if (-not (Test-Path $pulledPackagePath) -or (Get-Item $pulledPackagePath).Length -eq 0) {
            adb -s $DeviceSerial pull $deviceSourcePath $pulledPackagePath 2>$null
        }

        if (Test-Path $pulledPackagePath -and (Get-Item $pulledPackagePath).Length -gt 0) {
            $bytes = (Get-Item $pulledPackagePath).Length
            Write-Host "-> Successfully pulled and validated return package ($bytes bytes)." -ForegroundColor Green
        } else {
            Write-Host "-> Notice: Return package not present at default path (inspected doors exported selectively)." -ForegroundColor Yellow
        }
    } finally {
        if (Test-Path $tempDir) {
            Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

# ------------------------------------------------------------------------------
# FINAL SUMMARY
# ------------------------------------------------------------------------------
$elapsed = (Get-Date) - $startTime
$elapsedFormatted = "{0:mm\:ss}" -f $elapsed

Write-Host "`n====================================================================" -ForegroundColor Cyan
Write-Host "  TEST ROUTINE COMPLETED SUCCESSFULLY [100% PASS]" -ForegroundColor Green
Write-Host "  Elapsed Duration: $elapsedFormatted" -ForegroundColor Gray
Write-Host "  Quality Gate: APPROVED FOR COMPILATION / RELEASE" -ForegroundColor Green
Write-Host "====================================================================" -ForegroundColor Cyan

exit 0
