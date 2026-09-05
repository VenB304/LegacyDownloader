# Legacy Downloader — Tutorial

Legacy Downloader gets **Legacy Offline PC** and its song packs onto your
computer and keeps them updated. You don't need any technical knowledge to
use it — just follow the pictures below, in order.

Other languages: *(links added as each translation lands)*

---

## Quick start

For anyone who just wants the short version:

1. Download the zip from the [Releases page](../../releases) and extract it.
2. Double-click `LegacyDownloader.bat`. If Windows shows a blue warning
   screen, click **More info → Run anyway** (see [step 2](#2-windows-shows-a-blue-warning-screen-thats-normal) below — this is expected, not a virus).
3. Follow the on-screen welcome steps, pick your songs, and click
   **Download / Check for updates**.
4. When it says "You're all set!", open `Legacy.exe` in your game folder to
   play.

If anything looks confusing or doesn't match what's described, the detailed
walkthrough below has a picture for every screen.

---

## 1. Download and extract

1. Grab the latest `LegacyDownloaderVX.zip` from the [Releases page](../../releases).
2. Extract it — right-click the zip → **Extract All...** → pick a normal
   folder (Desktop is fine). Don't run it from inside the zip window itself.
3. Open the extracted folder and double-click **`LegacyDownloader.bat`**.

<!-- TODO screenshot: images/01-extracted-folder.png -->


## 2. Windows shows a blue warning screen — that's normal

The first time you run it, Windows may show a full blue screen saying
**"Windows protected your PC"**. This happens to almost every small,
independently-made program — Windows just doesn't recognize it yet, the
same way it wouldn't recognize any brand-new app on its first run anywhere.
It does **not** mean it found a virus.

<!-- TODO screenshot: images/02-smartscreen.png -->


1. Click the small **"More info"** text.
2. A **"Run anyway"** button appears — click it.

You should only need to do this once. If your antivirus separately flags
`rclone.exe` (a file inside this folder), see the [Troubleshooting](#troubleshooting)
section below — that's also a known false positive.

## 3. First run — Welcome screen

A **Welcome** window appears next.

<!-- TODO screenshot: images/03-welcome.png -->


- **Wrong language showing?** Click the flag dropdown in the corner and pick
  yours — the whole program switches instantly.
- Then answer the one question it asks:
  - **"I already have it"** — pick this if Legacy Offline PC is already on
    this PC somewhere.
  - **"Download it for me"** — pick this if you don't have the game yet.
    Everything after this is automatic.

### If you already have the game
A folder window pops up. Find and click the folder that has **`Legacy.exe`**
directly inside it (not a subfolder), then click **Select Folder**.

### If you don't have the game yet
A folder window pops up so you can pick where the game should live — an
empty folder, or a new one you create right there (there's a "New Folder"
button in that window). Click **Select Folder**, and the game starts
downloading immediately — no extra button to press.

This first download is large — roughly **1.2 GB**, usually somewhere
between 5 and 20 minutes depending on your internet. **Leave the window
open** until it finishes; you'll see progress moving in the window.

> Songs are a separate, second step — the first download is just the base
> game itself, so don't worry that no songs appeared yet.

## 4. The main window

Once the base game is in place, you land here:

<!-- TODO screenshot: images/04-main-window.png -->


- **Game folder** — where your game lives. **Change...** lets you point it
  somewhere else if you ever move the game.
- **Songs** — pick what you want:
  - **Everything** — every Just Dance edition available, and it'll grab new
    ones automatically as they get added later. This is the simplest option
    if you're not sure — pick this one.
  - **Only specific editions** — click **Choose editions...** to tick just
    the games you actually want (for example, only *Just Dance 2019*), if
    you'd rather not download everything.
- **Download / Check for updates** — the big button. Click it to fetch
  whatever you picked, and click it again any time later to check for new
  songs or updates.

## 5. Checking for updates

Clicking the big button doesn't download anything right away — it first
**checks** what you're missing. While it's checking, the progress bar may
just slide back and forth with no percentage shown — that's normal, it
means it's still comparing your files against the server, not stuck.

<!-- TODO screenshot: images/05-preview.png -->

Once it's done checking, a window lists what it found, with a total size.
Click **Download now** to actually get the files, or **Cancel** if you
just wanted to see what's available. If nothing has changed since last
time, it just says **"Everything is already up to date"** and stops there —
nothing to click.

<details>
<summary>If you've modified your game files (Kinect mod, patched exe) — click to expand</summary>

If a file you've personally changed (`Legacy.exe` or a Kinect DLL) differs
from the server's version, it gets its own checkbox instead of being lumped
in automatically:
- **Checked** = replace it with the server's copy (pick this if you haven't
  modded anything — it's just a normal game update).
- **Unchecked** = keep your own copy as-is.

Your in-game settings (screen resolution, windowed/fullscreen) are never
touched by an update, modded or not.
</details>

## 6. While it downloads

The progress bar and the log box below it update live — you'll see the game
and each song pack listed as they finish, one by one. **Don't close the
window while this is running.** When everything's done, you'll see:

> **You're all set!** Open `Legacy.exe` in your game folder to play.

That's your confirmation it worked — go start the game.

## 7. Coming back later for new songs

Just run `LegacyDownloader.bat` again any time. It remembers your folder and
your song choices, and clicking **Download / Check for updates** grabs
anything new since your last visit.

- **Add or remove songs**: use **Choose editions...** again. Unticking a
  game you already downloaded will ask whether to delete those files too, or
  just stop getting updates for it while keeping what you have.
- **Change language**: the flag dropdown, top-right, any time.

---

## Text/console version (advanced — most people don't need this)

There's also a plain text-menu version, for troubleshooting or if you prefer
it: double-click **`LegacyDownloader-Console.bat`** instead. Same features,
navigated with number keys:

```
[1] Download / check for new songs
[2] Choose which songs to get
[3] Change game folder
[4] Language
[5] Exit
```

> **Font note:** the graphical version displays every language correctly.
> This text version needs a font with the right characters — Japanese,
> Korean, Chinese, and Russian may show as boxes (□) here. If you want one
> of those languages, stick with the regular graphical version instead.

---

## Troubleshooting

- **Blue "Windows protected your PC" screen** — expected, see [step 2](#2-windows-shows-a-blue-warning-screen-thats-normal).
  Click More info → Run anyway.
- **Antivirus quarantines or deletes `rclone.exe`** — a known false
  positive. Some antivirus tools flag `rclone` as a "hacktool" because
  attackers can also use it, but it's a legitimate, widely-used open-source
  tool, and it's the only thing this program uses to fetch files. Restore it
  from your antivirus's quarantine/history, allow it, then run
  `LegacyDownloader.bat` again.
- **"rclone.exe is missing" message** — re-download the zip and extract
  again; don't run the tool from inside the zip viewer.
- **Nothing seems to happen when I click a folder button** — the picker
  window may have opened *behind* the main one; check your taskbar.
- **It says "up to date" but I'm missing songs** — open **Choose
  editions...** and check you've actually selected the ones you want (or
  pick **Everything**).
- **Still stuck?** Post in the Legacy Downloader thread on Discord with a
  screenshot of what you're seeing and which step you were on — someone
  will help.
