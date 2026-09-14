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
$script:ShareUrl         = $null

# The file share the tool downloads from, as an rclone WebDAV endpoint.
# This is the built-in default; a user can override it with a SHAREURL= line
# in config.txt (see Get-ShareConn / Save-Config) so the tool keeps working
# if the share ever moves and this repo is no longer maintained.
$script:DefaultShareUrl  = "https://cloud.ovosimpatico.com/public.php/dav/files/TqaYM8TnT2RPNr2/"

# Community-maintained song-name spreadsheet (title/artist/difficulty/effort
# per song, keyed by edition + internal codename). Fetched live every time
# the song browser opens - deliberately NOT bundled, so a new song added to
# the sheet shows up without a new release of this tool. See
# $script:SongCatalogCachePath for the on-disk fallback when the fetch fails.
$script:SongSheetUrl        = "https://docs.google.com/spreadsheets/d/1ufh7SAN0Q87UGFU2Yry8naX7hCjJ1q-XOjssqS3ULO4/export?format=csv&gid=28291419"
$script:SongCatalogCachePath = $null

$script:RcloneConfigArgs = @()
$script:SizeOnlyArgs     = @('--size-only')
$script:CommonArgs       = @()
$script:ScanArgs         = @()

# --- i18n state, filled in by Initialize-Language ---
$script:LangDir          = $null
$script:LangCode         = 'en'
$script:Strings          = @{}   # active language
$script:StringsFallback  = @{}   # English, always loaded as the fallback layer

function Get-ShareConn {
    # Build the rclone :webdav: connection string for a Nextcloud public
    # share link. For a Nextcloud public share the WebDAV username IS the
    # share token - the last path segment of the share's .../dav/files/<token>/
    # URL - so it's derived from the URL rather than configured separately.
    # An empty / blank / unusable URL falls back to the built-in default.
    param([string]$ShareUrl)

    $url = if ([string]::IsNullOrWhiteSpace($ShareUrl)) { $script:DefaultShareUrl } else { $ShareUrl.Trim() }
    if ($url -notmatch '/$') { $url += '/' }

    $token = ''
    $m = [regex]::Match($url, '/([^/]+)/\s*$')
    if ($m.Success) { $token = $m.Groups[1].Value }

    return ":webdav,url='$url',vendor='nextcloud',user='$token':"
}

function Initialize-LegacyCore {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$ScriptDir)

    $script:Rclone     = Join-Path $ScriptDir 'rclone.exe'
    $script:ConfigPath = Join-Path $ScriptDir 'config.txt'
    $script:LangDir    = Join-Path $ScriptDir 'lang'

    # Upgrading from a pre-V7 install: config.txt used to sit next to the
    # launcher, one level up from where bin\ (and this ScriptDir) now is.
    # Migrate it in place so an upgrading user's saved game folder / editions
    # / language aren't silently forgotten just because the file moved.
    # Best-effort: a locked/permission-denied source is skipped silently and
    # retried on the next launch (the source is only removed on success).
    $legacyConfigPath = Join-Path (Split-Path -Parent $ScriptDir) 'config.txt'
    if ((-not (Test-Path -LiteralPath $script:ConfigPath)) -and (Test-Path -LiteralPath $legacyConfigPath)) {
        try { Move-Item -LiteralPath $legacyConfigPath -Destination $script:ConfigPath -Force } catch { }
    }

    $script:SongCatalogCachePath = Join-Path $ScriptDir 'songcatalog.cache.json'

    $script:RcloneConfigPath = Join-Path $ScriptDir 'rclone.conf'
    if (-not (Test-Path -LiteralPath $script:RcloneConfigPath)) {
        New-Item -ItemType File -Path $script:RcloneConfigPath -Force | Out-Null
    }

    # Read the share URL straight from config.txt here (Load-Config, which
    # normally exposes it, runs later - and creates the file on first run).
    $script:ShareUrl = Read-ConfigValue 'SHAREURL'
    $script:Conn     = Get-ShareConn $script:ShareUrl

    $script:RcloneConfigArgs = @('--config', $script:RcloneConfigPath)

    # --size-only: compare files by SIZE ONLY and ignore modification time.
    # exFAT (what most external "play" drives use) rounds mtimes to a
    # 2-second grid, so roughly half of all files come back 1 second off the
    # server's value and rclone's default size+mtime check re-downloads them
    # on every run - even files rclone itself just wrote. A real song/patch
    # update always changes the file's size, so size-only is both safe for
    # this content and immune to however the drive was populated.
    $script:SizeOnlyArgs = @('--size-only')

    # --local-no-sparse: exFAT (the usual "play drive" filesystem) can't
    # honor rclone's Windows sparse-file pre-allocation for multi-thread
    # downloads (FSCTL_SET_SPARSE fails with "Incorrect function"). rclone
    # logs that as a scary-looking ERROR line but falls back and the file
    # still completes - this just stops it from trying in the first place.
    # Applied unconditionally (not just on exFAT): the cost on NTFS is at
    # most a little extra disk zero-fill instead of sparse pre-allocation,
    # which is far cheaper than detecting the filesystem type up front.
    $script:CommonArgs = @(
        '-P', '--transfers=4', '--checkers=8', '--stats=1s', '--local-no-sparse'
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
        '-v', '--use-json-log', '--stats=1s', '--transfers=4', '--checkers=8', '--local-no-sparse'
    ) + $script:SizeOnlyArgs + $script:RcloneConfigArgs

    return [PSCustomObject]@{
        ScriptDir        = $ScriptDir
        Rclone           = $script:Rclone
        ConfigPath       = $script:ConfigPath
        RcloneConfigPath = $script:RcloneConfigPath
        LangDir          = $script:LangDir
        Conn             = $script:Conn
        ShareUrl         = $script:ShareUrl
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
    if (-not (Test-Path -LiteralPath $path)) { return $h }
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
    if ([string]::IsNullOrWhiteSpace($script:LangDir) -or -not (Test-Path -LiteralPath $script:LangDir)) { return $out }
    $files = Get-ChildItem -LiteralPath $script:LangDir -Filter '*.json' -File -ErrorAction SilentlyContinue | Sort-Object Name
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

# Languages with a docs/tutorial/<code>.md file. Update this list whenever a
# new translation is added; anything not listed falls back to English.
$script:TutorialLangs = @('en', 'fr', 'es', 'de', 'it', 'pt', 'nl', 'ja', 'ko', 'zh-Hans', 'zh-Hant', 'ru')

function Get-TutorialUrl {
    param([string]$Code)
    $code = if ($script:TutorialLangs -contains $Code) { $Code } else { 'en' }
    return "https://github.com/VenB304/LegacyDownloader/blob/main/docs/tutorial/$code.md"
}

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
    # -LiteralPath: a folder path containing [ ] would otherwise be read as a
    # wildcard character class and Test-Path would report the exe as missing.
    return (Test-Path -LiteralPath (Join-Path $Path 'Legacy.exe'))
}

function Read-ConfigValue([string]$Key) {
    # First uncommented "<Key>=<value>" line from config.txt, trimmed; '' if none.
    if ([string]::IsNullOrWhiteSpace($script:ConfigPath) -or -not (Test-Path -LiteralPath $script:ConfigPath)) { return '' }
    $found = ''
    foreach ($line in Get-Content -LiteralPath $script:ConfigPath) {
        if ($line.Trim() -match ('^(?i:' + [regex]::Escape($Key) + ')\s*=\s*(.+)$')) { $found = $matches[1].Trim() }
    }
    return $found
}

function Load-Config {
    if (-not (Test-Path -LiteralPath $script:ConfigPath)) {
        Save-Config -GamePath '' -Editions 'AUTO' -Lang (Resolve-DefaultLanguage)
    }
    $gamePath = ''
    $editions = 'AUTO'
    $lang     = ''
    $shareUrl = ''
    $songFilters = ''
    foreach ($line in Get-Content -LiteralPath $script:ConfigPath) {
        $trimmed = $line.Trim()
        if ($trimmed -eq '' -or $trimmed.StartsWith('#')) { continue }
        $parts = $trimmed.Split('=', 2)
        if ($parts.Count -lt 2) { continue }
        $key = $parts[0].Trim().ToUpper()
        $value = $parts[1].Trim()
        if ($key -eq 'GAMEPATH')    { $gamePath = $value }
        if ($key -eq 'EDITIONS')    { $editions = $value }
        if ($key -eq 'LANG')        { $lang = $value }
        if ($key -eq 'SHAREURL')    { $shareUrl = $value }
        if ($key -eq 'SONGFILTERS') { $songFilters = $value }
    }
    if ([string]::IsNullOrWhiteSpace($editions)) { $editions = 'AUTO' }
    if ([string]::IsNullOrWhiteSpace($lang))     { $lang = 'en' }
    return [PSCustomObject]@{ GamePath = $gamePath; Editions = $editions; Lang = $lang; ShareUrl = $shareUrl; SongFilters = $songFilters }
}

function Save-Config([string]$GamePath, [string]$Editions, [string]$Lang, [string]$SongFilters) {
    # When no language is passed, keep whatever the file already has (so the
    # existing two-argument callers don't wipe the LANG line); default 'en'.
    if ([string]::IsNullOrWhiteSpace($Lang)) {
        $Lang = 'en'
        $existingLang = Read-ConfigValue 'LANG'
        if ($existingLang) { $Lang = $existingLang }
    }
    # SHAREURL is hand-edited only - never wipe an override the user added.
    $ShareUrl = Read-ConfigValue 'SHAREURL'
    # SONGFILTERS, like LANG, is only rewritten when a caller explicitly
    # passes it - an omitted argument preserves whatever's already saved
    # instead of silently clearing a user's per-song picks.
    $SongFiltersOut = if ($PSBoundParameters.ContainsKey('SongFilters')) { $SongFilters } else { Read-ConfigValue 'SONGFILTERS' }
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
        ""
        "# SHAREURL (advanced) - the rclone WebDAV link the tool downloads"
        "# from. Leave it commented out to use the built-in default. If the"
        "# share ever moves and no new build is available, paste the new"
        "# public WebDAV link here, e.g.:"
        "#   SHAREURL=https://cloud.example.com/public.php/dav/files/TOKEN/"
        $(if ($ShareUrl) { "SHAREURL=$ShareUrl" } else { "#SHAREURL=" })
        ""
        "# SONGFILTERS (set from the Search songs... screen) - only editions"
        "# with fewer than all their songs selected appear here, as"
        "# edition:code1|code2;edition2:code3. An edition with no entry here"
        "# means 'every song in it'."
        "SONGFILTERS=$SongFiltersOut"
    ) | Set-Content -LiteralPath $script:ConfigPath -Encoding UTF8
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
            1929 { return "Just Dance: Disney Party 2" }
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

# rclone writes NOTICE lines to stderr, and under the module's
# $ErrorActionPreference='Stop' a native command that touches stderr is
# promoted to a terminating error even with a 2>$null redirect (Windows
# PowerShell 5.1). These two helpers drop to SilentlyContinue for the call
# and swallow anything that still slips through - every caller already
# treats an empty result as "couldn't reach the share". (They can't route
# through Invoke-RcloneCapture: its Start-Process -Wait deadlocks when
# called straight from the GUI thread, which is why the plan scan runs in
# a child job.)
function Get-RemoteEditions {
    $rc = $script:Rclone; $conn = $script:Conn; $cfgArgs = $script:RcloneConfigArgs
    $ErrorActionPreference = 'SilentlyContinue'
    try { $out = & $rc lsf "$conn`maps" --dirs-only @cfgArgs 2>$null } catch { return @() }
    if ($LASTEXITCODE -ne 0) { return @() }
    return @($out | ForEach-Object { $_.TrimEnd('/') } | Where-Object { $_ -ne '' } | Sort-EditionNames)
}

function Get-RemoteSongs([string]$Edition) {
    $rc = $script:Rclone; $conn = $script:Conn; $cfgArgs = $script:RcloneConfigArgs
    $ErrorActionPreference = 'SilentlyContinue'
    try { $out = & $rc lsf "$conn`maps/$Edition" --files-only @cfgArgs 2>$null } catch { return @() }
    if ($LASTEXITCODE -ne 0) { return @() }
    return @($out | ForEach-Object { $_ -replace '_pc\.ipk$', '' } | Sort-Object)
}

function Get-RemoteSongMap {
    # Like calling Get-RemoteSongs once per edition and collecting the
    # results into a map, but as ONE rclone.exe spawn + ONE recursive
    # WebDAV listing instead of one of each PER EDITION (~24 of them,
    # sequentially, from the song picker's share-only-song scan) - each
    # spawn has real process-startup + fresh-connection overhead, and
    # profiling that scan showed the per-edition version taking many
    # seconds total. `lsf -R` walks the whole maps/ tree over one rclone
    # connection and returns paths already relative to it (e.g.
    # "2023/song_pc.ipk"), so grouping by the first path segment recovers
    # the same edition -> codes map for free.
    $rc = $script:Rclone; $conn = $script:Conn; $cfgArgs = $script:RcloneConfigArgs
    $ErrorActionPreference = 'SilentlyContinue'
    try { $out = & $rc lsf "$conn`maps" --files-only -R @cfgArgs 2>$null } catch { return @{} }
    if ($LASTEXITCODE -ne 0) { return @{} }
    $buckets = @{}
    foreach ($line in $out) {
        $slash = $line.IndexOf('/')
        if ($slash -lt 0) { continue }
        $ed = $line.Substring(0, $slash)
        $file = $line.Substring($slash + 1) -replace '_pc\.ipk$', ''
        if (-not $buckets.ContainsKey($ed)) { $buckets[$ed] = [System.Collections.Generic.List[string]]::new() }
        $buckets[$ed].Add($file)
    }
    $map = @{}
    foreach ($ed in $buckets.Keys) { $map[$ed] = @($buckets[$ed] | Sort-Object) }
    return $map
}

function Get-LocalEditions([string]$GamePath) {
    $mapsDir = Join-Path $GamePath 'maps'
    if (-not (Test-Path -LiteralPath $mapsDir)) { return @() }
    return @(Get-ChildItem -LiteralPath $mapsDir -Directory -ErrorAction SilentlyContinue | ForEach-Object { $_.Name } | Sort-EditionNames)
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
    if (-not (Test-Path -LiteralPath $mapsDir)) { return 0 }
    return @(Get-ChildItem -LiteralPath $mapsDir -Recurse -Filter '*.ipk' -File -ErrorAction SilentlyContinue).Count
}

# ----------------------------------------------------------------------------
# Per-song selection: SONGFILTERS parsing, the live song-name catalog, and
# the --include args that make a sync fetch only the chosen songs.
# ----------------------------------------------------------------------------

function Get-SongFilterMap([string]$Raw) {
    # "edition:code1|code2;edition2:code3" -> ordered edition -> @(codes).
    # An edition only appears here when fewer than all of its songs are
    # wanted; Get-EffectiveSongs returning $null (no entry) means "every song".
    $map = [ordered]@{}
    if ([string]::IsNullOrWhiteSpace($Raw)) { return $map }
    foreach ($part in ($Raw -split ';')) {
        $part = $part.Trim()
        if ($part -eq '') { continue }
        $idx = $part.IndexOf(':')
        if ($idx -lt 0) { continue }
        $ed = $part.Substring(0, $idx).Trim()
        $codes = @(($part.Substring($idx + 1) -split '\|') | ForEach-Object { $_.Trim().ToLowerInvariant() } | Where-Object { $_ -ne '' })
        if ($ed -ne '' -and $codes.Count -gt 0) { $map[$ed] = $codes }
    }
    return $map
}

function Format-SongFilters($Map) {
    if ($null -eq $Map -or $Map.Count -eq 0) { return '' }
    $parts = @()
    foreach ($ed in $Map.Keys) {
        $codes = @($Map[$ed])
        if ($codes.Count -eq 0) { continue }
        $parts += ("{0}:{1}" -f $ed, ($codes -join '|'))
    }
    return ($parts -join ';')
}

function Get-EffectiveSongs([string]$Edition, [string]$SongFiltersRaw) {
    # $null = every song in the edition; an array = only these codenames
    # (lowercase, no "_pc.ipk" suffix).
    $map = Get-SongFilterMap $SongFiltersRaw
    if ($map.Contains($Edition)) { return @($map[$Edition]) }
    return $null
}

function Get-SongIncludeArgs([string[]]$Codes) {
    # rclone --include args for a specific song subset ($null/empty = no
    # filter, i.e. every song - caller just omits these args in that case).
    # --ignore-case matters here: the sheet's codenames (and this tool's own
    # lowercased catalog) don't always match the real file's casing on the
    # share (e.g. the sheet's "firework" is actually "Firework_pc.ipk") -
    # confirmed against the live share while testing this feature.
    $out = @()
    foreach ($c in $Codes) {
        if ([string]::IsNullOrWhiteSpace($c)) { continue }
        $out += @('--include', "$($c.Trim().ToLowerInvariant())_pc.ipk")
    }
    if ($out.Count -gt 0) { $out += '--ignore-case' }
    return $out
}

function ConvertTo-RatingTier([string]$Raw) {
    # e.g. "2 - <tier name, accented>" -> 2. Blank/unparseable -> $null ("not rated").
    if ([string]::IsNullOrWhiteSpace($Raw)) { return $null }
    $m = [regex]::Match($Raw, '^\s*(\d+)')
    if (-not $m.Success) { return $null }
    return [int]$m.Groups[1].Value
}

function Format-DifficultyTier($Tier) {
    if ($null -eq $Tier -or [int]$Tier -lt 1 -or [int]$Tier -gt 4) { return (T 'songs.rating.unknown') }
    return (T "songs.difficulty.$Tier")
}

function Format-EffortTier($Tier) {
    if ($null -eq $Tier -or [int]$Tier -lt 0 -or [int]$Tier -gt 4) { return (T 'songs.rating.unknown') }
    return (T "songs.effort.$Tier")
}

function Get-SongCatalog {
    # Fetches the community song-name sheet fresh (title/artist/difficulty/
    # effort per edition+codename). Never throws: a failed fetch falls back
    # to the last successful fetch cached on disk, then to an empty list -
    # callers already have to handle "no metadata" (same convention as
    # Get-RemoteEditions/Get-RemoteSongs returning @() when unreachable).
    [CmdletBinding()]
    param()

    $records = $null
    $tmp = [System.IO.Path]::GetTempFileName()
    try {
        Invoke-WebRequest -Uri $script:SongSheetUrl -OutFile $tmp -UseBasicParsing -TimeoutSec 15 -ErrorAction Stop
        # Explicit UTF-8 decode of the downloaded bytes - Invoke-WebRequest's
        # own .Content string decoding guesses Latin-1 when the response (as
        # here) has no charset in its Content-Type header, which mangles the
        # sheet's accented song/tier text. Reading the saved file as UTF-8
        # (the same pattern Import-LangFile uses for lang\*.json) sidesteps
        # that guess entirely.
        $text = [System.IO.File]::ReadAllText($tmp, [System.Text.Encoding]::UTF8)
        # Explicit ASCII column names via -Header, skipping the sheet's own
        # header row (Select-Object -Skip 1): the real header row has
        # accented Portuguese column names ("Esforco", "Nome da musica", ...),
        # and this .psm1 file - like the rest of this codebase - avoids
        # embedding literal non-ASCII text in .ps1/.psm1 source (Windows
        # PowerShell 5.1 reads a BOM-less script via the system ANSI
        # codepage, which would silently mis-decode a literal accented
        # property-name string so it no longer matches the correctly-UTF8-
        # decoded runtime data).
        $rows = $text | ConvertFrom-Csv -Header 'Edition', 'Code', 'Title', 'Artist', 'DifficultyRaw', 'EffortRaw', 'CoverPhone' | Select-Object -Skip 1
        $parsed = foreach ($r in $rows) {
            $ed   = [string]$r.Edition
            $code = ([string]$r.Code).Trim().ToLowerInvariant()
            if ([string]::IsNullOrWhiteSpace($ed) -or [string]::IsNullOrWhiteSpace($code)) { continue }
            [PSCustomObject]@{
                Edition    = $ed
                Code       = $code
                Title      = [string]$r.Title
                Artist     = [string]$r.Artist
                Difficulty = ConvertTo-RatingTier ([string]$r.DifficultyRaw)
                Effort     = ConvertTo-RatingTier ([string]$r.EffortRaw)
            }
        }
        $records = @($parsed)
        if ($records.Count -gt 0 -and $script:SongCatalogCachePath) {
            try { $records | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $script:SongCatalogCachePath -Encoding UTF8 } catch { }
        }
    } catch {
        $records = $null
    } finally {
        Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
    }

    if ($null -eq $records -or $records.Count -eq 0) {
        $records = @()
        if ($script:SongCatalogCachePath -and (Test-Path -LiteralPath $script:SongCatalogCachePath)) {
            try {
                $cached = ([System.IO.File]::ReadAllText($script:SongCatalogCachePath, [System.Text.Encoding]::UTF8)) | ConvertFrom-Json
                $records = @($cached)
            } catch { $records = @() }
        }
    }
    return @($records)
}

function Get-CachedSongCatalog {
    # Display-only, no network: whatever Get-SongCatalog last wrote to disk,
    # or @() if the browser has never been opened yet. For places that want
    # to show friendly song names (the main window's tracking summary) but
    # can't justify a live fetch just to render a label.
    if (-not $script:SongCatalogCachePath -or -not (Test-Path -LiteralPath $script:SongCatalogCachePath)) { return @() }
    try {
        return @(([System.IO.File]::ReadAllText($script:SongCatalogCachePath, [System.Text.Encoding]::UTF8)) | ConvertFrom-Json)
    } catch {
        return @()
    }
}

function Get-SongDisplay($Record) {
    # Non-ASCII literals (the em dash here) are avoided in .ps1/.psm1 source
    # on purpose - see the [char]0x2713-style glyphs in the GUI file. Windows
    # PowerShell 5.1 reads a BOM-less script using the system ANSI codepage,
    # which mangles literal multi-byte UTF-8 characters embedded in source.
    if ($null -eq $Record) { return $null }
    $title  = [string]$Record.Title
    $artist = [string]$Record.Artist
    if ([string]::IsNullOrWhiteSpace($title)) { return $Record.Code }
    if ([string]::IsNullOrWhiteSpace($artist)) { return $title }
    return "$title $([char]0x2014) $artist"
}

function Get-DuplicateTitleKeys {
    # "edition|code" for every song whose Title collides (case-insensitive)
    # with another song in the SAME edition - real cases exist, e.g. JD2015's
    # "Bad Romance" (badromance) and its "badromancealt" variant show
    # identically otherwise. Callers append the codename to disambiguate only
    # these flagged rows, leaving every unambiguous title alone.
    param([Parameter(Mandatory = $true)]$Rows)
    # Only the COUNT per edition|title matters here (is it shared by more
    # than one row), not the actual list of codes - a plain int counter
    # avoids allocating a `New-Object System.Collections.Generic.List[string]`
    # per unique title (up to ~1000 of them on a full catalog), which
    # profiling found costing several hundred ms on its own (the same
    # New-Object-with-a-generic-type overhead documented elsewhere in this
    # file and in Gui.ps1's $refreshList).
    $countByKey = @{}
    foreach ($r in $Rows) {
        $t = ([string]$r.Title).Trim().ToLowerInvariant()
        if ($t -eq '') { continue }
        $k = "$($r.Edition)|$t"
        if ($countByKey.ContainsKey($k)) { $countByKey[$k]++ } else { $countByKey[$k] = 1 }
    }
    $dupes = [System.Collections.Generic.HashSet[string]]::new()
    foreach ($r in $Rows) {
        $t = ([string]$r.Title).Trim().ToLowerInvariant()
        if ($t -eq '') { continue }
        $k = "$($r.Edition)|$t"
        if ($countByKey[$k] -gt 1) { [void]$dupes.Add("$($r.Edition)|$($r.Code)") }
    }
    return $dupes
}

function Get-SongTitleForDisplay($Record, $DuplicateKeys) {
    # The record's Title, with " (code)" appended only when Get-
    # DuplicateTitleKeys flagged it as ambiguous within its edition.
    if ($null -eq $Record) { return $null }
    $title = if ([string]::IsNullOrWhiteSpace($Record.Title)) { $Record.Code } else { $Record.Title }
    if ($null -ne $DuplicateKeys -and $DuplicateKeys.Contains("$($Record.Edition)|$($Record.Code)")) {
        return "$title ($($Record.Code))"
    }
    return $title
}

function Initialize-SongSelectionContext {
    # Shared setup for both front-ends' song browser: builds the catalog
    # lookup tables and seeds the checked-song set from current config. An
    # edition with no SONGFILTERS entry means "every song in it"; AUTO means
    # "every song of every edition the catalog covers" (an edition the
    # catalog doesn't know about at all can't be represented here - see
    # Resolve-SongSelection for how that's carried through untouched).
    param(
        [Parameter(Mandatory = $true)]$Catalog,
        [Parameter(Mandatory = $true)][string]$CurrentEditions,
        [string]$CurrentSongFilters = ''
    )
    $rows = @($Catalog | Sort-Object Edition, Title)
    $duplicateKeys = Get-DuplicateTitleKeys -Rows $rows
    $byEdition = @{}
    foreach ($r in $rows) {
        if (-not $byEdition.ContainsKey($r.Edition)) { $byEdition[$r.Edition] = New-Object System.Collections.Generic.List[string] }
        $byEdition[$r.Edition].Add($r.Code)
    }
    $catalogEditions = @($byEdition.Keys | Sort-EditionNames)
    $wasAuto = ($CurrentEditions.ToUpper() -eq 'AUTO')
    $trackedList = if ($wasAuto) { @() } else { @($CurrentEditions -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' }) }
    $filterMap = Get-SongFilterMap $CurrentSongFilters
    $selectedKeys = New-Object System.Collections.Generic.HashSet[string]
    foreach ($ed in $catalogEditions) {
        $isTracked = $wasAuto -or ($trackedList -contains $ed)
        if (-not $isTracked) { continue }
        if ($filterMap.Contains($ed)) {
            foreach ($code in $filterMap[$ed]) { [void]$selectedKeys.Add("$ed|$code") }
        } else {
            foreach ($code in $byEdition[$ed]) { [void]$selectedKeys.Add("$ed|$code") }
        }
    }
    return [PSCustomObject]@{
        Rows            = $rows
        ByEdition       = $byEdition
        CatalogEditions = $catalogEditions
        TrackedList     = $trackedList
        FilterMap       = $filterMap
        SelectedKeys    = $selectedKeys
        DuplicateKeys   = $duplicateKeys
    }
}

function Resolve-SongSelection {
    # Turns a (possibly edited) checked-keys set back into @{ Editions;
    # SongFilters }, or $null if nothing ended up selected. "edition|code"
    # keys are used throughout so one HashSet covers every edition at once.
    param(
        [Parameter(Mandatory = $true)]$Context,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][System.Collections.Generic.HashSet[string]]$SelectedKeys
    )
    $resultMap = [ordered]@{}
    foreach ($ed in $Context.TrackedList) {
        if (-not ($Context.CatalogEditions -contains $ed)) {
            $resultMap[$ed] = if ($Context.FilterMap.Contains($ed)) { @($Context.FilterMap[$ed]) } else { 'ALL' }
        }
    }
    foreach ($ed in $Context.CatalogEditions) {
        $allCodes = @($Context.ByEdition[$ed])
        $checkedCodes = @($allCodes | Where-Object { $SelectedKeys.Contains("$ed|$_") })
        if ($checkedCodes.Count -eq 0) { continue }
        $resultMap[$ed] = if ($checkedCodes.Count -eq $allCodes.Count) { 'ALL' } else { $checkedCodes }
    }
    if ($resultMap.Count -eq 0) { return $null }
    $finalEditions = @($resultMap.Keys | Sort-EditionNames)
    $finalFilterMap = [ordered]@{}
    foreach ($ed in $finalEditions) { if ($resultMap[$ed] -ne 'ALL') { $finalFilterMap[$ed] = $resultMap[$ed] } }
    return @{ Editions = ($finalEditions -join ','); SongFilters = (Format-SongFilters $finalFilterMap) }
}

function Get-SongRemovalPlan {
    # Compares old vs new tracking state and returns one entry per edition
    # that lost something a user might have local files for: dropped
    # entirely (WholeEditionRemoved, RemovedCodes = $null - delete the whole
    # maps\<edition> folder, matching the tool's older "unchecked an edition"
    # behavior) or narrowed to fewer songs (RemovedCodes = the codes that
    # fell out, for a per-file delete). An edition the catalog doesn't cover
    # can only ever be dropped entirely, never narrowed - Resolve-SongSelection
    # never assigns such an edition a filter, so there is nothing to compute
    # per-song for it.
    param(
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][string[]]$OldEditions,
        [string]$OldSongFilters = '',
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][string[]]$NewEditions,
        [string]$NewSongFilters = '',
        [Parameter(Mandatory = $true)]$Catalog
    )
    $byEdition = @{}
    foreach ($r in $Catalog) {
        if (-not $byEdition.ContainsKey($r.Edition)) { $byEdition[$r.Edition] = New-Object System.Collections.Generic.List[string] }
        $byEdition[$r.Edition].Add($r.Code)
    }
    $oldFilterMap = Get-SongFilterMap $OldSongFilters
    $newFilterMap = Get-SongFilterMap $NewSongFilters

    $plan = @()
    foreach ($ed in @($OldEditions | Select-Object -Unique)) {
        $stillTracked = $NewEditions -contains $ed
        if ($stillTracked -and -not $oldFilterMap.Contains($ed) -and -not $newFilterMap.Contains($ed)) { continue }

        if (-not $byEdition.ContainsKey($ed)) {
            if (-not $stillTracked) { $plan += [PSCustomObject]@{ Edition = $ed; RemovedCodes = $null; WholeEditionRemoved = $true } }
            continue
        }

        $oldCodes = if ($oldFilterMap.Contains($ed)) { @($oldFilterMap[$ed]) } else { @($byEdition[$ed]) }
        $newCodes = if (-not $stillTracked) { @() } elseif ($newFilterMap.Contains($ed)) { @($newFilterMap[$ed]) } else { @($byEdition[$ed]) }
        $removedCodes = @($oldCodes | Where-Object { $newCodes -notcontains $_ })
        if ($removedCodes.Count -gt 0) {
            $plan += [PSCustomObject]@{ Edition = $ed; RemovedCodes = $removedCodes; WholeEditionRemoved = (-not $stillTracked) }
        }
    }
    return $plan
}

function Get-SongDisplayMap {
    # code -> display label for one edition's songs, built from whatever the
    # catalog knows (falls back to the raw code for anything the sheet
    # doesn't have). Duplicate labels within the set (real cases exist - e.g.
    # JD2014's justdance/justdanceosc/justdanceswtdlc all show as "Just Dance
    # - Lady Gaga...") get the codename appended so every entry stays unique.
    param(
        [Parameter(Mandatory = $true)][string]$Edition,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][string[]]$Codes,
        [Parameter(Mandatory = $true)]$Catalog
    )
    $byCode = @{}
    foreach ($rec in $Catalog) {
        if ($rec.Edition -eq $Edition) { $byCode[$rec.Code] = $rec }
    }
    $labels = [ordered]@{}
    foreach ($code in $Codes) {
        $lc = $code.ToLowerInvariant()
        $labels[$code] = if ($byCode.ContainsKey($lc)) { Get-SongDisplay $byCode[$lc] } else { $code }
    }
    $counts = @{}
    foreach ($v in $labels.Values) { $counts[$v] = 1 + ($(if ($counts.ContainsKey($v)) { $counts[$v] } else { 0 })) }
    $out = [ordered]@{}
    foreach ($code in $labels.Keys) {
        $v = $labels[$code]
        $out[$code] = if ($counts[$v] -gt 1) { "$v [$code]" } else { $v }
    }
    return $out
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
        [string]$SongFilters = '',
        [switch]$IgnoreWrongLevel
    )

    $mapsDir     = [System.IO.Path]::Combine($GamePath, 'maps')
    $gamePresent = Test-GameFolder $GamePath
    $mapsMissing = -not (Test-Path -LiteralPath $mapsDir)
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
            # Every song lives at "<edition>/<file>". A path with no separator
            # is a stray file at maps/ root or a mis-parsed log line - it must
            # not become a phantom edition (the whole maps tree still syncs in
            # the AUTO download job regardless). $ed is also skipped if it
            # doesn't look like an edition folder name.
            if ($f -notmatch '[\\/]') { continue }
            $ed = ($f -split '[\\/]', 2)[0]
            if ([string]::IsNullOrWhiteSpace($ed) -or $ed -notmatch '^[\w.\- ]+$') { continue }
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
            $includeArgs = Get-SongIncludeArgs (Get-EffectiveSongs $ed $SongFilters)
            $r = Invoke-RcloneCapture (@('copy', "$script:Conn`maps/$ed", [System.IO.Path]::Combine($mapsDir, $ed)) + $includeArgs + $script:ScanArgs)
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
    # "Moddable" = Legacy.exe or any Kinect*.dll (a patched exe or a swapped
    # Kinect shim - the exact name of which varies - must survive an update).
    $haveSettings = Test-Path -LiteralPath ([System.IO.Path]::Combine($GamePath, 'config.xml'))
    $baseAsk = @(); $baseNormal = @()
    foreach ($f in $base.Files) {
        $leaf = (Split-Path -Leaf $f).ToLower()
        if ($leaf -eq 'config.xml') {
            if ($haveSettings) { $plan.KeptSettings = $true } else { $baseNormal += $f }
            continue
        }
        # A protected file only counts as "moddable, ask before overwriting" when
        # the user actually has a local copy. On a first install / empty folder
        # every base file "would copy", including legacy.exe and the Kinect DLLs -
        # those are just the initial download, not a modified copy to protect.
        if (($leaf -eq 'legacy.exe') -or ($leaf -like 'kinect*.dll')) {
            $localCopy = [System.IO.Path]::Combine($GamePath, ($f -replace '/', '\'))
            if (Test-Path -LiteralPath $localCopy) { $baseAsk += $f } else { $baseNormal += $f }
        } else {
            $baseNormal += $f
        }
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
    if (Test-Path -LiteralPath ([System.IO.Path]::Combine($GamePath, 'config.xml'))) { $ex += '/config.xml' }
    foreach ($f in $KeepFiles) { if ($f) { $ex += $f } }
    return $ex
}

Export-ModuleMember -Function `
    Initialize-LegacyCore, Test-GameFolder, Resolve-GameFolder, `
    Load-Config, Save-Config, Sort-EditionNames, Get-EditionTitle, Format-EditionDisplay, `
    Get-RemoteEditions, Get-RemoteSongs, Get-RemoteSongMap, Get-LocalEditions, Get-LocalSongCount, `
    ConvertTo-QuotedArg, Invoke-RcloneCapture, ConvertFrom-RcloneSize, `
    Format-Bytes, Parse-DryRun, Get-UpdatePlan, `
    Start-RcloneCopy, Read-RcloneStats, Complete-RcloneCopy, Get-BaseSyncExcludes, `
    Initialize-Language, T, Get-AvailableLanguages, Resolve-DefaultLanguage, Get-LanguageCode, Get-TutorialUrl, `
    Get-SongFilterMap, Format-SongFilters, Get-EffectiveSongs, Get-SongIncludeArgs, `
    Get-SongCatalog, Get-CachedSongCatalog, Get-SongDisplay, Get-SongDisplayMap, Format-DifficultyTier, Format-EffortTier, `
    Initialize-SongSelectionContext, Resolve-SongSelection, Get-SongRemovalPlan, `
    Get-DuplicateTitleKeys, Get-SongTitleForDisplay
