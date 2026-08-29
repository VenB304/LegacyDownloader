# LegacyDownloader.ps1 - entry point / launcher.
#
# Loads the shared engine (LegacyDownloader.Core.psm1), checks rclone.exe,
# then hands off to a front-end:
#   * the GUI  (LegacyDownloader.Gui.ps1)      - default, when present
#   * the text menu (LegacyDownloader.Console.ps1) - with -Console, or when
#     the GUI script isn't there
param([switch]$Console)

$ErrorActionPreference = 'Stop'
try { $Host.UI.RawUI.WindowTitle = 'Legacy Downloader' } catch { }

$ScriptDir = $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($ScriptDir)) {
    $ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
}

Import-Module (Join-Path $ScriptDir 'LegacyDownloader.Core.psm1') -Force -DisableNameChecking

# Fills in module state and hands back every path / arg set the front-ends
# need. Kept as plain script variables so the dot-sourced front-end sees them.
$Core             = Initialize-LegacyCore -ScriptDir $ScriptDir
$Rclone           = $Core.Rclone
$ConfigPath       = $Core.ConfigPath
$RcloneConfigPath = $Core.RcloneConfigPath
$LangDir          = $Core.LangDir
$Conn             = $Core.Conn
$RcloneConfigArgs = $Core.RcloneConfigArgs
$SizeOnlyArgs     = $Core.SizeOnlyArgs
$CommonArgs       = $Core.CommonArgs
$ScanArgs         = $Core.ScanArgs

# Load the interface language now (config is created here on a first run,
# seeded from the PC's UI culture) so the front-end - and the messages just
# below - come out translated.
$bootCfg = Load-Config
$null = Initialize-Language -Code $bootCfg.Lang

# --- preflight: rclone.exe must be present and runnable ---
if (-not (Test-Path $Rclone)) {
    Write-Host (T 'entry.rclone_missing') -ForegroundColor Red
    Write-Host ""
    Read-Host (T 'common.press_enter_close') | Out-Null
    exit 1
}

try {
    & $Rclone version @RcloneConfigArgs *> $null
    if ($LASTEXITCODE -ne 0) { throw "exit code $LASTEXITCODE" }
} catch {
    Write-Host (T 'entry.rclone_broken') -ForegroundColor Red
    Write-Host ""
    Read-Host (T 'common.press_enter_close') | Out-Null
    exit 1
}

$GuiScript     = Join-Path $ScriptDir 'LegacyDownloader.Gui.ps1'
$ConsoleScript = Join-Path $ScriptDir 'LegacyDownloader.Console.ps1'

if (-not $Console -and (Test-Path $GuiScript)) {
    . $GuiScript
} elseif (Test-Path $ConsoleScript) {
    . $ConsoleScript
} else {
    Write-Host (T 'entry.no_frontend') -ForegroundColor Red
    Write-Host ""
    Read-Host (T 'common.press_enter_close') | Out-Null
    exit 1
}
