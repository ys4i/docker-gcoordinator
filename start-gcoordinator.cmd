@echo off
setlocal

cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0setup-windows.ps1" -Mode VcXsrv
if errorlevel 1 (
    echo.
    echo g-coordinator setup or startup failed. Review the error above.
    pause
    exit /b 1
)
