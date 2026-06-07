# Professional Rebuild Script for WartungsTool
Write-Host "Stopping Gradle Daemons..." -ForegroundColor Cyan
./android/gradlew --stop

Write-Host "Clearing stale caches and build artifacts..." -ForegroundColor Cyan
if (Test-Path "android/.gradle") { Remove-Item -Recurse -Force "android/.gradle" }
if (Test-Path "android/.kotlin") { Remove-Item -Recurse -Force "android/.kotlin" }
if (Test-Path "build") { Remove-Item -Recurse -Force "build" }

Write-Host "Refreshing Flutter dependencies..." -ForegroundColor Cyan
flutter clean
flutter pub get

Write-Host "Starting Release Build..." -ForegroundColor Green
flutter build apk --release