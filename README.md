# Legacy Downloader

Self-contained PowerShell tool that downloads and updates **Legacy Offline PC**
and its song "editions" from the public ovosimpatico Nextcloud share, using
[rclone](https://rclone.org/).

Ships with a WinForms GUI (default) and a text-menu console front-end,
both available in 12 languages and both able to pick individual songs
within an edition — not just whole editions — with search and
Difficulty/Effort filters, and surface songs that are on the live share
but missing from the community sheet. Runs natively on Linux via
PowerShell Core too (community contribution, credit
[@leleletus](https://github.com/leleletus)) — see
[Running on Linux](#running-on-linux) below. Under the hood: size-only
comparison (so an exFAT-mounted play drive doesn't get flagged as
out of date on every run), folder-level detection, a dry-run preview
before anything downloads, and protected files so a patched `Legacy.exe`
or Kinect DLL is never silently overwritten.

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

**Picking songs:** in the GUI, click **Select maps / songs** (works
regardless of which radio, "Everything" or "Specific", is selected). In
the console menu it's **[2] Choose which songs to get** → **[2] Specific
maps / songs**. Either way it opens a picker where you can check whole
editions or individual songs within them, search by title/artist/codename,
and filter by Difficulty/Effort.

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

## Running on Linux

The GUI needs Windows Forms and isn't available on Linux — everything else
(the console menu, and the full song-downloading engine underneath it)
runs on [PowerShell Core](https://github.com/PowerShell/PowerShell) via
community contribution [PR #1](https://github.com/VenB304/LegacyDownloader/pull/1).
You'll need `rclone` installed and on your `PATH` (get it from your distro's
package manager or <https://rclone.org/downloads/> — there's no bundled
binary the way the Windows zip ships one), then run:

```
pwsh bin/LegacyDownloader.ps1 -Console
```

`config.txt`/`rclone.conf` are created next to the script on first run,
same as on Windows.
