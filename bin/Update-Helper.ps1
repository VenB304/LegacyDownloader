# Update-Helper.ps1 - self-update's swap step.
#
# Spawned by Start-AppUpdateHelper (Core.psm1) as a detached process with a
# small visible console window (deliberately not hidden - see Core.psm1)
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
    # The window is visible now, so the same lines double as progress output.
    Write-Host $line
}

# Language-neutral title (product name + version only) so it needs no lang
# strings; the log lines below are the same technical English already
# written to update-helper.log.
try { $Host.UI.RawUI.WindowTitle = "LegacyDownloader - updating to $ExpectedVersion" } catch { }

function Get-StagedVersion([string]$BinDir) {
    $core = Join-Path $BinDir 'LegacyDownloader.Core.psm1'
    if (-not (Test-Path -LiteralPath $core)) { return $null }
    $versionLine = Get-Content -LiteralPath $core | Where-Object { $_ -match '^\$script:AppVersion\s*=' } | Select-Object -First 1
    if ($versionLine -notmatch "=\s*'([^']+)'") { return $null }
    return $Matches[1]
}

function Test-VersionsEqual([string]$A, [string]$B) {
    # Local copy of Core.psm1's Compare-AppVersions equality case (this
    # script is deliberately standalone, no Import-Module - see the file
    # header) - a plain string -ne here would wrongly treat 'V10' and
    # 'V10.0' as different releases and abort/roll back a perfectly good
    # update over a formatting difference alone. $null-safe: either side
    # being $null (Get-StagedVersion couldn't read a version line at all)
    # is never "equal", regardless of formatting. IsNullOrEmpty, not a bare
    # $null check - a [string]-typed parameter silently coerces an
    # explicitly-passed $null argument to "" in Windows PowerShell 5.1
    # (confirmed live), so $A/$B are never actually $null by the time this
    # line runs even when the caller passed real $null - a plain
    # "$null -eq $A" check would be dead code that looks like it guards
    # against exactly the case it doesn't actually catch.
    if ([string]::IsNullOrEmpty($A) -or [string]::IsNullOrEmpty($B)) { return $false }
    $pa = ($A -replace '^[vV]', '') -split '\.'
    $pb = ($B -replace '^[vV]', '') -split '\.'
    $n = [Math]::Max($pa.Count, $pb.Count)
    for ($i = 0; $i -lt $n; $i++) {
        $na = 0; $nb = 0
        if ($i -lt $pa.Count) { [void][int]::TryParse($pa[$i], [ref]$na) }
        if ($i -lt $pb.Count) { [void][int]::TryParse($pb[$i], [ref]$nb) }
        if ($na -ne $nb) { return $false }
    }
    return $true
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
    # Pre-create $newBin and copy $stagedBin's CHILDREN into it (not
    # $stagedBin itself) - copying the folder ITSELF only lands directly
    # inside $newBin while $newBin doesn't exist yet; if attempt 1 fails
    # partway (the exact locked-file scenario Invoke-WithRetry exists for),
    # $newBin now exists as a partial copy, and Copy-Item's behavior
    # against an EXISTING destination folder is different - it nests the
    # source folder AS A CHILD (bin_new_*\bin\... instead of bin_new_*\...),
    # which the post-copy version check below would never find. Wildcard-
    # copying children into an already-existing destination is correct on
    # every attempt, first or retried alike. -Force so a retry can
    # overwrite whatever attempt 1 partially wrote.
    Write-Log "Copying staged release to $newBin"
    if (-not (Test-Path -LiteralPath $newBin)) { New-Item -ItemType Directory -Path $newBin -Force | Out-Null }
    Invoke-WithRetry { Copy-Item -Path (Join-Path $stagedBin '*') -Destination $newBin -Recurse -Force -ErrorAction Stop } "copy staged bin to bin_new"

    $copiedVersion = Get-StagedVersion $newBin
    if (-not (Test-VersionsEqual $copiedVersion $ExpectedVersion)) {
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

    # bin\logs\ (the always-on troubleshooting log) lives inside bin\ same
    # as config.txt, and $oldBin gets deleted once the swap is verified -
    # without carrying it over, a successful self-update silently wipes
    # every pre-update log. Best-effort: a log history gap is real but
    # minor (the log itself starts working again immediately either way),
    # so a copy failure here logs and continues rather than failing the
    # whole update over it.
    $oldLogs = Join-Path $oldBin 'logs'
    if (Test-Path -LiteralPath $oldLogs) {
        Write-Log "Carrying bin\logs\ over from the old bin\"
        $newLogs = Join-Path $liveBin 'logs'
        # Same wildcard-into-a-pre-created-destination pattern as the
        # staged-bin copy above, for the same reason: Copy-Item nests the
        # source AS A CHILD if the destination already exists, rather than
        # merging into it - not expected to fire in practice (the release
        # zip never ships bin\logs\, and nothing writes to it between the
        # swap and this point), but costs nothing to guard against since
        # the pattern is already established two steps up.
        try {
            if (-not (Test-Path -LiteralPath $newLogs)) { New-Item -ItemType Directory -Path $newLogs -Force | Out-Null }
            Copy-Item -Path (Join-Path $oldLogs '*') -Destination $newLogs -Recurse -Force -ErrorAction Stop
        } catch { Write-Log "Non-fatal: couldn't carry bin\logs\ over: $($_.Exception.Message)" }
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
    if (-not (Test-VersionsEqual $liveVersion $ExpectedVersion)) {
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
    # The window is visible, so hold it a few seconds on failure - otherwise
    # it would vanish before anyone could read why the update didn't apply.
    Start-Sleep -Seconds 6
}
