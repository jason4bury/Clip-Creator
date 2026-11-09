@echo off
rem Starts Clip Creator from the script. The execution-policy bypass applies to this run only;
rem no Windows settings are changed. Settings and reports are kept in %APPDATA%\Clip Creator.
cd /d "%~dp0"
start "" powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File "%~dp0src\Clip-Creator.ps1"
