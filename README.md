# Legacy Downloader

Self-contained PowerShell tool that downloads and updates **Legacy Offline PC**
and its song "editions" from the public ovosimpatico Nextcloud share, using
[rclone](https://rclone.org/).

Ships with a WinForms GUI (default) and a text-menu console front-end,
both available in 13 languages and both able to pick individual songs
within an edition — not just whole editions — with search and
Difficulty/Effort filters, and surface songs that are on the live share
but missing from the community sheet. A **Requirements** checker
verifies the Kinect SDKs and Visual C++ runtimes the game itself needs
are installed and can fetch/install whatever's missing (Windows only —
see [Software requirements](#software-requirements) below). Runs
natively on Linux via PowerShell Core too (community contribution,
credit [@leleletus](https://github.com/leleletus)) — see
[Running on Linux](#running-on-linux) below. Under the hood: size-only
comparison (so an exFAT-mounted play drive doesn't get flagged as
out of date on every run), folder-level detection, a dry-run preview
before anything downloads, and protected files so a patched `Legacy.exe`
or Kinect DLL is never silently overwritten.

> **Upgrading from an older version?** If you're already on V10 or later,
> LegacyDownloader can update itself in place — see
> [Keeping the tool itself updated](#keeping-the-tool-itself-updated) below.
> If you're upgrading from V9.x or earlier, delete everything from your old
> install folder *except* `config.txt`, then extract the new zip into that
> same folder - `config.txt` (your game folder, editions, and language) is
> picked up automatically. Extracting the new zip on top of an old install
> **without** deleting the old files first leaves the old launchers sitting
> next to the new ones, since unzipping never removes files. This is the
> last time you'll need to do it manually.

## Getting started

**Just want to use it?** Grab the latest zip from the
[Releases page](https://github.com/VenB304/LegacyDownloader/releases), extract it, and double-click
`LegacyDownloader-GUI.bat`. A full step-by-step tutorial with screenshots is
available in 13 languages:

[English](docs/tutorial/en.md) · [Français](docs/tutorial/fr.md) ·
[Español](docs/tutorial/es.md) · [Filipino](docs/tutorial/fil.md) ·
[Deutsch](docs/tutorial/de.md) ·
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

**Picking songs:** in the GUI, choose **Specific** — the first time this
opens the picker straight away, and afterwards **Select maps / songs**
reopens it (that button is only available while **Specific** is selected;
**Everything** needs no picking). In the console menu it's **[2] Choose which songs to get** → **[2] Specific
maps / songs**. Either way it opens a picker where you can check whole
editions or individual songs within them, search by title/artist/codename,
and filter by Difficulty/Effort.

**Keeping your own copy of a song:** modified a song yourself (say, with a
higher-quality video)? In the picker, click the song's row (not its checkbox)
and click **Keep my version** (in the console picker: **F7** on the song).
The song stays tracked, but updates never overwrite your file - it gets a ✓
in the **Kept** column (`*` in the console). Click the button again to
release it. Only songs that are already downloaded can be kept; the list is
stored as `KEEPSONGS` in `config.txt`.

**Unticking songs you already downloaded:** the tool asks once, for
everything you unticked - **Delete the files**, **Keep the files, stop
updating**, or **Cancel** to leave your picks unchanged. Songs you marked
**Keep my version** are never deleted by this prompt.

**Quick Launch:** after a successful check/update, both front-ends offer to
launch `Legacy.exe` directly instead of just telling you to do it yourself —
in the GUI, a "Ready to Play" prompt with a **Launch Game** button; in the
console menu, a one-line prompt to press L then Enter. Turn on **Automatically
launch the game and close** in Settings to skip this prompt entirely and go
straight from opening the tool to playing.

## Software requirements

Legacy Offline PC itself needs a handful of Microsoft runtimes/drivers
beyond what Windows ships out of the box — verified against `Legacy.exe`'s
own PE import table and real DLL/registry checks, not guessed:

- Kinect for Windows SDK 1.8 and 2.0 (the drivers/service behind the
  `Kinect10.dll`/`Kinect20.dll` the game already ships with)
- Visual C++ 2010, 2012, and 2015+ Redistributable (x86)
- DirectX End-User Runtime (June 2010) — narrowly for `XINPUT1_3.dll`,
  which Windows doesn't ship natively

Click the **Requirements** button on the main window (or **[6] Check
software requirements** in the console menu) any time to see what's
installed and fetch/install anything missing — every download comes from
its own official Microsoft page, never a third-party mirror. This is
shown once automatically the first time you set up a brand-new install;
existing installs only ever see it if you open it yourself. Windows only
— not available when running on Linux.

## Settings

Click **Settings** on the main window (or **[5] Settings** in the console
menu, which opens `config.txt` in your default text editor instead of a
window) for a few extra options:

- Automatically check for updates when the app opens
- Automatically launch the game and close once nothing more is needed
- Limit download speed (MB/s) — blank/0 means unlimited
- A custom share URL, if the default one ever needs to change — paste
  either a Nextcloud share link (the friendly one Nextcloud itself gives
  you) or the raw WebDAV link, either works
- Check for LegacyDownloader updates automatically — see
  [Keeping the tool itself updated](#keeping-the-tool-itself-updated) below

Bandwidth limit and share URL changes take effect the next time you start
the tool, not immediately.

## Keeping the tool itself updated

LegacyDownloader can check for its own newer releases and update itself in
place — no more manually downloading a new zip and extracting it over your
old folder. When an update is available, a button appears next to Settings
on the main window (e.g. **"V11.1 Update Available"**); clicking it closes
the tool, installs the update, and reopens automatically - a small window
shows what it's doing for the few seconds that takes (it's deliberately not
hidden). Nothing installs
itself without you clicking that button first, and you can turn the
automatic check off in Settings if you'd rather check manually via the
[Releases page](https://github.com/VenB304/LegacyDownloader/releases).

In the console menu the same notice appears and pressing **U** starts the
update (Windows only).

On Linux, the self-updater checks for new releases the same way but never
applies them automatically, since the release zip doesn't ship a Linux
`rclone` binary — see [Running on Linux](#running-on-linux) below.

## Language

Pick a language from the dropdown in the top-right corner of the GUI, or via
option `[4] Language` in the console menu. The choice is saved as `LANG=` in
`config.txt` and auto-detected from your Windows UI language on first run.

13 languages supported:
English, Français, Deutsch, Español, Filipino, Italiano, Português, Nederlands,
日本語, 한국어, 简体中文, 繁體中文, Русский.

> **Console font note:** the GUI renders every language correctly.
> The *text/console* front-end needs a font with the right glyphs — Japanese,
> Korean, Chinese, and Russian may show as boxes in the default console font.
> Use the GUI for those languages, or change the console font to one that
> covers the script. (`[Console]::OutputEncoding` is forced to UTF-8
> automatically.)

## Antivirus warnings

Two things can trigger a false positive from Windows Defender or other
antivirus tools:

- **`rclone.exe`** is flagged by some engines as a "hacktool" because
  attackers also use it. It is the legitimate, widely used open-source tool
  this program relies on to fetch files. Restore it from your antivirus's
  quarantine, allow it, then run the tool again.
- **The release zip itself** can get a cloud "trojan" detection shortly
  after it is published, simply because the file is brand new and unsigned
  (V10 was hit this way). The zip contains only the PowerShell scripts in
  this repository, the language files, an icon, two `.bat` launchers and the
  official `rclone.exe`, so you can read exactly what runs. To be sure you
  have the real file, compare the SHA-256 shown next to the download on the
  [Releases page](https://github.com/VenB304/LegacyDownloader/releases)
  with `Get-FileHash <zip>`. Reporting it to your antivirus vendor as an
  incorrect detection helps everyone.

## Files

- `LegacyDownloader-GUI.bat` — → GUI (default); the end-user launcher
- `LegacyDownloader-Console.bat` — → text/console menu
- `bin/LegacyDownloader.ps1` — thin launcher (imports Core, runs preflight, loads front-end)
- `bin/LegacyDownloader.Core.psm1` — all pure logic (no `Write-Host` / `Read-Host`)
- `bin/LegacyDownloader.Console.ps1` — text/menu front-end
- `bin/LegacyDownloader.Gui.ps1` — WinForms GUI front-end
- `bin/Update-Helper.ps1` — the self-updater's swap step (waits for the tool to exit, swaps `bin\` in place, reopens; rolls back on any failure)
- `bin/LegacyDownloader.ico` — the app icon
- `bin/lang/*.json` — string tables for all 13 languages
- `docs/tutorial/*.md` — end-user tutorials with screenshots, in all 13 languages
- `bin/rclone.exe` *(gitignored — see below)*
- `README.txt` — end-user instructions (ships inside the distributable bundle)
- `LICENSE` — MIT license for this tool's own code (not the game content it downloads)
- `THIRD-PARTY-NOTICES.txt` — the license notice for the bundled `rclone.exe`

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
