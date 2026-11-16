<p align="center">
  <img src="assets/Clip-Creator.png" alt="Clip Creator logo" width="160">
</p>

# Clip Creator

A Windows app that makes one short random clip from every movie in a folder, ready to use as a Jellyfin, Emby or Kodi theme video.

![Version](https://img.shields.io/badge/version-v1.01-blue) ![Platform](https://img.shields.io/badge/platform-Windows-0078D6) ![PowerShell](https://img.shields.io/badge/PowerShell-5.1-5391FE) ![Licence](https://img.shields.io/badge/licence-MIT-green) ![Last commit](https://img.shields.io/github/last-commit/jason4bury/Clip-Creator)

## ✨ Features

Clip Creator is a front end for [FFmpeg](https://ffmpeg.org/). For each movie it picks a random point, away from the opening titles and end credits, cuts a short clip and saves it as `backdrops\theme.mp4` in a folder that matches the movie's own folder.

- **One clip per movie**: 10 seconds by default (1 to 600), starting at a random point
- **Avoids the start and end**: keeps clear of the first and last 60 seconds by default, when the movie is long enough
- **Keeps your folder layout**: `Mad Max (1979)\Mad Max.mkv` becomes `<output>\Mad Max (1979)\backdrops\theme.mp4`. Pick the movies folder itself as the output to save the clips straight into your library
- **Plays everywhere**: H.264 video and stereo AAC sound in an MP4, even from 10-bit HDR movies with 5.1 or 7.1 sound
- **Skips extras**: trailers, samples, `Extras`/`Featurettes` folders and existing `backdrops` folders are never treated as movies, so a second run never makes clips of clips. If a folder holds two videos (CD1/CD2 or two editions), the largest is used
- **Existing clips**: ask each time, always keep, or always replace
- **Safe to stop**: Stop finishes the current clip and stops; press it again to stop straight away. A clip is only saved once it's complete, so an existing `theme.mp4` is never lost to a failed or stopped run
- **Network friendly**: mapped drives and `\\NAS\share` paths work, and folders that can't be read are skipped rather than ending the run
- **Colour HTML report** after every run (and partial runs), with created, warnings, errors and skipped, and FFmpeg's own messages for anything that went wrong
- **Progress at a glance**: percentage, current movie, time left and clips created, with a colour log
- Remembers your folders and settings between runs

## 🖼️ Screenshots

![Clip Creator main window](docs/screenshots/main-window.png)

## 📋 Requirements

- Windows 10 or 11 with Windows PowerShell 5.1 (built in, nothing to install)
- [FFmpeg](https://ffmpeg.org/) with `ffmpeg.exe` and `ffprobe.exe`. The easiest way is `winget install Gyan.FFmpeg`, which adds both to `PATH`. You can also put the two files in the same folder as `Clip-Creator.ps1`. The **Check FFmpeg** button says whether they were found

## 📦 Installation

1. Download `Clip-Creator-v1.01.zip` from the [latest release](../../releases/latest). Right-click it, choose **Properties** and tick **Unblock** *before* unzipping, so Windows doesn't block the scripts. Then unzip it wherever you like to keep it.
2. Double-click **Clip Creator.cmd** in the unzipped folder. It makes a **Clip Creator** shortcut there and in the Start menu, and starts Clip Creator. From then on, use the shortcut, the Start menu or a pinned taskbar button.

Nothing is installed apart from FFmpeg, and no Windows settings are changed. The shortcut runs the script with PowerShell's execution policy bypassed for that run only. If Clip Creator doesn't open, run `"Clip Creator.cmd" debug` from a command prompt in that folder to see any errors.

**From the repo:** clone it, or download it as a zip (unblock it first, as above), then double-click **Start Clip Creator.cmd**.

**Updating from v1.00 (the exe):** unzip the new release, double-click **Clip Creator.cmd**, and delete `Clip Creator v1.00.exe` and any shortcut to it. Your settings and reports are in `%APPDATA%\Clip Creator\`, so they carry straight over. If you kept `ffmpeg.exe` and `ffprobe.exe` beside the old exe, move them into the new folder (beside `Clip-Creator.ps1`) or install FFmpeg with winget.

### Why no exe

Home tools used to ship as PS2EXE exes, and antivirus programs (ESET among them) kept flagging those exes as generic trojans by mistake. A plain script and a shortcut give the same one-click start without the false alarms, and you can read exactly what runs.

### Build a release

Double-click **Build.cmd** in the repo folder. It reads `build.json`, checks every script for syntax errors and that `$AppVersion` matches the newest `CHANGELOG.md` entry, runs PSScriptAnalyzer if it's installed, copies the release files into `..\Builds\Clip Creator v<version>\`, zips that folder for the GitHub release, refreshes `..\Builds\Clip Creator.lnk` (what the Home Launcher starts) and scans the result with ESET's command-line scanner if it's installed.

## 🚀 Usage

Start Clip Creator from its shortcut, the Start menu or **Clip Creator.cmd**.

1. Choose your **Movies folder**, for example `V:\Movies` or `\\NAS\Movies`.
2. Choose an **Output folder**. Use a separate folder to check the clips first, or the movies folder itself to save them straight into your library.
3. Set the clip length and how much of the start and end to avoid, and whether to include subfolders.
4. Press **Create clips**.

When the run finishes, Clip Creator offers to open the report and the output folder.

### Where the clips go

```
Movies folder                          Output folder
V:\Movies\Mad Max (1979)\Mad Max.mkv   ->  D:\Clips\Mad Max (1979)\backdrops\theme.mp4
V:\Movies\Sci-Fi\Alien (1979)\Alien.mkv ->  D:\Clips\Sci-Fi\Alien (1979)\backdrops\theme.mp4
V:\Movies\Loose Movie.mp4              ->  D:\Clips\Loose Movie\backdrops\theme.mp4
```

A movie sitting directly in the movies folder (not in a folder of its own) gets a folder named after the file. With **Include subfolders** off, only those loose files are used.

### Stopping

Press **Stop** once to stop after the clip that's being made. Press it again to stop straight away; the half-made clip is thrown away. Closing the window while clips are being made asks first. Either way, a partial report lists everything handled so far.

### Troubleshooting

- **"FFmpeg or FFprobe wasn't found"**: run `winget install Gyan.FFmpeg`, then restart Clip Creator (a new `PATH` only reaches programs started afterwards).
- **A mapped drive is missing from Browse**: drives mapped as your normal user don't show up in programs run as administrator. Start Clip Creator normally; it doesn't need admin rights. Typing or pasting a `\\NAS\share` path always works.
- **A movie is marked ERROR**: the report shows FFmpeg's message. Damaged files and some old formats can't be read; the run carries on with the next movie.
- **The time left jumps about**: it's based on the movies done so far, so it settles as the run goes on.
- **"Running scripts is disabled"**: start it with the Clip Creator shortcut or **Clip Creator.cmd**, which bypass the execution policy for Clip Creator only.
- **Something went wrong**: details are written to `Logs\crash.log` in the data folder (see Configuration).

## ⚙️ Configuration

Settings and reports are kept in:

```
%APPDATA%\Clip Creator\
```

| File or folder | What it holds |
| --- | --- |
| `settings.json` | movies and output folders, clip length, start/end gap, file types, subfolders and what to do with existing clips |
| `Reports\` | an HTML report from each run, named `Clip-Creator-Report-<date>-<time>.html` (the newest 50 are kept). **Reports** in the Log panel opens it |
| `Logs\crash.log` | details of anything that went wrong |

All the settings are on the main window and are saved when you start a run or close Clip Creator. None of this is part of the repository, so your folder paths and movie names stay on your PC. Versions before v1.00 saved their reports in the output folder; those old files can be deleted.

FFmpeg settings used for every clip: H.264 (`libx264`, preset `fast`, CRF 20, `yuv420p`), AAC stereo at 192 kbit/s, MP4 with `faststart`.

## 📝 Changelog

See [CHANGELOG.md](CHANGELOG.md). History from before the v1.00 renumbering is in [docs/HISTORY-before-1.00.md](docs/HISTORY-before-1.00.md).

## 📄 Licence

MIT, see [LICENSE](LICENSE). Copyright (c) 2026 Jason Rhodes.

Clip Creator uses [FFmpeg](https://ffmpeg.org/), which you install separately; it isn't included in this repository or the release. FFmpeg is licensed under the LGPL/GPL and is a trademark of Fabrice Bellard. Written with AI assistance from ChatGPT (OpenAI), and reviewed and rebuilt with Claude (Anthropic). Font: Segoe UI from Microsoft Windows.
