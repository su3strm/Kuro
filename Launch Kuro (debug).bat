@echo off
title Kuro - debug
rem Use this if Kuro does not open. It keeps a PowerShell window open that shows any error.
cd /d "%~dp0"
if not exist "%~dp0Kuro.ps1" (
    echo Kuro.ps1 was not found next to this file. Extract the whole zip first.
    pause
    exit /b
)
echo Unblocking downloaded files...
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Get-ChildItem -LiteralPath '%~dp0' -Recurse | Unblock-File"
echo Starting Kuro in debug mode. Click YES on the Windows permission prompt.
echo A second blue PowerShell window will open - any red error text will appear there.
powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File "%~dp0Kuro.ps1" -debug
echo.
echo If nothing opened, send a screenshot of this window.
pause
