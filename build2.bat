@echo off
setlocal
cd /d "F:\wo-bot\wo-bot-app"
set FLUTTER_ROOT=D:\Flutter\flutter
set PUB_HOSTED_URL=https://pub.flutter-io.cn
set FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn
set FLUTTER_SUPPRESS_ANALYTICS=true
set CHECK_FOR_UPDATES=false
echo === Building wo-bot web ===
D:\Flutter\flutter\bin\cache\dart-sdk\bin\dart.exe D:\Flutter\flutter\bin\cache\flutter_tools.snapshot build web --no-tree-shake-icons --web-renderer canvaskit 2>&1
echo === Build exit code: %ERRORLEVEL% ===
