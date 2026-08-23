<#
.SYNOPSIS
    Interactive runner script for WartungsTool on Windows.
.DESCRIPTION
    - Closes any running instances of WartungsTool to avoid database/file locks.
    - Prompts user to choose between a Fresh/Clean DB run or Persistent DB run.
    - Handles DB and log cleanup if Clean mode is selected.
    - Launches `flutter run -d Windows`.
.PARAMETER Mode
    Optional. Value: 'clean' (or 'c') or 'persistent' (or 'p'). If omitted, prompts interactively.
.PARAMETER Release
    Optional switch to launch in Release mode instead of Debug.
#>
param (
    [ValidateSet("clean", "persistent", "c", "p", "")]
    [string]$Mode = "",
    [switch]$Release
)

Set-Location $PSScriptRoot

Write-Host ""
Write-Host "======================================================" -ForegroundColor Cyan
Write-Host "        WartungsTool - Windows Launcher               " -ForegroundColor Cyan
Write-Host "======================================================" -ForegroundColor Cyan
Write-Host ""

# 1. Close any running instances of the app to release DB / file locks
Write-Host "[1/3] Checking for running application instances..." -ForegroundColor Yellow
$runningProcesses = Get-Process -Name "WartungsTool" -ErrorAction SilentlyContinue
if ($runningProcesses) {
    Write-Host "  Found running WartungsTool instance(s). Closing now..." -ForegroundColor Yellow
    $runningProcesses | Stop-Process -Force
    Start-Sleep -Milliseconds 1000
    Write-Host "  App instances closed successfully." -ForegroundColor Green
} else {
    Write-Host "  No running instances found." -ForegroundColor DarkGray
}

Get-Process -Name "MSBuild" -ErrorAction SilentlyContinue | Stop-Process -Force

# 2. Ask user for launch mode if not passed via parameter
if ([string]::IsNullOrWhiteSpace($Mode)) {
    Write-Host ""
    Write-Host "Select Database Mode:" -ForegroundColor White
    Write-Host "  [1] Fresh / Clean Start " -ForegroundColor Green -NoNewline
    Write-Host "-> Wipes local databases & logs (brand new state)" -ForegroundColor Gray
    Write-Host "  [2] Persistent Start    " -ForegroundColor Cyan -NoNewline
    Write-Host "-> Keeps current database & saved inspections" -ForegroundColor Gray
    Write-Host "  [Q] Quit / Cancel" -ForegroundColor Red
    Write-Host ""

    do {
        $choice = Read-Host "Enter selection [1 / 2 / Q] (Default: 2)"
        if ([string]::IsNullOrWhiteSpace($choice)) { $choice = "2" }
        $choice = $choice.Trim().ToUpper()
    } while ($choice -notin @("1", "2", "C", "P", "Q"))

    switch ($choice) {
        "1" { $Mode = "clean" }
        "C" { $Mode = "clean" }
        "2" { $Mode = "persistent" }
        "P" { $Mode = "persistent" }
        "Q" {
            Write-Host "Launch cancelled." -ForegroundColor Yellow
            exit 0
        }
    }
}

# Normalize mode
if ($Mode -in @("c", "clean")) {
    $Mode = "clean"
} else {
    $Mode = "persistent"
}

Write-Host ""

# 3. Clean databases if clean mode selected
if ($Mode -eq "clean") {
    Write-Host "[2/3] Performing CLEAN reset of databases and logs..." -ForegroundColor Magenta
    
    $filesToDelete = @(
        "$PSScriptRoot\.dart_tool\sqflite_common_ffi\databases\door_inspection.db",
        "$env:APPDATA\Cabarcas WartungTool\WartungsTool\working.db",
        "$PSScriptRoot\working.db",
        "$PSScriptRoot\migration_protocol.log"
    )

    $deletedCount = 0
    foreach ($file in $filesToDelete) {
        if (Test-Path $file) {
            Remove-Item -Path $file -Force -ErrorAction SilentlyContinue
            Write-Host "  [Deleted] $file" -ForegroundColor DarkYellow
            $deletedCount++
        }
    }

    if ($deletedCount -eq 0) {
        Write-Host "  No previous database files were found to delete." -ForegroundColor DarkGray
    } else {
        Write-Host "  Databases reset successfully. Fresh schema & catalog will be seeded on startup." -ForegroundColor Green
    }
} else {
    Write-Host "[2/3] Preserving existing database and inspection data." -ForegroundColor Cyan
}

# 4. Launch Flutter
Write-Host ""
Write-Host "[3/3] Launching application on Windows..." -ForegroundColor Cyan
$flutterArgs = @("run", "-d", "Windows")
if ($Release) {
    $flutterArgs += "--release"
}

Write-Host "Executing: flutter $($flutterArgs -join ' ')" -ForegroundColor DarkGray
Write-Host "------------------------------------------------------" -ForegroundColor DarkCyan
Write-Host ""

& flutter @flutterArgs
