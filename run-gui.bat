@echo off
setlocal
cd /d "%~dp0"
powershell.exe -NoLogo -NoProfile -STA -WindowStyle Hidden -ExecutionPolicy Bypass -File "%~dp0baseline-gui.ps1"
if errorlevel 1 (
    echo Unable to start the interface. Keep baseline-gui.ps1 and baseline-check.ps1 in the same folder.
    pause
)
