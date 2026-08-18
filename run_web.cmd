@echo off
title wo-bot Web Debug
setlocal enabledelayedexpansion

echo ============================================
echo   wo-bot-app Web Debug
echo   Mock robot: ws://localhost:18768
echo   Web page: http://localhost:58082
echo ============================================

echo.
echo Starting mock robot (display/tts/gimbal)...
start "MockRobot" cmd /c "cd /d F:\wo-bot\wo-bot-app && python mock_robot.py && pause"
timeout /t 3 >nul

echo Starting web server on port 58082...
start "WebServer" cmd /c "cd /d F:\wo-bot\wo-bot-app\build\web && python -m http.server 58082"
timeout /t 2 >nul

echo Opening browser...
start "" http://localhost:58082

echo.
echo ============================================
echo   TEST MOCK:  manually add localhost:18768
echo   REAL ROBOT: manually add 192.168.1.47:8765
echo   Press F12 for DevTools console.
echo   Close all windows to stop.
echo ============================================
pause
