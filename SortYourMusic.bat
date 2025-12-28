@echo off
echo ========================================
echo        Sort Your Music
echo ========================================
echo.
echo Starting server and opening browser...
echo Close this window when you're done.
echo.
cd /d "%~dp0web"
start http://127.0.0.1:8000/
powershell -ExecutionPolicy Bypass -File "%~dp0server.ps1"
