# Update-Helper.ps1 - self-update's swap step.
#
# Spawned by Start-AppUpdateHelper (Core.psm1) as a detached, hidden process
# right before the main app exits. Never run this by hand - it expects to
# be the only thing touching InstallDir\bin during its run.
#
# Design: wait for the main process to exit, copy the already-downloaded-
# and-verified staged release into a same-volume "bin_new_*" folder next to
# the live bin\ (so the actual swap is two same-volume renames - near-
# instant metadata operations, not a file-by-file copy that could fail
# partway through and leave a half-swapped install), verify the copy,
# rename bin\ -> bin_old_*, rename bin_new_* -> bin, verify again, then
# relaunch. Any failure at any point rolls back to the exact working
# install this started from and relaunches THAT instead - a failed update
# must be a no-op, never a brick.
param(
    [Parameter(Mandatory = $true)][string]$InstallDir,
    [Parameter(Mandatory = $true)][string]$StagingDir,
    [Parameter(Mandatory = $true)][string]$ExpectedVersion,
    [Parameter(Mandatory = $true)][ValidateSet('gui', 'console')][string]$RelaunchTarget,
    [Parameter(Mandatory = $true)][int]$MainPid
)

$ErrorActionPreference = 'Stop'
$logPath = Join-Path $InstallDir 'update-helper.log'

function Write-Log([string]$Message) {
    $line = "[{0}] {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message
    try { Add-Content -LiteralPath $logPath -Value $line -Encoding UTF8 } catch { }
}

function Get-StagedVersion([string]$BinDir) {
    $core = Join-Path $BinDir 'LegacyDownloader.Core.psm1'
    if (-not (Test-Path -LiteralPath $core)) { return $null }
    $versionLine = Get-Content -LiteralPath $core | Where-Object { $_ -match '^\$script:AppVersion\s*=' } | Select-Object -First 1
    if ($versionLine -notmatch "=\s*'([^']+)'") { return $null }
    return $Matches[1]
}

function Invoke-WithRetry([scriptblock]$Action, [string]$Description) {
    # AV scanning a freshly-written/moved file can transiently lock it -
    # documented history in this project (rclone.exe itself gets flagged
    # occasionally) - so retry with backoff rather than failing on the
    # first locked-file error.
    $attempts = 0
    while ($true) {
        try { & $Action; return } catch {
            $attempts++
            if ($attempts -ge 5) { throw }
            Write-Log "$Description failed (attempt $attempts/5): $($_.Exception.Message) - retrying"
            Start-Sleep -Milliseconds (500 * $attempts)
        }
    }
}

function Start-App {
    $bat = if ($RelaunchTarget -eq 'gui') { Join-Path $InstallDir 'LegacyDownloader-GUI.bat' } else { Join-Path $InstallDir 'LegacyDownloader-Console.bat' }
    if (-not (Test-Path -LiteralPath $bat)) { Write-Log "FAILED to relaunch: $bat not found"; return }
    Start-Process -FilePath $bat -WorkingDirectory $InstallDir | Out-Null
}

Write-Log "=== Update helper started ==="
Write-Log "InstallDir=$InstallDir StagingDir=$StagingDir ExpectedVersion=$ExpectedVersion RelaunchTarget=$RelaunchTarget MainPid=$MainPid"

# 1. Wait for the main process to exit - up to 30s. If it never does,
# abort without touching anything; the staged download is just discarded.
$waited = 0
$maxWaitMs = 30000
while ($waited -lt $maxWaitMs) {
    if (-not (Get-Process -Id $MainPid -ErrorAction SilentlyContinue)) { break }
    Start-Sleep -Milliseconds 500
    $waited += 500
}
if (Get-Process -Id $MainPid -ErrorAction SilentlyContinue) {
    Write-Log "FAILED: main process (PID $MainPid) never exited within ${maxWaitMs}ms - aborting, nothing touched."
    Remove-Item -LiteralPath $StagingDir -Recurse -Force -ErrorAction SilentlyContinue
    exit 1
}
Write-Log "Main process exited after ${waited}ms."

$liveBin = Join-Path $InstallDir 'bin'
$stamp = Get-Date -Format 'yyyyMMddHHmmss'
$oldBin = Join-Path $InstallDir "bin_old_$stamp"
$newBin = Join-Path $InstallDir "bin_new_$stamp"
$stagedBin = Join-Path $StagingDir 'bin'
$swapStarted = $false

try {
    # 2. Copy (not move) the staged bin\ into a same-volume "bin_new_*"
    # folder next to the live one. This step can be cross-volume (StagingDir
    # is under $env:TEMP, which may be a different drive than InstallDir)
    # and thus NOT atomic - but it only ever writes to a brand-new folder
    # nothing else references yet, so a failure here just leaves an inert
    # bin_new_* behind (cleaned up in the catch block) with the live bin\
    # completely untouched.
    Write-Log "Copying staged release to $newBin"
    Invoke-WithRetry { Copy-Item -LiteralPath $stagedBin -Destination $newBin -Recurse -ErrorAction Stop } "copy staged bin to bin_new"

    $copiedVersion = Get-StagedVersion $newBin
    if ($copiedVersion -ne $ExpectedVersion) {
        throw "post-copy version check failed (expected $ExpectedVersion, got '$copiedVersion')"
    }

    # 3. The actual swap: two same-volume renames, each a near-instant
    # metadata operation (verified live before this feature shipped - a
    # running process does not lock its own bin\ folder, so this is safe
    # to do without an extra existence check). $swapStarted gates the
    # rollback logic below - before this point, nothing about the live
    # install has changed yet.
    Write-Log "Swapping: bin -> $oldBin, then $newBin -> bin"
    Invoke-WithRetry { Rename-Item -LiteralPath $liveBin -NewName (Split-Path -Leaf $oldBin) -ErrorAction Stop } "rename live bin aside"
    $swapStarted = $true
    Invoke-WithRetry { Rename-Item -LiteralPath $newBin -NewName 'bin' -ErrorAction Stop } "rename bin_new into place"

    # config.txt lives INSIDE bin\ (Initialize-LegacyCore points ConfigPath
    # at $ScriptDir\config.txt, and ScriptDir is bin\ itself - confirmed by
    # a real end-to-end test with a planted marker value, which is exactly
    # how this got caught before shipping) - NOT at the install root like
    # the original plan assumed. The release zip never includes config.txt,
    # so it's completely absent from the newly-swapped-in bin\; it must be
    # carried over from the old one explicitly, or a real user's game
    # folder/editions/song picks would be silently wiped by every update.
    # rclone.conf and songcatalog.cache.json also live in bin\ but are
    # either always-empty (this app never stores named remotes in it) or a
    # regenerable cache with its own documented fetch-failure fallback -
    # not worth the extra risk of copying, unlike config.txt.
    $oldConfig = Join-Path $oldBin 'config.txt'
    if (Test-Path -LiteralPath $oldConfig) {
        Write-Log "Carrying config.txt over from the old bin\ (it lives inside bin\, never in the release zip)"
        Invoke-WithRetry { Copy-Item -LiteralPath $oldConfig -Destination (Join-Path $liveBin 'config.txt') -Force -ErrorAction Stop } "carry over config.txt"
    } else {
        Write-Log "No config.txt in the old bin\ - nothing to carry over (a fresh/never-configured install)."
    }

    # Root-level launchers/README - safe to overwrite directly by this
    # point (the original .bat's own cmd.exe host has already exited for
    # the GUI path; the console path's cmd.exe may still be open per the
    # plan's own noted asymmetry, but batch files aren't locked while
    # cmd.exe merely interprets them, so overwriting is still safe either
    # way - only relaunching into the SAME window would be the harder
    # problem, and this helper always opens a fresh one).
    foreach ($f in @('LegacyDownloader-GUI.bat', 'LegacyDownloader-Console.bat', 'README.txt')) {
        $src = Join-Path $StagingDir $f
        if (Test-Path -LiteralPath $src) {
            Invoke-WithRetry { Copy-Item -LiteralPath $src -Destination (Join-Path $InstallDir $f) -Force -ErrorAction Stop } "copy $f"
        }
    }

    # 4. Verify the now-live bin\ actually reports the expected version
    # before committing to deleting the old one.
    $liveVersion = Get-StagedVersion $liveBin
    if ($liveVersion -ne $ExpectedVersion) {
        throw "post-swap version check failed (expected $ExpectedVersion, got '$liveVersion')"
    }

    Write-Log "Swap verified OK (version $liveVersion). Removing $oldBin and the staging dir."
    Remove-Item -LiteralPath $oldBin -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $StagingDir -Recurse -Force -ErrorAction SilentlyContinue

    Write-Log "Relaunching ($RelaunchTarget)."
    Start-App
    Write-Log "=== Update complete ==="
} catch {
    Write-Log "FAILED: $($_.Exception.Message)"
    if ($swapStarted) {
        Write-Log "Rolling back: restoring $oldBin as bin"
        if (Test-Path -LiteralPath $liveBin) { Remove-Item -LiteralPath $liveBin -Recurse -Force -ErrorAction SilentlyContinue }
        if (Test-Path -LiteralPath $oldBin) {
            try { Rename-Item -LiteralPath $oldBin -NewName 'bin' -ErrorAction Stop }
            catch { Write-Log "ROLLBACK ALSO FAILED to restore bin from $oldBin - : $($_.Exception.Message)" }
        }
    } else {
        Write-Log "Swap never started - live bin\ was never touched, nothing to roll back."
    }
    Remove-Item -LiteralPath $newBin -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $StagingDir -Recurse -Force -ErrorAction SilentlyContinue
    Write-Log "Relaunching the still-working previous version."
    Start-App
    Write-Log "=== Update failed, rolled back, relaunched previous version ==="
}
