<#
.SYNOPSIS
    Clip Creator: makes one random MP4 clip from every movie in a folder with FFmpeg.

.DESCRIPTION
    A Windows Forms front end for FFmpeg. For each movie it picks a random point
    (away from the opening and closing minutes), cuts a short clip and saves it as
    <Output>\<movie folder>\backdrops\theme.mp4, the layout Jellyfin, Emby and Kodi
    use for theme videos. A colour HTML report is written after every run.

    Settings and reports are kept in %APPDATA%\Clip Creator\.

.NOTES
    Version:   1.00
    Author:    Jason Rhodes
    Licence:   MIT, Copyright (c) 2026 Jason Rhodes
    Repo:      https://github.com/jason4bury/Clip-Creator
    Requires:  Windows PowerShell 5.1 (or PowerShell 7), ffmpeg.exe and ffprobe.exe
               on PATH or beside the script/exe.
#>

$AppName    = 'Clip Creator'
$AppVersion = '1.00'
$Copyright  = 'Copyright (c) 2026 Jason Rhodes'
$RepoUrl    = 'https://github.com/jason4bury/Clip-Creator'

# ---------------------------------------------------------------------------
# Start-up
# ---------------------------------------------------------------------------

$script:IsExe = [System.Diagnostics.Process]::GetCurrentProcess().ProcessName -notmatch '^(powershell|pwsh|powershell_ise)$'

# Windows Forms dialogs need a single-threaded apartment. The exe is built with -STA;
# a script started some other way is restarted in Windows PowerShell with -STA.
if (-not $script:IsExe -and [System.Threading.Thread]::CurrentThread.GetApartmentState() -ne 'STA' -and $PSCommandPath) {
    Start-Process -FilePath 'powershell.exe' -WindowStyle Hidden -ArgumentList @(
        '-NoProfile', '-ExecutionPolicy', 'Bypass', '-STA', '-File', ('"{0}"' -f $PSCommandPath))
    return
}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# The process is DPI-aware and the window scales itself: every pixel size goes through
# S below (AutoScaleMode is None), and fonts are in points so Windows scales them. This
# must run before the first window is created, and gives the script and the exe the
# same sharp layout instead of a stretched bitmap.
try {
    if (-not ('ClipCreatorNative' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class ClipCreatorNative {
    [DllImport("user32.dll")]
    public static extern bool SetProcessDPIAware();
}
'@
    }
    [void][ClipCreatorNative]::SetProcessDPIAware()
} catch { Write-Verbose "DPI awareness not set: $($_.Exception.Message)" }

# Screen scale: 1.0 at 100%, 1.5 at 150%
$script:Scale = 1.0
try {
    $screenGraphics = [System.Drawing.Graphics]::FromHwnd([IntPtr]::Zero)
    try { $script:Scale = $screenGraphics.DpiX / 96 } finally { $screenGraphics.Dispose() }
} catch { Write-Verbose "Screen scale not read: $($_.Exception.Message)" }

function S([double]$n) {
    # A pixel size at 100%, scaled for this screen
    [int][Math]::Round($n * $script:Scale)
}

# Modern Windows folder picker (the Explorer-style one with an address bar). It accepts
# typed or pasted paths, mapped drives and UNC shares such as \\NAS\Movies.
try {
    if (-not ('ClipCreatorFolderPicker' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

public static class ClipCreatorFolderPicker {
    [ComImport, Guid("DC1C5A9C-E88A-4dde-A5A1-60F82A20AEF7")]
    private class FileOpenDialogCoClass { }

    [ComImport, Guid("d57c7288-d4ad-4768-be02-9d969532d960"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    private interface IFileOpenDialog {
        [PreserveSig] int Show(IntPtr hwndOwner);
        void SetFileTypes(uint count, IntPtr filterSpec);
        void SetFileTypeIndex(uint index);
        void GetFileTypeIndex(out uint index);
        void Advise(IntPtr events, out uint cookie);
        void Unadvise(uint cookie);
        void SetOptions(uint options);
        void GetOptions(out uint options);
        void SetDefaultFolder(IShellItem item);
        void SetFolder(IShellItem item);
        void GetFolder(out IShellItem item);
        void GetCurrentSelection(out IShellItem item);
        void SetFileName([MarshalAs(UnmanagedType.LPWStr)] string name);
        void GetFileName([MarshalAs(UnmanagedType.LPWStr)] out string name);
        void SetTitle([MarshalAs(UnmanagedType.LPWStr)] string title);
        void SetOkButtonLabel([MarshalAs(UnmanagedType.LPWStr)] string text);
        void SetFileNameLabel([MarshalAs(UnmanagedType.LPWStr)] string label);
        void GetResult(out IShellItem item);
    }

    [ComImport, Guid("43826D1E-E718-42EE-BC55-A1E261C37BFA"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    private interface IShellItem {
        void BindToHandler(IntPtr bindContext, ref Guid handler, ref Guid riid, out IntPtr result);
        void GetParent(out IShellItem parent);
        void GetDisplayName(uint sigdnName, [MarshalAs(UnmanagedType.LPWStr)] out string name);
    }

    [DllImport("shell32.dll", CharSet = CharSet.Unicode, PreserveSig = false)]
    private static extern void SHCreateItemFromParsingName(string path, IntPtr bindContext,
        [MarshalAs(UnmanagedType.LPStruct)] Guid riid, out IShellItem item);

    private const uint FOS_PICKFOLDERS = 0x20;
    private const uint FOS_FORCEFILESYSTEM = 0x40;
    private const uint FOS_PATHMUSTEXIST = 0x800;
    private const uint SIGDN_FILESYSPATH = 0x80058000;

    // Returns the chosen folder, or null if the user cancelled.
    public static string Pick(IntPtr owner, string title, string initialFolder) {
        IFileOpenDialog dialog = (IFileOpenDialog)new FileOpenDialogCoClass();
        try {
            uint options;
            dialog.GetOptions(out options);
            dialog.SetOptions(options | FOS_PICKFOLDERS | FOS_FORCEFILESYSTEM | FOS_PATHMUSTEXIST);
            if (!string.IsNullOrEmpty(title)) { dialog.SetTitle(title); }
            if (!string.IsNullOrEmpty(initialFolder) && System.IO.Directory.Exists(initialFolder)) {
                try {
                    IShellItem folder;
                    SHCreateItemFromParsingName(initialFolder, IntPtr.Zero, typeof(IShellItem).GUID, out folder);
                    dialog.SetFolder(folder);
                } catch (Exception) { }
            }
            if (dialog.Show(owner) != 0) { return null; }
            IShellItem result;
            dialog.GetResult(out result);
            string path;
            result.GetDisplayName(SIGDN_FILESYSPATH, out path);
            return path;
        } finally {
            Marshal.ReleaseComObject(dialog);
        }
    }
}
'@
    }
} catch { Write-Verbose "Modern folder picker unavailable: $($_.Exception.Message)" }

[System.Windows.Forms.Application]::EnableVisualStyles()

# ---------------------------------------------------------------------------
# Settings, data folder and constants
# ---------------------------------------------------------------------------

$script:DataDir     = Join-Path ([Environment]::GetFolderPath('ApplicationData')) $AppName
$script:SettingsFile = Join-Path $script:DataDir 'settings.json'
$script:ReportsDir  = Join-Path $script:DataDir 'Reports'
$script:LogsDir     = Join-Path $script:DataDir 'Logs'
$script:KeepReports = 50

$script:DefaultFileTypes = 'mkv, mp4, avi, mov, m4v, wmv, mpg, mpeg, ts, m2ts, webm'

# Folders media servers use for extras and theme media. Videos inside them are never
# treated as movies, so a second run can't make clips of clips or trailers.
$script:SkipFolderNames = @(
    'backdrops', 'extras', 'extrafanart', 'trailers', 'featurettes', 'behind the scenes',
    'deleted scenes', 'interviews', 'scenes', 'shorts', 'sample', 'samples', 'other',
    'theme-music', '.actors', '$recycle.bin', 'system volume information', '@eadir', '#recycle')

# File names that mark an extra rather than the movie (Jellyfin/Plex/Kodi naming)
$script:SkipFilePattern = '(^theme$)|(^sample$)|([-._ ](trailer|sample|featurette|behindthescenes|deleted|interview|scene|short|other|extra)$)'

$script:State = @{
    Running         = $false
    CancelRequested = $false
    StopNow         = $false
    CloseWhenDone   = $false
    CurrentProcess  = $null
}

function Get-DefaultSetting {
    [ordered]@{
        MoviesFolder      = ''
        OutputFolder      = ''
        ClipLength        = 10
        AvoidSeconds      = 60
        FileTypes         = $script:DefaultFileTypes
        IncludeSubfolders = $true
        ExistingClip      = 'Ask'
    }
}

function Import-Setting {
    $settings = Get-DefaultSetting
    if (Test-Path -LiteralPath $script:SettingsFile) {
        try {
            $saved = Get-Content -LiteralPath $script:SettingsFile -Raw -Encoding UTF8 | ConvertFrom-Json
            foreach ($name in @($settings.Keys)) {
                if ($saved.PSObject.Properties.Name -contains $name -and $null -ne $saved.$name) {
                    $settings[$name] = $saved.$name
                }
            }
        } catch {
            Write-Verbose "Settings file unreadable, using defaults: $($_.Exception.Message)"
        }
    }
    $settings
}

function Export-Setting([System.Collections.IDictionary]$Settings) {
    try {
        [void][System.IO.Directory]::CreateDirectory($script:DataDir)
        $json = [pscustomobject]$Settings | ConvertTo-Json
        [System.IO.File]::WriteAllText($script:SettingsFile, $json, [System.Text.UTF8Encoding]::new($false))
    } catch {
        Write-Verbose "Settings not saved: $($_.Exception.Message)"
    }
}

function Write-CrashLog([string]$Context, $ErrorRecord) {
    try {
        [void][System.IO.Directory]::CreateDirectory($script:LogsDir)
        $line = '[{0:yyyy-MM-dd HH:mm:ss}] {1} v{2}: {3}{4}{5}{4}' -f (Get-Date), $Context, $AppVersion,
            $ErrorRecord.Exception.Message, [Environment]::NewLine, $ErrorRecord.ScriptStackTrace
        [System.IO.File]::AppendAllText((Join-Path $script:LogsDir 'crash.log'), $line)
    } catch { Write-Verbose $_.Exception.Message }
}

# ---------------------------------------------------------------------------
# Helpers that don't touch the window (kept separate so they can be tested)
# ---------------------------------------------------------------------------

function Find-Tool([string]$Name) {
    # Beside the script or exe first, then PATH. PS2EXE can leave $PSScriptRoot empty,
    # so the exe's own folder is checked as well.
    $folders = New-Object System.Collections.Generic.List[string]
    if (-not [string]::IsNullOrWhiteSpace($PSScriptRoot)) { $folders.Add($PSScriptRoot) }
    try {
        $exeFolder = [System.IO.Path]::GetDirectoryName([System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName)
        if (-not [string]::IsNullOrWhiteSpace($exeFolder)) { $folders.Add($exeFolder) }
    } catch { Write-Verbose $_.Exception.Message }

    foreach ($folder in ($folders | Select-Object -Unique)) {
        $candidate = [System.IO.Path]::Combine($folder, "$Name.exe")
        if ([System.IO.File]::Exists($candidate)) { return $candidate }
    }

    $command = Get-Command "$Name.exe" -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($command -and -not [string]::IsNullOrWhiteSpace($command.Path)) { return $command.Path }
    return $null
}

function ConvertTo-ExtensionList([string]$Text) {
    # "mkv, .MP4; avi" -> .mkv .mp4 .avi
    $list = @($Text -split '[,;\s]+' | Where-Object { $_ } | ForEach-Object {
        '.' + $_.Trim().TrimStart('*').TrimStart('.').ToLowerInvariant()
    } | Where-Object { $_ -match '^\.[a-z0-9]+$' } | Select-Object -Unique)
    , $list
}

function Format-TimeLeft([double]$Seconds) {
    if ($Seconds -lt 0) { $Seconds = 0 }
    $span = [TimeSpan]::FromSeconds([Math]::Round($Seconds))
    '{0}:{1:mm}:{1:ss}' -f [int][Math]::Floor($span.TotalHours), $span
}

function Get-ClipStart([double]$Duration, [int]$ClipLength, [int]$AvoidSeconds) {
    # A random whole second to start from, keeping clear of the opening and closing
    # $AvoidSeconds when the movie is long enough. Returns -1 if it's shorter than a clip.
    if ($Duration -le $ClipLength) { return -1 }
    $min = 0
    $max = [int][Math]::Floor($Duration - $ClipLength)
    if ($AvoidSeconds -gt 0 -and $Duration -gt ($ClipLength + (2 * $AvoidSeconds))) {
        $min = $AvoidSeconds
        $max = [int][Math]::Floor($Duration - $ClipLength - $AvoidSeconds)
    }
    if ($max -le $min) { return $min }
    Get-Random -Minimum $min -Maximum ($max + 1)
}

function Test-IsExtraFile([string]$FileName) {
    $base = [System.IO.Path]::GetFileNameWithoutExtension($FileName).ToLowerInvariant()
    return $base -match $script:SkipFilePattern
}

function Test-IsInside([string]$Path, [string]$Folder) {
    # True when $Path is $Folder or anywhere below it
    if ([string]::IsNullOrWhiteSpace($Path) -or [string]::IsNullOrWhiteSpace($Folder)) { return $false }
    $p = $Path.TrimEnd('\', '/')
    $f = $Folder.TrimEnd('\', '/')
    return $p.Equals($f, [System.StringComparison]::OrdinalIgnoreCase) -or
           $p.StartsWith($f + '\', [System.StringComparison]::OrdinalIgnoreCase) -or
           $p.StartsWith($f + '/', [System.StringComparison]::OrdinalIgnoreCase)
}

function Get-RelativeFolder([string]$Folder, [string]$Root) {
    # The part of $Folder below $Root, or '' when it is $Root. Both are full paths.
    $f = $Folder.TrimEnd('\', '/')
    $r = $Root.TrimEnd('\', '/')
    if ($f.Equals($r, [System.StringComparison]::OrdinalIgnoreCase)) { return '' }
    if ($f.StartsWith($r + '\', [System.StringComparison]::OrdinalIgnoreCase) -or
        $f.StartsWith($r + '/', [System.StringComparison]::OrdinalIgnoreCase)) { return $f.Substring($r.Length + 1) }
    return ''
}

function Get-ClipPlan {
    <#
        Works out one clip per movie from a list of video files.
        - A file directly in the movies folder gets a folder named after the file:
          <Output>\<file name>\backdrops\theme.mp4
        - Files in a sub-folder share that folder's clip:
          <Output>\<sub-folder path>\backdrops\theme.mp4
          If a folder holds more than one video (CD1/CD2, two editions), the largest is
          used and the others are listed as skipped.
        Returns objects with File, Movie (path shown in the report), Target and Skip
        (a reason, or $null for the file to use).
    #>
    param(
        [object[]]$Files,      # objects with FullName, Name, DirectoryName, Length
        [string]$MoviesFolder,
        [string]$OutputFolder
    )
    $root = [System.IO.Path]::GetFullPath($MoviesFolder).TrimEnd('\', '/')
    $output = [System.IO.Path]::GetFullPath($OutputFolder)
    $groups = [ordered]@{}

    foreach ($file in $Files) {
        $relative = Get-RelativeFolder ([System.IO.Path]::GetFullPath($file.DirectoryName)) $root
        if ($relative -eq '') {
            $name = ([System.IO.Path]::GetFileNameWithoutExtension($file.Name)) -replace '[\\/:*?"<>|]', '_'
            $targetFolder = [System.IO.Path]::Combine($output, $name.Trim())
            $display = $file.Name
        } else {
            $targetFolder = [System.IO.Path]::Combine($output, $relative)
            $display = [System.IO.Path]::Combine($relative, $file.Name)
        }
        $target = [System.IO.Path]::Combine($targetFolder, 'backdrops', 'theme.mp4')
        $key = $target.ToLowerInvariant()
        if (-not $groups.Contains($key)) { $groups[$key] = New-Object System.Collections.Generic.List[object] }
        $groups[$key].Add([pscustomobject]@{ File = $file; Movie = $display; Target = $target; Skip = $null })
    }

    foreach ($key in $groups.Keys) {
        $items = @($groups[$key] | Sort-Object { [int64]$_.File.Length } -Descending)
        for ($i = 1; $i -lt $items.Count; $i++) {
            $items[$i].Skip = "Another video in this folder was used: $($items[0].File.Name) (the largest)."
        }
        $items[0]
        if ($items.Count -gt 1) { $items[1..($items.Count - 1)] }
    }
}

function Get-MovieFile {
    <#
        Lists video files under $Folder without stopping on folders it can't read.
        Skips extras and theme folders, anything inside $ExcludeFolder (the output
        folder, if it's inside the movies folder) and folder links (junction loops).
        $OnProgress is called every few hundred files so the window can stay responsive
        and the scan can be stopped.
    #>
    param(
        [string]$Folder,
        [string[]]$Extensions,
        [bool]$Recurse,
        [string]$ExcludeFolder,
        [scriptblock]$OnProgress
    )
    $found = New-Object System.Collections.Generic.List[object]
    $unreadable = 0
    $seen = 0
    $pending = New-Object System.Collections.Generic.Stack[string]
    $pending.Push($Folder)

    while ($pending.Count -gt 0) {
        $dir = $pending.Pop()
        try {
            $info = New-Object System.IO.DirectoryInfo($dir)
            foreach ($file in $info.EnumerateFiles()) {
                $seen++
                if ($OnProgress -and ($seen % 250) -eq 0) {
                    if (& $OnProgress $seen) { return [pscustomobject]@{ Files = $found; Unreadable = $unreadable; Stopped = $true } }
                }
                if ($Extensions -notcontains $file.Extension.ToLowerInvariant()) { continue }
                if (Test-IsExtraFile $file.Name) { continue }
                $found.Add($file)
            }
            if ($Recurse) {
                $subFolders = @($info.EnumerateDirectories() | Sort-Object Name -Descending)
                foreach ($sub in $subFolders) {
                    if (($sub.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) { continue }
                    if ($script:SkipFolderNames -contains $sub.Name.ToLowerInvariant()) { continue }
                    if ($ExcludeFolder -and (Test-IsInside $sub.FullName $ExcludeFolder)) { continue }
                    $pending.Push($sub.FullName)
                }
            }
        } catch {
            $unreadable++
            Write-Verbose "Can't read $dir : $($_.Exception.Message)"
        }
    }
    [pscustomobject]@{ Files = $found; Unreadable = $unreadable; Stopped = $false }
}

function Get-FfmpegArgumentList([int]$Start, [int]$ClipLength, [string]$InputFile, [string]$OutputFile) {
    # -map 0:V:0 takes the first real video stream (not cover art), the first audio
    # track if there is one. yuv420p and stereo AAC keep the clip playable in browsers
    # and on TVs even when the movie is 10-bit HDR with 5.1 or 7.1 sound.
    # The output is written as MP4 to a .part file and renamed when it's complete.
    ('-hide_banner -nostdin -loglevel error -ss {0} -i "{1}" -t {2} -map 0:V:0 -map "0:a:0?" ' +
     '-c:v libx264 -preset fast -crf 20 -pix_fmt yuv420p -c:a aac -b:a 192k -ac 2 ' +
     '-movflags +faststart -f mp4 -y "{3}"') -f $Start, $InputFile, $ClipLength, $OutputFile
}

function ConvertFrom-ProbeDuration([string]$Text) {
    # ffprobe prints the stream and container durations, one per line; some files say
    # N/A for one of them. The longest readable value wins.
    $best = 0.0
    foreach ($line in ($Text -split "`r?`n")) {
        $value = 0.0
        if ([double]::TryParse($line.Trim(), [System.Globalization.NumberStyles]::Float,
                [System.Globalization.CultureInfo]::InvariantCulture, [ref]$value) -and $value -gt $best) {
            $best = $value
        }
    }
    $best
}

function New-ReportHtml {
    param(
        [object[]]$Entries,
        [hashtable]$Run      # MoviesFolder, OutputFolder, ClipLength, AvoidSeconds, Started, Finished, Stopped, Created
    )
    $enc = { param($s) [System.Net.WebUtility]::HtmlEncode([string]$s) }
    $count = @{}
    foreach ($status in 'SUCCESS', 'WARNING', 'ERROR', 'SKIPPED') {
        $count[$status] = @($Entries | Where-Object { $_.Status -eq $status }).Count
    }
    $rows = foreach ($entry in $Entries) {
        $icon = switch ($entry.Status) {
            'SUCCESS' { '&#10003;' } 'WARNING' { '&#9888;' } 'ERROR' { '&#10006;' } default { '&#8212;' }
        }
        "<tr class='$($entry.Status.ToLowerInvariant())'><td class='status'><span class='status-icon'>$icon</span>$($entry.Status)</td>" +
        "<td>$(& $enc $entry.Movie)</td><td class='path'>$(& $enc $entry.Output)</td><td><pre>$(& $enc $entry.Detail)</pre></td></tr>"
    }
    if (-not $rows) { $rows = "<tr><td colspan='4'>No movies were processed.</td></tr>" }

    $title = if ($Run.Stopped) { 'Partial report' } else { 'Processing report' }
    $banner = ''
    if ($Run.Stopped) {
        $banner = "<div class='cancelled'>&#9888; Processing was stopped. This report lists the movies handled before it stopped.</div>"
    }
    $verb = if ($Run.Stopped) { 'Stopped' } else { 'Finished' }
    $meta = '{0} {1} &bull; {2} movie(s) handled &bull; {3} clip(s) created &bull; {4}-second clips, avoiding the first and last {5} seconds' -f
        $verb, (& $enc $Run.Finished.ToString('dd MMMM yyyy HH:mm')), @($Entries).Count, $Run.Created, $Run.ClipLength, $Run.AvoidSeconds
    $folders = 'Movies: {0} &bull; Output: {1}' -f (& $enc $Run.MoviesFolder), (& $enc $Run.OutputFolder)

    @"
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>$AppName - $title</title>
<style>
:root { color-scheme: dark; }
* { box-sizing: border-box; }
body { margin: 0; background: #07111f; color: #e7eef8; font-family: "Segoe UI", Arial, sans-serif; }
header { padding: 30px 40px; background: linear-gradient(135deg, #0b1e35, #102b4b); border-bottom: 1px solid #24496d; }
.brand { display: flex; align-items: center; gap: 18px; }
.logo { width: 56px; height: 56px; border-radius: 14px; background: linear-gradient(135deg, #18b7ff, #3d6bff); display: grid; place-items: center; font-size: 28px; }
h1 { margin: 0; font-size: 28px; }
.subtitle { margin-top: 4px; color: #9fb7d1; }
.cancelled { margin-top: 18px; padding: 12px 16px; border-radius: 10px; background: #4a3511; border: 1px solid #8b6723; color: #ffd166; font-weight: 600; }
main { max-width: 1500px; margin: auto; padding: 26px 34px 50px; }
.cards { display: grid; grid-template-columns: repeat(4, minmax(140px, 1fr)); gap: 14px; margin-bottom: 22px; }
.card { background: #0d1c2e; border: 1px solid #213b56; border-radius: 12px; padding: 16px 18px; }
.number { font-size: 28px; font-weight: 700; }
.label { color: #91a8c0; margin-top: 2px; }
.success-card .number { color: #64e49a; } .warning-card .number { color: #ffd166; }
.error-card .number { color: #ff6b78; } .skipped-card .number { color: #9fb7d1; }
.meta { color: #9fb7d1; margin: 0 0 6px; }
.table-wrap { overflow: auto; border: 1px solid #213b56; border-radius: 12px; background: #0b1828; margin-top: 18px; }
table { width: 100%; border-collapse: collapse; min-width: 900px; }
th { text-align: left; padding: 12px 14px; background: #10243a; color: #bcd2e8; position: sticky; top: 0; }
td { padding: 12px 14px; border-top: 1px solid #1c334a; vertical-align: top; }
tr.success { border-left: 4px solid #43d17d; }
tr.warning { border-left: 4px solid #ffc857; background: #2a220e55; }
tr.error { border-left: 4px solid #ff5263; background: #32131a88; }
tr.skipped { border-left: 4px solid #8195aa; }
.status { font-weight: 700; white-space: nowrap; }
.success .status { color: #64e49a; } .warning .status { color: #ffd166; }
.error .status { color: #ff7a86; } .skipped .status { color: #a9bacb; }
.status-icon { display: inline-block; width: 24px; font-size: 17px; }
.path { color: #9fc8ef; word-break: break-all; }
pre { margin: 0; white-space: pre-wrap; word-break: break-word; font-family: "Cascadia Mono", Consolas, monospace; font-size: 12px; color: inherit; }
footer { color: #7189a1; text-align: center; padding: 24px; }
@media (max-width: 800px) { .cards { grid-template-columns: repeat(2, 1fr); } main { padding: 18px 14px; } header { padding: 22px 18px; } }
</style>
</head>
<body>
<header>
<div class="brand"><div class="logo">&#127916;</div><div><h1>$AppName</h1><div class="subtitle">$title &bull; v$AppVersion</div></div></div>
$banner
</header>
<main>
<div class="cards">
<div class="card success-card"><div class="number">$($count['SUCCESS'])</div><div class="label">Created</div></div>
<div class="card warning-card"><div class="number">$($count['WARNING'])</div><div class="label">Created with warnings</div></div>
<div class="card error-card"><div class="number">$($count['ERROR'])</div><div class="label">Errors</div></div>
<div class="card skipped-card"><div class="number">$($count['SKIPPED'])</div><div class="label">Skipped</div></div>
</div>
<p class="meta">$meta</p>
<p class="meta">$folders</p>
<div class="table-wrap">
<table>
<thead><tr><th>Status</th><th>Movie</th><th>Clip</th><th>Details / FFmpeg messages</th></tr></thead>
<tbody>
$($rows -join "`r`n")
</tbody>
</table>
</div>
</main>
<footer>$AppName v$AppVersion &bull; video processing by FFmpeg</footer>
</body>
</html>
"@
}

function Save-Report([object[]]$Entries, [hashtable]$Run) {
    # Reports go to %APPDATA%\Clip Creator\Reports, not the output folder, so a media
    # server scanning the output never sees them. The newest $KeepReports are kept.
    [void][System.IO.Directory]::CreateDirectory($script:ReportsDir)
    $kind = if ($Run.Stopped) { 'Partial-Report' } else { 'Report' }
    $path = [System.IO.Path]::Combine($script:ReportsDir, ('Clip-Creator-{0}-{1:yyyyMMdd-HHmmss}.html' -f $kind, $Run.Finished))
    [System.IO.File]::WriteAllText($path, (New-ReportHtml -Entries $Entries -Run $Run), [System.Text.UTF8Encoding]::new($false))
    try {
        Get-ChildItem -LiteralPath $script:ReportsDir -Filter 'Clip-Creator-*.html' -File |
            Sort-Object LastWriteTime -Descending | Select-Object -Skip $script:KeepReports |
            Remove-Item -Force -ErrorAction SilentlyContinue
    } catch { Write-Verbose $_.Exception.Message }
    $path
}

# ---------------------------------------------------------------------------
# Window
# ---------------------------------------------------------------------------

$LogoBase64 = @'
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
WIXlG+WkBQAAAABJRU5ErkJggg==
'@

$Colour = @{
    Navy       = [System.Drawing.Color]::FromArgb(8, 29, 58)
    NavyLight  = [System.Drawing.Color]::FromArgb(14, 52, 98)
    Blue       = [System.Drawing.Color]::FromArgb(0, 105, 220)
    SubText    = [System.Drawing.Color]::FromArgb(180, 215, 245)
    Page       = [System.Drawing.Color]::FromArgb(236, 243, 250)
    Card       = [System.Drawing.Color]::White
    Text       = [System.Drawing.Color]::FromArgb(8, 29, 58)
    Hint       = [System.Drawing.Color]::FromArgb(92, 108, 128)
    LogBack    = [System.Drawing.Color]::FromArgb(12, 31, 53)
    Green      = [System.Drawing.Color]::FromArgb(18, 150, 72)
    Red        = [System.Drawing.Color]::FromArgb(214, 40, 56)
    ButtonBlue = [System.Drawing.Color]::FromArgb(10, 96, 214)
    Slate      = [System.Drawing.Color]::FromArgb(74, 85, 104)
}

function New-Font([float]$Size, [System.Drawing.FontStyle]$Style = [System.Drawing.FontStyle]::Regular, [string]$Family = 'Segoe UI') {
    New-Object System.Drawing.Font($Family, $Size, $Style)
}

function New-Label([string]$Text, [float]$Size = 9.75, [System.Drawing.FontStyle]$Style = [System.Drawing.FontStyle]::Regular, $ForeColor = $Colour.Text) {
    $label = New-Object System.Windows.Forms.Label
    $label.Text = $Text
    $label.AutoSize = $true
    $label.Font = New-Font $Size $Style
    $label.ForeColor = $ForeColor
    $label.Anchor = [System.Windows.Forms.AnchorStyles]::Left
    $label.Margin = New-Object System.Windows.Forms.Padding((S 3), (S 6), (S 3), (S 3))
    $label
}

function New-Card([string]$Title, [int]$Columns) {
    # A white card: a TableLayoutPanel whose first row is the heading
    $card = New-Object System.Windows.Forms.TableLayoutPanel
    $card.BackColor = $Colour.Card
    $card.Dock = [System.Windows.Forms.DockStyle]::Fill
    $card.Padding = New-Object System.Windows.Forms.Padding((S 14), (S 8), (S 14), (S 8))
    $card.Margin = New-Object System.Windows.Forms.Padding((S 6))
    $card.ColumnCount = $Columns
    $card.AutoSize = $true
    $card.AutoSizeMode = [System.Windows.Forms.AutoSizeMode]::GrowAndShrink
    $heading = New-Label $Title 12 ([System.Drawing.FontStyle]::Bold) $Colour.Navy
    $heading.Margin = New-Object System.Windows.Forms.Padding((S 0), (S 0), (S 0), (S 8))
    [void]$card.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::AutoSize)))
    $card.Controls.Add($heading, 0, 0)
    $card.SetColumnSpan($heading, $Columns)
    $card
}

function Add-CardRow($Card, [object[]]$Controls, [int[]]$Spans) {
    $row = $Card.RowCount
    if ($row -lt 1) { $row = 1 }
    [void]$Card.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::AutoSize)))
    $column = 0
    for ($i = 0; $i -lt $Controls.Count; $i++) {
        $Card.Controls.Add($Controls[$i], $column, $row)
        $span = 1
        if ($Spans -and $i -lt $Spans.Count) { $span = $Spans[$i] }
        if ($span -gt 1) { $Card.SetColumnSpan($Controls[$i], $span) }
        $column += $span
    }
    $Card.RowCount = $row + 1
}

function New-ActionButton([string]$Text, [System.Drawing.Color]$BackColor) {
    $button = New-Object System.Windows.Forms.Button
    $button.Text = $Text
    $button.Dock = [System.Windows.Forms.DockStyle]::Fill
    $button.Margin = New-Object System.Windows.Forms.Padding((S 6))
    $button.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $button.FlatAppearance.BorderSize = 0
    $button.BackColor = $BackColor
    $button.FlatAppearance.MouseOverBackColor = [System.Windows.Forms.ControlPaint]::Dark($BackColor, 0.05)
    $button.FlatAppearance.MouseDownBackColor = [System.Windows.Forms.ControlPaint]::Dark($BackColor, 0.15)
    $button.ForeColor = [System.Drawing.Color]::White
    $button.Font = New-Font 10.5 ([System.Drawing.FontStyle]::Bold)
    $button.Cursor = [System.Windows.Forms.Cursors]::Hand
    $button.Tag = $BackColor
    $button.UseVisualStyleBackColor = $false
    $button
}

function New-SmallButton([string]$Text) {
    $button = New-Object System.Windows.Forms.Button
    $button.Text = $Text
    $button.AutoSize = $true
    $button.AutoSizeMode = [System.Windows.Forms.AutoSizeMode]::GrowAndShrink
    $button.Padding = New-Object System.Windows.Forms.Padding((S 10), (S 2), (S 10), (S 2))
    $button.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $button.FlatAppearance.BorderSize = 0
    $button.BackColor = $Colour.Navy
    $button.FlatAppearance.MouseOverBackColor = $Colour.NavyLight
    $button.ForeColor = [System.Drawing.Color]::White
    $button.Font = New-Font 9.75
    $button.Cursor = [System.Windows.Forms.Cursors]::Hand
    $button.Anchor = [System.Windows.Forms.AnchorStyles]::Right
    $button.UseVisualStyleBackColor = $false
    $button
}

function Set-ActionEnabled([System.Windows.Forms.Button]$Button, [bool]$Enabled) {
    # Flat buttons keep their colour when disabled; fade it so the state is obvious
    $Button.Enabled = $Enabled
    $base = [System.Drawing.Color]$Button.Tag
    if ($Enabled) { $Button.BackColor = $base }
    else { $Button.BackColor = [System.Windows.Forms.ControlPaint]::LightLight($base) }
}

$logoImage = $null
try {
    $logoBytes = [Convert]::FromBase64String(($LogoBase64 -replace '\s', ''))
    $logoImage = [System.Drawing.Image]::FromStream((New-Object System.IO.MemoryStream(, $logoBytes)))
} catch { Write-Verbose "Logo not loaded: $($_.Exception.Message)" }

$settings = Import-Setting

$form = New-Object System.Windows.Forms.Form
$form.SuspendLayout()
$form.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::None
$form.Text = "$AppName v$AppVersion"
$form.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen
$form.ClientSize = New-Object System.Drawing.Size((S 1040), (S 700))
$form.MinimumSize = New-Object System.Drawing.Size((S 900), (S 660))
$form.BackColor = $Colour.Page
$form.Font = New-Font 9.75

# Window and taskbar icon: the exe's own icon, or assets\Clip-Creator.ico beside src\
try {
    if ($script:IsExe) {
        $form.Icon = [System.Drawing.Icon]::ExtractAssociatedIcon([System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName)
    } elseif ($PSScriptRoot) {
        $iconPath = [System.IO.Path]::Combine((Split-Path -Parent $PSScriptRoot), 'assets', 'Clip-Creator.ico')
        if ([System.IO.File]::Exists($iconPath)) { $form.Icon = New-Object System.Drawing.Icon($iconPath) }
    }
} catch { Write-Verbose "Icon not loaded: $($_.Exception.Message)" }

$tip = New-Object System.Windows.Forms.ToolTip

# ----- Main area: two columns of cards -----
$main = New-Object System.Windows.Forms.TableLayoutPanel
$main.Dock = [System.Windows.Forms.DockStyle]::Fill
$main.Padding = New-Object System.Windows.Forms.Padding((S 8), (S 8), (S 8), (S 0))
$main.ColumnCount = 2
$main.RowCount = 2
[void]$main.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 46)))
[void]$main.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 54)))
[void]$main.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::AutoSize)))
[void]$main.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 100)))
$form.Controls.Add($main)

# Folders card
$foldersCard = New-Card 'Folders' 2
[void]$foldersCard.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 100)))
[void]$foldersCard.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::AutoSize)))

$txtMovies = New-Object System.Windows.Forms.TextBox
$txtMovies.Dock = [System.Windows.Forms.DockStyle]::Fill
$txtMovies.Margin = New-Object System.Windows.Forms.Padding((S 3), (S 4), (S 6), (S 4))
$txtMovies.Text = [string]$settings.MoviesFolder
$btnBrowseMovies = New-SmallButton 'Browse...'
$txtOutput = New-Object System.Windows.Forms.TextBox
$txtOutput.Dock = [System.Windows.Forms.DockStyle]::Fill
$txtOutput.Margin = New-Object System.Windows.Forms.Padding((S 3), (S 4), (S 6), (S 4))
$txtOutput.Text = [string]$settings.OutputFolder
$btnBrowseOutput = New-SmallButton 'Browse...'
$lblFolderHint = New-Label "Saved as <output>\<movie>\backdrops\theme.mp4. Pick the movies folder to keep clips in your library." 8.75 ([System.Drawing.FontStyle]::Regular) $Colour.Hint
$lblFolderHint.MaximumSize = New-Object System.Drawing.Size((S 400), (S 0))

Add-CardRow $foldersCard @((New-Label 'Movies folder' 9.75 ([System.Drawing.FontStyle]::Bold))) @(2)
Add-CardRow $foldersCard @($txtMovies, $btnBrowseMovies)
Add-CardRow $foldersCard @((New-Label 'Output folder' 9.75 ([System.Drawing.FontStyle]::Bold))) @(2)
Add-CardRow $foldersCard @($txtOutput, $btnBrowseOutput)
Add-CardRow $foldersCard @($lblFolderHint) @(2)
$main.Controls.Add($foldersCard, 0, 0)

# Settings card
$settingsCard = New-Card 'Settings' 2
[void]$settingsCard.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::AutoSize)))
[void]$settingsCard.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 100)))

$numLength = New-Object System.Windows.Forms.NumericUpDown
$numLength.Minimum = 1
$numLength.Maximum = 600
$numLength.Value = [Math]::Min(600, [Math]::Max(1, [int]$settings.ClipLength))
$numLength.Size = New-Object System.Drawing.Size((S 90), (S 26))
$numLength.Anchor = [System.Windows.Forms.AnchorStyles]::Left
$numLength.Margin = New-Object System.Windows.Forms.Padding((S 3), (S 4), (S 3), (S 4))
$tip.SetToolTip($numLength, 'How long each clip is. Each one starts at a random point in the movie.')
$numAvoid = New-Object System.Windows.Forms.NumericUpDown
$numAvoid.Minimum = 0
$numAvoid.Maximum = 3600
$numAvoid.Value = [Math]::Min(3600, [Math]::Max(0, [int]$settings.AvoidSeconds))
$numAvoid.Size = New-Object System.Drawing.Size((S 90), (S 26))
$numAvoid.Anchor = [System.Windows.Forms.AnchorStyles]::Left
$numAvoid.Margin = New-Object System.Windows.Forms.Padding((S 3), (S 4), (S 3), (S 4))
$avoidHint = 'Keeps clips clear of the opening titles and end credits: clips never start in the first or end in the last this-many seconds, when the movie is long enough.'
$tip.SetToolTip($numAvoid, $avoidHint)
$lblAvoid = New-Label 'Avoid start/end (seconds)'
$tip.SetToolTip($lblAvoid, $avoidHint)

$txtTypes = New-Object System.Windows.Forms.TextBox
$txtTypes.Dock = [System.Windows.Forms.DockStyle]::Fill
$txtTypes.Margin = New-Object System.Windows.Forms.Padding((S 3), (S 4), (S 3), (S 4))
$txtTypes.Text = [string]$settings.FileTypes
$tip.SetToolTip($txtTypes, 'File extensions to look for, separated by commas')

$chkRecursive = New-Object System.Windows.Forms.CheckBox
$chkRecursive.Text = 'Include subfolders (one clip per movie folder)'
$chkRecursive.AutoSize = $true
$chkRecursive.Checked = [bool]$settings.IncludeSubfolders
$chkRecursive.Margin = New-Object System.Windows.Forms.Padding((S 3), (S 4), (S 3), (S 4))

$cmbExisting = New-Object System.Windows.Forms.ComboBox
$cmbExisting.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
[void]$cmbExisting.Items.AddRange(@('Ask each time', 'Keep the existing clip', 'Replace it'))
$existingIndex = @{ Ask = 0; Keep = 1; Replace = 2 }[[string]$settings.ExistingClip]
if ($null -eq $existingIndex) { $existingIndex = 0 }
$cmbExisting.SelectedIndex = $existingIndex
$cmbExisting.Width = S 200
$cmbExisting.Anchor = [System.Windows.Forms.AnchorStyles]::Left
$cmbExisting.Margin = New-Object System.Windows.Forms.Padding((S 3), (S 4), (S 3), (S 4))

Add-CardRow $settingsCard @((New-Label 'Clip length (seconds)'), $numLength)
Add-CardRow $settingsCard @($lblAvoid, $numAvoid)
Add-CardRow $settingsCard @((New-Label 'Movie file types'), $txtTypes)
Add-CardRow $settingsCard @((New-Label 'If a clip already exists'), $cmbExisting)
Add-CardRow $settingsCard @($chkRecursive) @(2)
$main.Controls.Add($settingsCard, 0, 1)

# Progress card
$progressCard = New-Card 'Progress' 3
foreach ($i in 1..3) {
    [void]$progressCard.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 33.3)))
}
$progressBar = New-Object System.Windows.Forms.ProgressBar
$progressBar.Style = [System.Windows.Forms.ProgressBarStyle]::Continuous
$progressBar.Dock = [System.Windows.Forms.DockStyle]::Fill
$progressBar.Height = S 22
$progressBar.Margin = New-Object System.Windows.Forms.Padding((S 3), (S 2), (S 3), (S 6))
$lblStatus = New-Label 'Ready' 9.75 ([System.Drawing.FontStyle]::Bold) $Colour.Blue
$lblPercent = New-Label '0%' 9.75 ([System.Drawing.FontStyle]::Bold) $Colour.Blue
$lblPercent.Anchor = [System.Windows.Forms.AnchorStyles]::Right
$lblCurrentCaption = New-Label 'Current movie' 8.75 ([System.Drawing.FontStyle]::Regular) $Colour.Hint
$lblTimeCaption = New-Label 'Time left' 8.75 ([System.Drawing.FontStyle]::Regular) $Colour.Hint
$lblCreatedCaption = New-Label 'Clips created' 8.75 ([System.Drawing.FontStyle]::Regular) $Colour.Hint
function New-ValueLabel([string]$Text) {
    # The three progress values share one shape so they line up
    $label = New-Label $Text 9.75 ([System.Drawing.FontStyle]::Bold)
    $label.AutoSize = $false
    $label.AutoEllipsis = $true
    $label.Dock = [System.Windows.Forms.DockStyle]::Fill
    $label.Height = S 26
    $label.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
    $label.Margin = New-Object System.Windows.Forms.Padding((S 3), (S 0), (S 3), (S 2))
    $label
}
$lblCurrent = New-ValueLabel '-'
$lblTimeLeft = New-ValueLabel '-'
$lblCreated = New-ValueLabel '0'

Add-CardRow $progressCard @($progressBar) @(3)
Add-CardRow $progressCard @($lblStatus, $lblPercent) @(2, 1)
Add-CardRow $progressCard @($lblCurrentCaption, $lblTimeCaption, $lblCreatedCaption)
Add-CardRow $progressCard @($lblCurrent, $lblTimeLeft, $lblCreated)
# An empty last row takes the spare height, so the values stay under their captions
[void]$progressCard.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 100)))
$progressCard.RowCount = $progressCard.RowCount + 1
$main.Controls.Add($progressCard, 1, 0)

# Log card
$logCard = New-Card 'Log' 2
[void]$logCard.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 100)))
[void]$logCard.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::AutoSize)))
$logCard.AutoSize = $false
# The heading spans both columns; move it to column 0 only so the buttons sit beside it
$logCard.SetColumnSpan($logCard.Controls[0], 1)
$logButtons = New-Object System.Windows.Forms.FlowLayoutPanel
$logButtons.AutoSize = $true
$logButtons.WrapContents = $false
$logButtons.Anchor = [System.Windows.Forms.AnchorStyles]::Right
$logButtons.Margin = New-Object System.Windows.Forms.Padding((S 0), (S 0), (S 0), (S 6))
$btnReports = New-SmallButton 'Reports'
$btnClearLog = New-SmallButton 'Clear log'
$tip.SetToolTip($btnReports, 'Open the folder with the HTML report from each run')
$logButtons.Controls.Add($btnReports)
$logButtons.Controls.Add($btnClearLog)
$logCard.Controls.Add($logButtons, 1, 0)

$txtLog = New-Object System.Windows.Forms.RichTextBox
$txtLog.Dock = [System.Windows.Forms.DockStyle]::Fill
$txtLog.ReadOnly = $true
$txtLog.BorderStyle = [System.Windows.Forms.BorderStyle]::None
$txtLog.BackColor = $Colour.LogBack
$txtLog.ForeColor = [System.Drawing.Color]::Gainsboro
$txtLog.Font = New-Font 9 ([System.Drawing.FontStyle]::Regular) 'Consolas'
$txtLog.DetectUrls = $false
$txtLog.Margin = New-Object System.Windows.Forms.Padding((S 0))
[void]$logCard.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 100)))
$logCard.Controls.Add($txtLog, 0, 1)
$logCard.SetColumnSpan($txtLog, 2)
$logCard.RowCount = 2
$main.Controls.Add($logCard, 1, 1)

# ----- Action buttons along the bottom -----
$actions = New-Object System.Windows.Forms.TableLayoutPanel
$actions.Dock = [System.Windows.Forms.DockStyle]::Bottom
$actions.Height = S 78
$actions.Padding = New-Object System.Windows.Forms.Padding((S 8), (S 2), (S 8), (S 10))
$actions.ColumnCount = 4
$actions.RowCount = 1
foreach ($i in 1..4) {
    [void]$actions.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 25)))
}
[void]$actions.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 100)))
$btnStart = New-ActionButton "Create clips`n(one per movie)" $Colour.Green
$btnStop = New-ActionButton "Stop`n(after this clip)" $Colour.Red
$btnOpen = New-ActionButton "Open output folder`n(view your clips)" $Colour.ButtonBlue
$btnCheck = New-ActionButton "Check FFmpeg`n(verify install)" $Colour.Slate
$actions.Controls.Add($btnStart, 0, 0)
$actions.Controls.Add($btnStop, 1, 0)
$actions.Controls.Add($btnOpen, 2, 0)
$actions.Controls.Add($btnCheck, 3, 0)
$form.Controls.Add($actions)

# ----- Header -----
$header = New-Object System.Windows.Forms.Panel
$header.Dock = [System.Windows.Forms.DockStyle]::Top
$header.Height = S 92
$header.BackColor = $Colour.Navy
$header.Add_Paint({
    param($eventSource, $e)
    $rect = $eventSource.ClientRectangle
    if ($rect.Width -le 0 -or $rect.Height -le 0) { return }
    $brush = New-Object System.Drawing.Drawing2D.LinearGradientBrush($rect, $Colour.Navy, $Colour.NavyLight, [single]0)
    $e.Graphics.FillRectangle($brush, $rect)
    $brush.Dispose()
})
$header.Add_Resize({ $header.Invalidate() })

$picLogo = New-Object System.Windows.Forms.PictureBox
$picLogo.Location = New-Object System.Drawing.Point((S 18), (S 12))
$picLogo.Size = New-Object System.Drawing.Size((S 68), (S 68))
$picLogo.SizeMode = [System.Windows.Forms.PictureBoxSizeMode]::Zoom
$picLogo.BackColor = [System.Drawing.Color]::Transparent
$picLogo.Image = $logoImage
$header.Controls.Add($picLogo)

$lblTitle = New-Object System.Windows.Forms.Label
$lblTitle.Text = $AppName
$lblTitle.AutoSize = $true
$lblTitle.Font = New-Font 22 ([System.Drawing.FontStyle]::Bold)
$lblTitle.ForeColor = [System.Drawing.Color]::White
$lblTitle.BackColor = [System.Drawing.Color]::Transparent
$lblTitle.Location = New-Object System.Drawing.Point((S 96), (S 10))
$header.Controls.Add($lblTitle)

$lblSubtitle = New-Object System.Windows.Forms.Label
$lblSubtitle.Text = 'A random theme clip from every movie, made with FFmpeg'
$lblSubtitle.AutoSize = $true
$lblSubtitle.Font = New-Font 10.5
$lblSubtitle.ForeColor = $Colour.SubText
$lblSubtitle.BackColor = [System.Drawing.Color]::Transparent
$lblSubtitle.Location = New-Object System.Drawing.Point((S 100), (S 54))
$header.Controls.Add($lblSubtitle)

$btnAbout = New-SmallButton 'About'
$btnAbout.BackColor = $Colour.NavyLight
$btnAbout.FlatAppearance.MouseOverBackColor = $Colour.Blue
$btnAbout.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Right
$btnAbout.Location = New-Object System.Drawing.Point(($form.ClientSize.Width - (S 100)), (S 30))
$header.Controls.Add($btnAbout)
$form.Controls.Add($header)

$form.ResumeLayout($false)
$form.PerformLayout()

# ---------------------------------------------------------------------------
# Window behaviour
# ---------------------------------------------------------------------------

function Add-Log([string]$Text, [System.Drawing.Color]$Color = [System.Drawing.Color]::Gainsboro) {
    $txtLog.SelectionStart = $txtLog.TextLength
    $txtLog.SelectionLength = 0
    $txtLog.SelectionColor = $Color
    $txtLog.AppendText(('[{0:HH:mm:ss}]  {1}{2}' -f (Get-Date), $Text, [Environment]::NewLine))
    $txtLog.SelectionColor = $txtLog.ForeColor
    $txtLog.ScrollToCaret()
}

function Show-Message([string]$Text, [string]$Title = $AppName,
                      [System.Windows.Forms.MessageBoxButtons]$Buttons = 'OK',
                      [System.Windows.Forms.MessageBoxIcon]$Icon = 'Information') {
    [System.Windows.Forms.MessageBox]::Show($form, $Text, $Title, $Buttons, $Icon)
}

function Select-Folder([string]$Title, [string]$InitialPath) {
    if ('ClipCreatorFolderPicker' -as [type]) {
        try { return [ClipCreatorFolderPicker]::Pick($form.Handle, $Title, $InitialPath) }
        catch { Add-Log "Folder picker problem, using the basic one: $($_.Exception.Message)" ([System.Drawing.Color]::Khaki) }
    }
    $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
    $dialog.Description = $Title
    $dialog.ShowNewFolderButton = $true
    if ($InitialPath -and [System.IO.Directory]::Exists($InitialPath)) { $dialog.SelectedPath = $InitialPath }
    try {
        if ($dialog.ShowDialog($form) -eq [System.Windows.Forms.DialogResult]::OK) { return $dialog.SelectedPath }
    } finally { $dialog.Dispose() }
    return $null
}

function Get-CurrentSetting {
    $settings = Get-DefaultSetting
    $settings.MoviesFolder = $txtMovies.Text.Trim()
    $settings.OutputFolder = $txtOutput.Text.Trim()
    $settings.ClipLength = [int]$numLength.Value
    $settings.AvoidSeconds = [int]$numAvoid.Value
    $settings.FileTypes = $txtTypes.Text.Trim()
    $settings.IncludeSubfolders = $chkRecursive.Checked
    $settings.ExistingClip = @('Ask', 'Keep', 'Replace')[[Math]::Max(0, $cmbExisting.SelectedIndex)]
    $settings
}

function Set-RunningState([bool]$Running) {
    $script:State.Running = $Running
    foreach ($control in @($txtMovies, $txtOutput, $btnBrowseMovies, $btnBrowseOutput, $numLength, $numAvoid, $txtTypes, $chkRecursive, $cmbExisting)) {
        $control.Enabled = -not $Running
    }
    Set-ActionEnabled $btnStart (-not $Running)
    Set-ActionEnabled $btnCheck (-not $Running)
    Set-ActionEnabled $btnStop $Running
}

function Set-Progress([int]$Done, [int]$Total) {
    $percent = 0
    if ($Total -gt 0) { $percent = [int][Math]::Floor(($Done * 100.0) / $Total) }
    $progressBar.Value = [Math]::Min(100, [Math]::Max(0, $percent))
    $lblPercent.Text = "$percent%"
}

function Invoke-Tool {
    <#
        Runs ffmpeg/ffprobe without a console window and without freezing the window.
        Both output streams are read in the background (reading one then the other can
        hang if the second fills up). Stop kills the tool; $TimeoutSeconds guards
        against a NAS that stops answering.
    #>
    param([string]$FilePath, [string]$Arguments, [int]$TimeoutSeconds = 0)

    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.FileName = $FilePath
    $startInfo.Arguments = $Arguments
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true

    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $startInfo
    [void]$process.Start()
    $script:State.CurrentProcess = $process
    $stdout = $process.StandardOutput.ReadToEndAsync()
    $stderr = $process.StandardError.ReadToEndAsync()
    $started = Get-Date
    $result = [pscustomobject]@{ ExitCode = -1; StdOut = ''; StdErr = ''; Stopped = $false; TimedOut = $false }

    try {
        while (-not $process.WaitForExit(40)) {
            [System.Windows.Forms.Application]::DoEvents()
            $stop = $script:State.CancelRequested -and $script:State.StopNow
            $late = $TimeoutSeconds -gt 0 -and ((Get-Date) - $started).TotalSeconds -gt $TimeoutSeconds
            if ($stop -or $late) {
                try { $process.Kill() } catch { Write-Verbose $_.Exception.Message }
                [void]$process.WaitForExit(5000)
                $result.Stopped = $stop
                $result.TimedOut = $late
                break
            }
        }
        [void]$process.WaitForExit()
        $result.ExitCode = $process.ExitCode
        $result.StdOut = $stdout.Result
        $result.StdErr = $stderr.Result
    } finally {
        $script:State.CurrentProcess = $null
        $process.Dispose()
    }
    $result
}

function Get-ExistingClipChoice([string]$Movie) {
    # 'Replace', 'Keep' or 'Stop'
    $mode = (Get-CurrentSetting).ExistingClip
    if ($mode -ne 'Ask') { return $mode }
    $answer = Show-Message ("There's already a clip for:`r`n`r`n$Movie`r`n`r`n" +
        "Yes = replace it`r`nNo = keep it and carry on`r`nCancel = keep it and stop here") `
        'Clip already exists' 'YesNoCancel' 'Question'
    switch ($answer) {
        'Yes'   { 'Replace' }
        'No'    { 'Keep' }
        default { 'Stop' }
    }
}

function Remove-EmptyFolder([string]$Path) {
    try {
        if ([System.IO.Directory]::Exists($Path) -and
            -not ([System.IO.Directory]::EnumerateFileSystemEntries($Path).GetEnumerator().MoveNext())) {
            [System.IO.Directory]::Delete($Path)
        }
    } catch { Write-Verbose $_.Exception.Message }
}

function Invoke-ClipRun {
    $current = Get-CurrentSetting
    $moviesFolder = $current.MoviesFolder
    $outputFolder = $current.OutputFolder

    if ([string]::IsNullOrWhiteSpace($moviesFolder) -or -not [System.IO.Directory]::Exists($moviesFolder)) {
        [void](Show-Message 'Choose a movies folder that exists.' 'Movies folder' 'OK' 'Warning')
        return
    }
    if ([string]::IsNullOrWhiteSpace($outputFolder)) {
        [void](Show-Message 'Choose an output folder for the clips.' 'Output folder' 'OK' 'Warning')
        return
    }
    try {
        $moviesFolder = [System.IO.Path]::GetFullPath($moviesFolder)
        $outputFolder = [System.IO.Path]::GetFullPath($outputFolder)
    } catch {
        [void](Show-Message "That folder path isn't valid.`r`n`r`n$($_.Exception.Message)" 'Folders' 'OK' 'Warning')
        return
    }
    $extensions = ConvertTo-ExtensionList $current.FileTypes
    if ($extensions.Count -eq 0) {
        $extensions = ConvertTo-ExtensionList $script:DefaultFileTypes
        $txtTypes.Text = $script:DefaultFileTypes
        $current.FileTypes = $script:DefaultFileTypes
        Add-Log 'No file types were listed, so the standard list is being used.' ([System.Drawing.Color]::Khaki)
    }

    $ffmpeg = Find-Tool 'ffmpeg'
    $ffprobe = Find-Tool 'ffprobe'
    if (-not $ffmpeg -or -not $ffprobe) {
        [void](Show-Message "FFmpeg or FFprobe wasn't found. Press Check FFmpeg for how to install it." 'FFmpeg not found' 'OK' 'Warning')
        return
    }
    try {
        [void][System.IO.Directory]::CreateDirectory($outputFolder)
    } catch {
        [void](Show-Message "The output folder couldn't be created or opened.`r`n`r`n$($_.Exception.Message)" 'Output folder' 'OK' 'Warning')
        return
    }

    Export-Setting $current
    $script:State.CancelRequested = $false
    $script:State.StopNow = $false
    Set-RunningState $true
    $entries = New-Object System.Collections.Generic.List[object]
    $created = 0
    $runStarted = Get-Date
    $lblCreated.Text = '0'
    $lblTimeLeft.Text = '-'
    $lblCurrent.Text = '-'
    Set-Progress 0 1

    try {
        # ----- Find the movies -----
        $lblStatus.Text = 'Looking for movies...'
        Add-Log "Looking for movies in $moviesFolder" ([System.Drawing.Color]::LightSkyBlue)
        $exclude = $null
        if ((Test-IsInside $outputFolder $moviesFolder) -and
            -not $outputFolder.TrimEnd('\').Equals($moviesFolder.TrimEnd('\'), [System.StringComparison]::OrdinalIgnoreCase)) {
            $exclude = $outputFolder
        }
        $scan = Get-MovieFile -Folder $moviesFolder -Extensions $extensions -Recurse $current.IncludeSubfolders -ExcludeFolder $exclude -OnProgress {
            param($seen)
            $lblStatus.Text = "Looking for movies... ($seen files checked)"
            [System.Windows.Forms.Application]::DoEvents()
            $script:State.CancelRequested
        }
        if ($scan.Unreadable -gt 0) {
            Add-Log "$($scan.Unreadable) folder(s) couldn't be read and were skipped." ([System.Drawing.Color]::Khaki)
        }
        if ($scan.Stopped) {
            $lblStatus.Text = 'Stopped'
            Add-Log 'Stopped while looking for movies.' ([System.Drawing.Color]::Orange)
            return
        }
        if ($scan.Files.Count -eq 0) {
            $lblStatus.Text = 'Ready'
            [void](Show-Message "No movies were found.`r`n`r`nLooked for: $($extensions -join ' ')" 'No movies' 'OK' 'Information')
            return
        }

        $plan = @(Get-ClipPlan -Files $scan.Files -MoviesFolder $moviesFolder -OutputFolder $outputFolder)
        $work = @($plan | Where-Object { -not $_.Skip })
        foreach ($item in ($plan | Where-Object { $_.Skip })) {
            $entries.Add([pscustomobject]@{ Status = 'SKIPPED'; Movie = $item.Movie; Output = ''; Detail = $item.Skip })
        }
        Add-Log ("Found {0} movie(s). Making {1}-second clips." -f $work.Count, $current.ClipLength) ([System.Drawing.Color]::LightSkyBlue)
        if ($plan.Count -gt $work.Count) {
            Add-Log "$($plan.Count - $work.Count) extra video(s) share a folder with a movie and were skipped (listed in the report)."
        }

        # ----- Make the clips -----
        $index = 0
        foreach ($item in $work) {
            if ($script:State.CancelRequested) { break }
            $index++
            $movie = $item.File
            $target = $item.Target
            $backdrops = [System.IO.Path]::GetDirectoryName($target)
            $lblCurrent.Text = [System.IO.Path]::GetFileNameWithoutExtension($movie.Name)
            $tip.SetToolTip($lblCurrent, $item.Movie)
            $lblStatus.Text = "Movie $index of $($work.Count)"

            $entry = [pscustomobject]@{ Status = 'ERROR'; Movie = $item.Movie; Output = $target; Detail = '' }
            $entries.Add($entry)

            if ([System.IO.File]::Exists($target)) {
                $choice = Get-ExistingClipChoice $item.Movie
                if ($choice -eq 'Stop') {
                    $entry.Status = 'SKIPPED'; $entry.Detail = 'The existing clip was kept and the run was stopped here.'
                    $script:State.CancelRequested = $true
                    Add-Log "Stopped at an existing clip: $($item.Movie)" ([System.Drawing.Color]::Orange)
                    break
                }
                if ($choice -eq 'Keep') {
                    $entry.Status = 'SKIPPED'; $entry.Detail = 'A clip already existed and was kept.'
                    Add-Log "Kept the existing clip: $target"
                    Set-Progress $index $work.Count
                    continue
                }
            }

            $probe = Invoke-Tool -FilePath $ffprobe -TimeoutSeconds 120 -Arguments (
                '-v error -select_streams V:0 -show_entries stream=duration:format=duration -of "default=noprint_wrappers=1:nokey=1" "{0}"' -f $movie.FullName)
            if ($probe.Stopped) { $entry.Status = 'SKIPPED'; $entry.Detail = 'Stopped before the clip was made.'; break }
            $duration = ConvertFrom-ProbeDuration $probe.StdOut
            $start = Get-ClipStart $duration $current.ClipLength $current.AvoidSeconds

            if ($duration -le 0) {
                $entry.Detail = "FFprobe couldn't read how long this video is."
                if ($probe.TimedOut) { $entry.Detail = 'FFprobe took more than 2 minutes to read this file and was stopped.' }
                if ($probe.StdErr.Trim()) { $entry.Detail += "`r`n" + $probe.StdErr.Trim() }
                Add-Log "Couldn't read the length of $($movie.Name)" ([System.Drawing.Color]::Salmon)
            } elseif ($start -lt 0) {
                $entry.Status = 'SKIPPED'
                $entry.Detail = 'This video is shorter than the clip length ({0:N0} seconds).' -f $duration
                Add-Log "Skipped $($movie.Name): shorter than the clip length."
            } else {
                $createdFolder = -not [System.IO.Directory]::Exists($backdrops)
                [void][System.IO.Directory]::CreateDirectory($backdrops)
                $partFile = $target + '.part'
                Add-Log ('Making a clip of {0} from {1}' -f $movie.Name, (Format-TimeLeft $start))
                $lblStatus.Text = "Movie $index of $($work.Count): making the clip..."

                $run = Invoke-Tool -FilePath $ffmpeg -Arguments (Get-FfmpegArgumentList $start $current.ClipLength $movie.FullName $partFile)
                $detail = ($run.StdErr + "`r`n" + $run.StdOut).Trim()

                if (-not $run.Stopped -and $run.ExitCode -eq 0 -and [System.IO.File]::Exists($partFile) -and (New-Object System.IO.FileInfo($partFile)).Length -gt 0) {
                    if ([System.IO.File]::Exists($target)) { [System.IO.File]::Delete($target) }
                    [System.IO.File]::Move($partFile, $target)
                    $created++
                    $lblCreated.Text = "$created"
                    if ($detail) {
                        $entry.Status = 'WARNING'; $entry.Detail = $detail
                        Add-Log "Made, with FFmpeg warnings: $target" ([System.Drawing.Color]::Khaki)
                    } else {
                        $entry.Status = 'SUCCESS'; $entry.Detail = 'Clip created from {0}.' -f (Format-TimeLeft $start)
                        Add-Log "Saved: $target" ([System.Drawing.Color]::LightGreen)
                    }
                } else {
                    if ([System.IO.File]::Exists($partFile)) { [System.IO.File]::Delete($partFile) }
                    if ($createdFolder) { Remove-EmptyFolder $backdrops }
                    if ($run.Stopped) {
                        $entry.Status = 'SKIPPED'; $entry.Detail = 'Stopped while this clip was being made; nothing was saved.'
                        Add-Log "Stopped while making the clip of $($movie.Name)." ([System.Drawing.Color]::Orange)
                        break
                    }
                    if (-not $detail) { $detail = "FFmpeg stopped with code $($run.ExitCode) and didn't make a clip." }
                    $entry.Detail = $detail
                    Add-Log "FFmpeg couldn't make a clip of $($movie.Name)" ([System.Drawing.Color]::Salmon)
                }
            }

            Set-Progress $index $work.Count
            $perMovie = ((Get-Date) - $runStarted).TotalSeconds / $index
            $lblTimeLeft.Text = Format-TimeLeft ($perMovie * ($work.Count - $index))
        }

        # ----- Finish -----
        $stopped = $script:State.CancelRequested
        $runInfo = @{
            MoviesFolder = $moviesFolder; OutputFolder = $outputFolder
            ClipLength = $current.ClipLength; AvoidSeconds = $current.AvoidSeconds
            Finished = Get-Date; Stopped = $stopped; Created = $created
        }
        $reportPath = $null
        try {
            $reportPath = Save-Report -Entries $entries -Run $runInfo
            Add-Log "Report saved: $reportPath" ([System.Drawing.Color]::LightSkyBlue)
        } catch {
            Add-Log "The report couldn't be saved: $($_.Exception.Message)" ([System.Drawing.Color]::Salmon)
        }

        if ($script:State.CloseWhenDone) { return }

        if ($stopped) {
            $lblStatus.Text = 'Stopped'
            Add-Log "Stopped. $created clip(s) were made before it stopped." ([System.Drawing.Color]::Orange)
            $question = "Stopped.`r`n`r`n$created clip(s) were made before it stopped.`r`n`r`nView the report?"
        } else {
            Set-Progress 1 1
            $lblStatus.Text = 'Finished'
            $lblTimeLeft.Text = Format-TimeLeft 0
            Add-Log "Finished. Made $created clip(s)." ([System.Drawing.Color]::LightGreen)
            $question = "Finished.`r`n`r`nMade $created clip(s).`r`n`r`nView the report?"
        }
        if ($reportPath -and (Show-Message $question $AppName 'YesNo' 'Information') -eq 'Yes') {
            Start-Process -FilePath $reportPath
        }
        if ($created -gt 0 -and (Show-Message 'Open the output folder to see the clips?' $AppName 'YesNo' 'Question') -eq 'Yes') {
            Start-Process -FilePath 'explorer.exe' -ArgumentList ('"{0}"' -f $outputFolder)
        }
    } catch {
        Write-CrashLog 'Create clips' $_
        $lblStatus.Text = 'Something went wrong'
        Add-Log "Something went wrong: $($_.Exception.Message)" ([System.Drawing.Color]::Salmon)
        [void](Show-Message ("Something went wrong and the run stopped.`r`n`r`n$($_.Exception.Message)`r`n`r`n" +
            "Details are in $(Join-Path $script:LogsDir 'crash.log')") $AppName 'OK' 'Error')
    } finally {
        Set-RunningState $false
        $lblCurrent.Text = '-'
        if ($script:State.CloseWhenDone) { $form.Close() }
    }
}

function Show-About {
    $about = New-Object System.Windows.Forms.Form
    $about.SuspendLayout()
    $about.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::None
    $about.Text = "About $AppName"
    $about.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterParent
    $about.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
    $about.MaximizeBox = $false
    $about.MinimizeBox = $false
    $about.ShowInTaskbar = $false
    $about.BackColor = [System.Drawing.Color]::White
    $about.Font = New-Font 9.75
    $about.AutoSize = $true
    $about.AutoSizeMode = [System.Windows.Forms.AutoSizeMode]::GrowAndShrink

    $layout = New-Object System.Windows.Forms.TableLayoutPanel
    $layout.AutoSize = $true
    $layout.ColumnCount = 2
    $layout.Padding = New-Object System.Windows.Forms.Padding((S 20), (S 18), (S 20), (S 16))
    [void]$layout.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::AutoSize)))
    [void]$layout.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::AutoSize)))

    $logo = New-Object System.Windows.Forms.PictureBox
    $logo.Size = New-Object System.Drawing.Size((S 72), (S 72))
    $logo.SizeMode = [System.Windows.Forms.PictureBoxSizeMode]::Zoom
    $logo.Image = $logoImage
    $logo.Margin = New-Object System.Windows.Forms.Padding((S 0), (S 0), (S 16), (S 0))
    $layout.Controls.Add($logo, 0, 0)
    $layout.SetRowSpan($logo, 2)

    $title = New-Label $AppName 18 ([System.Drawing.FontStyle]::Bold) $Colour.Navy
    $title.Margin = New-Object System.Windows.Forms.Padding((S 0), (S 4), (S 0), (S 0))
    $layout.Controls.Add($title, 1, 0)
    $version = New-Label "Version $AppVersion" 10 ([System.Drawing.FontStyle]::Regular) $Colour.Hint
    $version.Margin = New-Object System.Windows.Forms.Padding((S 2), (S 0), (S 0), (S 10))
    $layout.Controls.Add($version, 1, 1)

    $lines = @(
        @('', 'PowerShell/WinForms tool for making a random theme clip from every movie in a folder. Each clip is saved as backdrops\theme.mp4 for Jellyfin, Emby or Kodi.'),
        @('', ($Copyright + '. Released under the MIT licence.')),
        @('link', $RepoUrl),
        @('', 'Video processing by FFmpeg (ffmpeg.org), installed separately. FFmpeg is a trademark of Fabrice Bellard.'),
        @('', 'Written with AI assistance from ChatGPT (OpenAI), reviewed and rebuilt with Claude (Anthropic).'),
        @('', "Settings and reports: $script:DataDir")
    )
    $row = 2
    foreach ($line in $lines) {
        if ($line[0] -eq 'link') {
            $control = New-Object System.Windows.Forms.LinkLabel
            $control.Text = $line[1]
            $control.AutoSize = $true
            $control.LinkColor = $Colour.Blue
            $control.Add_LinkClicked({ Start-Process -FilePath $RepoUrl })
        } else {
            $control = New-Label $line[1] 9.75 ([System.Drawing.FontStyle]::Regular) ([System.Drawing.Color]::FromArgb(40, 55, 75))
            $control.MaximumSize = New-Object System.Drawing.Size((S 470), (S 0))
        }
        $control.Margin = New-Object System.Windows.Forms.Padding((S 2), (S 4), (S 0), (S 4))
        $layout.Controls.Add($control, 0, $row)
        $layout.SetColumnSpan($control, 2)
        $row++
    }

    $ok = New-Object System.Windows.Forms.Button
    $ok.Text = 'OK'
    $ok.Size = New-Object System.Drawing.Size((S 96), (S 30))
    $ok.Anchor = [System.Windows.Forms.AnchorStyles]::Right
    $ok.DialogResult = [System.Windows.Forms.DialogResult]::OK
    $ok.Margin = New-Object System.Windows.Forms.Padding((S 0), (S 12), (S 0), (S 0))
    $layout.Controls.Add($ok, 0, $row)
    $layout.SetColumnSpan($ok, 2)
    $about.AcceptButton = $ok
    $about.CancelButton = $ok
    $about.Controls.Add($layout)
    $about.ResumeLayout($false)
    $about.PerformLayout()

    [void]$about.ShowDialog($form)
    $about.Dispose()
}

# ----- Events -----
$btnBrowseMovies.Add_Click({
    $picked = Select-Folder 'Choose your movies folder (mapped drives and \\NAS\share paths work)' $txtMovies.Text
    if ($picked) { $txtMovies.Text = $picked }
})

$btnBrowseOutput.Add_Click({
    $initial = $txtOutput.Text
    if (-not $initial) { $initial = $txtMovies.Text }
    $picked = Select-Folder 'Choose where to save the clips' $initial
    if ($picked) { $txtOutput.Text = $picked }
})

$btnClearLog.Add_Click({ $txtLog.Clear() })

$btnReports.Add_Click({
    [void][System.IO.Directory]::CreateDirectory($script:ReportsDir)
    Start-Process -FilePath 'explorer.exe' -ArgumentList ('"{0}"' -f $script:ReportsDir)
})

$btnOpen.Add_Click({
    $folder = $txtOutput.Text.Trim()
    if ($folder -and [System.IO.Directory]::Exists($folder)) {
        Start-Process -FilePath 'explorer.exe' -ArgumentList ('"{0}"' -f $folder)
    } else {
        [void](Show-Message "The output folder doesn't exist yet. It's created when you make the first clips." 'Output folder')
    }
})

$btnCheck.Add_Click({
    $ffmpeg = Find-Tool 'ffmpeg'
    $ffprobe = Find-Tool 'ffprobe'
    if ($ffmpeg -and $ffprobe) {
        $versionLine = ''
        try {
            $check = Invoke-Tool -FilePath $ffmpeg -Arguments '-hide_banner -version' -TimeoutSeconds 15
            $versionLine = ($check.StdOut -split "`r?`n" | Select-Object -First 1)
        } catch { Write-Verbose $_.Exception.Message }
        Add-Log "FFmpeg found: $ffmpeg" ([System.Drawing.Color]::LightGreen)
        [void](Show-Message "FFmpeg and FFprobe were found.`r`n`r`n$versionLine`r`n`r`nFFmpeg:  $ffmpeg`r`nFFprobe: $ffprobe" 'Check FFmpeg')
    } else {
        Add-Log "FFmpeg or FFprobe wasn't found." ([System.Drawing.Color]::Salmon)
        [void](Show-Message ("FFmpeg and/or FFprobe couldn't be found.`r`n`r`n" +
            "Install FFmpeg with:  winget install Gyan.FFmpeg`r`nthen restart $AppName.`r`n`r`n" +
            "Or put ffmpeg.exe and ffprobe.exe in the same folder as $AppName.") 'Check FFmpeg' 'OK' 'Warning')
    }
})

$btnStop.Add_Click({
    if (-not $script:State.Running) { return }
    if ($script:State.CancelRequested) {
        # Second press: stop the clip that's being made as well
        $script:State.StopNow = $true
        Add-Log 'Stopping now.' ([System.Drawing.Color]::Orange)
        return
    }
    $script:State.CancelRequested = $true
    $btnStop.Text = "Stop now`n(abandon this clip)"
    Add-Log "Stopping after this movie's clip. Press Stop again to stop straight away." ([System.Drawing.Color]::Orange)
})

$btnStart.Add_Click({
    if ($script:State.Running) { return }
    try { Invoke-ClipRun }
    finally { $btnStop.Text = "Stop`n(after this clip)" }
})

$btnAbout.Add_Click({ Show-About })

$form.Add_Shown({
    # Fit the window on small or scaled screens
    $area = [System.Windows.Forms.Screen]::FromControl($form).WorkingArea
    if ($form.Width -gt $area.Width -or $form.Height -gt $area.Height) {
        $form.Width = [Math]::Min($form.Width, $area.Width)
        $form.Height = [Math]::Min($form.Height, $area.Height)
        $form.Location = $area.Location
    }
    $btnAbout.Left = $header.ClientSize.Width - $btnAbout.Width - (S 18)
    if (-not $txtMovies.Text) {
        Add-Log 'Welcome. Choose your movies folder and an output folder, then press Create clips.' ([System.Drawing.Color]::LightSkyBlue)
    } else {
        Add-Log 'Ready. Press Create clips to start.' ([System.Drawing.Color]::LightSkyBlue)
    }
    if (-not (Find-Tool 'ffmpeg') -or -not (Find-Tool 'ffprobe')) {
        Add-Log "FFmpeg wasn't found. Press Check FFmpeg for how to install it." ([System.Drawing.Color]::Khaki)
    }
})

$form.Add_FormClosing({
    param($eventSource, $e)
    if ($script:State.Running) {
        $answer = Show-Message 'Clips are still being made. Stop and close?' $AppName 'YesNo' 'Question'
        $e.Cancel = $true
        if ($answer -eq 'Yes') {
            # Stop straight away; the run finishes, saves its report, then closes the window
            $script:State.CancelRequested = $true
            $script:State.StopNow = $true
            $script:State.CloseWhenDone = $true
        }
        return
    }
    Export-Setting (Get-CurrentSetting)
})

Set-RunningState $false

try {
    [void]$form.ShowDialog()
} catch {
    Write-CrashLog 'Window' $_
    [System.Windows.Forms.MessageBox]::Show("$AppName closed because of an error:`r`n`r`n$($_.Exception.Message)", $AppName, 'OK', 'Error') | Out-Null
} finally {
    if ($logoImage) { $logoImage.Dispose() }
    $form.Dispose()
}
