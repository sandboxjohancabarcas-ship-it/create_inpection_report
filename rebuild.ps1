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
        # Use cmd /c rd for more aggressive directory removal on Windows
        cmd /c "rd /s /q `"$path`"" 2>$null
        # Fallback with PowerShell if cmd failed
        if (Test-Path $path) {
            Remove-Item -Recurse -Force $path -ErrorAction SilentlyContinue
        }
    }
}
Start-Sleep -Seconds 2

# 4. Flutter clean & dependencies
Write-Host "[4/5] Running flutter clean and fetching dependencies..." -ForegroundColor Gray
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
    Write-Host "APK is located in: build\app\outputs\flutter-apk\app-release.apk" -ForegroundColor Gray
} else {
    Write-Host "Build failed. The antivirus is likely still locking Gradle cache files." -ForegroundColor Red
    Write-Host "Ask Jana to add these AV exclusions:" -ForegroundColor Yellow
    Write-Host "  - $env:USERPROFILE\.gradle" -ForegroundColor White
    Write-Host "  - $PSScriptRoot" -ForegroundColor White
    Write-Host "  - Process: java.exe" -ForegroundColor White
}