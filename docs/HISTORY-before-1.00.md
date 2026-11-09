# History before v1.00

This is the development history of Clip Creator before it moved to the house-style version
numbering. Versions were renumbered at v1.00 (2026-11-07); see [CHANGELOG.md](../CHANGELOG.md)
for everything since. Names below are as they were at the time: the script was
`clip-creator.ps1` in the repo root, the window was titled "Random Movie Clips", and the
exe was "Clip Creator v1.x.x.exe". Versions 1.3.1 and 1.4.0 were never committed or tagged
on their own; their changes arrived with 1.5.0.

## [1.5.0]

### Added

- Added a partial HTML conversion log when processing is stopped before completion.
- Added a prompt to view the partial HTML conversion log after cancellation.
- Added a separate prompt to open the partial output folder containing clips created before cancellation.
- Partial reports clearly identify that processing was stopped by the user and include results up to the cancellation point.

### Changed

- Simplified generated clip folder structure.
- Removed the unnecessary extra folder based on the source video filename.
- Clips are now written directly to `Movie Folder\backdrops\theme.mp4`.
- Application version updated from **1.4.0** to **1.5.0**.
- About window now displays **Version 1.5.0**.
- Recommended executable filename is now `Clip Creator v1.5.0.exe`.

### Example

Previous output:

```text
Mad Max (1979)
└── Mad Max
    └── backdrops
        └── theme.mp4
```

New output:

```text
Mad Max (1979)
└── backdrops
    └── theme.mp4
```


## [1.4.0]

### Added

- Added the option to stop all remaining file creations when an existing `theme.mp4` is encountered.
- Existing-clip prompt now clearly explains the Yes, No and Cancel actions.
- Cancellation from the existing-clip prompt is recorded in the HTML processing log.

### Changed

- **Yes** overwrites the existing clip.
- **No** keeps the existing clip and continues processing.
- **Cancel** keeps the existing clip and stops files being created.
- Application version updated from **1.3.1** to **1.4.0**.
- About window now displays **Version 1.4.0**.
- Recommended executable filename is now `Clip Creator v1.4.0.exe`.


## [1.3.1]

### Fixed

- Fixed repeated `Cannot bind argument to parameter 'Path' because it is null` dialogs in the PS2EXE-compiled application.
- Fixed repeated `Cannot bind argument to parameter 'Path' because it is an empty string` dialogs when starting an export.
- Replaced PowerShell stream redirection used by FFprobe with .NET `ProcessStartInfo`.
- Replaced PowerShell stream redirection used by FFmpeg with .NET `ProcessStartInfo`.
- FFmpeg and FFprobe output/error streams are now captured directly without triggering PS2EXE path-binding errors.

### Changed

- Retains FFmpeg diagnostic capture for the HTML processing report using the new process-handling method.
- Application version updated from **1.3.0** to **1.3.1**.
- About window now displays **Version 1.3.1**.
- Recommended executable filename is now `Clip Creator v1.3.1.exe`.


## [1.3.0]

### Added

- Network-aware Windows Shell folder picker for the Movies Folder.
- Network-aware Windows Shell folder picker for the Output Folder.
- Improved support for mapped network drives used by NAS movie libraries.
- Support for selecting UNC network shares such as `\\Synology\Movies`.
- Fallback to the standard Windows Forms folder picker if Windows Shell browsing is unavailable.

### Changed

- Folder browsing now exposes local folders, This PC, mapped network drives and Windows network locations more reliably.
- Improved usability for movie collections stored on Synology and other NAS devices.
- Application version updated from **1.2.0** to **1.3.0**.
- About window now displays **Version 1.3.0**.
- Recommended executable filename is now `Clip Creator v1.3.0.exe`.


## [1.2.0]

### Added

- Self-contained HTML processing report generated after completed runs.
- Colour-coded summary for successful clips, warnings, errors and skipped movies.
- Detailed per-movie report containing output paths and FFmpeg diagnostics.
- Capture of FFmpeg diagnostic output for inclusion in the report.
- Prompt to view the HTML log in the default web browser.
- Timestamped report filenames so separate run reports are retained.

### Changed

- Successfully created clips that also produce FFmpeg diagnostic messages can be identified as warnings.
- Processing diagnostics are retained in a readable web report.
- Application version updated from **1.1.0** to **1.2.0**.
- About window now displays **Version 1.2.0**.
- Recommended executable filename is now `Clip Creator v1.2.0.exe`.


## [1.1.0]

### Added

- Preserves the source directory structure beneath the selected Movies Folder.
- Creates a `backdrops` directory inside each generated movie folder.
- Stores generated clips as `backdrops\theme.mp4`.
- Adds path-safety checks so rooted or drive-qualified source paths cannot accidentally be appended to the output folder.

### Fixed

- Fixed invalid output paths that could include a source drive letter such as `V:\` beneath the destination folder.
- Fixed the `GetFullPath()` empty-path error caused by the incorrect `$moviesFolder` variable reference; folder handling now correctly uses `$movieFolder`.

### Changed

- Application version updated from **1.0.0** to **1.1.0**.
- About window now displays **Version 1.1.0**.
- Recommended executable filename is now `Clip Creator v1.1.0.exe`.
- README updated for the new folder and `backdrops` output structure.


## [1.0.0]

### Added

-   Modern cinematic Windows Forms interface.
-   One random clip from each movie.
-   MP4 output saved as `theme.mp4`.
-   Separate output folder for each movie.
-   Configurable clip length and start/end avoidance period.
-   Optional recursive subfolder searching.
-   Support for common movie formats.
-   Progress percentage, current movie, time-left estimate and
    clips-created counter.
-   FFmpeg installation check.
-   Existing clip detection with overwrite confirmation.
-   Stop/cancel processing.
-   Open Output Folder control.
-   Completion prompt offering to open the output directory.
-   About dialog with creator, AI-assistance and FFmpeg credits.
-   Application version displayed in the About window.
-   Visual pressed-state feedback on the main GUI buttons.
-   MIT License and GitHub documentation.

### Changed

-   Recommended compiled executable filename is now
    `Clip Creator v1.0.0.exe`.
-   About header now displays
    `Version 1.0.0 • FFmpeg Movie Clip Utility`.
-   About description area was widened so the full description is
    visible.
-   README now includes PS2EXE build instructions and the versioned EXE
    naming convention.

### Fixed

-   Added explicit DPI-awareness handling for the compiled PS2EXE
    version.
-   Disabled Windows Forms automatic scaling to improve consistency
    between the `.ps1` and compiled `.exe`.
-   Improved alignment of the Movies Folder and Output Folder controls.
-   Improved progress percentage positioning and sizing.
-   Improved Current Movie, Time Left and Clips Created layout.
-   Corrected several About-window text and alignment issues.

### Packaging

-   Product: `Clip Creator`
-   Version: `1.0.0`
-   Recommended executable: `Clip Creator v1.0.0.exe`
-   PowerShell source: `clip-creator.ps1`
