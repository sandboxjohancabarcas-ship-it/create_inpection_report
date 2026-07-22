# Clean problematic Gradle transform cache
$gradleCache = "$env:USERPROFILE\.gradle\caches\8.14\transforms"
$problematic = Join-Path $gradleCache "6704c874f8eff0fc1bfe798957e56b0b"
if (Test-Path $problematic) {
    Write-Host "Removing specific transform directory: $problematic"
    Remove-Item -Recurse -Force $problematic
} else {
    Write-Host "Specific transform directory not found. Removing entire transforms folder just in case."
    if (Test-Path $gradleCache) {
        Remove-Item -Recurse -Force $gradleCache
    }
}
Write-Host "Gradle cache cleanup completed."
