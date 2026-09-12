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

## V7 — friendly top-level layout

Moved everything except the two launcher `.bat` files and `README.txt` into
`bin\` (`LegacyDownloader.ps1`/`.Core.psm1`/`.Console.ps1`/`.Gui.ps1`,
`rclone.exe`, `lang\`, and the runtime-generated `config.txt`/`rclone.conf`).
Reported issue: with Windows' "hide extensions for known file types" default
(most non-technical users have this on), `LegacyDownloader.ps1`,
`LegacyDownloader.vbs` (since removed - see below), and `LegacyDownloader.bat`
all displayed as the same bare "LegacyDownloader" name in Explorer,
distinguishable only by icon - a new user had no reliable way to tell which
one to double-click. Top level now ships exactly `LegacyDownloader-GUI.bat`,
`LegacyDownloader-Console.bat`, and `README.txt`; `LegacyDownloader-GUI.bat`
launches `bin\LegacyDownloader.ps1` (`$PSScriptRoot`-based path resolution
needed no code changes, only relocating the files as a unit).
`tools\build-release.ps1` and the other `tools\*.ps1` scripts were updated
for the new `bin\` paths.

**Dropped the `.vbs` hidden-launch trick (also V7):** `LegacyDownloader-GUI.bat`
used to `start` a `LegacyDownloader.vbs` helper, which used `WScript.Shell.Run`
to launch PowerShell fully hidden (window style 0) - avoiding even the
sub-100ms flash of the `.bat`'s own console window. Removed after user
reports of the release zip getting flagged as malicious: a `.vbs` silently
spawning a hidden, `-ExecutionPolicy Bypass` PowerShell process is a
well-documented dropper/loader pattern that antivirus and SmartScreen
heuristics watch for specifically, independent of whether anything is
digitally signed. `LegacyDownloader-GUI.bat` now calls
`start "" powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden
-File "%~dp0bin\LegacyDownloader.ps1"` directly. The `start` matters: without
it, `cmd.exe` runs `powershell.exe` as a blocking foreground child and its own
window stays open for the GUI's *entire* session instead of closing right
away (caught in review, before release - an early draft of this fix omitted
`start` and reintroduced a lingering console window, the exact problem the
`.vbs` existed to avoid). With `start`, `cmd.exe` detaches and exits almost
immediately, `bin\LegacyDownloader.ps1` still gets its own `-WindowStyle Hidden`
window, and the net effect matches the old `.vbs` behavior closely enough
(brief flash instead of zero flash) while dropping the WSH-spawns-hidden-
PowerShell half of the heuristic signature. `bin\LegacyDownloader.vbs` was
deleted; `tools\build-release.ps1`'s file list no longer references it.

This is a **partial** mitigation, not a full fix for "the zip gets flagged as
malicious": `-ExecutionPolicy Bypass` is still passed on every launch (both
`.bat` files), which is its own independently-flaggable signal, separate from
the WSH indirection this change removed - dropping *that* too would mean
either shipping unsigned scripts that Windows' default policy simply refuses
to run, or unblocking them first (`Unblock-File` after every extraction,
itself another script step), so it was left in as the pragmatic tradeoff for
a "download the zip and go" tool. Bundled `rclone.exe` also still gets
flagged by some antivirus engines as a "hacktool" (see the Troubleshooting
sections of the README/tutorials) - a separate, unrelated, and essentially
permanent false positive tied to what rclone *can do*, not to anything in
this repo's own scripts. Both of these are real, currently-unaddressed
sources of the same user-visible symptom.

**Upgrade path:** a returning user extracting V7 over a pre-V7 install would
otherwise have their `config.txt` (saved game folder, editions, language,
any `SHAREURL` override) orphaned at the old top-level location while
`Initialize-LegacyCore` looks for it under the new `bin\`. `Initialize-LegacyCore`
now migrates a legacy top-level `config.txt` into `bin\config.txt` in place
(one `Move-Item`, best-effort) the first time it doesn't find one already
there, before anything reads it.

This only handles `config.txt` - it does **not** clean up the rest of a
pre-V7 install. Zip extraction never deletes files that aren't in the
archive, so extracting V7 directly over an old install leaves the old
top-level `LegacyDownloader.ps1`/`.vbs`/`.bat`/`.Core.psm1`/`.Console.ps1`/
`.Gui.ps1`, its own `lang\`, and its own ~85 MB `rclone.exe` sitting there
unchanged, right alongside the new `bin\` tree and the two new launchers -
recreating the exact "which file do I click" pile V7 exists to fix, and the
old `LegacyDownloader.bat` chain still runs (pointed at the stale, now-
orphaned copies) if someone clicks it. README.md/README.txt's upgrade note
tells returning users to delete the old top-level files first (everything
except `config.txt`, which the migration needs) before extracting V7 into
the same folder - there is no automatic cleanup for this, by choice: the
app deleting its own previously-shipped files based on a version guess is a
worse failure mode (deleting the wrong thing on a mistaken assumption) than
asking the user to do it once during a manual upgrade.

## V6 changes

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
- **Sparse-file errors on exFAT**: rclone pre-allocates a sparse destination
  file for multi-thread downloads on Windows, which needs `FSCTL_SET_SPARSE` -
  a call exFAT (the usual "play drive" filesystem) doesn't support, so it
  fails with `Incorrect function` and rclone logs a scary-looking `ERROR`
  line (the transfer itself still completes via a fallback path). Both
  `CommonArgs` (console) and `GuiSyncArgs` (GUI) now include
  `--local-no-sparse` so rclone never attempts it. Applied unconditionally,
  not just when the target turns out to be exFAT - detecting the filesystem
  first isn't worth it for a flag whose only cost on NTFS is a bit of extra
  zero-fill instead of sparse pre-allocation, which is what `--local-no-sparse`
  actually trades away (see rclone's own docs for that flag).
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
