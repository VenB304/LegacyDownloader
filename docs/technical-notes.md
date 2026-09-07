# Technical notes

Implementation details for whoever works on this codebase next (including a
future me). Not needed to just use the tool — see the [tutorials](tutorial/)
or the main [README](../README.md) for that.

## Technical notes (V3–V5)

- **Size-only comparison** (`--size-only`): exFAT rounds modification times to
  a 2-second grid, so a mtime-based check re-downloaded roughly half the library
  on every run when the game lived on an external exFAT drive. File size is the
  reliable signal — a real update always changes it.
- **Game-folder level detection**: if `Legacy.exe` isn't directly in the
  configured folder (the Nextcloud share nests the game under a sub-folder),
  the tool detects the real location and offers to update `config.txt`.
- **Dry-run preview**: before downloading, shows per-edition file counts and
  total size. If nothing differs it reports "everything up to date" and skips
  the transfer entirely.
- **Protected files**: `Legacy.exe` and `Kinect*.dll` get a per-file confirm
  before being overwritten, so patched or modded binaries survive an update.
  `config.xml` (local game settings) is fetched once on a fresh install and
  never overwritten afterward — syncing the server's copy was resetting players'
  resolution / windowed-mode choices on every update.
- **GUI progress**: uses rclone's `--use-json-log` stats records for live
  per-file and overall progress. Dry-run (preview) uses plain-text output so
  rclone's "Skipped copy" lines remain parseable.
- **GUI headless test**: set env var `LEGACY_GUI_SELFTEST=1` before running
  `LegacyDownloader.ps1` — builds every form, dumps the control tree, and exits
  before `Application.Run`. Used in CI-style checks without a display.

## V6-era changes (unreleased, on `main`)

- **User-overridable share URL**: the WebDAV endpoint is no longer a hard-coded
  constant. `Initialize-LegacyCore` reads an optional `SHAREURL=` line from
  `config.txt` (via `Read-ConfigValue`) and builds `$script:Conn` with
  `Get-ShareConn`, which derives the Nextcloud public-share WebDAV `user=` from
  the URL's last path segment. Blank / missing / unusable falls back to
  `$script:DefaultShareUrl`. `Save-Config` never rewrites or drops a `SHAREURL`
  the user added, and emits a commented `#SHAREURL=` template otherwise. Point
  of this: if the share moves and no new build ships, people can repoint the
  tool themselves without editing `.psm1`.
- **Bracket-safe path checks**: every `Test-Path` / `Get-ChildItem` /
  `Get-Content` / `New-Item` touching a user-supplied folder now passes
  `-LiteralPath`. Without it, a game folder whose name contains `[` or `]`
  (e.g. `Just Dance [2024]`) was read as a wildcard character class, so
  `Test-GameFolder` reported the exe missing, `config.xml` protection in
  `Get-BaseSyncExcludes` silently switched off (an update then overwrote the
  player's settings), and the whole library re-downloaded as if fresh.
- **`Get-RemoteEditions` / `Get-RemoteSongs` stderr hardening**: rclone writes
  NOTICE lines to stderr, and under the module's `$ErrorActionPreference='Stop'`
  Windows PowerShell 5.1 promotes *any* native-command stderr write to a
  terminating error - even with `2>$null`. Both helpers now set
  `SilentlyContinue` for the call, wrap it in try/catch, and check
  `$LASTEXITCODE`, so an unreachable share returns `@()` (which every caller
  already handles) instead of crashing the console front-end mid-wizard. They
  deliberately don't route through `Invoke-RcloneCapture` - its
  `Start-Process -Wait` deadlocks when called straight from the GUI thread.
- **Moddable-file match widened**: the base-file bucketer keyed off a literal
  `@('legacy.exe','kinect10.dll','kinect20.dll')` list; it now matches
  `legacy.exe` or `kinect*.dll` (glob), so a differently-named Kinect shim
  (`KinectInteraction180_32.dll`, ...) still gets the per-file overwrite prompt.
- **Phantom-edition guard**: `Get-UpdatePlan`'s AUTO branch buckets songs by the
  first path segment of each `Parse-DryRun` line. It now skips lines with no
  `/` or `\` (a stray file at `maps/` root, or an unstripped log prefix) so they
  can't show up as a bogus edition in the preview.
- **In-app tutorial link**: `Get-TutorialUrl -Code` in `LegacyDownloader.Core.psm1`
  maps a language code to its `docs/tutorial/<code>.md` GitHub URL, falling back
  to English for any code not in `$script:TutorialLangs`. Wired to a `LinkLabel`
  on the Welcome dialog in `LegacyDownloader.Gui.ps1`. Update `$script:TutorialLangs`
  whenever a new tutorial translation lands.
- **Preview dialog layout fix**: `Show-PreviewDialog`'s three buttons (Show file
  list / Download now / Cancel) and the moddable-files hint label used to have
  fixed English-sized dimensions, which clipped longer translations (caught via
  French "Afficher la liste des fichiers" and the Spanish/French hint text).
  Both now measure the actual (translated) text at runtime — `TextRenderer.MeasureText`
  for button widths, plus `TextFormatFlags.WordBreak` for the hint label's wrapped
  height — instead of guessing a fixed size. Verified against all 12 languages'
  actual strings with no overlap.
- **Screenshot automation**: `tools/capture-tutorial-screenshots.ps1` (gitignored,
  local-only) drives an isolated copy of the app against a throwaway fake game
  folder to capture the Welcome/Main/Preview screenshots used in the tutorials,
  for any language. Rerun it whenever the GUI layout or a translation changes
  enough to need fresh screenshots. Two things worth knowing if you touch it:
  - Launch the GUI subprocess with `-WindowStyle Hidden`, not just default —
    otherwise the visible console host window (title also "Legacy Downloader",
    set by the entry script) can outrank the real GUI window in `EnumWindows`
    enumeration order, and you end up screenshotting/measuring the console
    instead of the app.
  - Any Win32 `GetWindowText`/`GetWindowTextLength` P/Invoke declaration needs
    `CharSet = CharSet.Unicode` explicitly. Without it, .NET's default ANSI
    marshaling silently garbles any window title containing Japanese, Korean,
    Chinese, or Russian characters into unmatchable text — this looked exactly
    like a flaky timing bug (Latin-script languages worked fine every time,
    CJK/Cyrillic failed consistently) before the actual cause was found.
