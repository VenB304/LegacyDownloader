# LegacyDownloader.Console.ps1 - the text / menu interface.
#
# Dot-sourced by LegacyDownloader.ps1 once the shared core module is loaded,
# Initialize-LegacyCore has run and Initialize-Language has set the interface
# language. Do not launch this file on its own - it relies on $Core (and
# $Rclone / $Conn / $CommonArgs) already being set by the entry script.
$ErrorActionPreference = 'Stop'

if (-not $Core) {
    Write-Host "Please run '..\LegacyDownloader-Console.bat' (or LegacyDownloader.ps1 -Console) - not this file directly." -ForegroundColor Yellow
    exit 1
}

# So Japanese / Korean / Chinese / Cyrillic strings from the language files
# print as text rather than "?". A console font that actually has those
# glyphs is still up to the user (documented in the README).
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }

# Languages shipped in lang\ - read once; used by the menu header and picker.
$AvailableLangs = @(Get-AvailableLanguages)

function HR { return (T 'common.rule') }

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

function Pause-Continue([string]$Message) {
    if ([string]::IsNullOrWhiteSpace($Message)) { $Message = T 'common.press_enter' }
    Write-Host ""
    Read-Host $Message | Out-Null
}

function Pause-Brief([string]$Message, [int]$Seconds = 1) {
    if ($Message) { Write-Host $Message }
    Start-Sleep -Seconds $Seconds
}

function Pause-Exit([int]$Code) {
    Write-Host ""
    Read-Host (T 'common.press_enter_close')
    exit $Code
}

function Exit-Console {
    # The main menu's "quit" option - Linux (5 items) and Windows (6 items,
    # Requirements bumps it down one slot) reach this via different case
    # labels in the switch below, but it's the exact same farewell either
    # way, so it's one function instead of two copies of the same 4 lines.
    Write-Host ""
    Write-Host (T 'menu.goodbye')
    Start-Sleep -Seconds 1
    exit 0
}

function Confirm-YesNo([string]$Prompt) {
    while ($true) {
        $ans = Read-Host (T 'common.yn_prompt' @{ prompt = $Prompt })
        if ($ans -match '^[Yy]') { return $true }
        if ($ans -match '^[Nn]') { return $false }
        Write-Host (T 'common.type_y_n')
    }
}

# Offers to launch Legacy.exe right after a successful check/update -
# Windows-only, gated the same way the Requirements menu item is (no real
# "launch a Windows exe" story on a native Linux console session). If
# AUTOLAUNCH is on, launches and exits immediately with no prompt - the
# fully-automatic opt-in a future Settings screen will expose.
function Show-LaunchPrompt([string]$GamePath, [bool]$AutoLaunch) {
    if ($IsLinux) { return }
    if ($AutoLaunch) {
        if (-not (Start-LegacyExe $GamePath)) { Write-Host (T 'menu.launch_exe_missing') -ForegroundColor Yellow }
        Exit-Console
        return
    }
    $ans = Read-Host (T 'menu.launch_prompt')
    if ($ans -match '^[Ll]') {
        if (-not (Start-LegacyExe $GamePath)) { Write-Host (T 'menu.launch_exe_missing') -ForegroundColor Yellow; return }
        Exit-Console
    }
}

# Shared by the menu's own "Download / check" option and the AUTOCHECK
# startup trigger, so the two don't duplicate the preview -> update ->
# launch-prompt sequence. Runs a --dry-run preview, updates if the user
# (or a real download) confirms one's needed, then offers Show-LaunchPrompt
# either way - matching Show-UpdatePreview's own "nothing left" early-out
# printing its own messaging, so only Dismissed (declined/net failure)
# skips the launch offer entirely.
function Invoke-CheckAndOfferLaunch {
    param([string]$GamePath, [string]$Editions, [string]$SongFilters, [bool]$AutoLaunch)
    $prev = Show-UpdatePreview -GamePath $GamePath -Editions $Editions -SongFilters $SongFilters
    if ($prev.Proceed) {
        Write-Host ""
        Invoke-Update -GamePath $GamePath -Editions $Editions -BaseExcludes $prev.BaseExcludes -SongFilters $SongFilters -Confirmed
        Write-Host ""
        Write-Host (T 'menu.up_to_date_play')
        Show-LaunchPrompt -GamePath $GamePath -AutoLaunch $AutoLaunch
    } elseif (-not $prev.Dismissed) {
        Show-LaunchPrompt -GamePath $GamePath -AutoLaunch $AutoLaunch
    }
}

# Opens config.txt in whatever's associated with .txt (Notepad on a normal
# Windows install) - the console's Settings entry point, deliberately not a
# console-native settings UI. Windows' ShellExecute (what Start-Process uses
# for a plain file path with no -FilePath pointing at an actual exe) is the
# well-supported case; PowerShell Core on Linux (including a headless/SSH
# session with no GUI editor at all) doesn't have the same guarantee, so a
# failure here falls back to printing the path instead of silently doing
# nothing. Returns $true/$false so the caller decides how to tell the user.
function Open-ConfigInEditor {
    try {
        Start-Process -FilePath $ConfigPath -ErrorAction Stop | Out-Null
        return $true
    } catch {
        return $false
    }
}

function Show-FolderPicker([string]$Description) {
    if ($IsLinux) {
        Write-Host ""
        $path = Read-Host "$Description (Enter full absolute path)"
        return $path.TrimEnd('\').TrimEnd('/')
    }

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
        [System.IO.Directory]::CreateDirectory($Path) | Out-Null
        return $true
    } catch {
        Write-Host (T 'error.cant_create_folder' @{ error = $_.Exception.Message }) -ForegroundColor Red
        return $false
    }
}

function Invoke-RcloneCopy([string]$Source, [string]$Dest, [string[]]$ExtraArgs = @(), [string]$Label = 'sync') {
    # Returns rclone's exit code (0 = success). Invoke-BaseSync needs this to
    # know whether it's actually safe to trust a protected file's post-copy
    # hash as a new baseline - a caller that doesn't care must explicitly
    # discard it (| Out-Null), or the bare exit code would otherwise leak
    # onto the console as stray pipeline output.
    #
    # Always-on troubleshooting log: this console runner streams -P's live
    # progress straight to the inherited console handles (no redirect, unlike
    # the GUI's Start-RcloneCopy), so it can't just capture-and-persist output
    # after the fact without killing that live meter. Instead rclone writes
    # straight to a fresh bin\logs\ file via --log-file, which a live test
    # (2026-09-22) confirmed coexists with -P cleanly - the terminal still
    # animates normally, and the log file gets real per-file detail (-v is
    # added alongside it; without -v a clean transfer logs nothing at all).
    $savedBuffer = Enter-NoScrollBuffer
    try {
        $quotedSource = ConvertTo-QuotedArg $Source
        $quotedDest   = ConvertTo-QuotedArg $Dest
        $quotedCommonArgs = $CommonArgs | ForEach-Object { ConvertTo-QuotedArg $_ }
        $logPath = New-RcloneLogPath $Label
        $quotedLogArgs = if ($logPath) { @('-v', '--log-file', (ConvertTo-QuotedArg $logPath)) } else { @() }
        # $ExtraArgs carries --exclude <pattern> pairs; a pattern with a space
        # (a moddable file the user chose to keep) must be quoted like everything
        # else or rclone splits it into two argv tokens.
        $quotedExtra  = $ExtraArgs | ForEach-Object { ConvertTo-QuotedArg $_ }
        $argLine = (@('copy', $quotedSource, $quotedDest) + $quotedCommonArgs + $quotedLogArgs + $quotedExtra) -join ' '
        $proc = Start-Process -FilePath $Rclone -ArgumentList $argLine -NoNewWindow -Wait -PassThru
        if ($logPath) { Invoke-RcloneLogRotation }
        return $proc.ExitCode
    } finally {
        Exit-NoScrollBuffer $savedBuffer
    }
}

function Invoke-BaseSync([string]$GamePath, [string[]]$ExtraExcludes = @()) {
    Write-Host (T 'sync.base')
    $excludeArgs = @('--exclude', 'maps/**')
    # config.xml is the game's local settings file (resolution, windowed vs
    # fullscreen, etc). Fetch it once on a fresh install, then never overwrite
    # it - syncing the server's copy was resetting people's settings on every
    # update.
    if (Test-Path -LiteralPath ([System.IO.Path]::Combine($GamePath, 'config.xml'))) {
        $excludeArgs += @('--exclude', '/config.xml')
    }
    foreach ($e in $ExtraExcludes) { $excludeArgs += @('--exclude', $e) }
    $code = Invoke-RcloneCopy "$Conn`LegacyPC - Game" $GamePath $excludeArgs -Label 'basesync'
    # Only trust a protected file's post-copy hash as a new baseline when the
    # copy actually succeeded - a failed/partial sync must not get recorded
    # as "this is what we wrote", or a real update that never landed would
    # look up-to-date to every future check.
    if ($code -eq 0) { Update-ProtectedFileHashes -GamePath $GamePath -KeepFiles $ExtraExcludes }
    Write-Host ""
}

function Invoke-EditionSync([string]$GamePath, [string]$Edition, [string[]]$SongCodes = $null) {
    Write-Host (T 'sync.edition' @{ edition = (Format-EditionDisplay $Edition) })
    # Join-Path twice, not "maps\$Edition" as one segment - Join-Path only
    # inserts the correct separator BETWEEN its two arguments, it doesn't
    # fix a separator embedded INSIDE a string handed to it. On Linux '\'
    # isn't a path separator at all (just an ordinary filename character),
    # so that used to build a literal "maps\<edition>" file/folder name
    # instead of a maps/<edition> path - found reviewing PR #1 (native
    # Linux support): AUTO-mode downloads were unaffected (Invoke-AllMapsSync
    # only ever does Join-Path $GamePath 'maps', no embedded separator) but
    # downloading a SPECIFIC edition would silently write to the wrong path.
    Invoke-RcloneCopy "$Conn`maps/$Edition" (Join-Path (Join-Path $GamePath 'maps') $Edition) (Get-SongFilterArgs -Edition $Edition -Songs $SongCodes -GamePath $GamePath) -Label "edition-$Edition" | Out-Null
    Write-Host ""
}

function Invoke-AllMapsSync([string]$GamePath, [switch]$Confirmed) {
    $mapsDir = Join-Path $GamePath 'maps'
    if (-not $Confirmed -and (Test-GameFolder $GamePath) -and -not (Test-Path -LiteralPath $mapsDir)) {
        Write-Host (T 'sync.maps_missing_warn') -ForegroundColor Yellow
        Write-Host "  $mapsDir"
        Write-Host (T 'sync.maps_missing_level')
        Write-Host (T 'sync.maps_missing_size')
        if (-not (Confirm-YesNo (T 'sync.maps_confirm_whole'))) {
            Write-Host (T 'common.skipped')
            return
        }
    }
    Write-Host (T 'sync.all_editions')
    Invoke-RcloneCopy "$Conn`maps" $mapsDir (Get-SongFilterArgs -GamePath $GamePath) -Label 'allmaps' | Out-Null
    Write-Host ""
}

function Invoke-Update([string]$GamePath, [string]$Editions, [string[]]$BaseExcludes = @(), [string]$SongFilters = '', [switch]$Confirmed) {
    Invoke-BaseSync $GamePath $BaseExcludes
    if ($Editions.ToUpper() -eq 'AUTO') {
        Invoke-AllMapsSync $GamePath -Confirmed:$Confirmed
    } else {
        $list = $Editions -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' }
        foreach ($ed in $list) { Invoke-EditionSync $GamePath $ed (Get-EffectiveSongs $ed $SongFilters) }
    }
    Write-Host (HR)
    Write-Host ("  " + (T 'common.done'))
    Write-Host (HR)
}

function Show-UpdatePreview {
    param([string]$GamePath, [string]$Editions, [string]$SongFilters = '')

    # Returns @{ Proceed; Dismissed; BaseExcludes }.
    #   Proceed   - caller should run the real sync now
    #   Dismissed - user explicitly backed out (cancel / declined a warning /
    #               server unreachable); distinct from "nothing to download",
    #               where both Proceed and Dismissed are false.
    # Runs the real sync commands with --dry-run first so the user sees
    # exactly what would download (and nothing does) before committing.
    $result = @{ Proceed = $false; Dismissed = $false; BaseExcludes = @() }

    Write-Host (T 'preview.checking')

    $plan = Get-UpdatePlan -GamePath $GamePath -Editions $Editions -SongFilters $SongFilters

    # A wrong game-folder level means every check would come back "missing"
    # and re-download the whole library into the wrong place. Say so up front
    # (Get-UpdatePlan bailed before the slow scan), unless they insist.
    if ($plan.WrongLevel) {
        Write-Host ""
        Write-Host (T 'preview.wrong_level_warn') -ForegroundColor Yellow
        Write-Host "  $GamePath" -ForegroundColor Yellow
        Write-Host (T 'preview.wrong_level_real') -ForegroundColor Yellow
        Write-Host "  $($plan.BetterPath)" -ForegroundColor Yellow
        Write-Host ""
        Write-Host (T 'preview.wrong_level_refetch')
        Write-Host (T 'preview.wrong_level_fix')
        Write-Host ""
        if (-not (Confirm-YesNo (T 'preview.wrong_level_ignore'))) {
            $result.Dismissed = $true
            return $result
        }
        $plan = Get-UpdatePlan -GamePath $GamePath -Editions $Editions -SongFilters $SongFilters -IgnoreWrongLevel
    }

    if (-not $plan.Ok) {
        Write-Host ""
        Write-Host (T 'preview.net_fail') -ForegroundColor Yellow
        $result.Dismissed = $true
        return $result
    }

    $baseNormal = @($plan.BaseNormal)
    $baseAsk    = @($plan.BaseAsk)
    $songFiles  = @($plan.SongFilesFlat)

    Write-Host ""
    Write-Host (HR)
    Write-Host ("  " + (T 'preview.header'))
    Write-Host (HR)
    Write-Host ""

    if ($plan.TotalFiles -eq 0) {
        Write-Host (T 'preview.up_to_date') -ForegroundColor Green
        Write-Host ""
        Write-Host (T 'preview.have_counts' @{ editions = $plan.LocalEditions; songs = $plan.LocalSongs })
        Write-Host (T 'preview.nothing_to_download')
        Write-Host ""
        return $result
    }

    if ($plan.GamePresent -and $plan.MapsMissing) {
        Write-Host (T 'preview.maps_missing_warn') -ForegroundColor Yellow
        Write-Host ""
    }

    if ($baseNormal.Count -gt 0) {
        $baseLine = T 'preview.base_line' @{ count = $baseNormal.Count }
        if ($baseAsk.Count -gt 0) { $baseLine += (T 'preview.base_line_mod_suffix' @{ count = $baseAsk.Count }) }
        Write-Host $baseLine
    } elseif ($baseAsk.Count -gt 0) {
        Write-Host (T 'preview.base_mod_only' @{ count = $baseAsk.Count })
    } else {
        Write-Host (T 'preview.base_up_to_date')
    }
    if ($plan.KeptSettings) { Write-Host (T 'preview.kept_settings') }

    if (@($plan.Songs).Count -gt 0) {
        Write-Host ""
        Write-Host (T 'preview.songs_header')
        foreach ($s in $plan.Songs) {
            $disp = Format-EditionDisplay $s.Edition
            Write-Host (T 'preview.song_line' @{ edition = $disp.PadRight(12); count = $s.Count })
        }
    } else {
        Write-Host (T 'preview.songs_up_to_date')
    }

    Write-Host ""
    Write-Host (T 'preview.total' @{ files = $plan.TotalFiles; size = (Format-Bytes $plan.TotalBytes) })
    Write-Host ""

    # Moddable base files: ask one at a time so an update can't silently
    # clobber a patched exe or the Kinect shim.
    $excludes = @()
    foreach ($pf in $baseAsk) {
        $leaf = Split-Path -Leaf $pf
        Write-Host (T 'preview.mod_differs' @{ name = $leaf }) -ForegroundColor Yellow
        Write-Host (T 'preview.mod_not_modded')
        Write-Host (T 'preview.mod_modded')
        if (-not (Confirm-YesNo (T 'preview.mod_overwrite_q' @{ name = $leaf }))) {
            $excludes += $pf
            Write-Host (T 'preview.mod_keeping' @{ name = $leaf })
        }
        Write-Host ""
    }
    $result.BaseExcludes = $excludes

    if (($baseNormal.Count + $songFiles.Count + $baseAsk.Count - $excludes.Count) -le 0) {
        Write-Host (T 'preview.nothing_left') -ForegroundColor Green
        Write-Host ""
        return $result
    }

    while ($true) {
        Write-Host (T 'preview.opt_download')
        Write-Host (T 'preview.opt_filelist')
        Write-Host (T 'preview.opt_cancel')
        $c = Read-Host (T 'common.choose_1_3')
        if ($c -eq '1') { $result.Proceed = $true; return $result }
        if ($c -eq '3') { $result.Dismissed = $true; return $result }
        if ($c -eq '2') {
            Write-Host ""
            if ($baseNormal.Count -gt 0) {
                Write-Host (T 'preview.list_base')
                foreach ($f in $baseNormal) { Write-Host "  $f" }
            }
            foreach ($pf in $baseAsk) {
                $tag = if ($excludes -contains $pf) { T 'preview.list_tag_keep' } else { T 'preview.list_tag_overwrite' }
                Write-Host ("  {0}  {1}" -f $pf, $tag)
            }
            if ($plan.KeptSettings) { Write-Host (T 'preview.list_config') }
            if ($songFiles.Count -gt 0) {
                Write-Host (T 'preview.list_songs')
                foreach ($f in ($songFiles | Sort-Object)) { Write-Host "  $f" }
            }
            Write-Host ""
            continue
        }
        Write-Host (T 'preview.choose_1_2_3')
    }
}

function Show-SongBrowser([string]$CurrentEditions, [string]$CurrentSongFilters, [string]$GamePath = '') {
    # Maps/songs picker. Default view is a tree - one row per edition with a
    # tri-state mark (x / [ ] / [square]-partial) and Right/Left to expand
    # it into its songs, each with their own checkbox. Typing a search, or
    # setting the Difficulty/Effort filter, flips the same screen to a flat,
    # sortable list of matching songs across every edition instead. Returns:
    #   @{ Action = 'Cancel' }
    #   @{ Action = 'Confirm'; Editions = <csv>; SongFilters = <raw SONGFILTERS string> }
    Write-Host ""
    Write-Host (T 'songbrowser.loading')
    $catalog = @(Get-SongCatalog)
    if ($catalog.Count -eq 0) {
        Write-Host (T 'songbrowser.load_failed') -ForegroundColor Yellow
        Pause-Continue
        return @{ Action = 'Cancel' }
    }

    $ctx = Initialize-SongSelectionContext -Catalog $catalog -CurrentEditions $CurrentEditions -CurrentSongFilters $CurrentSongFilters
    $rows            = $ctx.Rows
    $byEdition       = $ctx.ByEdition
    $catalogEditions = $ctx.CatalogEditions
    $selectedKeys    = $ctx.SelectedKeys
    $rowByKey = @{}
    foreach ($r in $rows) { $rowByKey["$($r.Edition)|$($r.Code)"] = $r }

    # "Keep my version" locks (KEEPSONGS), toggled with F7 on a song row. Only
    # a song that's really on disk can be kept (built lazily on first use).
    # Returned as KeepSongs when the picker is confirmed.
    $keepSet = Get-KeepKeySet
    $localKeys = $null

    $expanded         = New-Object System.Collections.Generic.HashSet[string]
    $search           = ''
    $editionFilter    = 'ALL'
    $difficultyFilter = 'ALL'
    $effortFilter     = 'ALL'
    $sortColumn       = 0
    $sortAscending    = $true
    $cursor           = 0
    $viewStart        = 0

    # Sort-Object's calculated-property scriptblocks (the -Property
    # @{Expression=...} form below) are invoked with the current object
    # bound to $_, the same convention as Where-Object/ForEach-Object -
    # NOT called with it as a positional argument the way $applyEditionCheck-
    # style scriptblocks elsewhere in this codebase are. A `param($r)`
    # scriptblock here never receives the row at all ($r is always $null
    # inside it), so every row's sort key silently evaluated to nothing and
    # Sort-Object fell back to an arbitrary internal order - sorting (and
    # therefore F5/F6, which only change $sortColumn/$sortAscending) was
    # completely inert. Confirmed both the bug and the fix with an isolated
    # Sort-Object test before touching this.
    $sortFields = @(
        { if ([string]::IsNullOrWhiteSpace($_.Title)) { $_.Code } else { $_.Title } }
        { [string]$_.Artist }
        { Format-EditionDisplay $_.Edition }
        { Format-DifficultyTier $_.Difficulty }
        { Format-EffortTier $_.Effort }
    )

    function Get-EditionTriMark([string]$Edition) {
        $codes = @($byEdition[$Edition])
        $checked = @($codes | Where-Object { $selectedKeys.Contains("$Edition|$_") }).Count
        if ($checked -eq 0) { return ' ' }
        if ($checked -eq $codes.Count) { return 'x' }
        return [char]0x25A0   # filled square - the "partial" glyph
    }

    $savedBuffer = Enter-NoScrollBuffer
    # Same defensive try/catch every other console-mode call in this file
    # already uses (Enter-NoScrollBuffer, Exit-NoScrollBuffer,
    # Reset-ConsoleInputMode) - CursorVisible needs a real console screen
    # buffer handle and throws "The handle is invalid" whenever one isn't
    # available (stdout redirected/piped, some non-standard terminals),
    # which would otherwise crash the whole picker with a raw exception
    # instead of just leaving the cursor visible.
    try { [Console]::CursorVisible = $false } catch { }
    try {
        while ($true) {
            $active = ($search -ne '') -or ($editionFilter -ne 'ALL') -or ($difficultyFilter -ne 'ALL') -or ($effortFilter -ne 'ALL')

            # Build this frame's visible rows. Every row is tagged Kind
            # 'Edition' (tri-state, toggling it selects/clears the whole
            # edition) or 'Song' (plain toggle) - Enter handling below is
            # identical either way, only rendering differs.
            #
            # $visible/$filtered are [List[object]], not a plain array built
            # with "+=" - PowerShell's array += allocates and copies a whole
            # NEW array on every single append, making a loop that does it
            # ~1000 times O(n^2). This redraws on every keystroke while
            # typing a search (no debounce here the way the GUI's search
            # box has - ReadKey already blocks between real keystrokes, so
            # one is enough), and profiling against the real ~1000-row
            # catalog measured this specific pattern as the majority of a
            # single frame's cost (as much as ~150ms of it) - typing felt
            # laggy because of it. List[object].Add() is O(1) amortized, and
            # every other place $visible/$filtered are used (.Count, [i]
            # indexing) works identically on a List as on an array, so this
            # is a drop-in swap, not a behavior change. Where-Object also
            # replaced with a plain foreach+continue for the same reason
            # (real, if smaller, per-item pipeline overhead of its own).
            $visible = [System.Collections.Generic.List[object]]::new()
            if ($active) {
                $q = $search.Trim().ToLowerInvariant()
                $filtered = [System.Collections.Generic.List[object]]::new()
                foreach ($r in $rows) {
                    if ($editionFilter -ne 'ALL' -and $r.Edition -ne $editionFilter) { continue }
                    if ($difficultyFilter -ne 'ALL' -and $r.Difficulty -ne $difficultyFilter) { continue }
                    if ($effortFilter -ne 'ALL' -and $r.Effort -ne $effortFilter) { continue }
                    if ($q -ne '' -and -not (([string]$r.Title).ToLowerInvariant().Contains($q) -or ([string]$r.Artist).ToLowerInvariant().Contains($q) -or $r.Code.ToLowerInvariant().Contains($q))) { continue }
                    $filtered.Add($r)
                }
                $sorted = @($filtered | Sort-Object -Property @{ Expression = $sortFields[$sortColumn] })
                if (-not $sortAscending) { [array]::Reverse($sorted) }
                foreach ($r in $sorted) { $visible.Add([PSCustomObject]@{ Kind = 'Song'; Edition = $r.Edition; Code = $r.Code; Indent = $false }) }
            } else {
                foreach ($ed in $catalogEditions) {
                    $visible.Add([PSCustomObject]@{ Kind = 'Edition'; Edition = $ed; Code = $null; Indent = $false })
                    if ($expanded.Contains($ed)) {
                        foreach ($code in $byEdition[$ed]) { $visible.Add([PSCustomObject]@{ Kind = 'Song'; Edition = $ed; Code = $code; Indent = $true }) }
                    }
                }
            }

            # Two virtual footer rows the cursor can land on, same pattern as
            # the edition-only checklist this replaced.
            $footerStart = $visible.Count
            $totalRows = $visible.Count + 2
            if ($cursor -ge $totalRows) { $cursor = $totalRows - 1 }
            if ($cursor -lt 0) { $cursor = 0 }

            Clear-Host
            # $(...), not plain (...) - a plain parenthesized `if` used as a
            # call argument gets parsed as trying to run a COMMAND named
            # "if" ("The term 'if' is not recognized..."), not as an
            # expression - `if` is only special-cased as a value on the
            # right-hand side of an assignment ($x = if (...) {...}), not
            # inside a bare sub-expression. $(...) (the subexpression
            # operator) does accept a full statement, if included.
            Write-Host $(if ($active) { T 'songbrowser.help' } else { T 'songbrowser.tree_help' })
            Write-Host (T 'songbrowser.keep_help')
            $editionLabel = if ($editionFilter -eq 'ALL') { T 'songbrowser.filter_all' } else { Format-EditionDisplay $editionFilter }
            $diffLabel    = if ($difficultyFilter -eq 'ALL') { T 'songbrowser.filter_all' } else { Format-DifficultyTier $difficultyFilter }
            $effortLabel  = if ($effortFilter -eq 'ALL') { T 'songbrowser.filter_all' } else { Format-EffortTier $effortFilter }
            Write-Host (T 'songbrowser.search_label' @{ text = $search })
            Write-Host ("  " + (T 'songbrowser.filter_edition' @{ value = $editionLabel }) + "    " + (T 'songbrowser.filter_difficulty' @{ value = $diffLabel }) + "    " + (T 'songbrowser.filter_effort' @{ value = $effortLabel }))
            Write-Host (T 'songbrowser.status_line' @{ shown = $visible.Count; total = $rows.Count; selected = $selectedKeys.Count })
            Write-Host ""

            $consoleHeight = try { [Console]::WindowHeight } catch { 30 }
            $viewportRows = [Math]::Max(5, $consoleHeight - 11)
            if ($cursor -lt $viewStart) { $viewStart = $cursor }
            if ($cursor -ge $viewStart + $viewportRows) { $viewStart = $cursor - $viewportRows + 1 }
            if ($viewStart -lt 0) { $viewStart = 0 }

            if ($visible.Count -eq 0) {
                Write-Host (T 'songbrowser.empty_results')
            } else {
                $viewEnd = [Math]::Min($visible.Count, $viewStart + $viewportRows) - 1
                for ($i = $viewStart; $i -le $viewEnd; $i++) {
                    $row = $visible[$i]
                    $pointer = if ($i -eq $cursor) { '>' } else { ' ' }
                    $indent = if ($row.Indent) { '    ' } else { '' }
                    if ($row.Kind -eq 'Edition') {
                        $mark = Get-EditionTriMark $row.Edition
                        # Plain ASCII, not Unicode triangles (was [char]0x25BC
                        # / [char]0x25B6) - Ven found the right-pointing
                        # triangle rendering as a broken glyph in their
                        # terminal while the down-pointing one (only ever
                        # shown once something is expanded) rendered fine, a
                        # console-font glyph-coverage gap between two
                        # codepoints in the same Unicode block, not
                        # something fixable by picking a "better" pair of
                        # Unicode arrows - no font coverage guarantee
                        # extends across an entire block. +/- (not '>', which
                        # the cursor $pointer to its left already uses) is
                        # the classic tree-view collapsed/expanded
                        # convention and is guaranteed to render in any
                        # console font since it's plain ASCII.
                        $arrow = if ($expanded.Contains($row.Edition)) { '-' } else { '+' }
                        $count = @($byEdition[$row.Edition]).Count
                        $checkedCount = @($byEdition[$row.Edition] | Where-Object { $selectedKeys.Contains("$($row.Edition)|$_") }).Count
                        $countText = if ($checkedCount -gt 0 -and $checkedCount -lt $count) { "$checkedCount/$count" } else { "$count" }
                        Write-Host ("{0}  [{1}] {2} {3} ({4} songs)" -f $pointer, $mark, $arrow, (Format-EditionDisplay $row.Edition), $countText)
                    } else {
                        $r = $rowByKey["$($row.Edition)|$($row.Code)"]
                        $mark = if ($selectedKeys.Contains("$($row.Edition)|$($row.Code)")) { 'x' } else { ' ' }
                        $keptStar = if ($keepSet.Contains("$($row.Edition)|$($row.Code)")) { '*' } else { ' ' }
                        $title = if ($r) { Get-SongTitleForDisplay $r $ctx.DuplicateKeys } else { $row.Code }
                        if ($active) {
                            $line = "{0}{1}  [{2}]{6}{3,-40} {4,-22} {5,-14}" -f $pointer, $indent, $mark, ($title.Substring(0, [Math]::Min(40, $title.Length))), (([string]$r.Artist).Substring(0, [Math]::Min(22, ([string]$r.Artist).Length))), (Format-EditionDisplay $row.Edition), $keptStar
                        } else {
                            $artist = if ($r) { [string]$r.Artist } else { '' }
                            $line = "{0}{1}  [{2}]{5}{3,-42} {4}" -f $pointer, $indent, $mark, ($title.Substring(0, [Math]::Min(42, $title.Length))), $artist, $keptStar
                        }
                        Write-Host $line
                    }
                }
            }
            Write-Host ""
            $doneIdx = $footerStart
            $cancelIdx = $footerStart + 1
            # Same $(...) fix as above - a plain parenthesized `if` as a
            # call argument (or, here, as one operand of string
            # concatenation) is parsed as an attempt to run a command
            # named "if".
            Write-Host ($(if ($cursor -eq $doneIdx) { '>' } else { ' ' }) + "  " + (T 'songbrowser.done'))
            Write-Host ($(if ($cursor -eq $cancelIdx) { '>' } else { ' ' }) + "  " + (T 'songbrowser.cancel'))

            $key = [Console]::ReadKey($true)
            if ($key.Key -eq 'UpArrow') { $cursor--; if ($cursor -lt 0) { $cursor = $totalRows - 1 }; continue }
            if ($key.Key -eq 'DownArrow') { $cursor++; if ($cursor -ge $totalRows) { $cursor = 0 }; continue }
            if ($key.Key -eq 'PageUp') { $cursor = [Math]::Max(0, $cursor - $viewportRows); continue }
            if ($key.Key -eq 'PageDown') { $cursor = [Math]::Min($totalRows - 1, $cursor + $viewportRows); continue }
            if ($key.Key -eq 'Home') { $cursor = 0; continue }
            if ($key.Key -eq 'End') { $cursor = $totalRows - 1; continue }
            if ($key.Key -eq 'Escape') { return @{ Action = 'Cancel' } }
            if ((-not $active) -and $key.Key -eq 'RightArrow' -and $cursor -lt $visible.Count) {
                $row = $visible[$cursor]
                if ($row.Kind -eq 'Edition') { [void]$expanded.Add($row.Edition) }
                continue
            }
            if ((-not $active) -and $key.Key -eq 'LeftArrow' -and $cursor -lt $visible.Count) {
                $row = $visible[$cursor]
                if ($row.Kind -eq 'Edition') {
                    [void]$expanded.Remove($row.Edition)
                } else {
                    [void]$expanded.Remove($row.Edition)
                    # Snap the cursor back to the parent edition's own row,
                    # since the child row it was on just disappeared.
                    for ($i = 0; $i -lt $visible.Count; $i++) {
                        if ($visible[$i].Kind -eq 'Edition' -and $visible[$i].Edition -eq $row.Edition) { $cursor = $i; break }
                    }
                }
                continue
            }
            if ($active -and $key.Key -eq 'F5') {
                $sortColumn = ($sortColumn + 1) % $sortFields.Count
                $cursor = 0; $viewStart = 0; continue
            }
            if ($active -and $key.Key -eq 'F6') { $sortAscending = -not $sortAscending; continue }
            if ($key.Key -eq 'F2') {
                $opts = @('ALL') + $catalogEditions
                $idx = [Array]::IndexOf($opts, $editionFilter)
                $editionFilter = $opts[($idx + 1) % $opts.Count]
                $cursor = 0; $viewStart = 0; continue
            }
            if ($key.Key -eq 'F3') {
                $opts = @('ALL', 1, 2, 3, 4)
                $idx = [Array]::IndexOf($opts, $difficultyFilter)
                $difficultyFilter = $opts[($idx + 1) % $opts.Count]
                $cursor = 0; $viewStart = 0; continue
            }
            if ($key.Key -eq 'F4') {
                $opts = @('ALL', 0, 1, 2, 3, 4)
                $idx = [Array]::IndexOf($opts, $effortFilter)
                $effortFilter = $opts[($idx + 1) % $opts.Count]
                $cursor = 0; $viewStart = 0; continue
            }
            if ($key.Key -eq 'F7') {
                if ($cursor -lt $visible.Count -and $visible[$cursor].Kind -eq 'Song') {
                    $k = "$($visible[$cursor].Edition)|$($visible[$cursor].Code)"
                    if ($null -eq $localKeys) { $localKeys = Get-LocalSongKeySet $GamePath }
                    if ($keepSet.Contains($k)) { [void]$keepSet.Remove($k) }
                    elseif ($localKeys.Contains($k)) { [void]$keepSet.Add($k) }
                    else { Pause-Brief (T 'gui.songbrowser_keep_none_local') 2 }
                }
                continue
            }
            if ($key.Key -eq 'Backspace') {
                # Only reset the cursor when Backspace actually changed
                # something - pressing it in the tree view (search already
                # empty, nothing to delete) used to jump the cursor back to
                # the very top of the list for no reason.
                if ($search.Length -gt 0) { $search = $search.Substring(0, $search.Length - 1); $cursor = 0; $viewStart = 0 }
                continue
            }
            if ($key.Key -eq 'Enter') {
                if ($cursor -eq $doneIdx) {
                    $resolved = Resolve-SongSelection -Context $ctx -SelectedKeys $selectedKeys
                    if ($null -eq $resolved) {
                        Write-Host ""
                        Write-Host (T 'songbrowser.none_selected_warn') -ForegroundColor Yellow
                        if (-not (Confirm-YesNo (T 'maps.go_back_list'))) { return @{ Action = 'Cancel' } }
                        continue
                    }
                    return @{ Action = 'Confirm'; Editions = $resolved.Editions; SongFilters = $resolved.SongFilters; KeepSongs = (Format-KeepKeySet $keepSet); Catalog = $catalog }
                }
                if ($cursor -eq $cancelIdx) { return @{ Action = 'Cancel' } }
                if ($cursor -lt $visible.Count) {
                    $row = $visible[$cursor]
                    if ($row.Kind -eq 'Edition') {
                        $goFull = (Get-EditionTriMark $row.Edition) -ne 'x'
                        foreach ($code in $byEdition[$row.Edition]) {
                            $k = "$($row.Edition)|$code"
                            if ($goFull) { [void]$selectedKeys.Add($k) } else { [void]$selectedKeys.Remove($k) }
                        }
                    } else {
                        $k = "$($row.Edition)|$($row.Code)"
                        if ($selectedKeys.Contains($k)) { [void]$selectedKeys.Remove($k) } else { [void]$selectedKeys.Add($k) }
                    }
                }
                continue
            }
            # Any other printable character -> append to the search text
            # (flips the view to the flat sortable table, see $active above).
            if ($key.KeyChar -and -not [char]::IsControl($key.KeyChar)) {
                $search += $key.KeyChar
                $cursor = 0; $viewStart = 0
            }
        }
    } finally {
        # try/catch here isn't just consistency - an unhandled exception
        # from this line would abort the REST of this finally block too,
        # skipping Exit-NoScrollBuffer/Reset-ConsoleInputMode and leaving
        # the console's buffer size/input mode unrestored.
        try { [Console]::CursorVisible = $true } catch { }
        Exit-NoScrollBuffer $savedBuffer
        Reset-ConsoleInputMode
    }
}

function Choose-Language([string]$CurrentCode) {
    $langs = @($AvailableLangs)
    if ($langs.Count -eq 0) { return $CurrentCode }

    Write-Host ""
    Write-Host (HR)
    Write-Host ("  " + (T 'lang.header'))
    Write-Host (HR)
    Write-Host ""

    $cur = $langs | Where-Object { $_.Code -eq $CurrentCode } | Select-Object -First 1
    if ($cur) {
        Write-Host (T 'lang.current' @{ name = ("{0} ({1})" -f $cur.NativeName, $cur.Name) })
        Write-Host ""
    }
    for ($i = 0; $i -lt $langs.Count; $i++) {
        Write-Host (T 'lang.item' @{ n = ($i + 1); native = $langs[$i].NativeName; english = $langs[$i].Name })
    }
    Write-Host ("  [0] " + (T 'lang.keep'))
    Write-Host ""

    while ($true) {
        $ans = Read-Host (T 'lang.prompt')
        if ($ans -eq '0' -or $ans -eq '') { return $CurrentCode }
        $n = 0
        if ([int]::TryParse($ans, [ref]$n) -and $n -ge 1 -and $n -le $langs.Count) {
            $pick = $langs[$n - 1]
            $null = Initialize-Language -Code $pick.Code
            Write-Host (T 'lang.changed' @{ name = ("{0} ({1})" -f $pick.NativeName, $pick.Name) })
            return $pick.Code
        }
        Write-Host (T 'common.invalid_choice')
    }
}

function Show-RequirementsWizard([string]$GamePath) {
    # Status + optional install for the software Legacy.exe needs beyond
    # what Windows ships (Kinect SDKs / VC++ redistributables / DirectX
    # runtime - see Get-RequirementDefinitions in the Core module for the
    # full rationale, verified against the real PE import table). Plain
    # ASCII status tags, not the 0x2713/0x2717 glyphs the GUI uses - this
    # console avoids relying on Unicode glyph coverage in an arbitrary
    # terminal font (see the collapsed/expanded arrow glyph fix elsewhere
    # in this project's history). Synchronous like the rest of this
    # console UI - runs to completion before returning, which is what
    # gives it the "blocks progressing" behavior the GUI achieves with a
    # modal dialog; called from one place only (the one-time first-run
    # flow at the bottom of this file, and the [5] main-menu option below)
    # never automatically, in Linux.
    Write-Host ""
    Write-Host (HR)
    Write-Host ("  " + (T 'menu.requirements_title'))
    Write-Host (HR)
    Write-Host ""
    Write-Host (T 'menu.requirements_intro')
    Write-Host ""

    $status = Get-RequirementsStatus -GamePath $GamePath
    foreach ($it in $status) {
        $tag = if ($it.Installed) { T 'menu.requirements_installed' } else { T 'menu.requirements_missing' }
        Write-Host ("  [{0,-7}] {1}" -f $tag, $it.Name)
    }
    Write-Host ""

    $missing = @($status | Where-Object { -not $_.Installed })
    if ($missing.Count -eq 0) {
        Write-Host (T 'menu.requirements_all_done')
        Pause-Continue
        return
    }

    foreach ($item in $missing) {
        if (-not (Confirm-YesNo (T 'menu.requirements_install_prompt' @{ name = $item.Name }))) { continue }
        Write-Host (T 'menu.requirements_downloading' @{ name = $item.Name })
        # A bundled copy resolves instantly inside Get-RequirementInstaller
        # with no callback invocations at all, and so does a missing
        # FetchUrl (directx has none - it's bundled-only) - only print an
        # in-place percent line for an item that's actually about to hit
        # the network, matching Get-RequirementInstaller's own "bundled,
        # then FetchUrl" gate.
        $willDownload = (-not $item.BundledPath) -and $item.FetchUrl
        # GetNewClosure() is required, not optional - a plain {} scriptblock
        # resolves free variables like $item in the CALLER's scope at
        # invocation time (Get-RequirementInstaller's own scope in the Core
        # module), not the scope it was written in.
        $progressCallback = {
            param($pct, $received, $total)
            $line = if ($pct -ge 0) {
                T 'menu.requirements_downloading_pct' @{ name = $item.Name; pct = $pct }
            } else {
                T 'menu.requirements_downloading' @{ name = $item.Name }
            }
            # Pad to a fixed width and `r back to column 0 so a shorter
            # line (e.g. 100% -> a later 9%) doesn't leave stray
            # characters from the previous, longer line behind.
            Write-Host -NoNewline ("`r  " + $line.PadRight(70))
        }.GetNewClosure()
        $onInstalling = { Write-Host (T 'menu.requirements_installing' @{ name = $item.Name }) }.GetNewClosure()

        $result = Invoke-RequirementInstall -Item $item -GamePath $GamePath -ProgressCallback $progressCallback -OnInstalling $onInstalling
        if ($willDownload) { Write-Host "" }

        if ($result.Outcome -eq 'DownloadFailed') {
            Write-Host (T 'menu.requirements_download_failed' @{ name = $item.Name; url = $result.OfficialUrl }) -ForegroundColor Yellow
            continue
        }
        switch ($result.Outcome) {
            'InstalledRebootRequired' { Write-Host (T 'menu.requirements_install_done_reboot' @{ name = $item.Name }) -ForegroundColor Green }
            'Installed'               { Write-Host (T 'menu.requirements_install_done' @{ name = $item.Name }) -ForegroundColor Green }
            'Cancelled'               { Write-Host (T 'menu.requirements_install_cancelled' @{ name = $item.Name }) -ForegroundColor Yellow }
            'Failed'                  { Write-Host (T 'menu.requirements_install_failed' @{ name = $item.Name; code = $result.ExitCode }) -ForegroundColor Red }
        }
    }

    Write-Host ""
    $finalStatus = Get-RequirementsStatus -GamePath $GamePath
    $stillMissing = @($finalStatus | Where-Object { -not $_.Installed })
    if ($stillMissing.Count -eq 0) {
        Write-Host (T 'menu.requirements_all_done')
    } else {
        Write-Host (T 'menu.requirements_some_missing')
    }
    Pause-Continue
}

function Run-MapsWizard([string]$GamePath, [string]$CurrentEditions, [string]$CurrentSongFilters = '') {
    # Returns $null (no change) or @{ Editions = <csv|'AUTO'>; SongFilters = <raw SONGFILTERS string> }.
    while ($true) {
        Write-Host (HR)
        Write-Host ("  " + (T 'maps.header'))
        Write-Host (HR)
        Write-Host ""
        Write-Host (T 'maps.opt_everything')
        Write-Host (T 'maps.opt_specific')
        Write-Host (T 'maps.opt_mainmenu')
        $choice = Read-Host (T 'common.choose_1_3')

        if ($choice -eq '3') { return $null }

        if ($choice -eq '1') {
            Write-Host ""
            $prev = Show-UpdatePreview -GamePath $GamePath -Editions 'AUTO'
            if ($prev.Proceed) {
                Write-Host ""
                Invoke-Update -GamePath $GamePath -Editions 'AUTO' -BaseExcludes $prev.BaseExcludes -Confirmed
            }
            return @{ Editions = 'AUTO'; SongFilters = '' }
        }

        if ($choice -ne '2') {
            Pause-Brief (T 'common.not_valid_option')
            continue
        }

        $browse = Show-SongBrowser -CurrentEditions $CurrentEditions -CurrentSongFilters $CurrentSongFilters -GamePath $GamePath
        Write-Host ""
        if ($browse.Action -ne 'Confirm') { continue }
        # Keep-my-version locks are saved at the picker's Done, like the
        # selection itself is (see below) - and before the preview, so the
        # scan and any download that follows already honor them.
        $priorKeep = [string](Load-Config).KeepSongs
        Save-Config @{ KeepSongs = [string]$browse.KeepSongs }

        # The picker's own "Done" is the real confirmation - captured here so
        # it survives regardless of what happens with the preview/download
        # below, matching the GUI's "Select maps / songs" button (which
        # saves on picker-OK, independent of whether an update-check ever
        # runs afterward). This used to only ever return at the very end of
        # the function, after the WHOLE preview flow completed - cancelling
        # the preview (below) looped back to the top of this wizard instead
        # of returning, so the caller's `if ($null -ne $mapsResult)` guard
        # saw $null and silently discarded the entire selection with no
        # warning. Confirmed as a real bug via a live interactive test:
        # picking a song, then cancelling the immediately-following preview,
        # lost the pick entirely even though the preview itself correctly
        # showed it as part of what would download.
        $result = @{ Editions = $browse.Editions; SongFilters = $browse.SongFilters }

        $prev = Show-UpdatePreview -GamePath $GamePath -Editions $browse.Editions -SongFilters $browse.SongFilters
        if ($prev.Dismissed) { return $result }

        # Whole editions dropped, or editions narrowed to fewer songs, may
        # have local files the player no longer wants - asked as one batch
        # below.
        $oldEditionList = @(if ($CurrentEditions.ToUpper() -eq 'AUTO') { Get-LocalEditions $GamePath } else { $CurrentEditions -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' } })
        $newEditionList = @($browse.Editions -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' })
        $removalPlan = @(Get-SongRemovalPlan -OldEditions $oldEditionList -OldSongFilters $CurrentSongFilters -NewEditions $newEditionList -NewSongFilters $browse.SongFilters -Catalog $browse.Catalog)
        # One prompt for the whole batch (was one Y/N per edition, with no
        # way to answer for all of them or back out). Cancel returns $null =
        # "no change": nothing deleted, the new selection is discarded and
        # the pending download below never runs.
        $removalItems = @(Get-SongRemovalPromptItems -Plan $removalPlan -GamePath $GamePath -KeepSongs $browse.KeepSongs)
        if ($removalItems.Count -gt 0) {
            Write-Host ""
            Write-Host (T 'maps.removal_headline')
            Write-Host (T 'maps.removal_hint')
            foreach ($ri in $removalItems) {
                $riDisp = Format-EditionDisplay $ri.Edition
                $riLine = if ($ri.Whole) { T 'maps.removal_item_edition' @{ edition = $riDisp } } else { T 'maps.removal_item_songs' @{ edition = $riDisp; count = $ri.Count } }
                Write-Host ("  - " + $riLine)
            }
            if (@($removalItems | Where-Object { $_.KeptCount -gt 0 }).Count -gt 0) { Write-Host (T 'maps.removal_kept_note') }
            Write-Host ""
            Write-Host ("[1] " + (T 'maps.removal_btn_delete'))
            Write-Host ("[2] " + (T 'maps.removal_btn_keep'))
            Write-Host (T 'preview.opt_cancel')
            while ($true) {
                $rc = Read-Host (T 'common.choose_1_3')
                if ($rc -eq '1' -or $rc -eq '2' -or $rc -eq '3') { break }
                Write-Host (T 'preview.choose_1_2_3')
            }
            if ($rc -eq '3') {
                # Cancel = no change at all, so put the previous locks back (they
                # were saved early only so the preview scan above honored them).
                Save-Config @{ KeepSongs = $priorKeep }
                return $null
            }
            if ($rc -eq '1') {
                foreach ($r in @(Invoke-SongRemovalDelete -Items $removalItems -GamePath $GamePath -KeepSongs $browse.KeepSongs)) {
                    if ($r.Failed) {
                        $failKey = if ($r.Whole) { 'maps.cant_delete' } else { 'maps.cant_delete_songs' }
                        Write-Host (T $failKey @{ edition = $r.Edition }) -ForegroundColor Yellow
                    } elseif ($r.Whole) {
                        Write-Host (T 'maps.deleted' @{ edition = $r.Edition })
                    } else {
                        Write-Host (T 'maps.songs_deleted' @{ count = $r.Count; edition = $r.Edition })
                    }
                }
            } else {
                foreach ($ri in $removalItems) { Write-Host (T 'maps.keeping_untracked' @{ edition = $ri.Edition }) }
            }
        }

        if ($prev.Proceed) {
            Write-Host ""
            Invoke-Update -GamePath $GamePath -Editions $browse.Editions -BaseExcludes $prev.BaseExcludes -SongFilters $browse.SongFilters -Confirmed
        }
        return $result
    }
}

function Run-SetupWizard {
    Write-Host (HR)
    Write-Host ("  " + (T 'setup.welcome_header'))
    Write-Host (HR)
    Write-Host ""
    Write-Host (T 'setup.welcome_body')
    Write-Host ""

    while ($true) {
        Write-Host (T 'setup.opt_have')
        Write-Host (T 'setup.opt_download')
        $choice = Read-Host (T 'common.choose_1_2')

        if ($choice -eq '1') {
            Write-Host ""
            Write-Host (T 'setup.popup_find_exe')
            $path = Show-FolderPicker (T 'setup.picker_have')
            if ($null -eq $path) {
                Write-Host (T 'setup.no_folder_picked')
                Pause-Brief
                continue
            }
            if (-not (Test-GameFolder $path)) {
                Write-Host (T 'setup.no_exe_here')
                if ((Confirm-YesNo (T 'setup.download_into_q')) -and (Ensure-Directory $path)) {
                    Write-Host ""
                    Invoke-BaseSync $path
                }
            }
            return $path
        }

        if ($choice -eq '2') {
            Write-Host ""
            Write-Host (T 'setup.popup_pick_empty')
            $path = Show-FolderPicker (T 'setup.picker_new')
            if ($null -eq $path) {
                Write-Host (T 'setup.no_folder_picked')
                Pause-Brief
                continue
            }
            if (Ensure-Directory $path) {
                Write-Host ""
                Invoke-BaseSync $path
            }
            return $path
        }

        Pause-Brief (T 'common.not_valid_option')
    }
}

# rclone.exe presence / runnability is checked by the entry script
# (LegacyDownloader.ps1) before this interface is loaded.

$cfg = Load-Config
# Captured before the first-run block below can reassign $cfg.GamePath -
# AUTOCHECK must never fire on a fresh setup session, only an existing
# install opening the tool for an unrelated reason.
$isFirstRunSession = [string]::IsNullOrWhiteSpace($cfg.GamePath)

if ([string]::IsNullOrWhiteSpace($cfg.GamePath)) {
    $pickedLang = Choose-Language $cfg.Lang
    if ($pickedLang -ne $cfg.Lang) {
        Save-Config @{ Lang = $pickedLang }
        $cfg = Load-Config
    }

    Write-Host ""
    $gamePath = Run-SetupWizard
    Save-Config @{ GamePath = $gamePath }
    $cfg = Load-Config

    Write-Host ""
    $mapsResult = Run-MapsWizard -GamePath $cfg.GamePath -CurrentEditions $cfg.Editions -CurrentSongFilters $cfg.SongFilters
    if ($null -ne $mapsResult) {
        Save-Config @{ Editions = $mapsResult.Editions; SongFilters = $mapsResult.SongFilters }
        $cfg = Load-Config
    }

    Write-Host ""
    Write-Host (HR)
    if (Test-GameFolder $cfg.GamePath) {
        Write-Host ("  " + (T 'done.all_set'))
        Write-Host (HR)
        Write-Host ""
        Write-Host (T 'done.to_play' @{ path = $cfg.GamePath })
    } else {
        Write-Host ("  " + (T 'done.almost'))
        Write-Host (HR)
        Write-Host ""
        Write-Host (T 'done.not_downloaded' @{ path = $cfg.GamePath })
    }
    # One-time-only requirements check for a brand-new install - the
    # whole surrounding block already only runs once, gated on a missing
    # config.txt, so a single call here (unlike the GUI, which needs two
    # separate hook points because its first-run download is async)
    # covers both the "have" and "download it for me" console paths.
    # Skipped entirely on Linux - see Show-RequirementsWizard.
    if (-not $IsLinux) { Show-RequirementsWizard -GamePath $cfg.GamePath }

    Write-Host ""
    Write-Host (T 'done.come_back')
    Pause-Continue
}

# Sanity-check the saved game folder: if Legacy.exe isn't right there but is
# one level up or down, offer to correct the setting. A wrong level here is
# what makes the tool think no songs are installed and re-download everything.
if (-not [string]::IsNullOrWhiteSpace($cfg.GamePath)) {
    $betterPath = Resolve-GameFolder $cfg.GamePath
    if ($betterPath -and ($betterPath -ne $cfg.GamePath.TrimEnd('\'))) {
        Write-Host ""
        Write-Host (T 'sanity.set_to') -ForegroundColor Yellow
        Write-Host "  $($cfg.GamePath)"
        Write-Host (T 'sanity.exe_actually')
        Write-Host "  $betterPath"
        Write-Host ""
        if (Confirm-YesNo (T 'sanity.point_correct_q')) {
            Save-Config @{ GamePath = $betterPath }
            $cfg = Load-Config
            Write-Host (T 'common.updated') -ForegroundColor Green
            Start-Sleep -Seconds 1
        }
    }
}

# AUTOCHECK: an existing install (never a fresh first-run setup session -
# see $isFirstRunSession above) opening the tool checks for updates
# automatically, once per process start. Windows-only in practice -
# Show-LaunchPrompt/Invoke-CheckAndOfferLaunch already gate the launch
# offer behind -not $IsLinux, but the check itself still runs on Linux too.
if (-not $isFirstRunSession -and $cfg.AutoCheck -and (Test-GameFolder $cfg.GamePath)) {
    Write-Host ""
    Invoke-CheckAndOfferLaunch -GamePath $cfg.GamePath -Editions $cfg.Editions -SongFilters $cfg.SongFilters -AutoLaunch $cfg.AutoLaunch
    Pause-Continue
}

# App self-update check - read-only GitHub API call, once per process
# start, on BOTH Windows and Linux (unlike the game-update AUTOCHECK
# above, this has no file-system side effects of its own). Linux gets the
# notice and can still see the release on GitHub, but the actual swap
# (the 'U' menu option below) is Windows-only - build-release.ps1 only
# ever bundles the Windows rclone.exe, so the whole "replace bin\ from the
# release zip" premise doesn't map onto a Linux install to begin with.
$PendingAppUpdate = $null
if ($cfg.CheckAppUpdates) {
    $appCheck = Test-AppUpdateAvailable
    if ($appCheck.Checked -and $appCheck.Available) { $PendingAppUpdate = $appCheck }
}

while ($true) {
    Clear-Host
    $langEntry = $AvailableLangs | Where-Object { $_.Code -eq $cfg.Lang } | Select-Object -First 1
    $langLabel = if ($langEntry) { $langEntry.NativeName } else { $cfg.Lang }

    $songFilterMap = Get-SongFilterMap $cfg.SongFilters
    $edDisplay = if ($cfg.Editions.ToUpper() -eq 'AUTO') {
        'AUTO'
    } else {
        ($cfg.Editions -split ',' | ForEach-Object {
            $ed = $_.Trim()
            $disp = Format-EditionDisplay $ed
            if ($songFilterMap.Contains($ed)) { $disp + (T 'songbrowser.count_suffix' @{ count = $songFilterMap[$ed].Count }) } else { $disp }
        }) -join ', '
    }

    Write-Host (HR)
    Write-Host ("  " + (T 'menu.title') + " " + $Version)
    Write-Host (T 'menu.game_folder' @{ path = $cfg.GamePath })
    Write-Host (T 'menu.editions' @{ editions = $edDisplay })
    Write-Host (T 'menu.language_line' @{ language = $langLabel })
    Write-Host (HR)
    Write-Host ""
    Write-Host (T 'menu.safety')
    Write-Host ""
    if ($null -ne $PendingAppUpdate) {
        if ($IsLinux) {
            Write-Host (T 'menu.update_available_notice_linux' @{ version = $PendingAppUpdate.LatestVersion; url = $PendingAppUpdate.ReleaseUrl }) -ForegroundColor Green
        } else {
            Write-Host (T 'menu.update_available_notice' @{ version = $PendingAppUpdate.LatestVersion }) -ForegroundColor Green
        }
        Write-Host ""
    }
    Write-Host (T 'menu.opt_download')
    Write-Host (T 'menu.opt_choose')
    Write-Host (T 'menu.opt_folder')
    Write-Host (T 'menu.opt_language')
    Write-Host (T 'menu.opt_settings')
    if (-not $IsLinux) { Write-Host (T 'menu.opt_requirements') }
    # NOT "Write-Host (if (...) {...} else {...})" - a bare if/else isn't a
    # valid expression inside a call's argument parens in PS 5.1 outside an
    # assignment (this exact mistake broke the song picker once before in
    # this project - see 2026-09-14 project history). Assign first instead.
    $exitLine   = if ($IsLinux) { T 'menu.opt_exit' } else { T 'menu.opt_exit_reqs' }
    $choosePrompt = if ($IsLinux) { T 'menu.choose_1_6' } else { T 'menu.choose_1_7' }
    Write-Host $exitLine
    $choice = Read-Host $choosePrompt

    switch ($choice) {
        '1' {
            Write-Host ""
            Invoke-CheckAndOfferLaunch -GamePath $cfg.GamePath -Editions $cfg.Editions -SongFilters $cfg.SongFilters -AutoLaunch $cfg.AutoLaunch
            Pause-Continue
        }
        '2' {
            Write-Host ""
            $mapsResult = Run-MapsWizard -GamePath $cfg.GamePath -CurrentEditions $cfg.Editions -CurrentSongFilters $cfg.SongFilters
            if ($null -ne $mapsResult) {
                Save-Config @{ Editions = $mapsResult.Editions; SongFilters = $mapsResult.SongFilters }
                $cfg = Load-Config
                Write-Host ""
                Write-Host (T 'menu.songs_ready')
                Pause-Brief (T 'common.saved') 2
            }
        }
        '3' {
            Write-Host ""
            Write-Host (T 'menu.popup_change_folder')
            $path = Show-FolderPicker (T 'menu.picker_change')
            if ($null -ne $path) {
                $ok = Test-GameFolder $path
                if (-not $ok) { $ok = Confirm-YesNo (T 'menu.exe_not_found_use_anyway') }
                if ($ok) {
                    Save-Config @{ GamePath = $path }
                    $cfg = Load-Config
                    Write-Host (T 'common.saved')
                    if (-not (Test-GameFolder $path)) {
                        Write-Host (T 'menu.folder_no_game')
                        Pause-Continue
                    } else {
                        Pause-Brief -Seconds 2
                    }
                }
            }
        }
        '4' {
            $pickedLang = Choose-Language $cfg.Lang
            if ($pickedLang -ne $cfg.Lang) {
                Save-Config @{ Lang = $pickedLang }
                $cfg = Load-Config
            }
            Pause-Brief -Seconds 1
        }
        '5' {
            Write-Host ""
            if (Open-ConfigInEditor) {
                Write-Host (T 'menu.settings_opened')
            } else {
                Write-Host (T 'menu.settings_open_failed' @{ path = $ConfigPath }) -ForegroundColor Yellow
            }
            Pause-Continue
        }
        '6' {
            if ($IsLinux) { Exit-Console }
            Show-RequirementsWizard -GamePath $cfg.GamePath
        }
        '7' {
            if ($IsLinux) {
                Pause-Brief (T 'common.not_valid_option')
            } else {
                Exit-Console
            }
        }
        'U' {
            # Deliberately not a numbered menu item - it's only ever
            # present some of the time (a pending update), and this
            # project has been bitten twice before by numbered-menu-
            # renumbering docs going stale (see the Settings option's own
            # checklist above). Windows-only, matching Quick Launch and
            # the rest of the apply mechanism - Linux only ever sees the
            # notice + release URL, never this actionable path.
            if ($null -eq $PendingAppUpdate -or $IsLinux) {
                Pause-Brief (T 'common.not_valid_option')
            } else {
                Write-Host ""
                if (Confirm-YesNo (T 'menu.update_confirm_q' @{ version = $PendingAppUpdate.LatestVersion })) {
                    Write-Host ""
                    Write-Host (T 'menu.update_downloading')
                    $staged = Invoke-AppUpdateDownloadAndStage -DownloadUrl $PendingAppUpdate.DownloadUrl -ExpectedVersion $PendingAppUpdate.LatestVersion
                    if (-not $staged.Ok) {
                        Write-Host (T 'menu.update_download_failed' @{ error = $staged.ErrMsg }) -ForegroundColor Red
                        Pause-Continue
                    } else {
                        Start-AppUpdateHelper -InstallDir (Split-Path -Parent $ScriptDir) -StagingDir $staged.StagingDir -ExpectedVersion $PendingAppUpdate.LatestVersion -RelaunchTarget 'console'
                        Exit-Console
                    }
                }
            }
        }
        default {
            Pause-Brief (T 'common.not_valid_option')
        }
    }
}
