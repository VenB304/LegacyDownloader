@echo off
rem Hand off to the .vbs launcher so no console window is left behind.
rem (Double-clicking LegacyDownloader.vbs directly is fully flash-free.)
start "" "%~dp0LegacyDownloader.vbs"
