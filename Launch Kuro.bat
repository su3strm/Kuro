@echo off
title Kuro
rem Starts Kuro. Windows will ask for administrator permission (needed for registry, services and power tweaks).
cd /d "%~dp0"
if not exist "%~dp0data\codes.db" (
    echo.
    echo  Kuro can't find its files.
    echo  Right-click the downloaded zip, choose "Extract All...", then run
    echo  "Launch Kuro.bat" from the extracted Kuro folder.
    echo.
    pause
    exit /b
)
rem Always runs Kuro.ps1: it is the file auto-update keeps up to date.
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Get-ChildItem -LiteralPath '%~dp0' -Recurse | Unblock-File" >nul 2>&1
start "" powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File "%~dp0Kuro.ps1"
