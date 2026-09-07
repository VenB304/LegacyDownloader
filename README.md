# Legacy Downloader

Self-contained PowerShell tool that downloads and updates **Legacy Offline PC**
and its song "editions" from the public ovosimpatico Nextcloud share, using
[rclone](https://rclone.org/).

The V4 line added a WinForms GUI (default), a text-menu console front-end, and
12-language support. **V5** refines the first run (picking a folder now starts
the base-game download straight away), hides the launcher console window, and
fixes the update check flagging a fresh install's `Legacy.exe` / Kinect DLLs as
"modified". Size-only comparison, folder-level detection, dry-run preview and
protected files all carry over from V3.

## Getting started

**Just want to use it?** Grab the latest zip from the
[Releases page](https://github.com/VenB304/LegacyDownloader/releases), extract it, and double-click
`LegacyDownloader.bat`. A full step-by-step tutorial with screenshots is
available in 12 languages:

[English](docs/tutorial/en.md) · [Français](docs/tutorial/fr.md) ·
[Español](docs/tutorial/es.md) · [Deutsch](docs/tutorial/de.md) ·
[Italiano](docs/tutorial/it.md) · [Português](docs/tutorial/pt.md) ·
[Nederlands](docs/tutorial/nl.md) · [日本語](docs/tutorial/ja.md) ·
[한국어](docs/tutorial/ko.md) · [简体中文](docs/tutorial/zh-Hans.md) ·
[繁體中文](docs/tutorial/zh-Hant.md) · [Русский](docs/tutorial/ru.md)

The app itself also has a "Need help? Open the tutorial" link on the
first-run welcome screen, which opens the tutorial in your current language.

## Usage

**GUI (default):** double-click `LegacyDownloader.bat`. It hands off to
`LegacyDownloader.vbs`, which starts the GUI with no console window left
behind. Double-clicking `LegacyDownloader.vbs` directly is fully flash-free.

**Text/console menu:** double-click `LegacyDownloader-Console.bat`, or run
`LegacyDownloader.ps1 -Console` from a terminal.

On a first run started with **"Download it for me"**, the GUI opens and
immediately starts downloading the **base game** (no preview) — song packs are
a deliberate second step you pick afterward. If the folder you choose already
contains `Legacy.exe`, it falls back to a normal checked update with a preview.

## Language

Pick a language from the dropdown in the top-right corner of the GUI, or via
option `[4] Language` in the console menu. The choice is saved as `LANG=` in
`config.txt` and auto-detected from your Windows UI language on first run.

12 languages supported:
English, Français, Deutsch, Español, Italiano, Português, Nederlands,
日本語, 한국어, 简体中文, 繁體中文, Русский.

> **Console font note:** the GUI renders every language correctly.
> The *text/console* front-end needs a font with the right glyphs — Japanese,
> Korean, Chinese, and Russian may show as boxes in the default console font.
> Use the GUI for those languages, or change the console font to one that
> covers the script. (`[Console]::OutputEncoding` is forced to UTF-8
> automatically.)

## Files

- `LegacyDownloader.ps1` — thin launcher (imports Core, runs preflight, loads front-end)
- `LegacyDownloader.vbs` — starts the GUI with a hidden console (no leftover window)
- `LegacyDownloader.bat` — → GUI (default); just calls the `.vbs`
- `LegacyDownloader-Console.bat` — → text/console menu
- `LegacyDownloader.Core.psm1` — all pure logic (no `Write-Host` / `Read-Host`)
- `LegacyDownloader.Console.ps1` — text/menu front-end
- `LegacyDownloader.Gui.ps1` — WinForms GUI front-end
- `lang/*.json` — string tables for all 12 languages
- `docs/tutorial/*.md` — end-user tutorials with screenshots, in all 12 languages
- `rclone.exe` *(gitignored — see below)*
- `README.txt` — end-user instructions (ships inside the distributable bundle)
- `LICENSE` — MIT license for this tool's own code (not the game content it downloads)

## Running from a clone

`rclone.exe` is **not** committed (~85 MB). Download the Windows amd64 build
from <https://rclone.org/downloads/>, drop `rclone.exe` in this folder, then
run `LegacyDownloader.bat`. `config.txt` is created automatically on first run.

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
