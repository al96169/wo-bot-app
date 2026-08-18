@echo off
setlocal enabledelayedexpansion
set PUB_HOSTED_URL=https://pub.flutter-io.cn
set FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn
set FLUTTER_PREBUILT_ENGINE_VERSION=b5990e5ccc5e325fd24f0746e7d6689bbebc7c65
set ANDROID_HOME=D:\ADSDK
set ANDROID_SDK_ROOT=D:\ADSDK
set DART_VM_OPTIONS=--old_gen_heap_size=4096
set PATH=D:\Flutter\flutter\bin;D:\ADSDK\emulator;D:\ADSDK\platform-tools;D:\ADSDK\tools\bin;%PATH%
cd /d F:\wo-bot\wo-bot-app

set LOGFILE=debug_log_%date:~0,4%%date:~5,2%%date:~8,2%_%time:~0,2%%time:~3,2%%time:~6,2%.txt
set LOGFILE=%LOGFILE: =0%

echo ============================================
echo   Debug Script - Saving to %LOGFILE%
echo ============================================

echo [1/4] Killing old emulators...
adb devices 2>nul | find "emulator" >nul
if %ERRORLEVEL% EQU 0 (adb -e emu kill >nul 2>&1 & timeout /t 3 >nul)

echo [2/4] Starting emulator...
start /b D:\ADSDK\emulator\emulator.exe -avd Flutter_API_35 -no-snapshot-load

echo [3/4] Waiting for emulator boot...
:wait
adb wait-for-device >nul 2>&1
timeout /t 3 >nul
for /f "tokens=*" %%i in ('adb shell getprop sys.boot_completed 2^>nul') do set BOOTED=%%i
if not "%BOOTED%"=="1" goto wait
echo Booted.
timeout /t 5 >nul

echo [4/4] Installing APK and launching...
adb install -r build\app\outputs\flutter-apk\app-debug.apk
adb shell am start -n com.example.wo_bot/.MainActivity

echo.
echo ============================================
echo   Logging started. Capture all [WS] [CM] [DevicePage]
echo   Press Ctrl+C to stop. Log saved to %LOGFILE%
echo ============================================
echo.

adb logcat -c
adb logcat flutter:I *:F > %LOGFILE%

pause
