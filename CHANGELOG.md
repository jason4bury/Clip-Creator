# Changelog

All notable changes to Clip Creator are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), with versions numbered
`<major>.<minor>` and a two-digit minor (v1.00, v1.01 ... v1.10) to match the release names.

## [Unreleased]

## [1.02] - 2026-11-19
### Changed
- **Messages and questions in Clip Creator's own look.** Every message and question now opens in a
  Clip Creator window (navy header with a coloured badge, the message on a white card, blue and slate
  buttons) instead of Windows' plain grey message box. `Show-Message` draws it, keeping the same
  answers (OK, Yes, No, Cancel), so the rest of the code didn't change. The text can be selected and
  copied, and a long message scrolls.
- Questions have plainly named buttons: an existing clip asks **Replace it**, **Keep it** or
  **Keep it and stop**; the end of a run asks **View report** / **Not now** and **Open folder** /
  **Not now**; closing during a run asks **Stop and close** or **Keep going**. Enter presses the main
  button; the safe one has the focus, and Esc or the X picks it.
- About notes what's new in 1.02.
- Unchanged: the box shown if Clip Creator closes because of an error, and the folder pickers.

## [1.01] - 2026-11-16
### Changed
- **No exe any more.** Antivirus programs (ESET among them) kept flagging the PS2EXE exe as a
  generic trojan by mistake, so Clip Creator now ships as its script, like the other Home tools.
  The release is `Clip-Creator-v1.01.zip`: unzip it and double-click **Clip Creator.cmd**, which
  makes a **Clip Creator** shortcut (in that folder and in the Start menu) that starts Clip Creator
  without a console window. `"Clip Creator.cmd" debug` starts it in the console to show any errors.
  Settings and reports stay in `%APPDATA%\Clip Creator`, so nothing needs moving.
- The taskbar button shows Clip Creator's own icon (not PowerShell's), and pinning it pins Clip
  Creator: the script sets the same taskbar ID (`jason4bury.Clip-Creator`) as the shortcut.
- The window icon comes from `assets\Clip-Creator.ico`, beside the script in a release or in
  `Source\assets\` in the repo.
- FFmpeg beside the program now means beside `Clip-Creator.ps1` (FFmpeg on `PATH` works as before).
- `Build.cmd` (the Home template build) replaces `Build-Exe.cmd`. It checks the scripts and the
  version, runs PSScriptAnalyzer, makes `Builds\Clip Creator v<version>\` and its zip, refreshes
  `Builds\Clip Creator.lnk` for the Home Launcher and scans the build with ESET if it's installed.
  `build.json` has a Release section instead of the ps2exe options.

### Internal
- Exe-only code removed (the exe check, the exe-folder FFmpeg look-up and taking the icon from
  the exe). New `src\New-ClipCreatorShortcut.ps1` (template shortcut maker) and
  `release\Clip Creator.cmd`. `.gitignore` covers `*.lnk`.

## [1.00] - 2026-11-07
First release in the house style, and a full review and rebuild of the script. Version
numbers restart here; the history before this (1.0.0 to 1.5.0) is kept in
[docs/HISTORY-before-1.00.md](docs/HISTORY-before-1.00.md).

### Added
- **Settings are remembered** in `%APPDATA%\Clip Creator\settings.json`: folders, clip
  length, start/end gap, file types, subfolders and the existing-clip choice.
- **"If a clip already exists"** setting: ask each time (as before), always keep, or
  always replace, so a big library doesn't mean a prompt for every movie.
- **Movie file types** can now be edited. The box was part of the old window's picture and
  couldn't be changed.
- **Stop now**: pressing Stop a second time abandons the clip that's being made instead of
  waiting for it to finish. Closing the window during a run asks first.
- **Reports** button in the Log panel opens the folder of HTML reports.
- Check FFmpeg shows the FFmpeg version and how to install it with winget.

### Changed
- **New window built from real controls.** The old window was one large picture with
  invisible buttons on top, which blurred when scaled, said "Random Movie Clips" and
  "10-second" whatever the settings, and had a maximise button that did nothing. The new
  window keeps the same layout and colours, is a normal resizable Windows window, scales
  sharply at 125% and 150%, and the script is 110 KB instead of 2.9 MB.
- **One name everywhere**: Clip Creator in the window title, About box, reports and exe.
- **Reports are saved in `%APPDATA%\Clip Creator\Reports\`** instead of the output folder,
  so they don't land in your media library. The newest 50 are kept. Finished and stopped
  runs use the same report, which now also lists the folders and settings used.
- **Extras are skipped**: videos in `backdrops`, `Extras`, `Trailers`, `Featurettes` and
  similar folders, and files named like `-trailer` or `sample`, are not treated as movies.
- **Clips play on more devices**: 10-bit and HDR movies give standard 8-bit H.264, and
  5.1/7.1 sound becomes stereo AAC. The first real video stream is used, never cover art.
- The window stays responsive while a clip is made, and the scan of a big NAS folder can
  be stopped.
- New installs start with empty folders instead of `D:\Movies` and `D:\Random Clips`.
- Browse uses the modern Windows folder picker, which accepts typed or pasted `\\NAS\share`
  paths, and no longer limits browsing to folders below the one already chosen.
- About shows the version, copyright, MIT licence, a link to the GitHub repo and where
  settings are kept.
- **New repo layout.** The script is `src/Clip-Creator.ps1`, the icon and logo are in
  `assets/`, and older history is in `docs/`. Builds go to the project's `Builds\` folder,
  outside the repo, named `Clip Creator v<version>.exe`, using `build.json` or
  `Build-Exe.cmd`. `Start Clip Creator.cmd` starts the script.
- The icon has 16 to 256 px sizes; the small ones drop the "clip-creator" text, which
  was unreadable at taskbar size.

### Fixed
- **Movies directly in the movies folder all wrote to the same clip.** Since 1.5.0, every
  loose file (and every movie when Include subfolders was off) was saved as
  `<output>\backdrops\theme.mp4`, each replacing the last. Each loose movie now gets a
  folder named after the file.
- **A folder with two videos made two clips in the same place**, asking to overwrite the
  first. The largest video is used and the others are listed as skipped.
- **A second run made clips of the clips** when the output was inside the movies folder,
  and of `backdrops\theme.mp4` files when the output was the movies folder.
- **A failed or stopped clip could delete the existing one.** Clips are written to a
  `.part` file and only replace `theme.mp4` once FFmpeg has finished successfully.
- Stop only took effect after the current clip, and the window froze while FFmpeg ran.
- Pressing Create clips during a run started a second run inside the first.
- Movies shorter than the clip are listed as skipped, not as "could not obtain a usable
  duration" errors.
- Files whose container doesn't record a length are read from the video stream instead.
- Folders that can't be read on a NAS are skipped and counted, instead of silently
  hiding everything below them.
- Esc no longer closes the window without asking.
- Time left shows hours past 24 correctly.

### Internal
- Duplicate report code merged, processing split into small functions, and the
  embedded 2.2 MB background image removed. Comment-based help, and `$AppName`,
  `$AppVersion` and `$Copyright` set once at the top.
- FFmpeg and FFprobe output is read in the background, so a chatty file can't hang the
  run; FFprobe gives up after 2 minutes on an unresponsive file.
- PSScriptAnalyzer-ready: approved verbs and singular nouns, no `$sender`, no empty
  `catch` blocks. Added `PSScriptAnalyzerSettings.psd1`.
- `RELEASE-NOTES-v1.5.0.md` removed; GitHub Releases carry the notes from now on.
