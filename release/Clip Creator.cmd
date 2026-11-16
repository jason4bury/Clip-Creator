@echo off
rem Clip Creator - double-click to start it.
rem Each time, this makes (or refreshes) the Clip Creator shortcut in this folder and in the Start menu,
rem then starts Clip Creator from it. After the first run you can use the shortcut, the Start menu or
rem a pinned taskbar button instead: they start Clip Creator without a console window.
rem The execution-policy bypass applies to Clip Creator's own run only; no Windows settings are changed.
rem If Clip Creator doesn't open, run   "Clip Creator.cmd" debug   to start it in this window and see any errors.
setlocal
set "PS=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
if /i "%~1"=="debug" (
    "%PS%" -NoProfile -ExecutionPolicy Bypass -STA -File "%~dp0Clip-Creator.ps1"
    pause
    exit /b
)
"%PS%" -NoProfile -ExecutionPolicy Bypass -File "%~dp0New-ClipCreatorShortcut.ps1" -Launch
if errorlevel 1 pause
