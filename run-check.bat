@echo off
setlocal
cd /d "%~dp0"
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0baseline-check.ps1" %*
if errorlevel 1 echo Check failed. See the error message above.
pause
