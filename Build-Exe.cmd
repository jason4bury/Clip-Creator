<# : batch part - runs the PowerShell part below. Just double-click this file.
@echo off
setlocal
set "BUILD_DIR=%~dp0"
set "BUILD_FILE=%~f0"
rem Started from PowerShell 7, PSModulePath points at PS7 modules that 5.1 can't load
set "PSModulePath="
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Invoke-Expression ([IO.File]::ReadAllText($env:BUILD_FILE))"
set "BUILD_RESULT=%ERRORLEVEL%"
echo.
pause
exit /b %BUILD_RESULT%
: end of batch part #>

# ===========================================================================
# Build-Exe.cmd - compiles src\Clip-Creator.ps1 into
# "..\Builds\<AppName> v<version>.exe", e.g. "Clip Creator v1.00.exe".
#
# Interim: once E:\Created\_shared\Build-Tool.ps1 is in place it replaces this
# file (it reads build.json instead). Until then, this builds the same way.
#
# Double-click this file (no admin rights needed). It:
#   1. sets the execution policy to Bypass for this build only (nothing
#      machine-wide changes),
#   2. checks src\Clip-Creator.ps1 has no syntax errors,
#   3. installs the ps2exe module for the current user if it's missing
#      (turning on TLS 1.2 and installing the NuGet provider first, so this
#      works unattended on a fresh PC),
#   4. reads $AppName and $AppVersion from src\Clip-Creator.ps1,
#   5. compiles the exe (STA, no console, no pop-ups for stray output or
#      errors) with the icon into the project's Builds folder, next to
#      Source and outside the repo.
#
# Replaces the hand-typed ps2exe command from the old README. Always builds
# in Windows PowerShell 5.1 (which ps2exe needs), even if you normally use
# PowerShell 7. Everything shown on screen is also written to Build-Exe.log
# (gitignored).
# ===========================================================================

$ErrorActionPreference = 'Stop'

$here = if ($env:BUILD_DIR) { $env:BUILD_DIR.TrimEnd('\') } else { (Get-Location).Path }

$scriptPath = Join-Path $here 'src\Clip-Creator.ps1'
$iconPath   = Join-Path $here 'assets\Clip-Creator.ico'
$buildsDir  = Join-Path (Split-Path -Parent $here) 'Builds'
$logPath    = Join-Path $here 'Build-Exe.log'
$failed     = $false

try { Start-Transcript -LiteralPath $logPath -Force | Out-Null } catch { Write-Verbose $_.Exception.Message }

try {
    # Process scope = this build only. Needed because ps2exe's module file won't load
    # under PowerShell's default "Restricted" policy.
    Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force
    $env:PSExecutionPolicyPreference = 'Bypass'   # and for any PowerShell ps2exe starts itself

    if (-not (Test-Path -LiteralPath $scriptPath)) {
        throw "Can't find the script to compile: $scriptPath"
    }

    # A syntax error would otherwise only show up when the exe is started
    $tokens = $null; $parseErrors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors.Count -gt 0) {
        $first = $parseErrors[0]
        throw "src\Clip-Creator.ps1 has $($parseErrors.Count) syntax error(s). First, on line $($first.Extent.StartLineNumber): $($first.Message)"
    }

    $useIcon = Test-Path -LiteralPath $iconPath
    if (-not $useIcon) {
        Write-Warning "Icon file not found at '$iconPath' - building without a custom icon."
    }

    # Pull the version straight out of the script so the exe's version metadata never
    # drifts out of sync with $AppVersion.
    $versionMatch = Select-String -LiteralPath $scriptPath -Pattern "AppVersion\s*=\s*'(\d+\.\d{2})'" | Select-Object -First 1
    if (-not $versionMatch) {
        throw "Couldn't find `$AppVersion = '<major>.<two-digit minor>' (e.g. '1.00') in $scriptPath."
    }
    $version = $versionMatch.Matches[0].Groups[1].Value

    $appName = 'Clip Creator'
    $nameMatch = Select-String -LiteralPath $scriptPath -Pattern "AppName\s*=\s*'([^']+)'" | Select-Object -First 1
    if ($nameMatch) { $appName = $nameMatch.Matches[0].Groups[1].Value }

    # Windows wants a four-part file version: 1.00 -> 1.0.0.0, 1.10 -> 1.10.0.0.
    $parts = $version.Split('.')
    $fileVersion = '{0}.{1}.0.0' -f [int]$parts[0], [int]$parts[1]

    if (-not (Test-Path -LiteralPath $buildsDir)) { New-Item -ItemType Directory -Path $buildsDir -Force | Out-Null }
    $outputPath = Join-Path $buildsDir "$appName v$version.exe"

    # The exe can't be replaced while it's running
    $running = @(Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.Path -and $_.Path -eq $outputPath })
    if ($running.Count -gt 0) { throw "$appName v$version.exe is running. Close it, then build again." }

    if (-not (Get-Module -ListAvailable -Name ps2exe)) {
        Write-Host 'ps2exe module not found - installing for the current user (one-time)...' -ForegroundColor Cyan

        # Windows PowerShell 5.1 can default to older TLS versions that the PowerShell
        # Gallery no longer accepts ("unable to resolve package source").
        try {
            [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
        } catch { Write-Verbose $_.Exception.Message }

        # Install-Module needs the NuGet provider; installing it up front avoids the
        # "NuGet provider is required to continue" prompt.
        if (-not (Get-PackageProvider -ListAvailable -Name NuGet -ErrorAction SilentlyContinue |
                  Where-Object { $_.Version -ge [version]'2.8.5.201' })) {
            Write-Host '  Installing the NuGet package provider...'
            Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Scope CurrentUser -Force | Out-Null
        }

        # -Force also skips the "untrusted repository" prompt for the PowerShell Gallery.
        Install-Module -Name ps2exe -Scope CurrentUser -Force -AllowClobber
        Write-Host '  ps2exe installed.'
        Write-Host ''
    }
    Import-Module ps2exe

    Write-Host "Building $appName v$version.exe..." -ForegroundColor Cyan
    Write-Host "  Script: $scriptPath"
    Write-Host "  Output: $outputPath"
    Write-Host ''

    $appArgs = @{
        inputFile    = $scriptPath
        outputFile   = $outputPath
        STA          = $true     # Windows Forms dialogs need a single-threaded apartment
        noConsole    = $true     # a window app, no black console box
        noOutput     = $true     # don't turn stray output into message boxes
        noError      = $true     # errors are shown in the window and the crash log
        noConfigFile = $true     # no extra .exe.config file next to the exe
        title        = $appName
        description  = 'PowerShell/WinForms tool for making a random theme clip from every movie in a folder'
        product      = $appName
        version      = $fileVersion
        company      = 'Jason Rhodes'
        copyright    = 'Copyright (c) 2026 Jason Rhodes'
    }
    if ($useIcon) { $appArgs['iconFile'] = $iconPath }
    Invoke-ps2exe @appArgs

    if (-not (Test-Path -LiteralPath $outputPath)) {
        throw "ps2exe didn't report an error, but $outputPath wasn't created."
    }
    Write-Host ''
    Write-Host "Done: $outputPath" -ForegroundColor Green
    Write-Host 'Settings and reports are in %APPDATA%\Clip Creator, so the exe and the script share them. Put ffmpeg on PATH or next to the exe.'
    Write-Host 'Some antivirus programs are wary of new ps2exe programs; if yours blocks it, allow it or use Start Clip Creator.cmd.' -ForegroundColor DarkGray
} catch {
    $failed = $true
    Write-Host ''
    Write-Host "Build failed: $($_.Exception.Message)" -ForegroundColor Red
}

try { Stop-Transcript | Out-Null } catch { Write-Verbose $_.Exception.Message }

if ($failed) { [Environment]::Exit(1) }
