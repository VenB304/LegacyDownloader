@echo off
rem Recovery: an update interrupted mid-swap (window closed, power loss) can leave bin\ renamed
rem to bin_old_* with no bin\ at all - put the previous copy back so the tool still starts.
rem Does nothing in normal use.
if not exist "%~dp0bin\LegacyDownloader.ps1" for /d %%D in ("%~dp0bin_old_*") do if not exist "%~dp0bin\" move "%%D" "%~dp0bin" >nul 2>&1
rem "start" detaches PowerShell so this window closes right away instead of
rem staying open behind the GUI for the whole session; -WindowStyle Minimized
rem leaves PowerShell's own window minimised on the taskbar. It is minimised, NOT
rem hidden, on purpose: a hidden PowerShell started with -ExecutionPolicy Bypass
rem is a classic malware launcher shape (VirusTotal: six antivirus engines flagged
rem the V11.4 zip for exactly that combination; with Minimized instead none of the
rem mainstream ones do). Do not use "start /min" instead: the minimised startup
rem state is inherited by the GUI's own first window, which then opens minimised.
rem This also calls PowerShell directly rather than through a .vbs helper, for
rem the same reason.
start "" powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Minimized -File "%~dp0bin\LegacyDownloader.ps1"
