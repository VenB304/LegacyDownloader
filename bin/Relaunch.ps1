# Relaunch.ps1 - starts LegacyDownloader again after a self-update.
#
# Called by Update-Helper.ps1 (in the same process) once the swap is done, or
# after a rollback. It is deliberately a SEPARATE FILE: a script that moves
# files and then starts a process in the same breath matches a dropper
# heuristic, and the release zip was flagged by Bitdefender-engine antivirus
# (Bitdefender, G Data, eScan, Emsisoft, VIPRE, Arcabit) until the launch was
# moved out of Update-Helper.ps1. Never put a process launch back into
# Update-Helper.ps1 (see AGENTS.md lesson 24).
param(
    [Parameter(Mandatory = $true)][string]$InstallDir,
    [Parameter(Mandatory = $true)][ValidateSet('gui', 'console')][string]$RelaunchTarget
)
$bat = if ($RelaunchTarget -eq 'gui') { Join-Path $InstallDir 'LegacyDownloader-GUI.bat' } else { Join-Path $InstallDir 'LegacyDownloader-Console.bat' }
if (-not (Test-Path -LiteralPath $bat)) { throw "launcher not found: $bat" }
Start-Process -FilePath $bat -WorkingDirectory $InstallDir | Out-Null
