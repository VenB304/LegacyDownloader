@echo off
rem Recovery: an update interrupted mid-swap (window closed, power loss) can leave bin\ renamed
rem to bin_old_* with no bin\ at all - put the previous copy back so the tool still starts.
rem Does nothing in normal use.
if not exist "%~dp0bin\LegacyDownloader.ps1" for /d %%D in ("%~dp0bin_old_*") do if not exist "%~dp0bin\" move "%%D" "%~dp0bin" >nul 2>&1
rem "start" detaches PowerShell so this window closes right away instead of
rem staying open behind the GUI for the whole session; -WindowStyle Hidden
rem keeps PowerShell's own window from ever appearing. This calls
rem PowerShell directly rather than through a .vbs helper, because a
rem .vbs that silently spawns a hidden PowerShell is a classic antivirus
rem false-positive trigger.
start "" powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0bin\LegacyDownloader.ps1"
