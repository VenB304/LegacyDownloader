# LegacyDownloader.ps1 - entry point / launcher.
#
# Loads the shared engine (LegacyDownloader.Core.psm1), checks rclone.exe,
# then hands off to a front-end:
#   * the GUI  (LegacyDownloader.Gui.ps1)      - default, when present
#   * the text menu (LegacyDownloader.Console.ps1) - with -Console, or when
#     the GUI script isn't there
#
# The GUI is normally launched with a hidden console (LegacyDownloader.vbs /
# .bat), so anything fatal here has to surface as a message box, not a
# Write-Host / Read-Host the user will never see.
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

# Decide the front-end up front - it changes how fatal errors are shown.
$GuiScript     = Join-Path $ScriptDir 'LegacyDownloader.Gui.ps1'
$ConsoleScript = Join-Path $ScriptDir 'LegacyDownloader.Console.ps1'
$UseGui        = (-not $Console) -and (Test-Path -LiteralPath $GuiScript)

function Show-FatalError([string]$Message) {
    if ($UseGui) {
        try {
            Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
            [System.Windows.Forms.MessageBox]::Show(
                $Message, 'Legacy Downloader',
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
        } catch {
            Write-Host $Message -ForegroundColor Red
        }
    } else {
        Write-Host $Message -ForegroundColor Red
        Write-Host ""
        Read-Host (T 'common.press_enter_close') | Out-Null
    }
}

# --- preflight: rclone.exe must be present and runnable ---
if (-not (Test-Path -LiteralPath $Rclone)) {
    Show-FatalError (T 'entry.rclone_missing')
    exit 1
}

try {
    & $Rclone version @RcloneConfigArgs *> $null
    if ($LASTEXITCODE -ne 0) { throw "exit code $LASTEXITCODE" }
} catch {
    Show-FatalError (T 'entry.rclone_broken')
    exit 1
}

if ($UseGui) {
    try {
        . $GuiScript
    } catch {
        Show-FatalError (("{0}`n`n{1}" -f (T 'entry.gui_crashed'), $_.Exception.Message))
        exit 1
    }
} elseif (Test-Path -LiteralPath $ConsoleScript) {
    . $ConsoleScript
} else {
    Show-FatalError (T 'entry.no_frontend')
    exit 1
}
