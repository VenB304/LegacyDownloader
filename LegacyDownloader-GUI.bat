@echo off
rem "start" detaches PowerShell so this window closes right away instead of
rem staying open behind the GUI for the whole session; -WindowStyle Hidden
rem keeps PowerShell's own window from ever appearing. See
rem docs/technical-notes.md ("Dropped the .vbs hidden-launch trick") for why
rem this calls PowerShell directly instead of through a .vbs helper.
start "" powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0bin\LegacyDownloader.ps1"
