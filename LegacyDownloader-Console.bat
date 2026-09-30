@echo off
rem Recovery: an update interrupted mid-swap (window closed, power loss) can leave bin\ renamed
rem to bin_old_* with no bin\ at all - put the previous copy back so the tool still starts.
rem Does nothing in normal use.
if not exist "%~dp0bin\LegacyDownloader.ps1" for /d %%D in ("%~dp0bin_old_*") do if not exist "%~dp0bin\" move "%%D" "%~dp0bin" >nul 2>&1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0bin\LegacyDownloader.ps1" -Console
