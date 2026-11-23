@echo off
rem Installs Nakbox with install.ps1 from this folder. Options are passed on,
rem for example: "Install Nakbox.bat" -Target wsl -InstallDir D:\Nakbox
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0install.ps1" %*
if errorlevel 1 exit /b %errorlevel%
pause
