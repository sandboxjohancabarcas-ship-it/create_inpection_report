# WartungsTool - Android Build Script with Automated Pre-Build Integration Test Gate
param(
    [switch]$SkipTests = $false,
    [switch]$Install = $false,
    [string]$DeviceSerial = ""
)

$rootDir = Resolve-Path "$PSScriptRoot\.."
Set-Location $rootDir

Write-Host "====================================================================" -ForegroundColor Cyan
Write-Host "  WartungsTool - Android Release Build Sequence" -ForegroundColor Cyan
Write-Host "====================================================================" -ForegroundColor Cyan

# 0. Pre-Build Integration Test Routine Gatekeeper
if (-not $SkipTests) {
    Write-Host "`n[0/5] Executing Pre-Build Integration Test Routine Gatekeeper..." -ForegroundColor Cyan
    & "$PSScriptRoot\run_test_routine.ps1" -PreBuild
    if ($LASTEXITCODE -ne 0) {
        Write-Host "`nABORT: Pre-Build Integration Tests FAILED. Android release build cancelled." -ForegroundColor Red
        exit 1
    }
    Write-Host "-> Pre-Build Quality Gate: PASSED. Proceeding to compilation." -ForegroundColor Green
} else {
    Write-Host "`n[0/5] Skipping test routine (-SkipTests specified)." -ForegroundColor Yellow
}

# 1. Environment Pre-checks
Write-Host "`n[1/5] Validating environment (Java 17 & Flutter)..." -ForegroundColor Gray
try {
    $javaVersion = java -version 2>&1 | Out-String
    if ($javaVersion -notmatch '17') {
        Write-Host "Warning: JDK 17 is required for AGP 8.x. Detected version:`n$javaVersion" -ForegroundColor Yellow
    }
} catch {
    Write-Host "Error: Java not found. Please install JDK 17." -ForegroundColor Red
    exit 1
}

# 2. Kill ALL processes that could hold file locks on Gradle cache
Write-Host "[2/5] Stopping all Gradle/Java processes..." -ForegroundColor Gray
if (Test-Path "android/gradlew.bat") {
    & .\android\gradlew.bat --stop 2>$null
}
Start-Sleep -Seconds 2
# Kill Java, Kotlin, and Gradle daemon processes
Get-Process "java", "javac", "javaw", "kotlin", "gradle" -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Seconds 3

# 3. Nuke the entire transforms cache — this is the directory causing the rename failures
Write-Host "[3/5] Removing Gradle transforms cache..." -ForegroundColor Gray
$transformPaths = @(
    "$env:USERPROFILE\.gradle\caches\8.14\transforms",
    "$env:USERPROFILE\.gradle\caches\transforms-4",
    "$env:USERPROFILE\.gradle\caches\transforms-3",
    "android\.gradle"
)
foreach ($path in $transformPaths) {
    if (Test-Path $path) {
        Write-Host "  Deleting: $path" -ForegroundColor DarkGray
        cmd /c "rd /s /q `"$path`"" 2>$null
        if (Test-Path $path) {
            Remove-Item -Recurse -Force $path -ErrorAction SilentlyContinue
        }
    }
}
Start-Sleep -Seconds 2

# 4. Synchronize Version & Build Date, clean & dependencies
Write-Host "[4/5] Updating version and build date timestamp..." -ForegroundColor Gray
& "$PSScriptRoot\update_version.ps1"
flutter clean
flutter pub get

# 5. Android Build
Write-Host "[5/5] Building Android APK (Release)..." -ForegroundColor Cyan

# Ensure no stale environment variables
if ($env:GRADLE_USER_HOME) {
    Remove-Item Env:\GRADLE_USER_HOME -ErrorAction SilentlyContinue
}

# Force no-daemon, no-cache, single-threaded via environment
$env:GRADLE_OPTS = "-Dorg.gradle.daemon=false -Dorg.gradle.parallel=false -Dorg.gradle.caching=false -Dorg.gradle.workers.max=1 -Dorg.gradle.unsafe.watch-fs=false"

# Final kill of any Java processes that may have started during flutter pub get
Get-Process "java", "javaw" -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Seconds 3

# Delete transforms one more time right before build
$transformMain = "$env:USERPROFILE\.gradle\caches\8.14\transforms"
if (Test-Path $transformMain) {
    cmd /c "rd /s /q `"$transformMain`"" 2>$null
}

# Build with --no-build-cache flag
flutter build apk --release --obfuscate --split-debug-info=build/app/outputs/symbols

if ($LASTEXITCODE -eq 0) {
    Write-Host "Android build completed successfully." -ForegroundColor Green
    $apkPath = "build\app\outputs\flutter-apk\app-release.apk"
    Write-Host "APK is located in: $apkPath" -ForegroundColor Gray

    if ($Install) {
        Write-Host "`nInstalling APK to connected Android device..." -ForegroundColor Cyan
        $adbArgs = @()
        if (-not [string]::IsNullOrWhiteSpace($DeviceSerial)) {
            $adbArgs += @("-s", $DeviceSerial)
        }
        $adbArgs += @("install", "-r", $apkPath)
        adb @adbArgs
        if ($LASTEXITCODE -eq 0) {
            Write-Host "APK installed successfully onto Android device!" -ForegroundColor Green
        } else {
            Write-Host "Installation via ADB failed." -ForegroundColor Red
        }
    }
} else {
    Write-Host "Build failed. The antivirus is likely still locking Gradle cache files." -ForegroundColor Red
    Write-Host "Ask Jana to add these AV exclusions:" -ForegroundColor Yellow
    Write-Host "  - $env:USERPROFILE\.gradle" -ForegroundColor White
    Write-Host "  - $rootDir" -ForegroundColor White
    Write-Host "  - Process: java.exe" -ForegroundColor White
}