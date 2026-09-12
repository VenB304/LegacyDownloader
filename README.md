# Legacy Downloader

Self-contained PowerShell tool that downloads and updates **Legacy Offline PC**
and its song "editions" from the public ovosimpatico Nextcloud share, using
[rclone](https://rclone.org/).

The V4 line added a WinForms GUI (default), a text-menu console front-end, and
12-language support. **V5** refines the first run (picking a folder now starts
the base-game download straight away), hides the launcher console window, and
fixes the update check flagging a fresh install's `Legacy.exe` / Kinect DLLs as
"modified". **V6** fixes a console-menu crash and adds a user-overridable
share URL. **V7** silences a harmless-but-scary rclone error on exFAT drives,
moves everything except the two launchers into `bin\` so extension-hidden
Explorer views aren't full of identically-named files, and drops a hidden-
launcher script that was getting the release flagged by antivirus/SmartScreen.
Size-only comparison, folder-level detection, dry-run preview and protected
files all carry over from V3.

> **Upgrading from an older version?** Delete everything from your old
> install folder *except* `config.txt`, then extract the new zip into that
> same folder - `config.txt` (your game folder, editions, and language) is
> picked up automatically. Extracting the new zip on top of an old install
> **without** deleting the old files first leaves the old launchers sitting
> next to the new ones, since unzipping never removes files.

## Getting started

**Just want to use it?** Grab the latest zip from the
[Releases page](https://github.com/VenB304/LegacyDownloader/releases), extract it, and double-click
`LegacyDownloader-GUI.bat`. A full step-by-step tutorial with screenshots is
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

**GUI (default):** double-click `LegacyDownloader-GUI.bat`. It launches
`bin\LegacyDownloader.ps1` with a hidden window, so no console window is
left running behind the GUI.

**Text/console menu:** double-click `LegacyDownloader-Console.bat`, or
run `bin\LegacyDownloader.ps1 -Console` from a terminal.

Everything besides these two launchers and this README lives in `bin\` -
you never need to open it. It exists so that with Windows' "hide file
extensions" setting (the default), you don't end up with several files that
all display as the same bare "LegacyDownloader" name.

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

- `LegacyDownloader-GUI.bat` — → GUI (default); the end-user launcher
- `LegacyDownloader-Console.bat` — → text/console menu
- `bin/LegacyDownloader.ps1` — thin launcher (imports Core, runs preflight, loads front-end)
- `bin/LegacyDownloader.Core.psm1` — all pure logic (no `Write-Host` / `Read-Host`)
- `bin/LegacyDownloader.Console.ps1` — text/menu front-end
- `bin/LegacyDownloader.Gui.ps1` — WinForms GUI front-end
- `bin/lang/*.json` — string tables for all 12 languages
- `docs/tutorial/*.md` — end-user tutorials with screenshots, in all 12 languages
- `bin/rclone.exe` *(gitignored — see below)*
- `README.txt` — end-user instructions (ships inside the distributable bundle)
- `LICENSE` — MIT license for this tool's own code (not the game content it downloads)

## Running from a clone

`rclone.exe` is **not** committed (~85 MB). Download the Windows amd64 build
from <https://rclone.org/downloads/>, drop `rclone.exe` into `bin\`, then run
`LegacyDownloader-GUI.bat` (or `bin\LegacyDownloader.ps1` directly from a
terminal). `bin\config.txt` is created automatically on first run.

## For contributors

Implementation details (size-only comparison, folder-level detection, the
GUI's progress plumbing, etc.) live in [docs/technical-notes.md](docs/technical-notes.md)
rather than here, to keep this README focused on using the tool.
