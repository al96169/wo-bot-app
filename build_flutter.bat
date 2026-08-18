@echo off
del /f "D:\Flutter\flutter\bin\cache\lockfile" 2>nul
cd /d "F:\wo-bot\wo-bot-app"
set FLUTTER_ROOT=D:\Flutter\flutter
set PUB_HOSTED_URL=https://pub.flutter-io.cn
set FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn
set FLUTTER_PREBUILT_ENGINE_VERSION=b5990e5ccc5e325fd24f0746e7d6689bbebc7c65
set FLUTTER_SUPPRESS_ANALYTICS=true
set CHECK_FOR_UPDATES=false
"D:\Flutter\flutter\bin\cache\dart-sdk\bin\dart.exe" --packages="D:\Flutter\flutter\packages\flutter_tools\.dart_tool\package_config.json" "D:\Flutter\flutter\packages\flutter_tools\bin\flutter_tools.dart" build web --no-tree-shake-icons
