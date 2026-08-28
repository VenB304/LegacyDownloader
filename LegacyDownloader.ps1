$ErrorActionPreference = 'Stop'
$Host.UI.RawUI.WindowTitle = 'Legacy Downloader'

function Enter-NoScrollBuffer {
    $rawUI = $Host.UI.RawUI
    $original = $rawUI.BufferSize
    try {
        $rawUI.BufferSize = New-Object System.Management.Automation.Host.Size($original.Width, $rawUI.WindowSize.Height)
    } catch { }
    return $original
}

function Exit-NoScrollBuffer($OriginalSize) {
    try { $Host.UI.RawUI.BufferSize = $OriginalSize } catch { }
}

try {
    Add-Type -Name NativeConsole -Namespace Win32 -MemberDefinition @'
[DllImport("kernel32.dll", SetLastError = true)]
public static extern bool GetConsoleMode(IntPtr hConsoleHandle, out uint lpMode);
[DllImport("kernel32.dll", SetLastError = true)]
public static extern bool SetConsoleMode(IntPtr hConsoleHandle, uint dwMode);
[DllImport("kernel32.dll", SetLastError = true)]
public static extern IntPtr GetStdHandle(int nStdHandle);
'@
} catch { }

function Reset-ConsoleInputMode {
    try {
        $STD_INPUT_HANDLE = -10
        $mode = 0x0001 -bor 0x0002 -bor 0x0004 -bor 0x0010 -bor 0x0020 -bor 0x0040 -bor 0x0080
        $handle = [Win32.NativeConsole]::GetStdHandle($STD_INPUT_HANDLE)
        [Win32.NativeConsole]::SetConsoleMode($handle, $mode) | Out-Null
    } catch { }
}

$ScriptDir  = Split-Path -Parent $MyInvocation.MyCommand.Path
$Rclone     = Join-Path $ScriptDir 'rclone.exe'
$ConfigPath = Join-Path $ScriptDir 'config.txt'

$RcloneConfigPath = Join-Path $ScriptDir 'rclone.conf'
if (-not (Test-Path $RcloneConfigPath)) {
    New-Item -ItemType File -Path $RcloneConfigPath -Force | Out-Null
}

$WebdavUrl  = "https://cloud.ovosimpatico.com/public.php/dav/files/TqaYM8TnT2RPNr2/"
$WebdavUser = "TqaYM8TnT2RPNr2"
$Conn = ":webdav,url='$WebdavUrl',vendor='nextcloud',user='$WebdavUser':"

$RcloneConfigArgs = @('--config', $RcloneConfigPath)

# --size-only: compare files by SIZE ONLY and ignore modification time.
# exFAT (what most external "play" drives use) rounds mtimes to a 2-second
# grid, so roughly half of all files come back 1 second off the server's
# value and rclone's default size+mtime check re-downloads them on every
# run - even files rclone itself just wrote. A real song/patch update
# always changes the file's size, so size-only is both safe for this
# content and immune to however the drive was populated.
$SizeOnlyArgs = @('--size-only')

$CommonArgs = @(
    '-P', '--transfers=4', '--checkers=8', '--stats=1s'
) + $SizeOnlyArgs + $RcloneConfigArgs

# Args for the pre-download "what would change" scan: no progress meter,
# verbose so every already-current file is named, dry-run so nothing moves.
$ScanArgs = @(
    '--transfers=4', '--checkers=8', '--dry-run', '-v'
) + $SizeOnlyArgs + $RcloneConfigArgs

function Pause-Continue([string]$Message = "Press Enter to continue") {
    Write-Host ""
    Read-Host $Message | Out-Null
}

function Pause-Brief([string]$Message, [int]$Seconds = 1) {
    if ($Message) { Write-Host $Message }
    Start-Sleep -Seconds $Seconds
}

function Pause-Exit([int]$Code) {
    Write-Host ""
    Read-Host "Press Enter to close"
    exit $Code
}

function Confirm-YesNo([string]$Prompt) {
    while ($true) {
        $ans = Read-Host "$Prompt (y/n)"
        if ($ans -match '^[Yy]') { return $true }
        if ($ans -match '^[Nn]') { return $false }
        Write-Host "Please type y or n."
    }
}

function Test-GameFolder([string]$Path) {
    if ([string]::IsNullOrWhiteSpace($Path)) { return $false }
    return (Test-Path (Join-Path $Path 'Legacy.exe'))
}

function Show-FolderPicker([string]$Description) {
    Add-Type -AssemblyName System.Windows.Forms
    $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
    $dialog.Description = $Description
    $dialog.ShowNewFolderButton = $true

    $owner = New-Object System.Windows.Forms.Form
    $owner.TopMost = $true
    $owner.ShowInTaskbar = $false
    $owner.StartPosition = 'CenterScreen'
    $owner.Size = New-Object System.Drawing.Size(0, 0)
    $owner.Show()
    $owner.Focus() | Out-Null

    $result = $dialog.ShowDialog($owner)
    $owner.Close()
    $owner.Dispose()

    if ($result -eq [System.Windows.Forms.DialogResult]::OK) {
        return $dialog.SelectedPath.TrimEnd('\')
    }
    return $null
}

function Ensure-Directory([string]$Path) {
    try {
        New-Item -ItemType Directory -Force -Path $Path -ErrorAction Stop | Out-Null
        return $true
    } catch {
        Write-Host "Couldn't create that folder: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

function Load-Config {
    if (-not (Test-Path $ConfigPath)) {
        Save-Config -GamePath '' -Editions 'AUTO'
    }
    $gamePath = ''
    $editions = 'AUTO'
    foreach ($line in Get-Content $ConfigPath) {
        $trimmed = $line.Trim()
        if ($trimmed -eq '' -or $trimmed.StartsWith('#')) { continue }
        $parts = $trimmed.Split('=', 2)
        if ($parts.Count -lt 2) { continue }
        $key = $parts[0].Trim().ToUpper()
        $value = $parts[1].Trim()
        if ($key -eq 'GAMEPATH') { $gamePath = $value }
        if ($key -eq 'EDITIONS') { $editions = $value }
    }
    if ([string]::IsNullOrWhiteSpace($editions)) { $editions = 'AUTO' }
    return [PSCustomObject]@{ GamePath = $gamePath; Editions = $editions }
}

function Save-Config([string]$GamePath, [string]$Editions) {
    @(
        "# Legacy Downloader - configuration"
        "# You normally don't need to edit this by hand - use the program's"
        "# menus (Change Game Path / Select Maps) instead."
        ""
        "GAMEPATH=$GamePath"
        ""
        "# EDITIONS is either AUTO (every edition, including new ones as they"
        "# get added later) or a comma-separated list of specific edition"
        "# folder names, e.g. 2024,2,3"
        "EDITIONS=$Editions"
    ) | Set-Content -Path $ConfigPath -Encoding UTF8
}

function Sort-EditionNames {
    param([Parameter(ValueFromPipeline = $true)][string[]]$InputObject)
    begin { $items = @() }
    process { $items += $InputObject }
    end {
        $items | Sort-Object -Property @(
            @{ Expression = { $n = 0; if ([int]::TryParse($_, [ref]$n)) { $n } else { [int]::MaxValue } } },
            @{ Expression = { $_ } }
        )
    }
}

function Get-RemoteEditions {
    $out = & $Rclone lsf "$Conn`maps" --dirs-only @RcloneConfigArgs 2>$null
    return @($out | ForEach-Object { $_.TrimEnd('/') } | Where-Object { $_ -ne '' } | Sort-EditionNames)
}

function Get-RemoteSongs([string]$Edition) {
    $out = & $Rclone lsf "$Conn`maps/$Edition" --files-only @RcloneConfigArgs 2>$null
    return @($out | ForEach-Object { $_ -replace '_pc\.ipk$', '' } | Sort-Object)
}

function Get-LocalEditions([string]$GamePath) {
    $mapsDir = Join-Path $GamePath 'maps'
    if (-not (Test-Path $mapsDir)) { return @() }
    return @(Get-ChildItem -Path $mapsDir -Directory -ErrorAction SilentlyContinue | ForEach-Object { $_.Name } | Sort-EditionNames)
}

function ConvertTo-QuotedArg([string]$Value) {
    if ($Value -notmatch '\s') { return $Value }
    $escaped = $Value -replace '(\\+)$', '$1$1'
    return '"' + $escaped + '"'
}

function Invoke-RcloneCapture([string[]]$RcloneArgs) {
    # Run rclone and hand back stdout+stderr as an array of lines, WITHOUT
    # letting rclone's stderr NOTICE output trip $ErrorActionPreference='Stop'
    # (that promotion happens before any 2>$null redirect - see the 2026-08
    # fix). Start-Process with redirect files keeps rclone's streams away
    # from PowerShell's error stream entirely.
    $outFile = [System.IO.Path]::GetTempFileName()
    $errFile = [System.IO.Path]::GetTempFileName()
    try {
        $argLine = ($RcloneArgs | ForEach-Object { ConvertTo-QuotedArg $_ }) -join ' '
        $proc = Start-Process -FilePath $Rclone -ArgumentList $argLine -NoNewWindow -Wait -PassThru `
                    -RedirectStandardOutput $outFile -RedirectStandardError $errFile
        $lines = @()
        $lines += @(Get-Content -LiteralPath $outFile -ErrorAction SilentlyContinue)
        $lines += @(Get-Content -LiteralPath $errFile -ErrorAction SilentlyContinue)
        $code = 0
        try { $code = [int]$proc.ExitCode } catch { $code = -1 }
        return [PSCustomObject]@{ ExitCode = $code; Lines = $lines }
    } finally {
        Remove-Item -LiteralPath $outFile, $errFile -Force -ErrorAction SilentlyContinue
    }
}

function ConvertFrom-RcloneSize([string]$Num, [string]$Unit) {
    $n = 0.0
    if (-not [double]::TryParse($Num, [ref]$n)) { return [long]0 }
    switch (($Unit -replace 'i?B?$', '').ToLower()) {
        'k' { return [long]($n * 1KB) }
        'm' { return [long]($n * 1MB) }
        'g' { return [long]($n * 1GB) }
        't' { return [long]($n * 1TB) }
        default { return [long]$n }
    }
}

function Format-Bytes([long]$Bytes) {
    if ($Bytes -ge 1GB) { return ('{0:N1} GB' -f ($Bytes / 1GB)) }
    if ($Bytes -ge 1MB) { return ('{0:N0} MB' -f ($Bytes / 1MB)) }
    if ($Bytes -ge 1KB) { return ('{0:N0} KB' -f ($Bytes / 1KB)) }
    return "$Bytes B"
}

function Parse-DryRun([string[]]$Lines) {
    # Pull "<path>: Skipped copy as --dry-run is set (size 12.3Mi)" lines out
    # of rclone -v --dry-run output -> relative paths + summed byte total.
    $files = @()
    [long]$bytes = 0
    $marker = ': Skipped copy as --dry-run is set'
    foreach ($raw in $Lines) {
        $ln = [string]$raw
        $i = $ln.IndexOf($marker)
        if ($i -lt 0) { continue }
        $left = $ln.Substring(0, $i)
        $left = $left -replace '^\s*\d{4}/\d{2}/\d{2}\s+\d{2}:\d{2}:\d{2}\s+\w+\s*:\s*', ''
        $left = $left -replace '^\s*(NOTICE|INFO|DEBUG|ERROR)\s*:\s*', ''
        $path = $left.Trim()
        if ($path -eq '') { continue }
        $files += $path
        $m = [regex]::Match($ln, '\(size\s+(?<num>[0-9.]+)\s*(?<unit>[A-Za-z]*)\)')
        if ($m.Success) {
            $bytes += ConvertFrom-RcloneSize $m.Groups['num'].Value $m.Groups['unit'].Value
        }
    }
    return [PSCustomObject]@{ Files = @($files); Bytes = $bytes }
}

function Resolve-GameFolder([string]$Path) {
    # If GAMEPATH doesn't point straight at Legacy.exe, check whether the
    # real install is one level up or down. The Nextcloud share nests the
    # game under a "LegacyPC - Game" folder and a hand-made rclone copy
    # keeps that name, so people commonly point one level too deep (at
    # ...\LegacyPC - Game when maps\ is its sibling) or too shallow.
    if ([string]::IsNullOrWhiteSpace($Path)) { return $null }
    $Path = $Path.TrimEnd('\')
    if (Test-GameFolder $Path) { return $Path }

    # [IO.Path]::Combine, not Join-Path: the latter throws if the drive
    # (e.g. an unplugged play drive) isn't currently mounted.
    $child = [System.IO.Path]::Combine($Path, 'LegacyPC - Game')
    if (Test-GameFolder $child) { return $child }

    if ((Split-Path -Leaf $Path) -eq 'LegacyPC - Game') {
        $parent = Split-Path -Parent $Path
        if ($parent -and (Test-GameFolder $parent)) { return $parent }
    }
    return $Path
}

function Get-LocalSongCount([string]$GamePath) {
    $mapsDir = [System.IO.Path]::Combine($GamePath, 'maps')
    if (-not (Test-Path $mapsDir)) { return 0 }
    return @(Get-ChildItem -Path $mapsDir -Recurse -Filter '*.ipk' -File -ErrorAction SilentlyContinue).Count
}

function Invoke-RcloneCopy([string]$Source, [string]$Dest, [string[]]$ExtraArgs = @()) {
    $savedBuffer = Enter-NoScrollBuffer
    try {
        $quotedSource = ConvertTo-QuotedArg $Source
        $quotedDest   = ConvertTo-QuotedArg $Dest
        $quotedCommonArgs = $CommonArgs | ForEach-Object { ConvertTo-QuotedArg $_ }
        $argLine = (@('copy', $quotedSource, $quotedDest) + $quotedCommonArgs + $ExtraArgs) -join ' '
        Start-Process -FilePath $Rclone -ArgumentList $argLine -NoNewWindow -Wait
    } finally {
        Exit-NoScrollBuffer $savedBuffer
    }
}

function Invoke-BaseSync([string]$GamePath, [string[]]$ExtraExcludes = @()) {
    Write-Host "Updating base game files (exe, DLLs, Support, .ipk)..."
    $excludeArgs = @('--exclude', 'maps/**')
    foreach ($e in $ExtraExcludes) { $excludeArgs += @('--exclude', $e) }
    Invoke-RcloneCopy "$Conn`LegacyPC - Game" $GamePath $excludeArgs
    Write-Host ""
}

function Invoke-EditionSync([string]$GamePath, [string]$Edition) {
    Write-Host "Updating edition $Edition..."
    Invoke-RcloneCopy "$Conn`maps/$Edition" (Join-Path $GamePath "maps\$Edition")
    Write-Host ""
}

function Invoke-AllMapsSync([string]$GamePath, [switch]$Confirmed) {
    $mapsDir = Join-Path $GamePath 'maps'
    if (-not $Confirmed -and (Test-GameFolder $GamePath) -and -not (Test-Path $mapsDir)) {
        Write-Host "WARNING: the game is installed here but there's no 'maps' folder:" -ForegroundColor Yellow
        Write-Host "  $mapsDir"
        Write-Host "Your game folder setting is probably pointing at the wrong level."
        Write-Host "Continuing will download the ENTIRE song library (100+ GB)."
        if (-not (Confirm-YesNo "Download the whole library anyway?")) {
            Write-Host "Skipped."
            return
        }
    }
    Write-Host "Updating ALL song editions - this may take a long time on first run."
    Invoke-RcloneCopy "$Conn`maps" $mapsDir
    Write-Host ""
}

function Invoke-Update([string]$GamePath, [string]$Editions, [string[]]$BaseExcludes = @(), [switch]$Confirmed) {
    Invoke-BaseSync $GamePath $BaseExcludes
    if ($Editions.ToUpper() -eq 'AUTO') {
        Invoke-AllMapsSync $GamePath -Confirmed:$Confirmed
    } else {
        $list = $Editions -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' }
        foreach ($ed in $list) { Invoke-EditionSync $GamePath $ed }
    }
    Write-Host "============================================"
    Write-Host "  Done."
    Write-Host "============================================"
}

function Show-UpdatePreview {
    param([string]$GamePath, [string]$Editions)

    # Returns @{ Proceed; Dismissed; BaseExcludes }.
    #   Proceed   - caller should run the real sync now
    #   Dismissed - user explicitly backed out (cancel / declined a warning /
    #               server unreachable); distinct from "nothing to download",
    #               where both Proceed and Dismissed are false.
    # Runs the real sync commands with --dry-run first so the user sees
    # exactly what would download (and nothing does) before committing.
    $result = @{ Proceed = $false; Dismissed = $false; BaseExcludes = @() }

    Write-Host "Checking what you already have (no downloads yet)..."

    $mapsDir     = [System.IO.Path]::Combine($GamePath, 'maps')   # not Join-Path: no drive check
    $gamePresent = Test-GameFolder $GamePath
    $mapsMissing = -not (Test-Path $mapsDir)
    $betterPath  = Resolve-GameFolder $GamePath
    $wrongLevel  = $betterPath -and ($betterPath -ne $GamePath.TrimEnd('\'))

    # A wrong game-folder level means every check would come back "missing"
    # and re-download the whole library into the wrong place. Say so up front
    # and bail out before doing the (slow) scan, unless they insist.
    if ($wrongLevel) {
        Write-Host ""
        Write-Host "WARNING: Legacy.exe isn't in your game folder:" -ForegroundColor Yellow
        Write-Host "  $GamePath" -ForegroundColor Yellow
        Write-Host "The real install looks like it's at:" -ForegroundColor Yellow
        Write-Host "  $betterPath" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "Downloading now would re-fetch EVERYTHING into the wrong place."
        Write-Host "Fix it first with main menu option [3] (Change game folder)."
        Write-Host ""
        if (-not (Confirm-YesNo "Ignore this and check for updates anyway?")) {
            $result.Dismissed = $true
            return $result
        }
    }

    $netFail = {
        Write-Host ""
        Write-Host "Couldn't reach the song server. Check your internet and try again." -ForegroundColor Yellow
        $result.Dismissed = $true
    }

    # ---- base game ----
    $baseRun = Invoke-RcloneCapture (@('copy', "$Conn`LegacyPC - Game", $GamePath, '--exclude', 'maps/**') + $ScanArgs)
    if ($baseRun.ExitCode -ne 0) { & $netFail; return $result }
    $base = Parse-DryRun $baseRun.Lines

    # ---- songs ----
    if ($Editions.ToUpper() -eq 'AUTO') {
        $mapRun = Invoke-RcloneCapture (@('copy', "$Conn`maps", $mapsDir) + $ScanArgs)
        if ($mapRun.ExitCode -ne 0) { & $netFail; return $result }
        $maps = Parse-DryRun $mapRun.Lines
    } else {
        $list = $Editions -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' }
        $mf = @(); [long]$mb = 0
        foreach ($ed in $list) {
            $r = Invoke-RcloneCapture (@('copy', "$Conn`maps/$ed", [System.IO.Path]::Combine($mapsDir, $ed)) + $ScanArgs)
            if ($r.ExitCode -ne 0) { & $netFail; return $result }
            $p = Parse-DryRun $r.Lines
            foreach ($f in $p.Files) { $mf += "$ed/$f" }
            $mb += $p.Bytes
        }
        $maps = [PSCustomObject]@{ Files = @($mf); Bytes = $mb }
    }

    # ---- separate the base files people commonly modify ----
    $protected = @('legacy.exe', 'kinect10.dll', 'kinect20.dll', 'config.xml')
    $baseProtected = @($base.Files | Where-Object { $protected -contains (Split-Path -Leaf $_).ToLower() })
    $baseNormal    = @($base.Files | Where-Object { $protected -notcontains (Split-Path -Leaf $_).ToLower() })

    $totalFiles = $base.Files.Count + $maps.Files.Count
    $totalBytes = $base.Bytes + $maps.Bytes

    Write-Host ""
    Write-Host "============================================"
    Write-Host "  Update check"
    Write-Host "============================================"
    Write-Host ""

    if ($totalFiles -eq 0) {
        Write-Host "Everything is already up to date." -ForegroundColor Green
        Write-Host ""
        Write-Host ("You have {0} edition(s) and {1} song(s) here." -f @(Get-LocalEditions $GamePath).Count, (Get-LocalSongCount $GamePath))
        Write-Host "Nothing to download."
        Write-Host ""
        return $result
    }

    if ($gamePresent -and $mapsMissing) {
        Write-Host "WARNING: your game is installed here but has no 'maps' subfolder," -ForegroundColor Yellow
        Write-Host "so this would download the ENTIRE library. Double-check your game" -ForegroundColor Yellow
        Write-Host "folder (main menu option [3]) first." -ForegroundColor Yellow
        Write-Host ""
    }

    if ($baseNormal.Count -gt 0) {
        $baseLine = "Base game : {0} file(s) to update" -f $baseNormal.Count
        if ($baseProtected.Count -gt 0) { $baseLine += " (+ {0} moddable file(s), see below)" -f $baseProtected.Count }
        Write-Host $baseLine
    } elseif ($baseProtected.Count -gt 0) {
        Write-Host ("Base game : {0} moddable file(s) differ, see below" -f $baseProtected.Count)
    } else {
        Write-Host "Base game : up to date"
    }

    if ($maps.Files.Count -gt 0) {
        $byEd = [ordered]@{}
        foreach ($f in $maps.Files) {
            $ed = ($f -split '[\\/]', 2)[0]
            if (-not $byEd.Contains($ed)) { $byEd[$ed] = 0 }
            $byEd[$ed] = $byEd[$ed] + 1
        }
        Write-Host ""
        Write-Host "Songs to download / update:"
        foreach ($k in ($byEd.Keys | Sort-EditionNames)) {
            Write-Host ("  {0,-10} {1} file(s)" -f $k, $byEd[$k])
        }
    } else {
        Write-Host "Songs     : up to date"
    }

    Write-Host ""
    Write-Host ("Total: {0} file(s), about {1}" -f $totalFiles, (Format-Bytes $totalBytes))
    Write-Host ""

    # Modifiable base files: ask one at a time, default No, so an update
    # can't silently clobber a patched exe or the Kinect shim.
    $excludes = @()
    foreach ($pf in $baseProtected) {
        $leaf = Split-Path -Leaf $pf
        Write-Host "The server's copy of '$leaf' differs from yours." -ForegroundColor Yellow
        Write-Host "If you've patched or modded it (Kinect, etc.), keep your version."
        if (-not (Confirm-YesNo "Overwrite your '$leaf' with the server's copy?")) {
            $excludes += $pf
            Write-Host "Keeping your '$leaf'."
        }
        Write-Host ""
    }
    $result.BaseExcludes = $excludes

    if (($baseNormal.Count + $maps.Files.Count + $baseProtected.Count - $excludes.Count) -le 0) {
        Write-Host "Nothing left to download." -ForegroundColor Green
        Write-Host ""
        return $result
    }

    while ($true) {
        Write-Host "[1] Download now"
        Write-Host "[2] Show full file list"
        Write-Host "[3] Cancel"
        $c = Read-Host "Choose an option (1-3)"
        if ($c -eq '1') { $result.Proceed = $true; return $result }
        if ($c -eq '3') { $result.Dismissed = $true; return $result }
        if ($c -eq '2') {
            Write-Host ""
            if ($baseNormal.Count -gt 0) {
                Write-Host "Base game:"
                foreach ($f in $baseNormal) { Write-Host "  $f" }
            }
            foreach ($pf in $baseProtected) {
                $tag = if ($excludes -contains $pf) { "(keeping yours)" } else { "(will overwrite)" }
                Write-Host ("  {0}  {1}" -f $pf, $tag)
            }
            if ($maps.Files.Count -gt 0) {
                Write-Host "Songs:"
                foreach ($f in ($maps.Files | Sort-Object)) { Write-Host "  $f" }
            }
            Write-Host ""
            continue
        }
        Write-Host "Please choose 1, 2 or 3."
    }
}

function Show-Checklist([string[]]$Items, [string[]]$PreChecked) {
    $checked = New-Object System.Collections.Generic.HashSet[string]
    foreach ($p in $PreChecked) { [void]$checked.Add($p) }

    $rows = @()
    $rows += $Items
    $rows += '---'
    $rows += '[ Back ]'
    $rows += '[ Cancel ]'
    $rows += '[ Continue ]'

    $cursor = 0
    while ($rows[$cursor] -eq '---') { $cursor++ }

    $savedBuffer = Enter-NoScrollBuffer
    [Console]::CursorVisible = $false

    try {
        while ($true) {
            Clear-Host
            Write-Host "Use the Up/Down arrow keys to move, press Enter to check/uncheck."
            Write-Host ""
            for ($i = 0; $i -lt $rows.Count; $i++) {
                $row = $rows[$i]
                $pointer = if ($i -eq $cursor) { '>' } else { ' ' }
                if ($row -eq '---') {
                    $line = ''
                } elseif ($row.StartsWith('[')) {
                    $line = "$pointer  $row"
                } else {
                    $mark = if ($checked.Contains($row)) { 'x' } else { ' ' }
                    $line = "$pointer  [$mark] $row"
                }
                Write-Host $line
            }

            $key = [Console]::ReadKey($true)
            switch ($key.Key) {
                'UpArrow' {
                    do { $cursor--; if ($cursor -lt 0) { $cursor = $rows.Count - 1 } } while ($rows[$cursor] -eq '---')
                }
                'DownArrow' {
                    do { $cursor++; if ($cursor -ge $rows.Count) { $cursor = 0 } } while ($rows[$cursor] -eq '---')
                }
                'Enter' {
                    $row = $rows[$cursor]
                    if ($row -eq '[ Back ]')     { return @{ Action = 'Back' } }
                    if ($row -eq '[ Cancel ]')   { return @{ Action = 'Cancel' } }
                    if ($row -eq '[ Continue ]') { return @{ Action = 'Continue'; Selected = @($checked) } }
                    if ($checked.Contains($row)) { [void]$checked.Remove($row) } else { [void]$checked.Add($row) }
                }
                'Escape' { return @{ Action = 'Cancel' } }
            }
        }
    } finally {
        [Console]::CursorVisible = $true
        Exit-NoScrollBuffer $savedBuffer
        Reset-ConsoleInputMode
    }
}

function Run-MapsWizard([string]$GamePath, [string]$CurrentEditions) {
    while ($true) {
        Write-Host "============================================"
        Write-Host "  Choose Which Songs To Get"
        Write-Host "============================================"
        Write-Host ""
        Write-Host "[1] Everything (all editions, plus new ones as they come out)"
        Write-Host "[2] Only specific editions (e.g. just Just Dance 2019, or a few)"
        Write-Host "[3] Go to Main Menu"
        $choice = Read-Host "Choose an option (1-3)"

        if ($choice -eq '3') { return $null }

        if ($choice -eq '1') {
            Write-Host ""
            $prev = Show-UpdatePreview -GamePath $GamePath -Editions 'AUTO'
            if ($prev.Proceed) {
                Write-Host ""
                Invoke-Update -GamePath $GamePath -Editions 'AUTO' -BaseExcludes $prev.BaseExcludes -Confirmed
            }
            return 'AUTO'
        }

        if ($choice -ne '2') {
            Pause-Brief "Not a valid option."
            continue
        }

        Write-Host ""
        Write-Host "Checking what's available..."
        $remote = Get-RemoteEditions
        if (-not $remote -or $remote.Count -eq 0) {
            Write-Host "Couldn't reach the song server. Check your internet connection and try again."
            Pause-Continue
            continue
        }

        $preChecked = if ($CurrentEditions.ToUpper() -eq 'AUTO') {
            Get-LocalEditions $GamePath
        } else {
            $CurrentEditions -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' }
        }

        $backToTop = $false
        while ($true) {
            Write-Host ""
            $result = Show-Checklist -Items $remote -PreChecked $preChecked
            Write-Host ""

            if ($result.Action -eq 'Cancel') { return $null }
            if ($result.Action -eq 'Back')   { $backToTop = $true; break }

            $selected = @($result.Selected | Sort-EditionNames)

            Write-Host "============================================"
            Write-Host "  Summary"
            Write-Host "============================================"
            if ($selected.Count -eq 0) {
                Write-Host "No editions selected."
            } else {
                $label = if ($selected.Count -eq 1) { "Selected Edition:" } else { "Selected Editions:" }
                Write-Host $label
                foreach ($ed in $selected) {
                    Write-Host "  $ed"
                    foreach ($song in (Get-RemoteSongs $ed)) { Write-Host "    - $song" }
                }
            }

            $previouslyTracked = if ($CurrentEditions.ToUpper() -eq 'AUTO') {
                Get-LocalEditions $GamePath
            } else {
                $CurrentEditions -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' }
            }
            $removed = @($previouslyTracked | Where-Object { $selected -notcontains $_ })
            if ($removed.Count -gt 0) {
                Write-Host ""
                Write-Host "You'll stop getting new songs for: $($removed -join ', ')"
            }
            Write-Host ""

            if ($selected.Count -eq 0) {
                Write-Host "Nothing is checked - there's nothing to download." -ForegroundColor Yellow
                if (-not (Confirm-YesNo "Go back to the list?")) { return $null }
                $preChecked = $selected
                continue
            }

            $prev = Show-UpdatePreview -GamePath $GamePath -Editions ($selected -join ',')
            if ($prev.Dismissed) {
                $preChecked = $selected
                continue
            }

            # Removed-edition cleanup runs whether or not there's anything new
            # to fetch (the user unchecked these on purpose).
            foreach ($ed in $removed) {
                $localDir = Join-Path $GamePath "maps\$ed"
                if (Test-Path $localDir) {
                    if (Confirm-YesNo "Delete the local files for '$ed' too, or just stop tracking it?") {
                        try {
                            Remove-Item -Recurse -Force $localDir -ErrorAction Stop
                            Write-Host "Deleted $ed."
                        } catch {
                            Write-Host "Couldn't delete $ed - it may be in use (e.g. the game is running). It'll just stay untracked instead." -ForegroundColor Yellow
                        }
                    } else {
                        Write-Host "Keeping $ed on disk, but it won't be updated anymore."
                    }
                }
            }

            if ($prev.Proceed) {
                Write-Host ""
                foreach ($ed in $selected) { Invoke-EditionSync $GamePath $ed }
                Invoke-BaseSync $GamePath $prev.BaseExcludes
            }

            return ($selected -join ',')
        }

        if ($backToTop) { continue }
    }
}

function Run-SetupWizard {
    Write-Host "============================================"
    Write-Host "  Welcome!"
    Write-Host "============================================"
    Write-Host ""
    Write-Host "This little program downloads Legacy Offline PC and its songs"
    Write-Host "for you, and can check for new songs later whenever you want."
    Write-Host "No typing folder paths - a window will pop up so you can just"
    Write-Host "click to pick a folder, like any other program you install."
    Write-Host ""

    while ($true) {
        Write-Host "[1] I already have the game on this PC"
        Write-Host "[2] I don't have it yet - download it for me"
        $choice = Read-Host "Choose an option (1-2)"

        if ($choice -eq '1') {
            Write-Host ""
            Write-Host "A window will pop up - find and click the folder that has"
            Write-Host "Legacy.exe inside it, then press Select Folder."
            $path = Show-FolderPicker "Select your Legacy Offline PC folder (the one with Legacy.exe in it)"
            if ($null -eq $path) {
                Write-Host "No folder was picked."
                Pause-Brief
                continue
            }
            if (-not (Test-GameFolder $path)) {
                Write-Host "Hmm, that folder doesn't seem to have Legacy.exe in it."
                if ((Confirm-YesNo "Download the game into this folder now?") -and (Ensure-Directory $path)) {
                    Write-Host ""
                    Invoke-BaseSync $path
                }
            }
            return $path
        }

        if ($choice -eq '2') {
            Write-Host ""
            Write-Host "A window will pop up - pick (or create) an empty folder for"
            Write-Host "the game to live in. Click 'Make New Folder' if you want a"
            Write-Host "fresh one, then press Select Folder."
            $path = Show-FolderPicker "Pick a folder for Legacy Offline PC (or click Make New Folder)"
            if ($null -eq $path) {
                Write-Host "No folder was picked."
                Pause-Brief
                continue
            }
            if (Ensure-Directory $path) {
                Write-Host ""
                Invoke-BaseSync $path
            }
            return $path
        }

        Pause-Brief "Not a valid option."
    }
}

if (-not (Test-Path $Rclone)) {
    Write-Host "ERROR: rclone.exe is missing from this folder. Re-download the bundle." -ForegroundColor Red
    Pause-Exit 1
}

try {
    & $Rclone version @RcloneConfigArgs *> $null
    if ($LASTEXITCODE -ne 0) { throw "exit code $LASTEXITCODE" }
} catch {
    Write-Host "ERROR: rclone.exe is here but won't run." -ForegroundColor Red
    Write-Host "This is usually antivirus quarantining it (rclone is sometimes"
    Write-Host "flagged as a 'hacktool' since attackers also use it - it's a"
    Write-Host "legitimate, widely-used open-source tool). Check your"
    Write-Host "antivirus's quarantine/history for rclone.exe, restore or"
    Write-Host "allow it, then run this again."
    Pause-Exit 1
}

$cfg = Load-Config

if ([string]::IsNullOrWhiteSpace($cfg.GamePath)) {
    $gamePath = Run-SetupWizard
    Save-Config -GamePath $gamePath -Editions $cfg.Editions
    $cfg = Load-Config

    Write-Host ""
    $mapsResult = Run-MapsWizard -GamePath $cfg.GamePath -CurrentEditions $cfg.Editions
    if ($null -ne $mapsResult) {
        Save-Config -GamePath $cfg.GamePath -Editions $mapsResult
        $cfg = Load-Config
    }

    Write-Host ""
    Write-Host "============================================"
    if (Test-GameFolder $cfg.GamePath) {
        Write-Host "  You're all set!"
        Write-Host "============================================"
        Write-Host ""
        Write-Host "To play: open Legacy.exe in $($cfg.GamePath)"
    } else {
        Write-Host "  Almost there"
        Write-Host "============================================"
        Write-Host ""
        Write-Host "The game hasn't actually been downloaded to $($cfg.GamePath) yet."
        Write-Host "Pick 'Download / check for new songs' from the menu whenever"
        Write-Host "you're ready to grab it."
    }
    Write-Host ""
    Write-Host "Come back and run this program anytime to check for new songs."
    Pause-Continue
}

# Sanity-check the saved game folder: if Legacy.exe isn't right there but is
# one level up or down, offer to correct the setting. A wrong level here is
# what makes the tool think no songs are installed and re-download everything.
if (-not [string]::IsNullOrWhiteSpace($cfg.GamePath)) {
    $betterPath = Resolve-GameFolder $cfg.GamePath
    if ($betterPath -and ($betterPath -ne $cfg.GamePath.TrimEnd('\'))) {
        Write-Host ""
        Write-Host "Your game folder is set to:" -ForegroundColor Yellow
        Write-Host "  $($cfg.GamePath)"
        Write-Host "but Legacy.exe is actually in:"
        Write-Host "  $betterPath"
        Write-Host ""
        if (Confirm-YesNo "Point the downloader at the correct folder?") {
            Save-Config -GamePath $betterPath -Editions $cfg.Editions
            $cfg = Load-Config
            Write-Host "Updated." -ForegroundColor Green
            Start-Sleep -Seconds 1
        }
    }
}

while ($true) {
    Clear-Host
    Write-Host "============================================"
    Write-Host "  Legacy Downloader"
    Write-Host "  Game folder : $($cfg.GamePath)"
    Write-Host "  Editions    : $($cfg.Editions)"
    Write-Host "============================================"
    Write-Host ""
    Write-Host "This never deletes anything on its own without asking you first."
    Write-Host "Your save data is always safe."
    Write-Host ""
    Write-Host "[1] Download / check for new songs"
    Write-Host "[2] Choose which songs to get"
    Write-Host "[3] Change game folder"
    Write-Host "[4] Exit"
    $choice = Read-Host "Choose an option (1-4)"

    switch ($choice) {
        '1' {
            Write-Host ""
            $prev = Show-UpdatePreview -GamePath $cfg.GamePath -Editions $cfg.Editions
            if ($prev.Proceed) {
                Write-Host ""
                Invoke-Update -GamePath $cfg.GamePath -Editions $cfg.Editions -BaseExcludes $prev.BaseExcludes -Confirmed
                Write-Host ""
                Write-Host "You're up to date! Open Legacy.exe in your game folder to play."
            }
            Pause-Continue
        }
        '2' {
            Write-Host ""
            $mapsResult = Run-MapsWizard -GamePath $cfg.GamePath -CurrentEditions $cfg.Editions
            if ($null -ne $mapsResult) {
                Save-Config -GamePath $cfg.GamePath -Editions $mapsResult
                $cfg = Load-Config
                Write-Host ""
                Write-Host "Those songs are ready - just launch Legacy.exe and pick them"
                Write-Host "from the song list like normal."
                Pause-Brief "Saved." 2
            }
        }
        '3' {
            Write-Host ""
            Write-Host "A window will pop up - find and click your Legacy Offline PC"
            Write-Host "folder (the one with Legacy.exe in it), then press Select Folder."
            Write-Host "Click Cancel in that window if you change your mind."
            $path = Show-FolderPicker "Select your Legacy Offline PC folder (the one with Legacy.exe in it)"
            if ($null -ne $path) {
                $ok = Test-GameFolder $path
                if (-not $ok) { $ok = Confirm-YesNo "Legacy.exe wasn't found there. Use this folder anyway?" }
                if ($ok) {
                    Save-Config -GamePath $path -Editions $cfg.Editions
                    $cfg = Load-Config
                    Write-Host "Saved."
                    if (-not (Test-GameFolder $path)) {
                        Write-Host "Don't forget to use 'Download / check for new songs' next -"
                        Write-Host "this folder doesn't have the game in it yet."
                        Pause-Continue
                    } else {
                        Pause-Brief -Seconds 2
                    }
                }
            }
        }
        '4' {
            Write-Host ""
            Write-Host "Enjoy the game! Come back anytime to check for new songs."
            Start-Sleep -Seconds 1
            exit 0
        }
        default {
            Pause-Brief "Not a valid option."
        }
    }
}
