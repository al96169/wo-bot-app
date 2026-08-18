@echo off
setlocal enabledelayedexpansion
set PUB_HOSTED_URL=https://pub.flutter-io.cn
set FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn
set FLUTTER_PREBUILT_ENGINE_VERSION=b5990e5ccc5e325fd24f0746e7d6689bbebc7c65
set ANDROID_HOME=D:\ADSDK
set ANDROID_SDK_ROOT=D:\ADSDK
set DART_VM_OPTIONS=--old_gen_heap_size=3072
set PATH=D:\Flutter\flutter\bin;D:\ADSDK\emulator;D:\ADSDK\platform-tools;D:\ADSDK\tools\bin;%PATH%
cd /d F:\wo-bot\wo-bot-app

echo Killing old emulators...
adb devices 2>nul | find "emulator" >nul
if %ERRORLEVEL% EQU 0 (adb -e emu kill >nul 2>&1 & timeout /t 5 >nul)

echo Starting Flutter_API_35...
start /b D:\ADSDK\emulator\emulator.exe -avd Flutter_API_35 -no-snapshot-load

echo Waiting for boot...
:wait
adb wait-for-device >nul 2>&1
timeout /t 3 >nul
for /f "tokens=*" %%i in ('adb shell getprop sys.boot_completed 2^>nul') do set BOOTED=%%i
if not "%BOOTED%"=="1" goto wait
echo Booted. Waiting 10s...
timeout /t 10 >nul

echo.
echo Installing APK...
adb install -r build\app\outputs\flutter-apk\app-debug.apk
if %ERRORLEVEL% NEQ 0 (
    echo Install failed, trying flutter run...
    flutter run
    goto end
)

echo Launching app...
adb shell am start -n com.example.wo_bot/.MainActivity
echo.
echo App launched! Press Ctrl+C in the emulator window to stop.

:end
pause
