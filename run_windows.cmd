@echo off
setlocal enabledelayedexpansion
set PUB_HOSTED_URL=https://pub.flutter-io.cn
set FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn
set FLUTTER_PREBUILT_ENGINE_VERSION=b5990e5ccc5e325fd24f0746e7d6689bbebc7c65
set PATH=D:\Flutter\flutter\bin;%PATH%
cd /d F:\wo-bot\wo-bot-app
echo === Project Dir ===
cd
echo === Flutter Version ===
flutter --version
echo === Devices ===
flutter devices
echo === Starting App ===
flutter run -d windows
pause
