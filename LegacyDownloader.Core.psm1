# LegacyDownloader.Core.psm1
# Shared engine for the Legacy Downloader console and GUI front-ends.
#
# Pure logic only: no Write-Host, no Read-Host, no menu code. A front-end
# calls Initialize-LegacyCore once (passing the folder the tool lives in),
# then uses these helpers. Everything the front-ends need to know about
# rclone paths / connection strings / argument sets comes back from
# Initialize-LegacyCore as an object.

$ErrorActionPreference = 'Stop'

# --- module-scoped state, filled in by Initialize-LegacyCore ---
$script:Rclone           = $null
$script:ConfigPath       = $null
$script:RcloneConfigPath = $null
$script:Conn             = $null
$script:RcloneConfigArgs = @()
$script:SizeOnlyArgs     = @('--size-only')
$script:CommonArgs       = @()
$script:ScanArgs         = @()

# --- i18n state, filled in by Initialize-Language ---
$script:LangDir          = $null
$script:LangCode         = 'en'
$script:Strings          = @{}   # active language
$script:StringsFallback  = @{}   # English, always loaded as the fallback layer

function Initialize-LegacyCore {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$ScriptDir)

    $script:Rclone     = Join-Path $ScriptDir 'rclone.exe'
    $script:ConfigPath = Join-Path $ScriptDir 'config.txt'
    $script:LangDir    = Join-Path $ScriptDir 'lang'

    $script:RcloneConfigPath = Join-Path $ScriptDir 'rclone.conf'
    if (-not (Test-Path $script:RcloneConfigPath)) {
        New-Item -ItemType File -Path $script:RcloneConfigPath -Force | Out-Null
    }

    $webdavUrl  = "https://cloud.ovosimpatico.com/public.php/dav/files/TqaYM8TnT2RPNr2/"
    $webdavUser = "TqaYM8TnT2RPNr2"
    $script:Conn = ":webdav,url='$webdavUrl',vendor='nextcloud',user='$webdavUser':"

    $script:RcloneConfigArgs = @('--config', $script:RcloneConfigPath)

    # --size-only: compare files by SIZE ONLY and ignore modification time.
    # exFAT (what most external "play" drives use) rounds mtimes to a
    # 2-second grid, so roughly half of all files come back 1 second off the
    # server's value and rclone's default size+mtime check re-downloads them
    # on every run - even files rclone itself just wrote. A real song/patch
    # update always changes the file's size, so size-only is both safe for
    # this content and immune to however the drive was populated.
    $script:SizeOnlyArgs = @('--size-only')

    $script:CommonArgs = @(
        '-P', '--transfers=4', '--checkers=8', '--stats=1s'
    ) + $script:SizeOnlyArgs + $script:RcloneConfigArgs

    # Args for the pre-download "what would change" scan: no progress meter,
    # verbose so every already-current file is named, dry-run so nothing moves.
    # Plain text output on purpose - Parse-DryRun reads the human "Skipped
    # copy as --dry-run is set" lines, which --use-json-log would restructure.
    $script:ScanArgs = @(
        '--transfers=4', '--checkers=8', '--dry-run', '-v'
    ) + $script:SizeOnlyArgs + $script:RcloneConfigArgs

    # Args for a real GUI download: JSON logs so the front-end can parse a
    # progress percentage / speed / ETA out of the periodic stats records
    # (see Read-RcloneStats). No -P: the interactive meter and clean logging
    # don't mix.
    $script:GuiSyncArgs = @(
        '-v', '--use-json-log', '--stats=1s', '--transfers=4', '--checkers=8'
    ) + $script:SizeOnlyArgs + $script:RcloneConfigArgs

    return [PSCustomObject]@{
        ScriptDir        = $ScriptDir
        Rclone           = $script:Rclone
        ConfigPath       = $script:ConfigPath
        RcloneConfigPath = $script:RcloneConfigPath
        LangDir          = $script:LangDir
        Conn             = $script:Conn
        RcloneConfigArgs = $script:RcloneConfigArgs
        SizeOnlyArgs     = $script:SizeOnlyArgs
        CommonArgs       = $script:CommonArgs
        ScanArgs         = $script:ScanArgs
        GuiSyncArgs      = $script:GuiSyncArgs
    }
}

# ----------------------------------------------------------------------------
# i18n
# ----------------------------------------------------------------------------

function Import-LangFile([string]$Code) {
    # Read lang\<Code>.json into a flat hashtable of key -> string. Returns an
    # empty hashtable if the file is missing or unreadable.
    $h = @{}
    if ([string]::IsNullOrWhiteSpace($script:LangDir)) { return $h }
    $path = Join-Path $script:LangDir ($Code + '.json')
    if (-not (Test-Path $path)) { return $h }
    try {
        $raw  = [System.IO.File]::ReadAllText($path, [System.Text.Encoding]::UTF8)
        $json = $raw | ConvertFrom-Json
        foreach ($p in $json.PSObject.Properties) { $h[$p.Name] = [string]$p.Value }
    } catch {
        return @{}
    }
    return $h
}

function Get-AvailableLanguages {
    # One entry per lang\*.json: Code / NativeName / Name (English name).
    $out = @()
    if ([string]::IsNullOrWhiteSpace($script:LangDir) -or -not (Test-Path $script:LangDir)) { return $out }
    $files = Get-ChildItem -Path $script:LangDir -Filter '*.json' -File -ErrorAction SilentlyContinue | Sort-Object Name
    foreach ($f in $files) {
        try {
            $json = ([System.IO.File]::ReadAllText($f.FullName, [System.Text.Encoding]::UTF8)) | ConvertFrom-Json
            $code   = if ($json.'_meta.code')       { [string]$json.'_meta.code' }       else { $f.BaseName }
            $native = if ($json.'_meta.nativeName') { [string]$json.'_meta.nativeName' } else { $code }
            $eng    = if ($json.'_meta.name')       { [string]$json.'_meta.name' }       else { $code }
            $out += [PSCustomObject]@{ Code = $code; NativeName = $native; Name = $eng }
        } catch { }
    }
    return $out
}

function Resolve-DefaultLanguage {
    # Best language code for this PC's UI culture, limited to what's actually
    # shipped in lang\. Falls back to 'en'.
    $avail = @(Get-AvailableLanguages | ForEach-Object { $_.Code })
    if ($avail.Count -eq 0) { return 'en' }
    try { $c = [System.Globalization.CultureInfo]::CurrentUICulture } catch { return 'en' }
    $name = $c.Name                       # e.g. ja-JP, zh-CN, pt-BR
    $two  = $c.TwoLetterISOLanguageName   # e.g. ja, zh, pt

    if ($two -eq 'zh') {
        if (($name -match 'Hant|TW|HK|MO') -and ($avail -contains 'zh-Hant')) { return 'zh-Hant' }
        if ($avail -contains 'zh-Hans') { return 'zh-Hans' }
        if ($avail -contains 'zh-Hant') { return 'zh-Hant' }
    }
    if ($avail -contains $name) { return $name }
    if ($avail -contains $two)  { return $two }
    return 'en'
}

function Initialize-Language {
    # Load English as the fallback layer, then the requested language on top.
    # An unknown or broken code silently falls back to English. Returns the
    # code that ended up active.
    param([string]$Code)

    $script:StringsFallback = Import-LangFile 'en'
    if ([string]::IsNullOrWhiteSpace($Code)) { $Code = 'en' }

    if ($Code -eq 'en') {
        $script:Strings  = $script:StringsFallback
        $script:LangCode = 'en'
        return $script:LangCode
    }

    $loaded = Import-LangFile $Code
    if ($loaded.Count -eq 0) {
        $script:Strings  = $script:StringsFallback
        $script:LangCode = 'en'
    } else {
        $script:Strings  = $loaded
        $script:LangCode = $Code
    }
    return $script:LangCode
}

function Get-LanguageCode { return $script:LangCode }

function T {
    # Translate a key. Missing keys fall back to English, then to the key
    # itself. {placeholder} tokens are filled from the optional -Vars hash.
    param(
        [Parameter(Mandatory = $true, Position = 0)][string]$Key,
        [Parameter(Position = 1)][hashtable]$Vars
    )
    $s = $null
    if ($script:Strings -and $script:Strings.ContainsKey($Key))               { $s = $script:Strings[$Key] }
    elseif ($script:StringsFallback -and $script:StringsFallback.ContainsKey($Key)) { $s = $script:StringsFallback[$Key] }
    if ($null -eq $s) { return $Key }

    # NB: $Vars.get_Count(), not $Vars.Count - a caller may pass a key literally
    # named "count" (or "keys"/"values"), which would shadow the .Count property
    # in member access and make an empty-check like "$Vars.Count -gt 0" wrong
    # whenever that value is 0.
    if ($null -ne $Vars -and $Vars.get_Count() -gt 0) {
        $s = [regex]::Replace($s, '\{([A-Za-z0-9_]+)\}', {
            param($m)
            $n = $m.Groups[1].Value
            if ($Vars.ContainsKey($n)) { return [string]$Vars[$n] }
            return $m.Value
        })
    }
    return $s
}

function Test-GameFolder([string]$Path) {
    if ([string]::IsNullOrWhiteSpace($Path)) { return $false }
    return (Test-Path (Join-Path $Path 'Legacy.exe'))
}

function Load-Config {
    if (-not (Test-Path $script:ConfigPath)) {
        Save-Config -GamePath '' -Editions 'AUTO' -Lang (Resolve-DefaultLanguage)
    }
    $gamePath = ''
    $editions = 'AUTO'
    $lang     = ''
    foreach ($line in Get-Content $script:ConfigPath) {
        $trimmed = $line.Trim()
        if ($trimmed -eq '' -or $trimmed.StartsWith('#')) { continue }
        $parts = $trimmed.Split('=', 2)
        if ($parts.Count -lt 2) { continue }
        $key = $parts[0].Trim().ToUpper()
        $value = $parts[1].Trim()
        if ($key -eq 'GAMEPATH') { $gamePath = $value }
        if ($key -eq 'EDITIONS') { $editions = $value }
        if ($key -eq 'LANG')     { $lang = $value }
    }
    if ([string]::IsNullOrWhiteSpace($editions)) { $editions = 'AUTO' }
    if ([string]::IsNullOrWhiteSpace($lang))     { $lang = 'en' }
    return [PSCustomObject]@{ GamePath = $gamePath; Editions = $editions; Lang = $lang }
}

function Save-Config([string]$GamePath, [string]$Editions, [string]$Lang) {
    # When no language is passed, keep whatever the file already has (so the
    # existing two-argument callers don't wipe the LANG line); default 'en'.
    if ([string]::IsNullOrWhiteSpace($Lang)) {
        $Lang = 'en'
        if (Test-Path $script:ConfigPath) {
            foreach ($line in Get-Content $script:ConfigPath) {
                if ($line.Trim() -match '^(?i:LANG)\s*=\s*(.+)$') { $Lang = $matches[1].Trim() }
            }
        }
    }
    @(
        "# Legacy Downloader - configuration"
        "# You normally don't need to edit this by hand - use the program's"
        "# menus (Change Game Path / Select Maps / Language) instead."
        ""
        "GAMEPATH=$GamePath"
        ""
        "# EDITIONS is either AUTO (every edition, including new ones as they"
        "# get added later) or a comma-separated list of specific edition"
        "# folder names, e.g. 2024,2,3"
        "EDITIONS=$Editions"
        ""
        "# LANG is the interface language - a file name (without .json) from"
        "# the lang folder, e.g. en, ja, fr, de, es, zh-Hans. Change it from"
        "# the Language menu."
        "LANG=$Lang"
    ) | Set-Content -Path $script:ConfigPath -Encoding UTF8
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

function Get-EditionTitle([string]$Edition) {
    if ([string]::IsNullOrWhiteSpace($Edition)) { return $null }
    $trimmed = $Edition.Trim()
    $num = 0
    if ([int]::TryParse($trimmed, [ref]$num)) {
        if ($num -eq 1) { return "Just Dance" }
        if ($num -ge 2 -and $num -le 4) { return "Just Dance $num" }
        if ($num -ge 2014 -and $num -le 2022) { return "Just Dance $num" }
        if ($num -ge 2023 -and $num -le 2026) { return "Just Dance $num Edition" }
        switch ($num) {
            2027 { return "Just Dance: Decades of Hits" }
            123  { return "Just Dance Kids" }
            1928 { return "Just Dance: Disney Party" }
            2009 { return "Michael Jackson: The Experience" }
            3112 { return "Just Dance Wii 2" }
            4118 { return "Just Dance Wii U" }
            4514 { return "Just Dance China" }
            4884 { return "ABBA: You Can Dance" }
        }
    }
    return $null
}

function Format-EditionDisplay([string]$Edition) {
    if ([string]::IsNullOrWhiteSpace($Edition)) { return '' }
    $title = Get-EditionTitle $Edition
    if ($title) {
        return $title
    }
    return "$Edition (check in-game songlist)"
}

function Get-RemoteEditions {
    $rc = $script:Rclone; $conn = $script:Conn; $cfgArgs = $script:RcloneConfigArgs
    $out = & $rc lsf "$conn`maps" --dirs-only @cfgArgs 2>$null
    return @($out | ForEach-Object { $_.TrimEnd('/') } | Where-Object { $_ -ne '' } | Sort-EditionNames)
}

function Get-RemoteSongs([string]$Edition) {
    $rc = $script:Rclone; $conn = $script:Conn; $cfgArgs = $script:RcloneConfigArgs
    $out = & $rc lsf "$conn`maps/$Edition" --files-only @cfgArgs 2>$null
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
        $proc = Start-Process -FilePath $script:Rclone -ArgumentList $argLine -NoNewWindow -Wait -PassThru `
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

# ----------------------------------------------------------------------------
# Update plan  (shared by the console preview and the GUI preview dialog)
# ----------------------------------------------------------------------------

function Get-UpdatePlan {
    # Work out exactly what a download would fetch, without fetching anything.
    # Pure: runs the same rclone commands as the real sync, but with --dry-run,
    # and returns a structured plan. No prompts, no Write-Host - the caller
    # renders it (console text or a GUI dialog) and decides what to do.
    #
    # If the game folder is set one level off, returns early with
    # .WrongLevel = $true and no scan; call again with -IgnoreWrongLevel to
    # scan anyway. On a network failure returns .Ok = $false / .NetFail = $true.
    param(
        [Parameter(Mandatory = $true)][string]$GamePath,
        [Parameter(Mandatory = $true)][string]$Editions,
        [switch]$IgnoreWrongLevel
    )

    $mapsDir     = [System.IO.Path]::Combine($GamePath, 'maps')
    $gamePresent = Test-GameFolder $GamePath
    $mapsMissing = -not (Test-Path $mapsDir)
    $betterPath  = Resolve-GameFolder $GamePath
    $wrongLevel  = [bool]($betterPath -and ($betterPath -ne $GamePath.TrimEnd('\')))

    $plan = [PSCustomObject]@{
        Ok            = $true
        NetFail       = $false
        WrongLevel    = $wrongLevel
        BetterPath    = $betterPath
        GamePresent   = $gamePresent
        MapsMissing   = $mapsMissing
        BaseNormal    = @()
        BaseAsk       = @()
        KeptSettings  = $false
        BaseBytes     = [long]0
        Songs         = @()
        SongFilesFlat = @()
        SongBytes     = [long]0
        TotalFiles    = 0
        TotalBytes    = [long]0
        LocalEditions = @(Get-LocalEditions $GamePath).Count
        LocalSongs    = (Get-LocalSongCount $GamePath)
    }

    if ($wrongLevel -and -not $IgnoreWrongLevel) { return $plan }

    # ---- base game ----
    $baseRun = Invoke-RcloneCapture (@('copy', "$script:Conn`LegacyPC - Game", $GamePath, '--exclude', 'maps/**') + $script:ScanArgs)
    if ($baseRun.ExitCode -ne 0) { $plan.Ok = $false; $plan.NetFail = $true; return $plan }
    $base = Parse-DryRun $baseRun.Lines

    # ---- songs ----
    $songFilesFlat = @()
    $songBytes     = [long]0
    $songs         = @()

    if ($Editions.ToUpper() -eq 'AUTO') {
        $mapRun = Invoke-RcloneCapture (@('copy', "$script:Conn`maps", $mapsDir) + $script:ScanArgs)
        if ($mapRun.ExitCode -ne 0) { $plan.Ok = $false; $plan.NetFail = $true; return $plan }
        $m = Parse-DryRun $mapRun.Lines
        $songBytes = $m.Bytes
        $byEd = [ordered]@{}
        foreach ($f in $m.Files) {
            $ed = ($f -split '[\\/]', 2)[0]
            if (-not $byEd.Contains($ed)) { $byEd[$ed] = @() }
            $byEd[$ed] += $f
            $songFilesFlat += $f
        }
        foreach ($k in ($byEd.Keys | Sort-EditionNames)) {
            $songs += [PSCustomObject]@{ Edition = [string]$k; Count = @($byEd[$k]).Count; Files = @($byEd[$k]) }
        }
    } else {
        $list = $Editions -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' }
        foreach ($ed in $list) {
            $r = Invoke-RcloneCapture (@('copy', "$script:Conn`maps/$ed", [System.IO.Path]::Combine($mapsDir, $ed)) + $script:ScanArgs)
            if ($r.ExitCode -ne 0) { $plan.Ok = $false; $plan.NetFail = $true; return $plan }
            $p = Parse-DryRun $r.Lines
            $songBytes += $p.Bytes
            $prefixed = @($p.Files | ForEach-Object { "$ed/$_" })
            $songFilesFlat += $prefixed
            # Only list an edition that actually has something to fetch - matches
            # the AUTO branch (which buckets from real files) and the original
            # preview, which never showed up-to-date editions.
            if ($prefixed.Count -gt 0) {
                $songs += [PSCustomObject]@{ Edition = [string]$ed; Count = $prefixed.Count; Files = $prefixed }
            }
        }
    }

    # ---- bucket the changed base files ----
    #   ask    - files a player might have modded (confirm before overwriting)
    #   normal - plain content (update silently)
    #   config.xml - local settings: keep whatever's on disk unless missing
    $askNames     = @('legacy.exe', 'kinect10.dll', 'kinect20.dll')
    $haveSettings = Test-Path ([System.IO.Path]::Combine($GamePath, 'config.xml'))
    $baseAsk = @(); $baseNormal = @()
    foreach ($f in $base.Files) {
        $leaf = (Split-Path -Leaf $f).ToLower()
        if ($leaf -eq 'config.xml') {
            if ($haveSettings) { $plan.KeptSettings = $true } else { $baseNormal += $f }
            continue
        }
        if ($askNames -contains $leaf) { $baseAsk += $f } else { $baseNormal += $f }
    }

    $plan.BaseNormal    = @($baseNormal)
    $plan.BaseAsk       = @($baseAsk)
    $plan.BaseBytes     = $base.Bytes
    $plan.Songs         = @($songs)
    $plan.SongFilesFlat = @($songFilesFlat)
    $plan.SongBytes     = $songBytes
    $plan.TotalFiles    = $baseNormal.Count + $baseAsk.Count + @($songFilesFlat).Count
    $plan.TotalBytes    = $base.Bytes + $songBytes
    return $plan
}

# ----------------------------------------------------------------------------
# Headless download primitive  (used by the GUI; the console keeps its own
# rclone runner that streams the -P meter straight to the terminal)
# ----------------------------------------------------------------------------

function Start-RcloneCopy {
    # Launch "rclone copy" WITHOUT waiting. Returns a job handle whose
    # ErrFile grows with JSON log records - poll it with Read-RcloneStats.
    param(
        [Parameter(Mandatory = $true)][string]$Source,
        [Parameter(Mandatory = $true)][string]$Dest,
        [string[]]$ExtraArgs = @(),
        [string]$Label = ''
    )
    $outFile = [System.IO.Path]::GetTempFileName()
    $errFile = [System.IO.Path]::GetTempFileName()
    $allArgs = @('copy', $Source, $Dest) + $script:GuiSyncArgs + $ExtraArgs
    $argLine = ($allArgs | ForEach-Object { ConvertTo-QuotedArg $_ }) -join ' '
    $proc = Start-Process -FilePath $script:Rclone -ArgumentList $argLine -NoNewWindow -PassThru `
                -RedirectStandardOutput $outFile -RedirectStandardError $errFile
    return [PSCustomObject]@{
        Label   = $Label
        Process = $proc
        OutFile = $outFile
        ErrFile = $errFile
    }
}

function Read-RcloneStats {
    # Progress snapshot from a Start-RcloneCopy job's ErrFile.
    # Returns stats object, plus an array of ALL objects (files) mentioned in the log records.
    param([Parameter(Mandatory = $true)]$Job)

    $lines = @()
    try {
        $fs = [System.IO.File]::Open($Job.ErrFile, 'Open', 'Read', 'ReadWrite')
        try {
            $sr = New-Object System.IO.StreamReader($fs)
            $text = $sr.ReadToEnd()
            $sr.Dispose()
        } finally { $fs.Dispose() }
        $lines = $text -split "`r?`n" | Where-Object { $_ -ne '' }
    } catch { return $null }
    if (-not $lines -or $lines.Count -eq 0) { return $null }

    $stats   = $null
    $objects = [System.Collections.Generic.List[string]]::new()
    foreach ($ln in $lines) {
        $o = $null
        try { $o = $ln | ConvertFrom-Json } catch { continue }
        if ($null -eq $o) { continue }
        if ($o.PSObject.Properties.Name -contains 'stats' -and $o.stats) {
            $stats = $o.stats
            if ($o.stats.transferring) {
                foreach ($t in $o.stats.transferring) {
                    if ($t.name -and -not $objects.Contains([string]$t.name)) { $objects.Add([string]$t.name) }
                }
            }
        } elseif ($o.PSObject.Properties.Name -contains 'object' -and $o.object) {
            $objStr = [string]$o.object
            if (-not $objects.Contains($objStr)) { $objects.Add($objStr) }
        }
    }
    if ($null -eq $stats) {
        if ($objects.Count -gt 0) {
            return [PSCustomObject]@{
                HasStats       = $false
                Bytes          = [long]0
                TotalBytes     = [long]0
                Percent        = 0
                Speed          = [double]0
                Eta            = $null
                Transfers      = 0
                TotalTransfers = 0
                Object         = if ($objects.Count -gt 0) { $objects[$objects.Count - 1] } else { '' }
                Objects        = @($objects)
            }
        }
        return $null
    }

    $pct = 0
    if ([double]$stats.totalBytes -gt 0) { $pct = [int](100.0 * [double]$stats.bytes / [double]$stats.totalBytes) }
    if ($pct -lt 0) { $pct = 0 } elseif ($pct -gt 100) { $pct = 100 }

    return [PSCustomObject]@{
        HasStats       = $true
        Bytes          = [long]$stats.bytes
        TotalBytes     = [long]$stats.totalBytes
        Percent        = $pct
        Speed          = [double]$stats.speed
        Eta            = $(if ($null -eq $stats.eta) { $null } else { [int]$stats.eta })
        Transfers      = [int]$stats.transfers
        TotalTransfers = [int]$stats.totalTransfers
        Object         = if ($objects.Count -gt 0) { $objects[$objects.Count - 1] } else { '' }
        Objects        = @($objects)
    }
}

function Complete-RcloneCopy {
    # Tidy up a finished job: return its exit code and delete the temp files.
    param([Parameter(Mandatory = $true)]$Job)
    $code = -1
    try { $code = [int]$Job.Process.ExitCode } catch { $code = -1 }
    Remove-Item -LiteralPath $Job.OutFile, $Job.ErrFile -Force -ErrorAction SilentlyContinue
    return $code
}

function Get-BaseSyncExcludes {
    # The --exclude list Invoke-BaseSync / a GUI base copy should use:
    # always skip maps/**, skip /config.xml when the user already has one,
    # plus any moddable files the user chose to keep.
    param([Parameter(Mandatory = $true)][string]$GamePath, [string[]]$KeepFiles = @())
    $ex = @('maps/**')
    if (Test-Path ([System.IO.Path]::Combine($GamePath, 'config.xml'))) { $ex += '/config.xml' }
    foreach ($f in $KeepFiles) { if ($f) { $ex += $f } }
    return $ex
}

Export-ModuleMember -Function `
    Initialize-LegacyCore, Test-GameFolder, Resolve-GameFolder, `
    Load-Config, Save-Config, Sort-EditionNames, Get-EditionTitle, Format-EditionDisplay, `
    Get-RemoteEditions, Get-RemoteSongs, Get-LocalEditions, Get-LocalSongCount, `
    ConvertTo-QuotedArg, Invoke-RcloneCapture, ConvertFrom-RcloneSize, `
    Format-Bytes, Parse-DryRun, Get-UpdatePlan, `
    Start-RcloneCopy, Read-RcloneStats, Complete-RcloneCopy, Get-BaseSyncExcludes, `
    Initialize-Language, T, Get-AvailableLanguages, Resolve-DefaultLanguage, Get-LanguageCode
