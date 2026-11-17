@echo off
title Build Kuro.exe
rem Turns Kuro.ps1 into Kuro.exe using the free PS2EXE module (needs internet the first time).
cd /d "%~dp0"
echo Installing / updating the PS2EXE module...
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "if (-not (Get-Module -ListAvailable ps2exe)) { [Net.ServicePointManager]::SecurityProtocol='Tls12'; Install-PackageProvider NuGet -MinimumVersion 2.8.5.201 -Force -Scope CurrentUser | Out-Null; Install-Module ps2exe -Scope CurrentUser -Force }"
echo Building Kuro.exe ...
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Import-Module ps2exe; Invoke-ps2exe -inputFile '.\Kuro.ps1' -outputFile '.\Kuro.exe' -iconFile '.\assets\Kuro.ico' -noConsole -requireAdmin -STA -x64 -title 'Kuro' -description 'Kuro FPS Optimizer' -product 'Kuro' -company 'Kuro' -version '1.8.0.0'"
if exist Kuro.exe (
    echo.
    echo Done! Kuro.exe is ready. Keep it next to the "data" and "assets" folders.
) else (
    echo.
    echo Build failed - see the messages above.
)
pause
