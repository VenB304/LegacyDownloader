Legacy Downloader
==================

Everything you need is in this folder already - no separate downloads,
no accounts, nothing else to install.

USAGE:

Double-click "LegacyDownloader.bat". Everything else is done by
clicking through menus and windows - you never need to type or edit
anything by hand.

FIRST RUN:

It'll ask whether you already have the game on this PC, or want it
downloaded for you:

  - Already have it: a window pops up - click the folder that has
    Legacy.exe inside it, then press Select Folder.
  - Don't have it yet: a window pops up - pick or create an empty
    folder for the game to live in, then press Select Folder. It
    downloads the base game there for you.

Either way, you'll then be asked which songs you want:

  - Everything - downloads every edition, and automatically includes
    new ones the maker adds later. No further action needed, ever.
  - Only specific editions - shows a list you move through with the
    Up/Down arrow keys, Enter to check/uncheck one, then
    Back/Cancel/Continue at the bottom of the same list.

AFTER SETUP:

You'll land on a menu each time you run it:

  [1] Download / check for new songs
  [2] Choose which songs to get
  [3] Change game folder
  [4] Exit

BEFORE IT DOWNLOADS ANYTHING:

Any time it's about to download, it checks first and shows you what's
actually missing or out of date - which editions have new songs, how
many files, and the total size - then asks:

  [1] Download now
  [2] Show full file list
  [3] Cancel

If nothing has changed, it just says "everything is already up to date"
and downloads nothing. If your copy of Legacy.exe or a Kinect .dll
differs from the server's, it asks before replacing it, so a patched or
modded setup won't get overwritten. If you haven't modded your game,
just answer yes to those - it means the game itself got an update. And
if your game folder is set one level off, it offers to correct it for
you.

It only ever adds or updates files - it never deletes anything on its
own. The one exception: if you uncheck an edition you'd previously
downloaded, it'll ask you directly whether to delete those files or
just leave them on disk without further updates. Nothing is ever
removed without you being asked first.

TROUBLESHOOTING:

- "A required file is missing from this folder" - something's missing
  from the zip, or antivirus quarantined it. Re-download the bundle.
- "rclone.exe is here but won't run" - checked automatically every time
  you start it. It's almost always antivirus: the download tool this
  uses (rclone) gets flagged by some antivirus engines as a "hacktool,"
  because attackers also use it (it's a legitimate, widely-used
  open-source tool otherwise). Check your antivirus's quarantine or
  history for rclone.exe, restore or allow it, then run this again.
- "Legacy.exe wasn't found there" - you can still continue anyway if
  you're sure the folder's right (e.g. before the game's been
  downloaded yet).
- A blue "Windows protected your PC" popup on first run - that's
  SmartScreen (common for any unsigned program from the internet),
  click "More info" then "Run anyway."
