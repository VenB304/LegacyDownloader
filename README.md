# Legacy Downloader

Self-contained PowerShell tool that downloads and updates **Legacy Offline PC**
and its song "editions" from the public ovosimpatico Nextcloud share, using
[rclone](https://rclone.org/).

## Files

- `LegacyDownloader.ps1` — the tool
- `LegacyDownloader.bat` — launcher (double-click this)
- `README.txt` — end-user instructions (ships inside the distributable bundle)

## Running from a clone

`rclone.exe` is **not** committed (85 MB). Download it from
<https://rclone.org/downloads/> (Windows amd64), drop `rclone.exe` in this
folder, then run `LegacyDownloader.bat`. `config.txt` is created automatically
on first run.

## v3 notes

- **Size-only comparison** (`--size-only`): exFAT rounds modification times to a
  2-second grid, so the old size+mtime check re-downloaded roughly half the
  library on every run when the game lived on an external exFAT drive. A real
  song/patch update always changes the file size, so size is the reliable signal.
- **Game-folder level detection**: if `Legacy.exe` isn't directly in the
  configured folder but is one level up or down (the Nextcloud share nests the
  game under a `LegacyPC - Game` folder), the tool offers to fix `config.txt`.
- **Dry-run preview**: before downloading, shows per-edition counts and total
  size. If nothing differs it reports "everything up to date" and downloads
  nothing; otherwise it asks before transferring.
- **Protected files**: `Legacy.exe`, `Kinect10.dll` and `Kinect20.dll` each get
  a per-file confirm before being overwritten, so patched or modded binaries
  survive an update. `config.xml` (local game settings) is fetched once on a
  fresh install and never overwritten afterward — syncing the server's copy was
  resetting players' resolution / windowed-mode choices on every update.
