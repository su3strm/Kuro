@echo off
title Kuro
rem Starts Kuro. Windows will ask for administrator permission (needed for registry, services and power tweaks).
rem The first time it runs from a downloaded folder it installs Kuro (Desktop + Start menu shortcuts) and starts it.
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
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Get-ChildItem -LiteralPath '%~dp0' -Recurse | Unblock-File" >nul 2>&1
set "KURO_HOME=%LOCALAPPDATA%\Programs\Kuro\"
if /i not "%~dp0"=="%KURO_HOME%" if exist "%~dp0Install-Kuro.ps1" (
    start "" powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File "%~dp0Install-Kuro.ps1"
    exit /b
)
rem Always runs Kuro.ps1: it is the file auto-update keeps up to date.
start "" powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File "%~dp0Kuro.ps1"
