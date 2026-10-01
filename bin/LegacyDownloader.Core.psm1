# LegacyDownloader.Core.psm1
# Shared engine for the Legacy Downloader console and GUI front-ends.
#
# Pure logic only: no Write-Host, no Read-Host, no menu code. A front-end
# calls Initialize-LegacyCore once (passing the folder the tool lives in),
# then uses these helpers. Everything the front-ends need to know about
# rclone paths / connection strings / argument sets comes back from
# Initialize-LegacyCore as an object.

$ErrorActionPreference = 'Stop'

# Single source of truth for the version shown in the GUI title bar and the
# console header, and used by tools\build-release.ps1 to name the release
# zip - bump this one line for a new release, nowhere else.
$script:AppVersion = 'V11.3'

function Get-AppVersion { return $script:AppVersion }

# The public GitHub repo this tool ships releases from. The update check asks
# the plain WEB site which release is latest (github.com/<repo>/releases/latest
# redirects to .../releases/tag/<tag>) and only falls back to the REST API:
# the API allows just 60 unauthenticated requests per hour PER IP ADDRESS, and
# people on shared addresses (VPN, Cloudflare WARP, carrier-grade NAT - common
# where Discord is blocked) exhaust that instantly, so V10/V11's API-only check
# failed for them with "(403) Forbidden". The web route isn't subject to it.
$script:UpdateRepoWebUrl = 'https://github.com/VenB304/LegacyDownloader'
$script:UpdateRepoApiUrl = 'https://api.github.com/repos/VenB304/LegacyDownloader/releases/latest'

function Compare-AppVersions([string]$A, [string]$B) {
    # Numeric-tuple comparison, not a string compare. 'V9.3' vs 'v10'
    # breaks under a naive lexicographic/string comparison - '9' sorts
    # after '1' character-by-character, so '9.3' would wrongly compare as
    # "greater than" '10'. Strips a leading v/V from each side, splits on
    # '.', compares each segment as [int] (a missing trailing segment on
    # the shorter side counts as 0, so 'v10' == 'v10.0'). Returns -1/0/1.
    $pa = ($A -replace '^[vV]', '') -split '\.'
    $pb = ($B -replace '^[vV]', '') -split '\.'
    $n = [Math]::Max($pa.Count, $pb.Count)
    for ($i = 0; $i -lt $n; $i++) {
        $na = 0; $nb = 0
        if ($i -lt $pa.Count) { [void][int]::TryParse($pa[$i], [ref]$na) }
        if ($i -lt $pb.Count) { [void][int]::TryParse($pb[$i], [ref]$nb) }
        if ($na -ne $nb) { return [Math]::Sign($na - $nb) }
    }
    return 0
}

function Get-RedirectTarget([string]$Url) {
    # HEAD without following redirects. Returns @{ Status; Location } for ANY
    # HTTP answer (a 4xx/5xx comes back as a status, not an exception); throws
    # only when there is no HTTP answer at all (offline, DNS, TLS, timeout).
    $req = [System.Net.HttpWebRequest]::Create($Url)
    $req.Method = 'HEAD'
    $req.AllowAutoRedirect = $false
    $req.Timeout = 10000
    $req.UserAgent = 'LegacyDownloader (+https://github.com/VenB304/LegacyDownloader)'
    $resp = $null
    try {
        try { $resp = $req.GetResponse() }
        catch [System.Net.WebException] {
            if ($null -eq $_.Exception.Response) { throw }
            $resp = $_.Exception.Response
        }
        return @{ Status = [int]$resp.StatusCode; Location = [string]$resp.Headers['Location'] }
    } finally { if ($null -ne $resp) { $resp.Close() } }
}

function Get-ReleaseApiResponse {
    # The REST API call, on its own so the fallback route can be exercised in tests.
    return Invoke-RestMethod -Uri $script:UpdateRepoApiUrl -Headers @{ 'User-Agent' = 'LegacyDownloader' } -TimeoutSec 10 -ErrorAction Stop
}

function Get-LatestReleaseInfo {
    # Fails soft - returns Ok=$false on any network/parse error, never throws.
    # Two routes, web first (see $script:UpdateRepoWebUrl for why):
    #  1. github.com/<repo>/releases/latest redirects to .../releases/tag/<tag>;
    #     the zip is named LegacyDownloader<Version>.zip by tools\build-release.ps1,
    #     and a HEAD on its download URL confirms it exists under that name.
    #  2. The REST API (exact asset list) if the web route can't answer.
    $out = @{ Ok = $false; Tag = ''; Version = ''; DownloadUrl = ''; ZipName = ''; ReleaseUrl = ''; ErrMsg = '' }
    try {
        $r = Get-RedirectTarget "$script:UpdateRepoWebUrl/releases/latest"
        if ($r.Status -ge 300 -and $r.Status -lt 400 -and $r.Location -match '/releases/tag/([^/?#]+)$') {
            $tag = [System.Uri]::UnescapeDataString($Matches[1])
            if ($tag -match '^[A-Za-z0-9._\-]+$') {
                $version = 'V' + ($tag -replace '^[vV]', '')
                $zipName = "LegacyDownloader$version.zip"
                $downloadUrl = "$script:UpdateRepoWebUrl/releases/download/$tag/$zipName"
                $a = Get-RedirectTarget $downloadUrl
                if ($a.Status -ge 300 -and $a.Status -lt 400) {
                    $out.Ok = $true; $out.Tag = $tag; $out.Version = $version
                    $out.DownloadUrl = $downloadUrl; $out.ZipName = $zipName
                    $out.ReleaseUrl = "$script:UpdateRepoWebUrl/releases/tag/$tag"
                    return [PSCustomObject]$out
                }
            }
        }
    } catch { }
    try {
        $resp = Get-ReleaseApiResponse
        $asset = @($resp.assets | Where-Object { $_.name -like 'LegacyDownloader*.zip' }) | Select-Object -First 1
        if (-not $asset) { $out.ErrMsg = 'release has no LegacyDownloader*.zip asset'; return [PSCustomObject]$out }
        $out.Ok = $true
        $out.Tag = [string]$resp.tag_name
        $out.Version = 'V' + ($resp.tag_name -replace '^[vV]', '')
        $out.DownloadUrl = [string]$asset.browser_download_url
        $out.ZipName = [string]$asset.name
        $out.ReleaseUrl = [string]$resp.html_url
    } catch {
        $out.ErrMsg = $_.Exception.Message
        if ($out.ErrMsg -match '\((403|429)\)') {
            $out.ErrMsg = "GitHub is limiting requests from your network right now (HTTP $($Matches[1]) - common on shared VPN / Cloudflare WARP addresses). Try again later, or download the new version from the Releases page."
        }
    }
    return [PSCustomObject]$out
}

function Test-AppUpdateAvailable {
    # Checked=$false means the check itself failed (network/parse) -
    # deliberately distinct from Available=$false (checked fine, already
    # current), so a caller can stay silent on a failed check (same
    # graceful-offline posture as AUTOCHECK's rclone check) instead of
    # showing an error for what's usually just no internet.
    $current = Get-AppVersion
    $info = Get-LatestReleaseInfo
    if (-not $info.Ok) {
        return [PSCustomObject]@{
            Available = $false; Checked = $false; CurrentVersion = $current
            LatestVersion = ''; DownloadUrl = ''; ZipName = ''; ReleaseUrl = ''; ErrMsg = $info.ErrMsg
        }
    }
    $newer = (Compare-AppVersions $info.Version $current) -gt 0
    return [PSCustomObject]@{
        Available = $newer; Checked = $true; CurrentVersion = $current
        LatestVersion = $info.Version; DownloadUrl = $info.DownloadUrl; ZipName = $info.ZipName
        ReleaseUrl = $info.ReleaseUrl; ErrMsg = ''
    }
}

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
#
# Uses the gviz query endpoint, not the more obvious .../export?format=csv
# link: the export endpoint is meant for occasional interactive/manual
# export and Google's anti-abuse system started returning it as an HTML
# bot-challenge page (HTTP 400) for this tool's traffic pattern (confirmed
# 2026-09-15 - reachable, redirects fine, then blocked specifically at the
# export step; two independent HTTP clients hit the identical response).
# gviz is meant for exactly this kind of live programmatic embedding
# (charts/dashboards querying a sheet) and was NOT blocked from the same
# network at the same time. We don't have edit access to the sheet to also
# set up a "Publish to web" CDN link (the more bulletproof option, per
# Google) - only the community sheet's own maintainer does.
$script:SongSheetUrl        = "https://docs.google.com/spreadsheets/d/1ufh7SAN0Q87UGFU2Yry8naX7hCjJ1q-XOjssqS3ULO4/gviz/tq?tqx=out:json&gid=28291419"
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

    # Accept the friendlier public-share link Nextcloud's own UI actually
    # hands users (https://host/s/TOKEN) - not just the raw WebDAV path the
    # SHAREURL comment always documented - and rewrite it to the WebDAV form
    # this connection string needs. Anything that doesn't match this shape
    # (already WebDAV-style, or something else entirely) passes through
    # unchanged, so the existing hand-edit power-user path still works.
    $shareLink = [regex]::Match($url, '^(https?://[^/]+)/s/([^/?#]+)/?\s*$')
    if ($shareLink.Success) {
        $url = "$($shareLink.Groups[1].Value)/public.php/dav/files/$($shareLink.Groups[2].Value)/"
    }

    if ($url -notmatch '/$') { $url += '/' }

    $token = ''
    $m = [regex]::Match($url, '/([^/]+)/\s*$')
    if ($m.Success) { $token = $m.Groups[1].Value }

    return ":webdav,url='$url',vendor='nextcloud',user='$token':"
}

function Initialize-LegacyCore {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$ScriptDir)

    $script:AppDir = $ScriptDir

    # Windows PowerShell 5.1's .NET Framework doesn't always default
    # ServicePointManager to TLS 1.2 (depends on the machine's .NET/OS
    # patch level - an older/locked-down Windows install can still default
    # to TLS 1.0, which GitHub has rejected since 2018). Set explicitly
    # rather than rely on the machine's default: this covers every
    # Invoke-RestMethod/Invoke-WebRequest/HttpWebRequest call the app makes
    # (Get-LatestReleaseInfo's GitHub API check, Invoke-AppUpdateDownload-
    # AndStage's release download, the requirements checker's own
    # HttpWebRequest downloads), since they all read the same process-wide
    # setting. -bor preserves whatever protocols were already enabled
    # rather than replacing them outright.
    if (-not $IsLinux) {
        try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 } catch { }
    }

    if ($IsLinux) {
        $cmd = Get-Command rclone -ErrorAction SilentlyContinue
        $script:Rclone = if ($cmd) { $cmd.Source } else { 'rclone' }
    } else {
        $script:Rclone = Join-Path $ScriptDir 'rclone.exe'
    }
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

    # BWLIMIT, same early-read story as SHAREURL. Blank/'0' means unlimited -
    # never pass --bwlimit=0 to rclone, which means "block all transfer", not
    # "no limit". Baked into CommonArgs/GuiSyncArgs below once here, same as
    # SHAREURL is baked into $script:Conn - a change made from the Settings
    # window takes effect the next time the tool starts, not immediately.
    #
    # --multi-thread-streams=0 is bundled in alongside --bwlimit, and ONLY
    # when a real limit is set: live-tested (2026-09-22) against the actual
    # base-game files, --bwlimit alone does NOT cap a file at/above rclone's
    # multi-thread-cutoff (default 250MiB - bundle_pc.ipk is ~900MB,
    # patch_pc.ipk ~277MB, both routinely hit by a base-game sync) - a real
    # --bwlimit=1M copy of patch_pc.ipk measured ~17 MiB/s, completely
    # unthrottled, while the exact same copy with --multi-thread-streams=0
    # added measured ~0.8 MiB/s, right at the configured cap. Root cause:
    # rclone's multi-thread chunked-download mode doesn't respect the global
    # limiter the same way a normal single-stream transfer does. Scoped to
    # only fire when BWLIMIT is actually set (not the unlimited/default
    # case) - forcing single-stream unconditionally would cost real transfer
    # speed on a fast connection for no reason when there's no cap to honor.
    $bwLimit = Read-ConfigValue 'BWLIMIT'
    # A zero value means "unlimited" regardless of unit suffix - '0M'/'0K'/
    # '0G' all mean zero bytes/s to rclone (block everything) just as much
    # as bare '0' does. The Settings window's own Save validation now
    # rejects a zero-with-suffix input too, but this still needs the same
    # check independently since config.txt can be hand-edited straight
    # past that GUI validation entirely.
    $bwLimitArgs = if ([string]::IsNullOrWhiteSpace($bwLimit) -or $bwLimit -match '^0+[KkMmGg]?$') { @() } else { @("--bwlimit=$bwLimit", '--multi-thread-streams=0') }

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
    ) + $script:SizeOnlyArgs + $script:RcloneConfigArgs + $bwLimitArgs

    # Args for the pre-download "what would change" scan: no progress meter,
    # verbose so every already-current file is named, dry-run so nothing moves.
    # Plain text output on purpose - Parse-DryRun reads the human "Skipped
    # copy as --dry-run is set" lines, which --use-json-log would restructure.
    # No --bwlimit here on purpose - a --dry-run scan never transfers a
    # single byte, so a bandwidth cap has nothing to apply to.
    $script:ScanArgs = @(
        '--transfers=4', '--checkers=8', '--dry-run', '-v'
    ) + $script:SizeOnlyArgs + $script:RcloneConfigArgs

    # Args for a real GUI download: JSON logs so the front-end can parse a
    # progress percentage / speed / ETA out of the periodic stats records
    # (see Read-RcloneStats). No -P: the interactive meter and clean logging
    # don't mix.
    $script:GuiSyncArgs = @(
        '-v', '--use-json-log', '--stats=1s', '--transfers=4', '--checkers=8', '--local-no-sparse'
    ) + $script:SizeOnlyArgs + $script:RcloneConfigArgs + $bwLimitArgs

    return [PSCustomObject]@{
        ScriptDir        = $ScriptDir
        Version          = $script:AppVersion
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
$script:TutorialLangs = @('en', 'fr', 'es', 'fil', 'de', 'it', 'pt', 'nl', 'ja', 'ko', 'zh-Hans', 'zh-Hant', 'ru')

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
        Save-Config @{ GamePath = ''; Editions = 'AUTO'; Lang = (Resolve-DefaultLanguage) }
    }
    $gamePath = ''
    $editions = 'AUTO'
    $lang     = ''
    $shareUrl = ''
    $songFilters = ''
    $keepSongs = ''
    $autoLaunch = $false
    $autoCheck = $false
    $bwLimit = ''
    $checkAppUpdates = $true
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
        if ($key -eq 'KEEPSONGS')   { $keepSongs = $value }
        if ($key -eq 'AUTOLAUNCH')  { $autoLaunch = ($value -eq 'true') }
        if ($key -eq 'AUTOCHECK')   { $autoCheck = ($value -eq 'true') }
        if ($key -eq 'BWLIMIT')     { $bwLimit = $value }
        if ($key -eq 'CHECKAPPUPDATES') { $checkAppUpdates = ($value -eq 'true') }
    }
    if ([string]::IsNullOrWhiteSpace($editions)) { $editions = 'AUTO' }
    if ([string]::IsNullOrWhiteSpace($lang))     { $lang = 'en' }
    return [PSCustomObject]@{
        GamePath = $gamePath; Editions = $editions; Lang = $lang; ShareUrl = $shareUrl
        SongFilters = $songFilters; KeepSongs = $keepSongs; AutoLaunch = $autoLaunch; AutoCheck = $autoCheck; BwLimit = $bwLimit
        CheckAppUpdates = $checkAppUpdates
    }
}

function Save-Config([hashtable]$Values = @{}) {
    # Merges $Values (only the keys actually being changed) over whatever's
    # currently on disk - one preserve-unless-specified rule instead of a
    # pile of per-key special cases (the old positional-parameter version
    # needed a separate ContainsKey/Read-ConfigValue trick for every value
    # added after GamePath/Editions). Recognized keys: GamePath, Editions,
    # Lang, ShareUrl, SongFilters, KeepSongs, AutoLaunch, AutoCheck, BwLimit,
    # CheckAppUpdates.
    $current = if (Test-Path -LiteralPath $script:ConfigPath) { Load-Config } else { $null }
    function Resolve-Field([string]$Key, $Default) {
        if ($Values.ContainsKey($Key)) { return $Values[$Key] }
        if ($null -ne $current) { return $current.$Key }
        return $Default
    }
    $GamePath    = Resolve-Field 'GamePath' ''
    $Editions    = Resolve-Field 'Editions' 'AUTO'
    $Lang        = Resolve-Field 'Lang' 'en'
    $ShareUrl    = Resolve-Field 'ShareUrl' ''
    $SongFilters = Resolve-Field 'SongFilters' ''
    $KeepSongs   = Resolve-Field 'KeepSongs' ''
    $AutoLaunch  = Resolve-Field 'AutoLaunch' $false
    $AutoCheck   = Resolve-Field 'AutoCheck' $false
    $BwLimit     = Resolve-Field 'BwLimit' ''
    # CHECKAPPUPDATES defaults ON (opt-out), unlike every other toggle here -
    # it's a read-only version check, categorically lower risk than the
    # others, so the same conservative-default reasoning correctly lands on
    # the opposite default for this one.
    $CheckAppUpdates = Resolve-Field 'CheckAppUpdates' $true
    if ([string]::IsNullOrWhiteSpace($Lang)) { $Lang = 'en' }
    $AutoLaunchOut = if ($AutoLaunch) { 'true' } else { 'false' }
    $AutoCheckOut  = if ($AutoCheck)  { 'true' } else { 'false' }
    $CheckAppUpdatesOut = if ($CheckAppUpdates) { 'true' } else { 'false' }
    @(
        "# Legacy Downloader - configuration"
        "# You normally don't need to edit this by hand - use the program's"
        "# menus (Change Game Path / Select Maps / Language / Settings)"
        "# instead."
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
        "# SHAREURL (advanced, also settable from Settings) - where the tool"
        "# downloads from. Accepts either a Nextcloud share link copied"
        "# straight from its own UI (https://host/s/TOKEN) or the raw WebDAV"
        "# link - either works. Leave it commented out to use the built-in"
        "# default. If the share ever moves and no new build is available,"
        "# paste the new link here, e.g.:"
        "#   SHAREURL=https://cloud.example.com/s/TOKEN"
        $(if ($ShareUrl) { "SHAREURL=$ShareUrl" } else { "#SHAREURL=" })
        ""
        "# SONGFILTERS (set from the Search songs... screen) - only editions"
        "# with fewer than all their songs selected appear here, as"
        "# edition:code1|code2;edition2:code3. An edition with no entry here"
        "# means 'every song in it'."
        "SONGFILTERS=$SongFilters"
        ""
        "# KEEPSONGS (set from the Search songs... screen with 'Keep my"
        "# version') - songs you have your own modified copy of. They stay"
        "# tracked, but an update never overwrites your file. Same format as"
        "# SONGFILTERS: edition:code1|code2;edition2:code3. Only takes effect"
        "# while the file exists locally."
        "KEEPSONGS=$KeepSongs"
        ""
        "# AUTOLAUNCH (also settable from Settings) - when true, automatically"
        "# launches Legacy.exe and closes this tool right after a successful"
        "# check/update, with no prompt. Default false."
        "AUTOLAUNCH=$AutoLaunchOut"
        ""
        "# AUTOCHECK (also settable from Settings) - when true, automatically"
        "# checks for updates as soon as the tool opens (an existing install"
        "# only - never on a fresh first-run setup). Default false."
        "AUTOCHECK=$AutoCheckOut"
        ""
        "# BWLIMIT (also settable from Settings) - caps rclone's download"
        "# speed, in rclone's own bandwidth syntax (e.g. 5M = 5 MB/s, 800k ="
        "# 800 KB/s). Blank/absent means unlimited. Takes effect the next"
        "# time the tool starts."
        "BWLIMIT=$BwLimit"
        ""
        "# CHECKAPPUPDATES (also settable from Settings) - when true, checks"
        "# once at startup whether a newer LegacyDownloader release exists"
        "# (a read-only GitHub API call, no download). Default true - unlike"
        "# every other toggle above, this one is opt-out, since a version"
        "# check has no file-system or download side effects of its own."
        "CHECKAPPUPDATES=$CheckAppUpdatesOut"
    ) | Set-Content -LiteralPath $script:ConfigPath -Encoding UTF8
}

function Assert-ZipEntriesConfined([string]$ZipPath, [string]$DestinationDir) {
    # Throws if any entry in the archive would be written outside $DestinationDir
    # ("zip slip": entry names like ..\..\x, or an absolute path). Windows
    # PowerShell 5.1's Expand-Archive did not always check this, so the entry
    # names are inspected BEFORE anything is extracted.
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $root = [System.IO.Path]::GetFullPath($DestinationDir).TrimEnd([char]92, [char]47) + [System.IO.Path]::DirectorySeparatorChar
    $zip = [System.IO.Compression.ZipFile]::OpenRead($ZipPath)
    try {
        foreach ($entry in $zip.Entries) {
            $target = $null
            try { $target = [System.IO.Path]::GetFullPath((Join-Path $DestinationDir $entry.FullName)) } catch { }
            if ($null -eq $target -or -not $target.StartsWith($root, [System.StringComparison]::OrdinalIgnoreCase)) {
                throw "unsafe path in the update package: $($entry.FullName)"
            }
        }
    } finally { $zip.Dispose() }
}

function Invoke-AppUpdateDownloadAndStage([string]$DownloadUrl, [string]$ExpectedVersion, [scriptblock]$ProgressCallback, [scriptblock]$PhaseCallback) {
    # Downloads the release zip to $env:TEMP and extracts it to a staging
    # folder OUTSIDE the live install - never directly into the running
    # bin\. Sanity-checks the staged copy's own $script:AppVersion line
    # against $ExpectedVersion before returning: cheap insurance against a
    # corrupt download or a mismatched/renamed asset. Returns
    # @{ Ok; StagingDir; ErrMsg } - StagingDir is $null on failure, and any
    # partial staging directory is cleaned up before returning.
    #
    # -ProgressCallback (optional, same shape as Get-RequirementInstaller's:
    # invoked as & $ProgressCallback $percent $bytesReceived $totalBytes,
    # -1 percent when the server sent no Content-Length): a real live test
    # (2026-09-23) confirmed the previous plain `Invoke-WebRequest -OutFile`
    # blocked the GUI's message pump for the whole download with no way to
    # service it, long enough for Windows to mark the main window "Not
    # Responding" - looks like a crash, not a working update. Manual
    # HttpWebRequest + buffered stream copy instead, same reasoning and
    # same pattern already proven for the requirements checker's own
    # downloads: Invoke-WebRequest has no per-byte hook at all in Windows
    # PowerShell 5.1, so there's no way to report progress (or let a caller
    # pump DoEvents()) through it.
    $tempZip = Join-Path $env:TEMP ("LegacyDownloaderUpdate_" + [guid]::NewGuid().ToString('N') + ".zip")
    $stagingDir = Join-Path $env:TEMP ("legacydownloader_update_" + [guid]::NewGuid().ToString('N'))
    if (-not $ProgressCallback) { $ProgressCallback = {} }
    # -PhaseCallback (optional): invoked as & $PhaseCallback $phase $percent
    # after the download finishes, so a GUI can keep showing something real
    # (and pump its message loop) through the steps that used to run silently
    # behind a bar frozen at 100%: 'verify', 'unpack' (percent 0-100, by
    # bytes), 'check'. Percent is -1 when a phase has no measurable progress.
    if (-not $PhaseCallback) { $PhaseCallback = {} }
    try {
        $req = [System.Net.HttpWebRequest]::Create($DownloadUrl)
        $req.UserAgent = 'LegacyDownloader (+https://github.com/VenB304/LegacyDownloader)'
        $req.Timeout = 600000
        $req.ReadWriteTimeout = 600000
        $deadline = [DateTime]::UtcNow.AddMilliseconds(600000)
        $resp = $req.GetResponse()
        try {
            $total = [long]$resp.ContentLength
            $inStream = $resp.GetResponseStream()
            try {
                $outStream = [System.IO.File]::Create($tempZip)
                try {
                    $buffer = New-Object byte[] 65536
                    $received = [long]0
                    $lastPct = -1
                    $lastTick = [Environment]::TickCount
                    while (($read = $inStream.Read($buffer, 0, $buffer.Length)) -gt 0) {
                        if ([DateTime]::UtcNow -gt $deadline) { throw "download exceeded the 600s time budget" }
                        $outStream.Write($buffer, 0, $read)
                        $received += $read
                        if ($total -gt 0) {
                            $pct = [Math]::Min(100, [Math]::Max(0, [int](($received * 100) / $total)))
                            if ($pct -ne $lastPct) { $lastPct = $pct; & $ProgressCallback $pct $received $total }
                        } else {
                            $nowTick = [Environment]::TickCount
                            if (($nowTick - $lastTick) -ge 100) { $lastTick = $nowTick; & $ProgressCallback -1 $received $total }
                        }
                    }
                } finally { $outStream.Dispose() }
            } finally { $inStream.Dispose() }
        } finally { $resp.Dispose() }
        if (-not (Test-Path -LiteralPath $tempZip) -or (Get-Item -LiteralPath $tempZip).Length -eq 0) { throw "empty download" }
        & $PhaseCallback 'verify' -1
        Assert-ZipEntriesConfined $tempZip $stagingDir
        # Entry-by-entry extraction instead of Expand-Archive: Expand-Archive
        # gives no hook at all, so the window could neither show progress nor
        # repaint (Windows marked it "Not Responding") while a slow disk or a
        # real-time antivirus scan chewed through the unpacked files.
        # Assert-ZipEntriesConfined above already rejected any entry that
        # would land outside $stagingDir.
        & $PhaseCallback 'unpack' 0
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $zip = [System.IO.Compression.ZipFile]::OpenRead($tempZip)
        try {
            $sumBytes = [long]0
            foreach ($entry in $zip.Entries) { $sumBytes += $entry.Length }
            $doneBytes = [long]0
            $lastUnpackPct = -1
            [void][System.IO.Directory]::CreateDirectory($stagingDir)
            foreach ($entry in $zip.Entries) {
                $target = [System.IO.Path]::GetFullPath((Join-Path $stagingDir $entry.FullName))
                if ($entry.FullName.EndsWith('/') -or $entry.FullName.EndsWith('\')) {
                    [void][System.IO.Directory]::CreateDirectory($target)
                    continue
                }
                [void][System.IO.Directory]::CreateDirectory([System.IO.Path]::GetDirectoryName($target))
                [System.IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $target, $true)
                $doneBytes += $entry.Length
                $unpackPct = if ($sumBytes -gt 0) { [Math]::Min(100, [int](($doneBytes * 100) / $sumBytes)) } else { 100 }
                if ($unpackPct -ne $lastUnpackPct) { $lastUnpackPct = $unpackPct; & $PhaseCallback 'unpack' $unpackPct }
            }
        } finally { $zip.Dispose() }
        & $PhaseCallback 'check' -1
        $stagedCore = Join-Path $stagingDir 'bin\LegacyDownloader.Core.psm1'
        if (-not (Test-Path -LiteralPath $stagedCore)) {
            throw "staged package is missing bin\LegacyDownloader.Core.psm1"
        }
        $versionLine = Get-Content -LiteralPath $stagedCore | Where-Object { $_ -match '^\$script:AppVersion\s*=' } | Select-Object -First 1
        if ($versionLine -notmatch "=\s*'([^']+)'") {
            throw "couldn't read the staged package's version string"
        }
        $stagedVersion = $Matches[1]
        if ((Compare-AppVersions $stagedVersion $ExpectedVersion) -ne 0) {
            throw "staged package reports version '$stagedVersion', expected '$ExpectedVersion'"
        }
        return [PSCustomObject]@{ Ok = $true; StagingDir = $stagingDir; ErrMsg = '' }
    } catch {
        Remove-Item -LiteralPath $stagingDir -Recurse -Force -ErrorAction SilentlyContinue
        return [PSCustomObject]@{ Ok = $false; StagingDir = $null; ErrMsg = $_.Exception.Message }
    } finally {
        Remove-Item -LiteralPath $tempZip -Force -ErrorAction SilentlyContinue
    }
}

function Start-AppUpdateHelper {
    # Spawns bin\Update-Helper.ps1 as a real detached process (so it
    # survives this process exiting) and returns immediately - the caller
    # is responsible for actually exiting right after this returns, since
    # the helper's very first step is waiting for this process's PID to
    # disappear. InstallDir is the app root (parent of bin\, where the two
    # .bat launchers live); RelaunchTarget is 'gui' or 'console'.
    param(
        [Parameter(Mandatory = $true)][string]$InstallDir,
        [Parameter(Mandatory = $true)][string]$StagingDir,
        [Parameter(Mandatory = $true)][string]$ExpectedVersion,
        [Parameter(Mandatory = $true)][ValidateSet('gui', 'console')][string]$RelaunchTarget
    )
    $helperScript = Join-Path $InstallDir 'bin\Update-Helper.ps1'
    # ConvertTo-QuotedArg, not hand-rolled "`"$x`"" quoting: an install at a
    # drive root gives InstallDir = 'D:\', and a hand-quoted "D:\" makes
    # Windows read the \" as an escaped quote, so the helper received a
    # garbled -InstallDir and the update never started (the app had already
    # closed). ConvertTo-QuotedArg leaves a space-free 'D:\' alone and
    # doubles trailing backslashes when a path does need quotes.
    $argList = @(
        '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (ConvertTo-QuotedArg $helperScript)
        '-InstallDir', (ConvertTo-QuotedArg $InstallDir)
        '-StagingDir', (ConvertTo-QuotedArg $StagingDir)
        '-MainPid', $PID
        '-ExpectedVersion', (ConvertTo-QuotedArg $ExpectedVersion)
        '-RelaunchTarget', $RelaunchTarget
    )
    # Deliberately NOT hidden: a script spawning a hidden, execution-policy-
    # bypassed PowerShell child is the same dropper/loader heuristic shape
    # that got the V5-V6 .vbs launcher flagged. The helper shows a small
    # console window for the few seconds the swap takes.
    # -PassThru: returns the helper's Process so a GUI can keep its progress
    # window up until the helper's own console window is actually on screen
    # (otherwise there is a blank gap between the app vanishing and the
    # helper appearing). Callers that don't need it pipe it to Out-Null.
    Start-Process -FilePath 'powershell.exe' -ArgumentList $argList -PassThru
}

function Start-LegacyExe([string]$GamePath) {
    # Launches Legacy.exe from the given game folder. Returns $true if the
    # process was started, $false if the exe wasn't found there - callers
    # decide how to tell the user (Write-Host vs. a MessageBox is a
    # front-end concern, not Core's).
    $exePath = Join-Path $GamePath 'Legacy.exe'
    if (-not (Test-Path -LiteralPath $exePath)) { return $false }
    Start-Process -FilePath $exePath | Out-Null
    return $true
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
            3111 { return "Just Dance Wii" }
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

function Get-LocalSongMap([string]$GamePath) {
    # Local counterpart to Get-RemoteSongMap: one recursive filesystem walk
    # of maps\ instead of one directory listing per edition, grouped by
    # edition -> the codes actually present on disk (stripping _pc.ipk).
    # Used to seed the song picker from what's REALLY downloaded rather
    # than from config's AUTO/specific-list flag, which can say "AUTO" for
    # a moment with nothing extra actually fetched (e.g. a user who flips
    # to Everything and immediately back to Specific).
    #
    # No game folder set yet (GamePath '') means "nothing downloaded" -
    # same as the game folder not existing - but Join-Path's own -Path
    # parameter rejects an empty string outright (a mandatory [string]
    # binding quirk, confirmed directly rather than assumed), so that case
    # has to be caught before ever reaching it.
    if ([string]::IsNullOrEmpty($GamePath)) { return @{} }
    $mapsDir = Join-Path $GamePath 'maps'
    if (-not (Test-Path -LiteralPath $mapsDir)) { return @{} }
    $map = @{}
    Get-ChildItem -LiteralPath $mapsDir -Recurse -Filter '*.ipk' -File -ErrorAction SilentlyContinue | ForEach-Object {
        $ed = $_.Directory.Name
        $code = $_.BaseName -replace '_pc$', ''
        if (-not $map.ContainsKey($ed)) { $map[$ed] = New-Object System.Collections.Generic.List[string] }
        $map[$ed].Add($code)
    }
    $out = @{}
    foreach ($ed in $map.Keys) { $out[$ed] = @($map[$ed] | Sort-Object) }
    return $out
}

function Get-LocalSongSelection {
    # Builds the same {Editions=<csv>; SongFilters=<raw SONGFILTERS>} shape
    # Save-Config/Initialize-SongSelectionContext already use everywhere
    # else, but derived from what's actually on disk (Get-LocalSongMap)
    # instead of from config. An edition whose local codes exactly match
    # every code the catalog has for it is recorded as a whole edition (no
    # filter entry, matching the "no entry = every song" convention);
    # anything short of that - a genuine partial selection, or an edition
    # the live catalog doesn't currently know about at all - is recorded
    # explicitly so nothing locally present gets silently dropped.
    param(
        [Parameter(Mandatory = $true)][string]$GamePath,
        [Parameter(Mandatory = $true)]$Catalog
    )
    $localMap = Get-LocalSongMap $GamePath
    if ($localMap.Count -eq 0) { return @{ Editions = ''; SongFilters = '' } }

    $byEdition = @{}
    foreach ($r in $Catalog) {
        if (-not $byEdition.ContainsKey($r.Edition)) { $byEdition[$r.Edition] = New-Object System.Collections.Generic.List[string] }
        $byEdition[$r.Edition].Add($r.Code)
    }

    $editions = New-Object System.Collections.Generic.List[string]
    $filterParts = New-Object System.Collections.Generic.List[string]
    foreach ($ed in (@($localMap.Keys) | Sort-EditionNames)) {
        $localCodes = [System.Collections.Generic.HashSet[string]]::new([string[]]@($localMap[$ed]), [System.StringComparer]::OrdinalIgnoreCase)
        if ($localCodes.Count -eq 0) { continue }
        [void]$editions.Add($ed)
        $fullCodes = if ($byEdition.ContainsKey($ed)) { @($byEdition[$ed]) } else { @() }
        $isWholeEdition = ($fullCodes.Count -gt 0) -and (@($fullCodes | Where-Object { -not $localCodes.Contains($_) })).Count -eq 0
        if ($isWholeEdition) { continue }
        $codesPresent = if ($fullCodes.Count -gt 0) { @($fullCodes | Where-Object { $localCodes.Contains($_) }) } else { @($localMap[$ed]) }
        if ($codesPresent.Count -gt 0) { [void]$filterParts.Add("$ed`:" + ($codesPresent -join '|')) }
    }
    return @{ Editions = ($editions -join ','); SongFilters = ($filterParts -join ';') }
}

function Get-TrackedDownloadStatus {
    # Data model for the main window's "View tracked" dialog: reconciles
    # what's TRACKED (per config's Editions/SongFilters - reusing the exact
    # same seeding Initialize-SongSelectionContext already does for the
    # picker) against what's actually DOWNLOADED (Get-LocalSongMap, real
    # files on disk), so drift between the two - something tracked that
    # hasn't been fetched yet, or a leftover file no longer tracked - is
    # visible instead of silently invisible. Every returned row is one of:
    #   Green  - tracked AND downloaded
    #   Yellow - tracked, not yet downloaded
    #   Red    - downloaded, not (or no longer) tracked
    # A song downloaded from a custom/local edition the live catalog has
    # never heard of still gets a row (IsUnknown = $true, same convention
    # the picker's own share-only-song merge already uses) rather than
    # being silently dropped, so "someone added their own maps by hand"
    # is visible here too, not just missing.
    param(
        # AllowEmptyString: a mandatory [string] parameter otherwise rejects
        # an explicitly-passed '' at bind time (distinct from the usual
        # missing-argument case) - a fresh install with no GamePath set yet
        # is exactly that case, and every call below handles '' fine
        # (Get-LocalSongMap Join-Path's it into a relative 'maps' that
        # simply won't exist, returning an empty map, not a crash).
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$GamePath,
        [Parameter(Mandatory = $true)][string]$Editions,
        [string]$SongFilters = '',
        [Parameter(Mandatory = $true)]$Catalog
    )
    $trackedKeys = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    if (-not [string]::IsNullOrWhiteSpace($Editions)) {
        $ctx = Initialize-SongSelectionContext -Catalog $Catalog -CurrentEditions $Editions -CurrentSongFilters $SongFilters
        foreach ($k in $ctx.SelectedKeys) { [void]$trackedKeys.Add($k) }
    }

    $localMap = Get-LocalSongMap $GamePath
    $downloadedKeys = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($ed in $localMap.Keys) {
        foreach ($code in $localMap[$ed]) { [void]$downloadedKeys.Add("$ed|$code") }
    }

    $byKey = @{}
    foreach ($r in $Catalog) { $byKey["$($r.Edition)|$($r.Code)"] = $r }

    $unionKeys = [System.Collections.Generic.HashSet[string]]::new($trackedKeys, [System.StringComparer]::OrdinalIgnoreCase)
    [void]$unionKeys.UnionWith($downloadedKeys)

    $rows = New-Object System.Collections.Generic.List[object]
    $editionSeen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($key in $unionKeys) {
        $sep = $key.IndexOf('|')
        $ed = $key.Substring(0, $sep)
        $code = $key.Substring($sep + 1)
        $tracked = $trackedKeys.Contains($key)
        $downloaded = $downloadedKeys.Contains($key)
        $status = if ($tracked -and $downloaded) { 'Green' } elseif ($tracked) { 'Yellow' } else { 'Red' }
        $rec = $byKey[$key]
        $row = if ($null -ne $rec) {
            [PSCustomObject]@{ Edition = $rec.Edition; Code = $rec.Code; Title = $rec.Title; Artist = $rec.Artist; Difficulty = $rec.Difficulty; Effort = $rec.Effort; IsUnknown = $false; Status = $status }
        } else {
            [PSCustomObject]@{ Edition = $ed; Code = $code; Title = $null; Artist = $null; Difficulty = $null; Effort = $null; IsUnknown = $true; Status = $status }
        }
        $rows.Add($row)
        [void]$editionSeen.Add($ed)
    }

    # .ToArray(), not @($rows) - wrapping a List[object] containing
    # PSCustomObjects in @() right before/inside a function's return value
    # hits a real Windows PowerShell 5.1 interpreter bug ("Argument types
    # do not match" from PSEnumerableBinder) - confirmed in isolation,
    # .ToArray() sidesteps it cleanly.
    return @{
        Rows     = $rows.ToArray()
        Editions = @(@($editionSeen) | Sort-EditionNames)
    }
}

function ConvertTo-QuotedArg([string]$Value) {
    # Quotes one argument for a command LINE (Start-Process -ArgumentList
    # takes a joined string), following CommandLineToArgvW's rules: quote
    # when the value has whitespace OR a double quote; inside the quotes a
    # run of backslashes before a quote is doubled and the quote escaped, and
    # trailing backslashes (which would otherwise escape our closing quote)
    # are doubled. Before, an embedded quote passed straight through and could
    # split one value into several arguments (flag injection into rclone from
    # a hostile song code).
    if ($Value -notmatch '[\s"]') { return $Value }
    $escaped = [regex]::Replace($Value, '(\\*)"', { param($m) $m.Groups[1].Value + $m.Groups[1].Value + '\"' })
    $escaped = [regex]::Replace($escaped, '(\\+)$', { param($m) $m.Value + $m.Value })
    return '"' + $escaped + '"'
}

# ----------------------------------------------------------------------------
# Always-on troubleshooting log (bin\logs\) - no setting to turn it off (see
# the V10 plan's "Always-on troubleshooting log" section: a log a user has to
# remember to enable before the bug happens is much less useful than one
# that's just always there). One shared write+rotate helper for every rclone-
# invoking call site, so file-writing/rotation logic lives in exactly one
# place rather than being reimplemented per call site:
#   - Invoke-RcloneCapture (the dry-run scan, shared by both front-ends) and
#     Complete-RcloneCopy (the GUI's real transfers) already fully capture
#     rclone's output headlessly - they just hand it to Save-RcloneLogLines.
#   - The console's real transfer (Invoke-RcloneCopy in the console
#     front-end) streams live via -P and can't be redirected without killing
#     that live terminal progress meter, so it instead has rclone write
#     straight to a New-RcloneLogPath file via --log-file, verified live
#     (2026-09-22) to coexist with -P without disrupting the progress
#     display or losing per-file detail (a real "Copied (new)" line showed
#     up in the log file while -P kept animating normally on stdout).
# ----------------------------------------------------------------------------

function Get-RcloneLogDir {
    # Created lazily. Fails soft (returns $null) if it can't be created (e.g.
    # a read-only install location) - a missing log directory should never
    # be the reason a real download can't proceed.
    $dir = Join-Path $script:AppDir 'logs'
    if (-not (Test-Path -LiteralPath $dir)) {
        try { New-Item -ItemType Directory -Path $dir -Force -ErrorAction Stop | Out-Null } catch { return $null }
    }
    return $dir
}

function New-RcloneLogPath([string]$Label) {
    $dir = Get-RcloneLogDir
    if ($null -eq $dir) { return $null }
    $safeLabel = ($Label -replace '[^A-Za-z0-9_-]+', '_').Trim('_')
    if ([string]::IsNullOrWhiteSpace($safeLabel)) { $safeLabel = 'run' }
    # HHmmss (not just HH:mm) plus the caller's Label keeps concurrent GUI
    # queue entries (base + several editions, each started within the same
    # second) from colliding on one filename.
    $stamp = Get-Date -Format 'yyyy-MM-dd_HHmmss'
    return Join-Path $dir "$stamp`_$safeLabel.log"
}

function Invoke-RcloneLogRotation {
    # Keep only the newest N run logs. Unlike an opt-in toggle, this log has
    # no way to turn it off, so EVERY run adds a file - the cap has to ship
    # in the same commit as the logging itself or a machine that's run this
    # tool for months grows an unbounded bin\logs\. Count-based (not a byte
    # budget): simpler to verify deterministically by forcing N+few runs and
    # confirming the oldest ones are actually gone.
    param([int]$KeepCount = 30)
    $dir = Get-RcloneLogDir
    if ($null -eq $dir) { return }
    $files = @(Get-ChildItem -LiteralPath $dir -Filter '*.log' -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending)
    if ($files.Count -le $KeepCount) { return }
    foreach ($f in ($files | Select-Object -Skip $KeepCount)) {
        Remove-Item -LiteralPath $f.FullName -Force -ErrorAction SilentlyContinue
    }
}

function Save-RcloneLogLines([string]$Label, [string[]]$Lines) {
    # For the headless-capture call sites (the dry-run scan, the GUI's real
    # transfers) - already-captured output gets written out + rotated in one
    # call. A no-op on empty/unwritable input, never throws.
    if ($null -eq $Lines -or $Lines.Count -eq 0) { return }
    $path = New-RcloneLogPath $Label
    if ($null -eq $path) { return }
    try { [System.IO.File]::WriteAllLines($path, $Lines, [System.Text.Encoding]::UTF8) } catch { return }
    Invoke-RcloneLogRotation
}

function Invoke-RcloneCapture([string[]]$RcloneArgs, [string]$Label = 'scan') {
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
        Save-RcloneLogLines -Label $Label -Lines $lines
        return [PSCustomObject]@{ ExitCode = $code; Lines = $lines }
    } finally {
        Remove-Item -LiteralPath $outFile, $errFile -Force -ErrorAction SilentlyContinue
    }
}

function ConvertFrom-RcloneSize([string]$Num, [string]$Unit) {
    # rclone always prints its dry-run sizes with a period decimal point,
    # regardless of the machine's locale. An unqualified TryParse honors the
    # CURRENT CULTURE instead: on a Windows region where '.' is a thousands
    # separator (e.g. de-DE), "753.2" silently parses as 7532 - a ~10x size
    # inflation, not just a display quirk - and on a region where '.' isn't
    # valid at all (e.g. fr-FR), it fails outright and returns 0, silently
    # undercounting. Force invariant parsing so this can't depend on the
    # user's Windows region.
    $n = 0.0
    $style = [System.Globalization.NumberStyles]::Float
    $inv = [System.Globalization.CultureInfo]::InvariantCulture
    if (-not [double]::TryParse($Num, $style, $inv, [ref]$n)) { return [long]0 }
    switch (($Unit -replace 'i?B?$', '').ToLower()) {
        'k' { return [long]($n * 1KB) }
        'm' { return [long]($n * 1MB) }
        'g' { return [long]($n * 1GB) }
        't' { return [long]($n * 1TB) }
        default { return [long]$n }
    }
}

function Format-Bytes([long]$Bytes) {
    # PowerShell's -f operator formats numbers using the OS's regional
    # settings, not the app's own selected language - on a Windows install
    # set to a comma-decimal locale that silently produced "75,2 GB" even
    # while the GUI itself was set to English. Force invariant (period-
    # decimal) formatting so this never depends on Windows region.
    $inv = [System.Globalization.CultureInfo]::InvariantCulture
    if ($Bytes -ge 1GB) { return (($Bytes / 1GB).ToString('N1', $inv) + ' GB') }
    if ($Bytes -ge 1MB) { return (($Bytes / 1MB).ToString('N0', $inv) + ' MB') }
    if ($Bytes -ge 1KB) { return (($Bytes / 1KB).ToString('N0', $inv) + ' KB') }
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

function ConvertTo-RcloneGlobLiteral([string]$Text) {
    # rclone filter patterns are globs; backslash-escape the metacharacters so
    # a song code or edition folder name is always matched literally.
    return [regex]::Replace($Text, '[\\*?\[\]{}]', { param($m) '\' + $m.Value })
}

function Test-SafeEditionName([string]$Edition) {
    # An edition is ONE folder name under maps\. The value comes from
    # config.txt and the online catalog, both editable by a user or a third
    # party, and ends up in path joins and a recursive delete - so anything
    # that could resolve elsewhere ('', '.', '..', a path separator, a drive
    # colon, characters invalid in a file name) is rejected outright.
    if ([string]::IsNullOrWhiteSpace($Edition)) { return $false }
    if ($Edition -eq '.' -or $Edition -eq '..') { return $false }
    if ($Edition -ne $Edition.Trim() -or $Edition.EndsWith('.')) { return $false }
    if ($Edition.IndexOfAny([System.IO.Path]::GetInvalidFileNameChars()) -ge 0) { return $false }
    if ($Edition.IndexOfAny([char[]]@([char]92, [char]47, [char]58)) -ge 0) { return $false }   # \ / :
    return $true
}

function Resolve-KeepSongsRaw($KeepSongs) {
    # $null = "read KEEPSONGS from config.txt" (so the background scan job and
    # the download queue see the same value without extra plumbing).
    if ($null -eq $KeepSongs) {
        if ([string]::IsNullOrEmpty($script:ConfigPath)) { return '' }   # Core not initialized (tests, tooling): no config, no locks
        return [string](Load-Config).KeepSongs
    }
    return [string]$KeepSongs
}

function Get-KeepKeySet($KeepSongs = $null) {
    # KEEPSONGS -> HashSet of "Edition|code" keys (case-insensitive), the shape
    # both pickers work with. The comma keeps PowerShell from unrolling the set.
    $set = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $map = Get-SongFilterMap (Resolve-KeepSongsRaw $KeepSongs)
    foreach ($ed in @($map.Keys)) { foreach ($c in @($map[$ed])) { [void]$set.Add("$ed|$c") } }
    return ,$set
}

function Format-KeepKeySet($Keys) {
    # "Edition|code" keys -> the KEEPSONGS string (edition:code|code;...),
    # editions and codes sorted so config.txt doesn't churn.
    $byEd = [ordered]@{}
    foreach ($k in @($Keys | Sort-Object)) {
        $i = ([string]$k).IndexOf('|')
        if ($i -lt 1) { continue }
        $ed = $k.Substring(0, $i)
        if (-not $byEd.Contains($ed)) { $byEd[$ed] = @() }
        $byEd[$ed] += $k.Substring($i + 1).ToLowerInvariant()
    }
    return (Format-SongFilters $byEd)
}

function Get-LocalSongKeySet([string]$GamePath) {
    # "Edition|code" keys for every song file actually on disk.
    $set = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $localMap = Get-LocalSongMap $GamePath
    foreach ($ed in @($localMap.Keys)) { foreach ($c in @($localMap[$ed])) { [void]$set.Add("$ed|$c") } }
    return ,$set
}

function Get-KeptSongCodes {
    # The codes from KEEPSONGS ("Keep my version") for $Edition whose file
    # really exists in maps\<edition>. A lock only protects a file the user
    # actually has - a kept song that isn't on disk (deleted, or never
    # downloaded) is simply fetched again, and is protected from then on.
    param(
        [Parameter(Mandatory = $true)][string]$Edition,
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$GamePath,
        $KeepSongs = $null
    )
    if ([string]::IsNullOrEmpty($GamePath)) { return @() }
    if (-not (Test-SafeEditionName $Edition)) { return @() }
    $map = Get-SongFilterMap (Resolve-KeepSongsRaw $KeepSongs)
    if (-not $map.Contains($Edition)) { return @() }
    $dir = Join-Path (Join-Path $GamePath 'maps') $Edition
    if (-not (Test-Path -LiteralPath $dir)) { return @() }
    $present = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($f in @(Get-ChildItem -LiteralPath $dir -Filter '*_pc.ipk' -File -ErrorAction SilentlyContinue)) {
        [void]$present.Add(($f.BaseName -replace '_pc$', ''))
    }
    return @($map[$Edition] | Where-Object { $present.Contains($_) })
}

function New-RcloneFilterFile([string[]]$Rules) {
    # Writes ordered filter rules (one per line) to a small file in %TEMP% and
    # returns its path, for rclone's --filter-from. The name is a hash of the
    # content, so identical rules reuse one file instead of piling up. UTF-8
    # WITHOUT a BOM: rclone would read a BOM as part of the first rule.
    $text = ($Rules -join "`n") + "`n"
    $sha = [System.Security.Cryptography.SHA1]::Create()
    try { $hash = -join ($sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($text)) | ForEach-Object { $_.ToString('x2') }) }
    finally { $sha.Dispose() }
    $path = Join-Path ([System.IO.Path]::GetTempPath()) "legacydownloader_filters_$hash.txt"
    if (-not (Test-Path -LiteralPath $path)) { [System.IO.File]::WriteAllText($path, $text, (New-Object System.Text.UTF8Encoding($false))) }
    # Housekeeping: every distinct rule set is its own file, so drop our own week-old ones.
    try {
        Get-ChildItem -LiteralPath ([System.IO.Path]::GetTempPath()) -Filter 'legacydownloader_filters_*.txt' -File -ErrorAction SilentlyContinue |
            Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-7) } | Remove-Item -Force -ErrorAction SilentlyContinue
    } catch { }
    return $path
}

function Get-SongFilterArgs {
    # The rclone filter args for one transfer, combining the wanted-songs
    # subset (SONGFILTERS) with the "Keep my version" locks (KEEPSONGS).
    #   -Edition <name>: the source is maps/<edition>; -Songs is that
    #     edition's effective subset ($null/empty = every song).
    #   -Edition omitted: the source is the whole maps tree (Everything /
    #     AUTO mode); only lock exclusions apply.
    # With no kept song present this is EXACTLY Get-SongIncludeArgs (or
    # nothing), so users without locks see no change at all. With locks it
    # has to use ordered --filter rules: rclone ignores a plain --exclude
    # whenever any --include is present (measured against the bundled
    # rclone.exe), and --filter rules are first-match-wins in the order
    # given - lock exclusions first, then the includes, then an explicit
    # "- *" (--filter does NOT add the implicit exclude-everything-else that
    # --include does).
    # A handful of rules ride on the command line, but hundreds of kept songs
    # would blow past CreateProcess's 32,767-character limit (about 800 kept
    # songs in Everything mode), so a long rule list goes into a --filter-from
    # file instead - same rules, same order.
    # -KeepSongs omitted = read it from config.txt, so the background scan
    # job and the download queue pick it up without extra plumbing.
    param(
        [string]$Edition = '',
        [string[]]$Songs = $null,
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$GamePath,
        $KeepSongs = $null
    )
    $KeepSongs = Resolve-KeepSongsRaw $KeepSongs
    $rules = New-Object System.Collections.Generic.List[string]

    if ($Edition -ne '') {
        $kept = @(Get-KeptSongCodes -Edition $Edition -GamePath $GamePath -KeepSongs $KeepSongs)
        if ($kept.Count -eq 0) { return @(Get-SongIncludeArgs $Songs) }
        foreach ($c in $kept) { $rules.Add("- /$(ConvertTo-RcloneGlobLiteral $c)_pc.ipk") }
        $wanted = @($Songs | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        if ($wanted.Count -gt 0) {
            foreach ($c in $wanted) { $rules.Add("+ $(ConvertTo-RcloneGlobLiteral $c.Trim().ToLowerInvariant())_pc.ipk") }
            $rules.Add('- *')
        }
    } else {
        $map = Get-SongFilterMap $KeepSongs
        foreach ($ed in @($map.Keys)) {
            foreach ($c in @(Get-KeptSongCodes -Edition $ed -GamePath $GamePath -KeepSongs $KeepSongs)) {
                $rules.Add("- /$(ConvertTo-RcloneGlobLiteral $ed)/$(ConvertTo-RcloneGlobLiteral $c)_pc.ipk")
            }
        }
        if ($rules.Count -eq 0) { return @() }
    }

    if (($rules -join ' ').Length -gt 6000) {
        return @('--filter-from', (New-RcloneFilterFile $rules.ToArray()), '--ignore-case')
    }
    $out = @()
    foreach ($r in $rules) { $out += @('--filter', $r) }
    $out += '--ignore-case'
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

function ConvertFrom-GvizCell($Cells, [int]$Index) {
    # A gviz row's cell array can be shorter than expected if trailing
    # columns are blank for that row - bounds-check rather than assume 7.
    # A present cell is either JSON null (blank) or {v: <raw value>,
    # f: <formatted display string>}. Prefer .f when present - for the
    # Edition column (a gviz "number" column) it's the clean sheet display
    # text ("2014", "1928") rather than .v's double ("2014.0", "1928.0").
    if ($Index -ge $Cells.Count) { return '' }
    $Cell = $Cells[$Index]
    if ($null -eq $Cell -or $null -eq $Cell.v) { return '' }
    if ($Cell.PSObject.Properties.Match('f').Count -gt 0 -and $null -ne $Cell.f) { return [string]$Cell.f }
    return [string]$Cell.v
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
        # gviz wraps its JSON in a JS call: /*O_o*/\ngoogle.visualization.
        # Query.setResponse({...});  - unwrap by anchoring on that known
        # wrapper (not by searching for the outermost { }, which could be
        # fooled by braces inside a song title).
        $m = [regex]::Match($text, '(?s)setResponse\((.*)\);\s*$')
        if (-not $m.Success) { throw "Unexpected gviz response format" }
        $data = $m.Groups[1].Value | ConvertFrom-Json
        # gviz already excludes the sheet's own header row from .rows (it
        # goes into .cols[].label instead), unlike the raw CSV export.
        $parsed = foreach ($row in $data.table.rows) {
            $cells = @($row.c)
            $ed   = ConvertFrom-GvizCell $cells 0
            $code = (ConvertFrom-GvizCell $cells 1).Trim().ToLowerInvariant()
            if ([string]::IsNullOrWhiteSpace($ed) -or [string]::IsNullOrWhiteSpace($code)) { continue }
            [PSCustomObject]@{
                Edition    = $ed
                Code       = $code
                Title      = ConvertFrom-GvizCell $cells 2
                Artist     = ConvertFrom-GvizCell $cells 3
                Difficulty = ConvertTo-RatingTier (ConvertFrom-GvizCell $cells 4)
                Effort     = ConvertTo-RatingTier (ConvertFrom-GvizCell $cells 5)
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
    #
    # NOTE: ConvertFrom-Json emits a JSON array as ONE non-enumerated
    # pipeline object (a real PowerShell/ConvertFrom-Json quirk). Wrapping
    # that directly in "return @(... | ConvertFrom-Json)" makes a caller who
    # ALSO wraps the call in @() - the normal, defensive way to call any
    # function that might return an array - get back a 1-element array
    # containing the WHOLE real array as its single element, instead of the
    # flat array. Assigning to a plain variable first, with no @() anywhere
    # in the assignment, and returning that variable bare avoids it - proven
    # correct for both "$x = Get-CachedSongCatalog" and the actual call site
    # in use, "$x = @(Get-CachedSongCatalog)", across 0/1/N-item results.
    if (-not $script:SongCatalogCachePath -or -not (Test-Path -LiteralPath $script:SongCatalogCachePath)) { return @() }
    try {
        $rows = [System.IO.File]::ReadAllText($script:SongCatalogCachePath, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
        return $rows
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
        # AllowEmptyString: Get-LocalSongSelection returns Editions = '' for
        # a fresh GamePath with zero local maps (not 'AUTO' - nothing is
        # tracked yet), and a mandatory [string] parameter otherwise rejects
        # that '' at bind time. '' -split ',' | Where { $_ -ne '' } already
        # collapses to an empty $trackedList, so this is handled correctly
        # below without further changes.
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$CurrentEditions,
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
        WasAuto         = $wasAuto
        # Editions that exist on the share but have no row in the community
        # sheet at all (filled in by Add-ShareOnlySongs, e.g. 3111).
        ShareOnlyEditions = (New-Object System.Collections.Generic.HashSet[string])
    }
}

function Add-ShareOnlySongs {
    # Folds what is really on the share (Get-RemoteSongMap's edition -> codes
    # map) into a song-selection context built from the community sheet, so
    # the picker also offers songs the sheet doesn't know about. Two cases:
    #   * an edition the sheet covers, plus share files it doesn't list: the
    #     extra codes are added to that edition (codes compare case-
    #     insensitively - sheet "firework" vs share "Firework_pc.ipk" is the
    #     same song);
    #   * an edition on the share that the sheet has NO rows for at all (JD
    #     Wii, 3111): the whole edition is added, flagged in
    #     Context.ShareOnlyEditions.
    # Mutates the context (ByEdition, CatalogEditions, Rows, SelectedKeys,
    # ShareOnlyEditions) and returns ONLY the rows it added (IsUnknown = $true,
    # no Title/Artist - callers render the code). Seeds SelectedKeys the same
    # way Initialize-SongSelectionContext does for catalog songs: tracked (or
    # AUTO) with no filter = every code, with a filter = only the listed ones.
    param(
        [Parameter(Mandatory = $true)]$Context,
        [AllowNull()]$RemoteMap
    )
    $added = New-Object System.Collections.Generic.List[object]
    if ($null -eq $RemoteMap) { return @() }
    foreach ($ed in @($RemoteMap.Keys)) {
        $edName = [string]$ed
        if ([string]::IsNullOrWhiteSpace($edName) -or -not (Test-SafeEditionName $edName)) { continue }
        $isNewEdition = -not $Context.ByEdition.ContainsKey($edName)
        if ($isNewEdition) { $Context.ByEdition[$edName] = New-Object System.Collections.Generic.List[string] }
        $existing = [System.Collections.Generic.HashSet[string]]::new([string[]]@($Context.ByEdition[$edName]), [System.StringComparer]::OrdinalIgnoreCase)
        $isTracked = $Context.WasAuto -or ($Context.TrackedList -contains $edName)
        $hasFilter = $Context.FilterMap.Contains($edName)
        foreach ($code in @($RemoteMap[$ed])) {
            $codeName = [string]$code
            if ([string]::IsNullOrWhiteSpace($codeName) -or $existing.Contains($codeName)) { continue }
            [void]$existing.Add($codeName)
            [void]$Context.ByEdition[$edName].Add($codeName)
            # An edition with a sheet-known filter was already seeded by
            # Initialize-SongSelectionContext; a share-only edition never was.
            if ($isTracked -and ((-not $hasFilter) -or ($isNewEdition -and (@($Context.FilterMap[$edName]) -contains $codeName)))) {
                [void]$Context.SelectedKeys.Add("$edName|$codeName")
            }
            $added.Add([PSCustomObject]@{ Edition = $edName; Code = $codeName; Title = $null; Artist = $null; Difficulty = $null; Effort = $null; IsUnknown = $true })
        }
        if ($isNewEdition) {
            if ($Context.ByEdition[$edName].Count -eq 0) { [void]$Context.ByEdition.Remove($edName) }
            else { [void]$Context.ShareOnlyEditions.Add($edName) }
        }
    }
    if ($added.Count -eq 0) { return @() }
    $combined = New-Object System.Collections.Generic.List[object]
    $combined.AddRange([object[]]@($Context.Rows))
    $combined.AddRange($added)
    $Context.Rows = $combined.ToArray()
    $Context.CatalogEditions = @($Context.ByEdition.Keys | Sort-EditionNames)
    return $added.ToArray()
}

function Resolve-SongSelection {
    # Turns a (possibly edited) checked-keys set back into @{ Editions;
    # SongFilters }, or $null if nothing ended up selected. "edition|code"
    # keys are used throughout so one HashSet covers every edition at once.
    param(
        [Parameter(Mandatory = $true)]$Context,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][System.Collections.Generic.HashSet[string]]$SelectedKeys
    )
    # Share-only songs (IsUnknown - on the live share, absent from the
    # community sheet) get merged into $Context.ByEdition/Rows by the
    # picker's own unknown-song scan, so a checked share-only code counts
    # toward "every code in this edition is checked" the same as a real
    # catalog code does. That's a real bug if left alone: collapsing to
    # 'ALL' (no SongFilters entry) only ever means "every song the CATALOG
    # currently knows about" once reloaded later - Initialize-
    # SongSelectionContext's own "no filter = every code in ByEdition"
    # expansion is built fresh from the catalog fetch at THAT time, with no
    # memory of a share-only extra that happened to be checked when this was
    # saved. Confirmed as a real, reproducible loss: check every catalog
    # song in an edition PLUS one share-only song, save, reload - the
    # share-only pick silently vanishes. An edition with any checked
    # share-only code must always keep an explicit filter list instead.
    $unknownCodesByEdition = @{}
    foreach ($r in $Context.Rows) {
        if (-not $r.IsUnknown) { continue }
        if (-not $unknownCodesByEdition.ContainsKey($r.Edition)) { $unknownCodesByEdition[$r.Edition] = New-Object System.Collections.Generic.HashSet[string] }
        [void]$unknownCodesByEdition[$r.Edition].Add($r.Code)
    }
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
        # An edition the sheet has NO rows for (every row is share-only) has no
        # "catalog subset" for an explicit list to protect: all-checked is simply
        # the whole folder, so it stays 'ALL' and picks up songs added later.
        $isShareOnlyEdition = $null -ne $Context.ShareOnlyEditions -and $Context.ShareOnlyEditions.Contains($ed)
        $hasCheckedUnknown = (-not $isShareOnlyEdition) -and $unknownCodesByEdition.ContainsKey($ed) -and (@($checkedCodes | Where-Object { $unknownCodesByEdition[$ed].Contains($_) })).Count -gt 0
        $resultMap[$ed] = if ($checkedCodes.Count -eq $allCodes.Count -and -not $hasCheckedUnknown) { 'ALL' } else { $checkedCodes }
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

function Get-SongRemovalPromptItems {
    # Narrows a Get-SongRemovalPlan result down to what there is actually
    # something to ask about: entries with real, DELETABLE files on disk. A
    # dropped edition counts if its maps\<edition> folder holds anything
    # besides songs the user marked Keep my version; a narrowed edition counts
    # only if at least one of its unchecked songs is really there and isn't
    # kept. KeptCount says how many kept songs sit in an entry, so the
    # front-ends can tell the user they will be left alone. Front-ends show
    # the items in ONE prompt, then hand them to Invoke-SongRemovalDelete.
    param(
        # AllowNull too: Get-SongRemovalPlan emits nothing (not an empty array)
        # when there is nothing to remove, so a caller's $plan is $null then.
        [Parameter(Mandatory = $true)][AllowNull()][AllowEmptyCollection()]$Plan,
        [Parameter(Mandatory = $true)][string]$GamePath,
        $KeepSongs = $null
    )
    $KeepSongs = Resolve-KeepSongsRaw $KeepSongs
    $items = @()
    foreach ($entry in @($Plan)) {
        if ($null -eq $entry) { continue }
        $ed = [string]$entry.Edition
        if (-not (Test-SafeEditionName $ed)) { continue }
        $localDir = Join-Path (Join-Path $GamePath 'maps') $ed
        if (-not (Test-Path -LiteralPath $localDir -PathType Container)) { continue }
        $kept = @(Get-KeptSongCodes -Edition $ed -GamePath $GamePath -KeepSongs $KeepSongs)
        if ($entry.WholeEditionRemoved) {
            $fileCount = @(Get-ChildItem -LiteralPath $localDir -File -Recurse -ErrorAction SilentlyContinue).Count
            if ($fileCount -gt 0 -and ($fileCount - $kept.Count) -le 0) { continue }   # only kept songs in there
            $items += [PSCustomObject]@{ Edition = $ed; Whole = $true; Codes = @(); Count = 0; KeptCount = $kept.Count }
        } else {
            $existing = @($entry.RemovedCodes | Where-Object { Test-Path -LiteralPath (Join-Path $localDir "${_}_pc.ipk") })
            $deletable = @($existing | Where-Object { $kept -notcontains $_ })
            if ($deletable.Count -gt 0) {
                $items += [PSCustomObject]@{ Edition = $ed; Whole = $false; Codes = $deletable; Count = $deletable.Count; KeptCount = ($existing.Count - $deletable.Count) }
            }
        }
    }
    return $items
}

function Invoke-SongRemovalDelete {
    # Deletes the local files behind Get-SongRemovalPromptItems entries: a
    # dropped edition's files, or just the unchecked <code>_pc.ipk files of a
    # narrowed one. Songs marked Keep my version are NEVER deleted here - the
    # lock protects the user's own modified copy from deletion as well as from
    # updates (a whole edition is then emptied around them and its folder
    # stays). Every path is confined to maps\<one folder>: an unsafe edition
    # name is refused, not joined. Returns one result per item (Edition,
    # Whole, Count = files removed, KeptLeft = kept songs left in place,
    # Failed = $true if anything couldn't be removed, e.g. the game has it
    # open) so each front-end can word its own messages. Never throws.
    param(
        [Parameter(Mandatory = $true)][AllowNull()][AllowEmptyCollection()]$Items,
        [Parameter(Mandatory = $true)][string]$GamePath,
        $KeepSongs = $null
    )
    $KeepSongs = Resolve-KeepSongsRaw $KeepSongs
    $mapsDir = Join-Path $GamePath 'maps'
    $results = @()
    foreach ($item in @($Items)) {
        if ($null -eq $item) { continue }
        $ed = [string]$item.Edition
        $failed = $false; $removed = 0; $keptLeft = 0
        $localDir = $null
        if (Test-SafeEditionName $ed) {
            $localDir = Join-Path $mapsDir $ed
            $mapsFull = [System.IO.Path]::GetFullPath($mapsDir).TrimEnd([char]92, [char]47)
            $dirFull = [System.IO.Path]::GetFullPath($localDir).TrimEnd([char]92, [char]47)
            if (-not [string]::Equals([System.IO.Path]::GetDirectoryName($dirFull), $mapsFull, [System.StringComparison]::OrdinalIgnoreCase)) { $localDir = $null }
        }
        if ($null -eq $localDir) {
            $failed = $true
        } else {
            $kept = @(Get-KeptSongCodes -Edition $ed -GamePath $GamePath -KeepSongs $KeepSongs)
            if ($item.Whole) {
                if ($kept.Count -eq 0) {
                    try { Remove-Item -LiteralPath $localDir -Recurse -Force -ErrorAction Stop; $removed = 1 } catch { $failed = $true }
                } else {
                    foreach ($f in @(Get-ChildItem -LiteralPath $localDir -File -Recurse -Force -ErrorAction SilentlyContinue)) {
                        if ($f.BaseName -match '_pc$' -and $f.Extension -ieq '.ipk' -and ($kept -contains ($f.BaseName -replace '_pc$', ''))) { $keptLeft++; continue }
                        try { Remove-Item -LiteralPath $f.FullName -Force -ErrorAction Stop; $removed++ } catch { $failed = $true }
                    }
                    # tidy sub-folders the deletions emptied (never the edition folder itself: kept songs live there)
                    foreach ($d in @(Get-ChildItem -LiteralPath $localDir -Directory -Recurse -Force -ErrorAction SilentlyContinue | Sort-Object { $_.FullName.Length } -Descending)) {
                        if (@(Get-ChildItem -LiteralPath $d.FullName -Force -ErrorAction SilentlyContinue).Count -eq 0) { Remove-Item -LiteralPath $d.FullName -Force -ErrorAction SilentlyContinue }
                    }
                }
            } else {
                foreach ($code in $item.Codes) {
                    if ($kept -contains $code) { $keptLeft++; continue }
                    $target = Join-Path $localDir "${code}_pc.ipk"
                    if (Test-Path -LiteralPath $target) {
                        try { Remove-Item -LiteralPath $target -Force -ErrorAction Stop; $removed++ } catch { $failed = $true }
                    }
                }
            }
        }
        $results += [PSCustomObject]@{ Edition = $ed; Whole = [bool]$item.Whole; Count = $removed; KeptLeft = $keptLeft; Failed = $failed }
    }
    return $results
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
        BaseAskSuspected = @()
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
    $baseRun = Invoke-RcloneCapture (@('copy', "$script:Conn`LegacyPC - Game", $GamePath, '--exclude', 'maps/**') + $script:ScanArgs) -Label 'scan-base'
    if ($baseRun.ExitCode -ne 0) { $plan.Ok = $false; $plan.NetFail = $true; return $plan }
    $base = Parse-DryRun $baseRun.Lines

    # ---- songs ----
    $songFilesFlat = @()
    $songBytes     = [long]0
    $songs         = @()

    if ($Editions.ToUpper() -eq 'AUTO') {
        $mapRun = Invoke-RcloneCapture (@('copy', "$script:Conn`maps", $mapsDir) + (Get-SongFilterArgs -GamePath $GamePath) + $script:ScanArgs) -Label 'scan-allmaps'
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
        # Tried replacing this per-edition loop with one whole-tree scan
        # (like the AUTO branch above), the same shape of fix that turned
        # the share-only-song scan's ~24 spawns into 1 (see
        # Get-RemoteSongMap, ~47s -> ~4s against the live share). Measured
        # it directly against the live share first rather than assuming the
        # same win applies here: for 1 tracked edition the whole-tree scan
        # was ~4x SLOWER (~8.6s vs ~2s - scanning everything costs roughly
        # the same regardless of how few editions are tracked, while a
        # per-edition scan only ever pays for what's actually needed); for
        # 4 (Ven's own actual tracked-edition count) it was roughly a wash;
        # it only clearly won past ~10 tracked editions (~2.9x). Since
        # tracking a HANDFUL of specific editions - not most/all of them,
        # which is what AUTO mode is already for - is the realistic common
        # case this branch exists for, the whole-tree version would have
        # made the typical case worse, not better. Reverted; left as a
        # per-edition scan.
        $list = $Editions -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' }
        foreach ($ed in $list) {
            $includeArgs = Get-SongFilterArgs -Edition $ed -Songs (Get-EffectiveSongs $ed $SongFilters) -GamePath $GamePath
            $r = Invoke-RcloneCapture (@('copy', "$script:Conn`maps/$ed", [System.IO.Path]::Combine($mapsDir, $ed)) + $includeArgs + $script:ScanArgs) -Label "scan-edition-$ed"
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
    # "Protected" = Legacy.exe, any Kinect*.dll, or the bundle/patch ipks (see
    # Test-ProtectedBaseFile) - a patched exe, a swapped Kinect shim, or a
    # modded bundle/patch must survive an update. Presence alone isn't enough
    # to decide "ask": a returning user who never touched the file would be
    # asked on every single release forever (this is what was silently
    # freezing Legacy.exe/Kinect DLLs for non-modding users - the update
    # never applied because the safe default is "keep mine", so a user who
    # doesn't read the checklist never gets it). Instead compare the local
    # file's hash against what Update-ProtectedFileHashes last recorded for
    # it: a match means nothing has touched the file since WE wrote it, so
    # it's safe to auto-update like any other base file; a mismatch (or no
    # record yet) means it's genuinely unaccounted for, so ask like before.
    $haveSettings = Test-Path -LiteralPath ([System.IO.Path]::Combine($GamePath, 'config.xml'))
    $protectedHashes = Get-ProtectedFileHashRecord $GamePath
    $baseAsk = @(); $baseAskSuspected = @(); $baseNormal = @()
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
        if (Test-ProtectedBaseFile $leaf) {
            $localCopy = [System.IO.Path]::Combine($GamePath, ($f -replace '/', '\'))
            if (Test-Path -LiteralPath $localCopy) {
                $localHash = Get-FileHashSafe $localCopy
                $recorded  = if ($protectedHashes.ContainsKey($leaf)) { $protectedHashes[$leaf] } else { $null }
                if ($recorded -and $localHash -and ($localHash -eq $recorded)) {
                    $baseNormal += $f
                } else {
                    $baseAsk += $f
                    # A recorded hash that exists but DOESN'T match is real evidence
                    # something changed the file after this tool last wrote it - that's
                    # a genuine suspected mod, not just "never been checked before".
                    # BaseAskSuspected lets the GUI default the checklist to "protect"
                    # only for that case, and to "take the update" everywhere else - so
                    # an existing install's first check under this logic doesn't repeat
                    # the exact bug this mechanism exists to fix (a user who never reads
                    # the checklist staying frozen forever because the blanket default
                    # used to be "keep").
                    if ($recorded) { $baseAskSuspected += $f }
                }
            } else {
                $baseNormal += $f
            }
        } else {
            $baseNormal += $f
        }
    }

    $plan.BaseNormal      = @($baseNormal)
    $plan.BaseAsk         = @($baseAsk)
    $plan.BaseAskSuspected = @($baseAskSuspected)
    $plan.BaseBytes       = $base.Bytes
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
    # Tidy up a finished job: persist its JSON log (already fully captured in
    # ErrFile by Start-RcloneCopy's redirect - no extra rclone args needed
    # here, GuiSyncArgs already carries -v) to bin\logs\, then return its exit
    # code and delete the temp files.
    param([Parameter(Mandatory = $true)]$Job)
    $code = -1
    try { $code = [int]$Job.Process.ExitCode } catch { $code = -1 }
    try {
        $lines = @(Get-Content -LiteralPath $Job.ErrFile -ErrorAction SilentlyContinue)
        Save-RcloneLogLines -Label $Job.Label -Lines $lines
    } catch { }
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

# ----------------------------------------------------------------------------
# Protected base files: Legacy.exe, the Kinect shim DLLs, and the bundle/patch
# ipks all live at the base-game root and are the files a real Legacy PC mod
# is most likely to replace. Get-UpdatePlan asks before overwriting one, but
# only when the local copy's hash doesn't match what WE last wrote there
# (see Update-ProtectedFileHashes) - that's what lets a non-modding user who
# always answers "keep mine" without reading (the common case that was
# quietly freezing Legacy.exe forever) start auto-updating again after the
# first honest answer, while a genuinely modded file never matches and keeps
# getting the protective prompt on every release.
# ----------------------------------------------------------------------------

function Test-ProtectedBaseFile([string]$Leaf) {
    $l = $Leaf.ToLowerInvariant()
    return ($l -in @('legacy.exe', 'bundle_pc.ipk', 'patch_pc.ipk')) -or ($l -like 'kinect*.dll')
}

function Get-FileHashSafe([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
    try { return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash } catch { return $null }
}

function Get-ProtectedFileHashPath([string]$GamePath) {
    return [System.IO.Path]::Combine($GamePath, '.legacydownloader-protected.json')
}

function Get-ProtectedFileHashRecord([string]$GamePath) {
    # filename (lowercase) -> SHA256 of the copy this tool itself last wrote there.
    $path = Get-ProtectedFileHashPath $GamePath
    if (-not (Test-Path -LiteralPath $path)) { return @{} }
    try {
        $raw  = [System.IO.File]::ReadAllText($path, [System.Text.Encoding]::UTF8)
        $json = $raw | ConvertFrom-Json
        $h = @{}
        if ($json) { foreach ($p in $json.PSObject.Properties) { $h[$p.Name] = [string]$p.Value } }
        return $h
    } catch {
        return @{}
    }
}

function Save-ProtectedFileHashRecord([string]$GamePath, [hashtable]$Record) {
    try { $Record | ConvertTo-Json | Set-Content -LiteralPath (Get-ProtectedFileHashPath $GamePath) -Encoding UTF8 } catch { }
}

function Update-ProtectedFileHashes {
    # Call right after a base-game sync actually writes to GamePath. Records
    # the post-copy hash of every protected file that wasn't excluded (kept)
    # this round, so the next Get-UpdatePlan can tell "untouched since we
    # wrote it" (safe to auto-update next time) apart from "genuinely
    # modified since" (ask again). A file the user chose to keep is left out
    # on purpose - its record (if any) must not advance, or a later release
    # would silently overwrite it the moment its declined hash happens to
    # match a stale recorded baseline.
    param(
        [Parameter(Mandatory = $true)][string]$GamePath,
        [string[]]$KeepFiles = @()
    )
    $keepLeaves = @($KeepFiles | Where-Object { $_ } | ForEach-Object { (Split-Path -Leaf $_).ToLowerInvariant() })
    $files = @(Get-ChildItem -LiteralPath $GamePath -File -ErrorAction SilentlyContinue |
        Where-Object { (Test-ProtectedBaseFile $_.Name) -and ($keepLeaves -notcontains $_.Name.ToLowerInvariant()) })
    if ($files.Count -eq 0) { return }
    $record = Get-ProtectedFileHashRecord $GamePath
    foreach ($f in $files) {
        $hash = Get-FileHashSafe $f.FullName
        if ($hash) { $record[$f.Name.ToLowerInvariant()] = $hash }
    }
    Save-ProtectedFileHashRecord $GamePath $record
}

# ----------------------------------------------------------------------------
# Software requirements: the Kinect SDKs / Visual C++ redistributables /
# DirectX End-User Runtime that Legacy.exe needs beyond what Windows ships
# natively. Verified against Legacy.exe's REAL PE import table (Python
# pefile, not a string scan) plus a real Discord bug report, not guessed -
# see docs/notes/ in the repo for the analysis. Every URL below was checked
# by hand against Microsoft's own download pages; none of these are
# third-party mirrors, per project decision (official Microsoft sources
# only, or a clear manual link on failure - never a fallback host).
# ----------------------------------------------------------------------------

function Get-RequirementDefinitions {
    # Static catalog, one entry per requirement. Names are proper nouns and
    # deliberately never localized/translated (same convention as "Legacy.exe"
    # / "Kinect10.dll" / "config.xml" elsewhere in this project).
    #   Bundled/BundledRelPath - path (relative to GamePath) to the copy that
    #     already ships in the game's own Support\ folder, if any.
    #   OfficialUrl  - Microsoft's own landing page for this download; shown
    #     to the user as the manual-fallback link if a fetch fails.
    #   FetchUrl     - the actual installer file, for Get-RequirementInstaller
    #     to download directly. $null for items that are always bundled.
    #   SilentArgs   - command-line args for an unattended install, or $null
    #     if the installer has no silent mode at all (both Kinect SDKs - by
    #     Microsoft's own design, EULA acceptance can't be scripted).
    #   DetectMethod - which Get-RequirementsStatus strategy decides
    #     Installed: 'DllsAndUninstallMatch' (dlls AND an Uninstall-hive
    #     match), 'Vc2015' (dlls AND the fixed VS14 runtime key),
    #     'DllsOnly' (no reliable registry marker), or 'UninstallMatch'
    #     (Uninstall-hive match alone, no consumable DLL to check). A future
    #     item that fits one of these can reuse it with no code change; a
    #     genuinely new detection shape needs a new case AND a new value
    #     here, so the two can't drift out of sync silently.
    #   Severity     - 'Critical' surfaces as the Requirements button's red
    #     state in the GUI (Refresh-RequirementsButton) - reserved for an
    #     item with a real confirmed crash report behind it, not just
    #     "missing is bad" (every missing item is already "bad").
    #   CheckDlls    - DLL(s) whose real presence in the correct system
    #     folder is checked alongside (VC++/DirectX) or instead of (none
    #     apply to the Kinect SDKs, which don't ship their own consumable
    #     DLL - Kinect10.dll/Kinect20.dll already ship with the game itself)
    #     the registry, so a registry key left behind by a broken/partial
    #     install doesn't read as "installed."
    #   UninstallPatterns - substrings (all must match, AND) checked against
    #     DisplayName entries in the Uninstall registry hive.
    return @(
        [PSCustomObject]@{
            Id = 'vc2010'; Name = 'Visual C++ 2010 Redistributable (x86)'
            Bundled = $false; BundledRelPath = $null
            OfficialUrl = 'https://www.microsoft.com/en-us/download/details.aspx?id=26999'
            FetchUrl    = 'https://download.microsoft.com/download/1/6/5/165255E7-1014-4D0A-B094-B6A430A6BFFC/vcredist_x86.exe'
            SilentArgs  = '/q /norestart'
            DetectMethod = 'DllsAndUninstallMatch'; Severity = 'Normal'
            CheckDlls   = @('msvcp100.dll', 'msvcr100.dll')
            UninstallPatterns = @('Visual C\+\+ 2010', 'x86')
        }
        [PSCustomObject]@{
            Id = 'vc2012'; Name = 'Visual C++ 2012 Redistributable (x86)'
            Bundled = $true; BundledRelPath = 'Support\vcredist\vcredist_x86.exe'
            OfficialUrl = 'https://www.microsoft.com/en-us/download/details.aspx?id=30679'
            FetchUrl    = 'https://download.microsoft.com/download/1/6/B/16B06F60-3B20-4FF2-B699-5E9B7962F9AE/VSU_4/vcredist_x86.exe'
            SilentArgs  = '/install /quiet /norestart'
            DetectMethod = 'DllsAndUninstallMatch'; Severity = 'Normal'
            CheckDlls   = @('msvcp110.dll', 'msvcr110.dll')
            UninstallPatterns = @('Visual C\+\+ 2012', 'x86')
        }
        [PSCustomObject]@{
            # Legacy.exe's own linker version is 14.0 - it was genuinely
            # built with the VS2015 toolset. Microsoft has since split VS2015
            # out of the "latest v14" bucket into its own legacy/unsupported
            # download (as of their Dec 2025 doc update), which now covers
            # VS2017-2026 and keeps extending every VS release - so "2015" is
            # the real lower bound that matters here (what actually built the
            # game) and "+" avoids re-going-stale every time Microsoft ships
            # a new VS version, unlike a fixed upper year would. The FETCH
            # itself (see FetchUrl below) is still the CURRENT "latest v14"
            # redistributable - Microsoft's own compatibility promise is that
            # a newer v14 redistributable always satisfies an app built with
            # an older v14 toolset, VS2015 included.
            Id = 'vc2015'; Name = 'Visual C++ 2015+ Redistributable (x86)'
            Bundled = $false; BundledRelPath = $null
            OfficialUrl = 'https://learn.microsoft.com/en-us/cpp/windows/latest-supported-vc-redist'
            FetchUrl    = 'https://aka.ms/vc14/vc_redist.x86.exe'
            SilentArgs  = '/install /quiet /norestart'
            DetectMethod = 'Vc2015'; Severity = 'Normal'
            CheckDlls   = @('msvcp140.dll', 'vcruntime140.dll')
            UninstallPatterns = @()   # detected via Test-Vc2015Installed instead
        }
        [PSCustomObject]@{
            # Legacy.exe only imports modern d3d11.dll/dxgi.dll (both native
            # to Windows) - the D3DX9/10/11 components this redist also
            # provides genuinely aren't needed. It's needed narrowly for
            # XINPUT1_3.dll, which Windows does NOT ship natively (only
            # xinput1_4.dll/xinput9_1_0.dll are built in) - confirmed via a
            # real Discord user's missing-DLL crash report, after an earlier
            # AI-generated analysis wrongly claimed this whole item was
            # unnecessary.
            Id = 'directx'; Name = 'DirectX End-User Runtime (June 2010)'
            Bundled = $true; BundledRelPath = 'Support\DirectX\DXSETUP.exe'
            OfficialUrl = 'https://www.microsoft.com/en-us/download/details.aspx?id=8109'
            FetchUrl    = $null
            SilentArgs  = '/silent'
            DetectMethod = 'DllsOnly'; Severity = 'Normal'
            CheckDlls   = @('xinput1_3.dll')
            UninstallPatterns = @()   # legacy cab installer, no reliable registry marker - see Test-SystemDllPresent
        }
        [PSCustomObject]@{
            Id = 'kinect18'; Name = 'Kinect for Windows SDK 1.8'
            Bundled = $false; BundledRelPath = $null
            OfficialUrl = 'https://www.microsoft.com/en-us/download/details.aspx?id=40278'
            FetchUrl    = 'https://download.microsoft.com/download/e/1/d/e1dec243-0389-4a23-87bf-f47de869fc1a/KinectSDK-v1.8-Setup.exe'
            SilentArgs  = $null   # no silent install exists - Microsoft's own EULA-driven design
            # Critical: a real Discord crash report is specifically behind
            # "both Kinect SDKs missing" (see Refresh-RequirementsButton) -
            # not a generic "missing is bad", every missing item is already bad.
            DetectMethod = 'UninstallMatch'; Severity = 'Critical'
            CheckDlls   = @()
            UninstallPatterns = @('Kinect for Windows SDK', 'v?1\.8')
        }
        [PSCustomObject]@{
            Id = 'kinect20'; Name = 'Kinect for Windows SDK 2.0'
            Bundled = $false; BundledRelPath = $null
            OfficialUrl = 'https://www.microsoft.com/en-us/download/details.aspx?id=44561'
            FetchUrl    = 'https://download.microsoft.com/download/f/2/d/f2d1012e-3bc6-49c5-b8b3-5acff58af7b8/KinectSDK-v2.0_1409-Setup.exe'
            SilentArgs  = $null
            DetectMethod = 'UninstallMatch'; Severity = 'Critical'
            CheckDlls   = @()
            UninstallPatterns = @('Kinect for Windows SDK', 'v?2\.0')
        }
    )
}

function Test-SystemDllPresent([string]$DllName) {
    # Whether $DllName exists in the correct system directory for an x86
    # process - Legacy.exe is 32-bit (confirmed via its PE header), so on a
    # 64-bit OS the DLL that matters is the SysWOW64 copy, not the native
    # 64-bit one in System32. On a genuinely 32-bit OS, System32 IS the
    # 32-bit directory.
    if ($IsLinux) { return $false }
    $sysDir = if ([Environment]::Is64BitOperatingSystem) {
        Join-Path $env:WINDIR 'SysWOW64'
    } else {
        Join-Path $env:WINDIR 'System32'
    }
    return (Test-Path -LiteralPath (Join-Path $sysDir $DllName))
}

function Get-InstalledDisplayNames {
    # Every DisplayName in the registry's "installed programs" list
    # (Uninstall hive, both the native and the 32-bit/Wow6432Node view -
    # these installers are all x86 even on a 64-bit OS), walked ONCE. Both
    # hives together hold every installed program on the machine, so this
    # can be a genuinely slow enumeration - Get-RequirementsStatus used to
    # call Test-UninstallDisplayNameMatch (which used to do this same walk
    # itself) once per item, re-walking both hives from scratch 4 times
    # (vc2010/vc2012/kinect18/kinect20) for one status check. Walking once
    # and matching every item's patterns against the cached result instead
    # measured close to a 4x cut in this function's share of the ~900ms a
    # real Get-RequirementsStatus call took on a real dev machine.
    if ($IsLinux) { return @() }
    $roots = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall'
    )
    $names = @()
    foreach ($root in $roots) {
        if (-not (Test-Path -LiteralPath $root)) { continue }
        foreach ($k in (Get-ChildItem -LiteralPath $root -ErrorAction SilentlyContinue)) {
            $dn = $null
            try { $dn = (Get-ItemProperty -LiteralPath $k.PSPath -Name DisplayName -ErrorAction SilentlyContinue).DisplayName } catch { }
            if ($dn) { $names += $dn }
        }
    }
    return $names
}

function Test-UninstallDisplayNameMatch([string[]]$Patterns, [string[]]$DisplayNames) {
    # True if some name in $DisplayNames (from Get-InstalledDisplayNames)
    # matches every pattern in $Patterns (AND, not one brittle exact-order
    # phrase - Microsoft's own exact DisplayName wording has varied release
    # to release, e.g. "x86" vs "(x86)", so requiring the meaningful
    # substrings independently is more robust than betting on one string).
    if ($Patterns.Count -eq 0 -or $DisplayNames.Count -eq 0) { return $false }
    foreach ($dn in $DisplayNames) {
        $allMatch = $true
        foreach ($p in $Patterns) { if ($dn -notmatch $p) { $allMatch = $false; break } }
        if ($allMatch) { return $true }
    }
    return $false
}

function Test-Vc2015Installed {
    # Microsoft's own documented Intune/SCCM detection method for the VC++
    # v14 x86 runtime (binary-compatible from VS2015 through whatever the
    # current VS release is - 2026 as of this writing, and climbing - all
    # tracked under version "14.0"): an Installed=1 DWORD under this fixed
    # key, present since the very first 2015 release - unlike VC++
    # 2010/2012, which each register under their own product-specific
    # entries with no equivalent single stable key, so those two are
    # detected via Test-UninstallDisplayNameMatch instead.
    if ($IsLinux) { return $false }
    $path = 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\VisualStudio\14.0\VC\Runtimes\X86'
    if (-not (Test-Path -LiteralPath $path)) { return $false }
    try {
        $v = (Get-ItemProperty -LiteralPath $path -Name Installed -ErrorAction SilentlyContinue).Installed
        return ($v -eq 1)
    } catch { return $false }
}

function Get-RequirementsStatus {
    # One status object per Get-RequirementDefinitions entry, reflecting
    # whether it's ACTUALLY satisfied right now on this machine. The three
    # VC++ items and DirectX all get a real DLL-file-presence check, not
    # registry alone - a stale-but-present registry key from a broken/
    # partial install is exactly the failure mode behind the real
    # MSVCP140.dll-class crash reports this feature exists to catch, so a
    # registry-only check would hide precisely the case that matters.
    [CmdletBinding()]
    param([string]$GamePath)

    $defs = Get-RequirementDefinitions
    # Walked once for the whole batch, not once per item - see
    # Get-InstalledDisplayNames for why that used to be a real cost.
    $displayNames = Get-InstalledDisplayNames
    $out = @()
    foreach ($d in $defs) {
        $dllsOk = $true
        foreach ($dll in $d.CheckDlls) { if (-not (Test-SystemDllPresent $dll)) { $dllsOk = $false; break } }

        # Dispatches on DetectMethod (a field on the definition), not on
        # $d.Id - a future item that reuses one of these four shapes needs
        # no change here at all, just the right DetectMethod value on its
        # own definition. An unrecognized DetectMethod warns instead of
        # silently reporting "not installed", so a typo'd or missing value
        # on a new definition can't hide as a false negative.
        $installed = switch ($d.DetectMethod) {
            'DllsAndUninstallMatch' { $dllsOk -and (Test-UninstallDisplayNameMatch $d.UninstallPatterns $displayNames) }
            'Vc2015'                { $dllsOk -and (Test-Vc2015Installed) }
            'DllsOnly'              { $dllsOk }   # no reliable registry marker for a legacy cab installer - file presence is ground truth here
            'UninstallMatch'        { Test-UninstallDisplayNameMatch $d.UninstallPatterns $displayNames }
            default {
                Write-Warning "Get-RequirementsStatus: requirement '$($d.Id)' has an unrecognized DetectMethod '$($d.DetectMethod)' - treating as not installed"
                $false
            }
        }

        $bundledPath = $null
        if ($d.Bundled -and $GamePath) {
            $p = [System.IO.Path]::Combine($GamePath, $d.BundledRelPath)
            if (Test-Path -LiteralPath $p) { $bundledPath = $p }
        }

        $out += [PSCustomObject]@{
            Id          = $d.Id
            Name        = $d.Name
            Installed   = [bool]$installed
            Severity    = $d.Severity
            BundledPath = $bundledPath
            OfficialUrl = $d.OfficialUrl
            FetchUrl    = $d.FetchUrl
            SilentArgs  = $d.SilentArgs
            Interactive = ($null -eq $d.SilentArgs)
        }
    }
    return $out
}

function Get-RequirementInstaller {
    # Ensures a local, runnable installer file for $Item exists, either by
    # using the already-bundled copy or by downloading it from its own
    # FetchUrl. NEVER falls back to any other host - on any failure returns
    # .Ok = $false with .OfficialUrl still set, so the caller can show a
    # manual-download link instead of a dead end.
    #
    # -ProgressCallback (optional): invoked as & $ProgressCallback $percent
    # $bytesReceived $totalBytes while an actual network download is in
    # progress (never for a bundled-copy or a failed-preflight return, since
    # no bytes move in either case). $percent is always clamped to 0-100 (a
    # misreporting server can't push a caller-side control like a WinForms
    # ProgressBar out of its valid range), or -1 when the server didn't send
    # a Content-Length, so the caller can fall back to an indeterminate
    # display. The known-total case is throttled to fire only when the
    # whole-number percentage actually changes; the unknown-total case is
    # throttled to at most ~10/sec, since there's no percentage to gate on.
    param(
        [Parameter(Mandatory = $true)]$Item,
        [Parameter(Mandatory = $true)][string]$DestDir,
        [scriptblock]$ProgressCallback
    )
    # .Downloaded distinguishes a real temp-folder download (safe for a
    # caller to delete once it's done with it) from the bundled path
    # (points straight at the game's own Support\ folder - never delete
    # that).
    if ($Item.BundledPath -and (Test-Path -LiteralPath $Item.BundledPath)) {
        return [PSCustomObject]@{ Ok = $true; Path = $Item.BundledPath; OfficialUrl = $Item.OfficialUrl; Downloaded = $false }
    }
    if ([string]::IsNullOrWhiteSpace($Item.FetchUrl)) {
        return [PSCustomObject]@{ Ok = $false; Path = $null; OfficialUrl = $Item.OfficialUrl; Downloaded = $false }
    }
    try {
        if (-not (Test-Path -LiteralPath $DestDir)) { [System.IO.Directory]::CreateDirectory($DestDir) | Out-Null }
    } catch {
        return [PSCustomObject]@{ Ok = $false; Path = $null; OfficialUrl = $Item.OfficialUrl; Downloaded = $false }
    }
    # Always keyed by Item.Id, not a name parsed from the URL - vc2010 and
    # vc2012's real Microsoft download links both happen to end in the
    # same "vcredist_x86.exe" leaf name (vc2012's is normally never used
    # since it's bundled, but IS reachable as a fallback if the Support
    # folder copy is ever missing/corrupted), which would otherwise let
    # two different items collide on the same destination file.
    $dest = Join-Path $DestDir "$($Item.Id).exe"

    # A no-op default rather than a separate Invoke-WebRequest-only code
    # path for callers that don't care about progress: two independently
    # maintained HTTP download implementations (timeouts, empty-file check,
    # cleanup-on-failure) were a real maintenance risk, and this one is what
    # both real front-ends always use for anything that isn't a bundled
    # copy.
    if (-not $ProgressCallback) { $ProgressCallback = {} }

    # Manual HttpWebRequest + buffered stream copy instead of Invoke-
    # WebRequest -OutFile: that cmdlet has no per-byte hook at all in
    # Windows PowerShell 5.1, so there's no way to report progress through
    # it. HttpWebRequest is what Invoke-WebRequest itself uses internally
    # here, so the TLS/ServicePointManager-level behavior is unchanged -
    # only the User-Agent needed setting explicitly below, since
    # HttpWebRequest (unlike Invoke-WebRequest) sends none by default.
    try {
        $req = [System.Net.HttpWebRequest]::Create($Item.FetchUrl)
        $req.UserAgent = 'LegacyDownloader (+https://github.com/VenB304/LegacyDownloader)'
        # Timeout covers waiting for the response headers; ReadWriteTimeout
        # covers each individual stream Read() call, catching a truly
        # stalled connection faster than waiting for one overall cap to
        # expire. Neither one bounds the TOTAL transfer time by itself
        # though (a connection that always delivers its next chunk just
        # under the ReadWriteTimeout could run indefinitely), so $deadline
        # below restores the original single 600s-for-the-whole-download
        # guarantee on top of them.
        $req.Timeout = 600000
        $req.ReadWriteTimeout = 600000
        $deadline = [DateTime]::UtcNow.AddMilliseconds(600000)
        $resp = $req.GetResponse()
        try {
            $total = [long]$resp.ContentLength   # -1 when the server omits it
            $inStream = $resp.GetResponseStream()
            try {
                $outStream = [System.IO.File]::Create($dest)
                try {
                    $buffer = New-Object byte[] 65536
                    $received = [long]0
                    $lastPct = -1
                    $lastTick = [Environment]::TickCount
                    while (($read = $inStream.Read($buffer, 0, $buffer.Length)) -gt 0) {
                        if ([DateTime]::UtcNow -gt $deadline) { throw "download exceeded the 600s time budget" }
                        $outStream.Write($buffer, 0, $read)
                        $received += $read
                        if ($total -gt 0) {
                            # Clamped even though a well-behaved server should
                            # never report more bytes than its own declared
                            # Content-Length - a stale/incorrect header on a
                            # mirror is exactly the kind of thing this
                            # shouldn't crash on, matching the same clamp the
                            # rclone-based progress bar already applies.
                            $pct = [Math]::Min(100, [Math]::Max(0, [int](($received * 100) / $total)))
                            if ($pct -ne $lastPct) {
                                $lastPct = $pct
                                & $ProgressCallback $pct $received $total
                            }
                        } else {
                            # No percentage to throttle on when the total is
                            # unknown - throttle by time instead, so a large
                            # file served without Content-Length doesn't fire
                            # a callback (and a GUI DoEvents() pump) on every
                            # single 64KB read.
                            $nowTick = [Environment]::TickCount
                            if (($nowTick - $lastTick) -ge 100) {
                                $lastTick = $nowTick
                                & $ProgressCallback -1 $received $total
                            }
                        }
                    }
                } finally {
                    $outStream.Dispose()
                }
            } finally {
                $inStream.Dispose()
            }
        } finally {
            $resp.Dispose()
        }
        if (-not (Test-Path -LiteralPath $dest) -or (Get-Item -LiteralPath $dest).Length -eq 0) { throw "empty download" }
        return [PSCustomObject]@{ Ok = $true; Path = $dest; OfficialUrl = $Item.OfficialUrl; Downloaded = $true }
    } catch {
        Remove-Item -LiteralPath $dest -Force -ErrorAction SilentlyContinue
        return [PSCustomObject]@{ Ok = $false; Path = $null; OfficialUrl = $Item.OfficialUrl; Downloaded = $false }
    }
}

function Install-Requirement {
    # Runs $Item's installer at $Path. Silent items pass their documented
    # unattended args and wait for the process to exit; the two Kinect SDKs
    # have no silent mode at all (Microsoft's own EULA-driven design) - just
    # launched and waited on, showing their own UI same as a manual install.
    # Exit code isn't treated as the final word either way - the caller
    # re-runs Get-RequirementsStatus afterward as the real source of truth.
    #
    # A user declining the elevation (UAC) prompt does NOT surface as a
    # System.ComponentModel.Win32Exception (ERROR_CANCELLED/1223), despite
    # that being the real underlying error ShellExecuteEx throws - verified
    # against real reports of this exact PowerShell behavior, not assumed:
    # Start-Process's own cmdlet wrapping swallows that Win32Exception and
    # rethrows a bare System.InvalidOperationException instead (no
    # InnerException, so the real native error code never reaches calling
    # code at all). Catching InvalidOperationException as the actual
    # "declined" case - broadly, not by matching the exception's message
    # text, which would break on a non-English Windows install - is safe
    # specifically because every call here uses a fixed FilePath and a
    # fixed (or absent) ArgumentList we control; there's no other
    # parameter-shape mistake this narrow call could realistically throw
    # that kind of exception for. The Win32Exception catch is kept too, in
    # case some other PowerShell/Windows version path does throw it
    # directly.
    param(
        [Parameter(Mandatory = $true)]$Item,
        [Parameter(Mandatory = $true)][string]$Path
    )
    try {
        $proc = if ($Item.SilentArgs) {
            Start-Process -FilePath $Path -ArgumentList $Item.SilentArgs -Wait -PassThru -ErrorAction Stop
        } else {
            Start-Process -FilePath $Path -Wait -PassThru -ErrorAction Stop
        }
        $code = 0
        try { $code = [int]$proc.ExitCode } catch { $code = 0 }
        # 3010 = success, reboot required; 1638 = a newer version is already
        # installed - both are effectively "fine," not a real failure. A
        # driver install (the Kinect SDKs especially) can leave the
        # registry/files saying "installed" before a pending reboot
        # actually finishes activating it - RebootRequired is surfaced
        # separately from Ok so a caller can say so, rather than silently
        # implying everything's immediately ready to use.
        $ok = ($code -eq 0 -or $code -eq 3010 -or $code -eq 1638)
        return [PSCustomObject]@{ Ok = $ok; Cancelled = $false; ExitCode = $code; RebootRequired = ($code -eq 3010) }
    } catch [System.InvalidOperationException] {
        return [PSCustomObject]@{ Ok = $false; Cancelled = $true; ExitCode = -1; RebootRequired = $false }
    } catch [System.ComponentModel.Win32Exception] {
        return [PSCustomObject]@{ Ok = $false; Cancelled = $true; ExitCode = -1; RebootRequired = $false }
    } catch {
        return [PSCustomObject]@{ Ok = $false; Cancelled = $false; ExitCode = -1; RebootRequired = $false }
    }
}

function Invoke-RequirementInstall {
    # The whole download -> install -> temp-cleanup -> re-check sequence for
    # ONE requirement, as a single pure call with no UI - the console and
    # GUI front-ends used to each reimplement this near-verbatim (right down
    # to sharing the same "trust a fresh re-check" comment word for word),
    # just to render the outcome differently. Both now call this and only
    # own how each Outcome value is displayed.
    #
    # Returns @{ Outcome; OfficialUrl; ExitCode }. Outcome is one of:
    #   'DownloadFailed'          - Get-RequirementInstaller couldn't produce
    #     a runnable installer; OfficialUrl is set so the caller can show a
    #     manual-download link instead of a dead end.
    #   'InstalledRebootRequired' / 'Installed' - a FRESH re-check confirms
    #     it's actually installed now. Trusted over the installer's own exit
    #     code on purpose - not every installer here follows the same MSI
    #     0/3010/1638 convention (DXSETUP.exe's exact convention is
    #     unverified), so asking "is it actually installed now" is more
    #     honest than trusting a guessed-at exit code.
    #   'Cancelled' - the user declined/cancelled the installer itself.
    #   'Failed'    - genuinely failed; ExitCode is set.
    # -OnInstalling (optional): invoked with no args right after the fetch
    # succeeds, before Install-Requirement runs - the one piece of real-time
    # narration that can't just be read off the returned Outcome afterward,
    # since Install-Requirement itself can block for a while (the Kinect
    # SDKs run their own real installer UI with no silent mode at all). Lets
    # each caller flip its own "Installing {name}..." message/label at the
    # right moment instead of only finding out once this whole call returns.
    param(
        [Parameter(Mandatory = $true)]$Item,
        [Parameter(Mandatory = $true)][string]$GamePath,
        [scriptblock]$ProgressCallback,
        [scriptblock]$OnInstalling
    )
    $destDir = Join-Path $env:TEMP 'LegacyDownloaderRequirements'
    $fetch = Get-RequirementInstaller -Item $Item -DestDir $destDir -ProgressCallback $ProgressCallback
    if (-not $fetch.Ok) {
        return [PSCustomObject]@{ Outcome = 'DownloadFailed'; OfficialUrl = $fetch.OfficialUrl; ExitCode = $null }
    }
    if ($OnInstalling) { & $OnInstalling }

    $res = Install-Requirement -Item $Item -Path $fetch.Path
    if ($fetch.Downloaded) {
        # Only ever the temp-folder copy just downloaded - $fetch.Path
        # points straight at the game's own Support\ folder when it came
        # from there instead, and that must never be touched.
        Remove-Item -LiteralPath $fetch.Path -Force -ErrorAction SilentlyContinue
    }

    $nowInstalled = (@(Get-RequirementsStatus -GamePath $GamePath | Where-Object { $_.Id -eq $Item.Id }))[0].Installed
    $outcome = if ($nowInstalled -and $res.RebootRequired) { 'InstalledRebootRequired' }
        elseif ($nowInstalled) { 'Installed' }
        elseif ($res.Cancelled) { 'Cancelled' }
        else { 'Failed' }
    return [PSCustomObject]@{ Outcome = $outcome; OfficialUrl = $Item.OfficialUrl; ExitCode = $res.ExitCode }
}

Export-ModuleMember -Function `
    Initialize-LegacyCore, Get-AppVersion, Test-GameFolder, Resolve-GameFolder, `
    Load-Config, Save-Config, Sort-EditionNames, Get-EditionTitle, Format-EditionDisplay, `
    Get-RemoteEditions, Get-RemoteSongs, Get-RemoteSongMap, Add-ShareOnlySongs, Get-LocalEditions, Get-LocalSongCount, `
    Get-LocalSongMap, Get-LocalSongSelection, Get-TrackedDownloadStatus, `
    ConvertTo-QuotedArg, Invoke-RcloneCapture, ConvertFrom-RcloneSize, `
    Format-Bytes, Parse-DryRun, Get-UpdatePlan, `
    Start-RcloneCopy, Read-RcloneStats, Complete-RcloneCopy, Get-BaseSyncExcludes, `
    Test-ProtectedBaseFile, Get-ProtectedFileHashRecord, Update-ProtectedFileHashes, `
    Initialize-Language, T, Get-AvailableLanguages, Resolve-DefaultLanguage, Get-LanguageCode, Get-TutorialUrl, `
    Get-SongFilterMap, Format-SongFilters, Get-EffectiveSongs, Get-SongIncludeArgs, Get-SongFilterArgs, Get-KeptSongCodes, `
    Get-SongCatalog, Get-CachedSongCatalog, Get-SongDisplay, Get-SongDisplayMap, Format-DifficultyTier, Format-EffortTier, `
    Initialize-SongSelectionContext, Resolve-SongSelection, Get-SongRemovalPlan, `
    Get-SongRemovalPromptItems, Invoke-SongRemovalDelete, Test-SafeEditionName, `
    Get-KeepKeySet, Format-KeepKeySet, Get-LocalSongKeySet, `
    Get-DuplicateTitleKeys, Get-SongTitleForDisplay, `
    Get-RequirementDefinitions, Get-RequirementsStatus, Get-RequirementInstaller, Install-Requirement, `
    Invoke-RequirementInstall, Start-LegacyExe, `
    Compare-AppVersions, Get-LatestReleaseInfo, Test-AppUpdateAvailable, `
    Invoke-AppUpdateDownloadAndStage, Start-AppUpdateHelper, `
    Get-RcloneLogDir, New-RcloneLogPath, Invoke-RcloneLogRotation, Save-RcloneLogLines

