Legacy Downloader
==================

Everything you need is in this folder already - no separate downloads,
no accounts, nothing else to install.

A step-by-step tutorial with screenshots (in 13 languages) is available at:
https://github.com/VenB304/LegacyDownloader/tree/main/docs/tutorial
The app itself also has a "Need help? Open the tutorial" link on the
first-run welcome screen.


USAGE
-----

Double-click "LegacyDownloader-GUI.bat" to open the GUI. No console
window is left sitting behind it.

Prefer a plain text/console menu instead? Double-click
"LegacyDownloader-Console.bat".

(Everything else in this folder lives inside "bin" - you never need to
open it. It's just kept out of the way so you always have exactly two
things to choose between.)


UPGRADING FROM AN OLDER VERSION
--------------------------------

Delete everything from your old install folder EXCEPT "config.txt", then
extract this new zip into that same folder - config.txt (your game
folder, editions, and language) is picked up automatically, no re-setup
needed.

If you extract this zip on top of an old install WITHOUT deleting the
old files first, the old launcher(s) will just sit there unused next to
the new ones - unzipping never removes files on its own.


FIRST RUN
---------

A welcome window will ask whether you already have the game on this PC,
or want it downloaded for you:

  - Already have it: a window pops up - click the folder that has
    Legacy.exe inside it, then press Select Folder.

  - Don't have it yet: a window pops up - pick or create an empty
    folder for the game to live in, then press Select Folder. The
    main window opens and immediately starts downloading the base
    game - no prompt, it just goes.

From the main window's "Songs" section you then choose what you want
(the base-game download, if any, keeps running in the background):

  - Everything - downloads every edition, and automatically includes
    new ones the maker adds later. No further action needed, ever.

  - Specific - click "Select maps / songs" to open a picker where you
    can check whole editions or individual songs within them, search
    by title/artist/codename, and filter by Difficulty/Effort.
    Available in both the GUI and the console menu.


AFTER SETUP
-----------

The GUI stays open and shows your current status. Hit "Download /
Check for updates" whenever you want new songs.

In the console menu you'll see:

  [1] Download / check for new songs
  [2] Choose which songs to get
  [3] Change game folder
  [4] Language
  [5] Check software requirements
  [6] Exit


BEFORE IT DOWNLOADS ANYTHING
-----------------------------

(One exception: the very first base-game download, right after you
pick a folder in "Download it for me", just starts - no preview.)

For updates it checks first and shows what's actually missing or out
of date - which editions have new songs, how many files, and the total
size. In the GUI a preview window appears with a "Download now" button.
In the console menu it asks:

  [1] Download now
  [2] Show full file list
  [3] Cancel

If nothing has changed it just says "everything is already up to date"
and downloads nothing. Your copy of Legacy.exe or a Kinect .dll will be
flagged if it differs from the server's, and you'll be asked before it's
replaced - so a patched or modded setup won't get overwritten without
your say-so. Your settings file (config.xml) is downloaded once on the
first install and then never touched again, so updates won't reset your
resolution or windowed/fullscreen choice.

It only ever adds or updates files - it never deletes anything on its
own. If you uncheck an edition you'd previously downloaded, it'll ask
whether to delete those files or just leave them on disk. Nothing is
ever removed without you being asked first.


SOFTWARE REQUIREMENTS
----------------------

Legacy Offline PC itself needs a few Microsoft runtimes/drivers besides
Windows itself: the Kinect for Windows SDK (1.8 and 2.0), Visual C++
2010/2012/2015+ Redistributable, and the DirectX End-User Runtime.

Click "Requirements" on the main window (or "[5] Check software
requirements" in the console menu) any time to see what's installed and
install anything missing - each download comes straight from its own
official Microsoft page, never anywhere else. You'll see this once
automatically the very first time you set this tool up; after that it's
only ever shown if you open it yourself. Windows only.


LANGUAGE
--------

In the GUI: use the Language dropdown in the top-right corner.
In the console menu: choose option [4] Language.

Your choice is saved automatically. On first run the language is
detected from your Windows system language.

Supported: English, Francais, Deutsch, Espanol, Filipino, Italiano,
Portugues, Nederlands, Japanese, Korean, Chinese (Simplified), Chinese
(Traditional), Russian. (13 total.)

Note for the console/text menu: the GUI displays every language
correctly. In the plain console window, Japanese, Korean, Chinese,
and Russian may show as boxes if your console font doesn't include
those characters. The GUI works fine for all languages regardless.


TROUBLESHOOTING
---------------

- "rclone.exe is missing" - something's missing from the zip, or
  antivirus quarantined it. Re-download the bundle.

- "rclone.exe is here but won't run" - almost always antivirus.
  rclone gets flagged by some engines as a "hacktool" because
  attackers also use it (it's a legitimate, widely-used open-source
  tool). Check your antivirus quarantine or history for rclone.exe,
  restore or allow it, then run this again.

- "Legacy.exe wasn't found there" - you can still proceed if you're
  sure the folder is right (e.g. before the game has been downloaded
  yet).

- A security warning when you first run "LegacyDownloader-GUI.bat" -
  this can happen with any downloaded script. Click through it ("More
  info" then "Run anyway," or similar wording) - it appears because the
  program isn't code-signed, not because it's harmful.

- Songs show as boxes in the console - your console font doesn't cover
  that script. Switch to the GUI ("LegacyDownloader-GUI.bat") instead.
