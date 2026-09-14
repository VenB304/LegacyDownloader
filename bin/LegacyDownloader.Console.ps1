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

function Confirm-YesNo([string]$Prompt) {
    while ($true) {
        $ans = Read-Host (T 'common.yn_prompt' @{ prompt = $Prompt })
        if ($ans -match '^[Yy]') { return $true }
        if ($ans -match '^[Nn]') { return $false }
        Write-Host (T 'common.type_y_n')
    }
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
        New-Item -ItemType Directory -Force -LiteralPath $Path -ErrorAction Stop | Out-Null
        return $true
    } catch {
        Write-Host (T 'error.cant_create_folder' @{ error = $_.Exception.Message }) -ForegroundColor Red
        return $false
    }
}

function Invoke-RcloneCopy([string]$Source, [string]$Dest, [string[]]$ExtraArgs = @()) {
    $savedBuffer = Enter-NoScrollBuffer
    try {
        $quotedSource = ConvertTo-QuotedArg $Source
        $quotedDest   = ConvertTo-QuotedArg $Dest
        $quotedCommonArgs = $CommonArgs | ForEach-Object { ConvertTo-QuotedArg $_ }
        # $ExtraArgs carries --exclude <pattern> pairs; a pattern with a space
        # (a moddable file the user chose to keep) must be quoted like everything
        # else or rclone splits it into two argv tokens.
        $quotedExtra  = $ExtraArgs | ForEach-Object { ConvertTo-QuotedArg $_ }
        $argLine = (@('copy', $quotedSource, $quotedDest) + $quotedCommonArgs + $quotedExtra) -join ' '
        Start-Process -FilePath $Rclone -ArgumentList $argLine -NoNewWindow -Wait
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
    Invoke-RcloneCopy "$Conn`LegacyPC - Game" $GamePath $excludeArgs
    Write-Host ""
}

function Invoke-EditionSync([string]$GamePath, [string]$Edition, [string[]]$SongCodes = $null) {
    Write-Host (T 'sync.edition' @{ edition = (Format-EditionDisplay $Edition) })
    Invoke-RcloneCopy "$Conn`maps/$Edition" (Join-Path $GamePath "maps\$Edition") (Get-SongIncludeArgs $SongCodes)
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
    Invoke-RcloneCopy "$Conn`maps" $mapsDir
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

function Show-SongBrowser([string]$CurrentEditions, [string]$CurrentSongFilters) {
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

    $expanded         = New-Object System.Collections.Generic.HashSet[string]
    $search           = ''
    $editionFilter    = 'ALL'
    $difficultyFilter = 'ALL'
    $effortFilter     = 'ALL'
    $sortColumn       = 0
    $sortAscending    = $true
    $cursor           = 0
    $viewStart        = 0

    $sortFields = @(
        { param($r) if ([string]::IsNullOrWhiteSpace($r.Title)) { $r.Code } else { $r.Title } }
        { param($r) [string]$r.Artist }
        { param($r) Format-EditionDisplay $r.Edition }
        { param($r) Format-DifficultyTier $r.Difficulty }
        { param($r) Format-EffortTier $r.Effort }
    )

    function Get-EditionTriMark([string]$Edition) {
        $codes = @($byEdition[$Edition])
        $checked = @($codes | Where-Object { $selectedKeys.Contains("$Edition|$_") }).Count
        if ($checked -eq 0) { return ' ' }
        if ($checked -eq $codes.Count) { return 'x' }
        return [char]0x25A0   # filled square - the "partial" glyph
    }

    $savedBuffer = Enter-NoScrollBuffer
    [Console]::CursorVisible = $false
    try {
        while ($true) {
            $active = ($search -ne '') -or ($editionFilter -ne 'ALL') -or ($difficultyFilter -ne 'ALL') -or ($effortFilter -ne 'ALL')

            # Build this frame's visible rows. Every row is tagged Kind
            # 'Edition' (tri-state, toggling it selects/clears the whole
            # edition) or 'Song' (plain toggle) - Enter handling below is
            # identical either way, only rendering differs.
            $visible = @()
            if ($active) {
                $q = $search.Trim().ToLowerInvariant()
                $filtered = @($rows | Where-Object {
                    ($editionFilter -eq 'ALL' -or $_.Edition -eq $editionFilter) -and
                    ($difficultyFilter -eq 'ALL' -or $_.Difficulty -eq $difficultyFilter) -and
                    ($effortFilter -eq 'ALL' -or $_.Effort -eq $effortFilter) -and
                    ($q -eq '' -or ([string]$_.Title).ToLowerInvariant().Contains($q) -or ([string]$_.Artist).ToLowerInvariant().Contains($q) -or $_.Code.Contains($q))
                })
                $filtered = @($filtered | Sort-Object -Property @{ Expression = $sortFields[$sortColumn] })
                if (-not $sortAscending) { [array]::Reverse($filtered) }
                foreach ($r in $filtered) { $visible += [PSCustomObject]@{ Kind = 'Song'; Edition = $r.Edition; Code = $r.Code; Indent = $false } }
            } else {
                foreach ($ed in $catalogEditions) {
                    $visible += [PSCustomObject]@{ Kind = 'Edition'; Edition = $ed; Code = $null; Indent = $false }
                    if ($expanded.Contains($ed)) {
                        foreach ($code in $byEdition[$ed]) { $visible += [PSCustomObject]@{ Kind = 'Song'; Edition = $ed; Code = $code; Indent = $true } }
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
            Write-Host (if ($active) { T 'songbrowser.help' } else { T 'songbrowser.tree_help' })
            $editionLabel = if ($editionFilter -eq 'ALL') { T 'songbrowser.filter_all' } else { Format-EditionDisplay $editionFilter }
            $diffLabel    = if ($difficultyFilter -eq 'ALL') { T 'songbrowser.filter_all' } else { Format-DifficultyTier $difficultyFilter }
            $effortLabel  = if ($effortFilter -eq 'ALL') { T 'songbrowser.filter_all' } else { Format-EffortTier $effortFilter }
            Write-Host (T 'songbrowser.search_label' @{ text = $search })
            Write-Host ("  " + (T 'songbrowser.filter_edition' @{ value = $editionLabel }) + "    " + (T 'songbrowser.filter_difficulty' @{ value = $diffLabel }) + "    " + (T 'songbrowser.filter_effort' @{ value = $effortLabel }))
            Write-Host (T 'songbrowser.status_line' @{ shown = $visible.Count; total = $rows.Count; selected = $selectedKeys.Count })
            Write-Host ""

            $consoleHeight = try { [Console]::WindowHeight } catch { 30 }
            $viewportRows = [Math]::Max(5, $consoleHeight - 10)
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
                        $arrow = if ($expanded.Contains($row.Edition)) { [char]0x25BC } else { [char]0x25B6 }
                        $count = @($byEdition[$row.Edition]).Count
                        $checkedCount = @($byEdition[$row.Edition] | Where-Object { $selectedKeys.Contains("$($row.Edition)|$_") }).Count
                        $countText = if ($checkedCount -gt 0 -and $checkedCount -lt $count) { "$checkedCount/$count" } else { "$count" }
                        Write-Host ("{0}  [{1}] {2} {3} ({4} songs)" -f $pointer, $mark, $arrow, (Format-EditionDisplay $row.Edition), $countText)
                    } else {
                        $r = $rowByKey["$($row.Edition)|$($row.Code)"]
                        $mark = if ($selectedKeys.Contains("$($row.Edition)|$($row.Code)")) { 'x' } else { ' ' }
                        $title = if ($r) { Get-SongTitleForDisplay $r $ctx.DuplicateKeys } else { $row.Code }
                        if ($active) {
                            $line = "{0}{1}  [{2}] {3,-40} {4,-22} {5,-14}" -f $pointer, $indent, $mark, ($title.Substring(0, [Math]::Min(40, $title.Length))), (([string]$r.Artist).Substring(0, [Math]::Min(22, ([string]$r.Artist).Length))), (Format-EditionDisplay $row.Edition)
                        } else {
                            $artist = if ($r) { [string]$r.Artist } else { '' }
                            $line = "{0}{1}  [{2}] {3,-42} {4}" -f $pointer, $indent, $mark, ($title.Substring(0, [Math]::Min(42, $title.Length))), $artist
                        }
                        Write-Host $line
                    }
                }
            }
            Write-Host ""
            $doneIdx = $footerStart
            $cancelIdx = $footerStart + 1
            Write-Host ((if ($cursor -eq $doneIdx) { '>' } else { ' ' }) + "  " + (T 'songbrowser.done'))
            Write-Host ((if ($cursor -eq $cancelIdx) { '>' } else { ' ' }) + "  " + (T 'songbrowser.cancel'))

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
            if ($key.Key -eq 'Backspace') {
                if ($search.Length -gt 0) { $search = $search.Substring(0, $search.Length - 1) }
                $cursor = 0; $viewStart = 0; continue
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
                    return @{ Action = 'Confirm'; Editions = $resolved.Editions; SongFilters = $resolved.SongFilters; Catalog = $catalog }
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
        [Console]::CursorVisible = $true
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

        $browse = Show-SongBrowser -CurrentEditions $CurrentEditions -CurrentSongFilters $CurrentSongFilters
        Write-Host ""
        if ($browse.Action -ne 'Confirm') { continue }

        $prev = Show-UpdatePreview -GamePath $GamePath -Editions $browse.Editions -SongFilters $browse.SongFilters
        if ($prev.Dismissed) { continue }

        # Whole editions dropped, or editions narrowed to fewer songs, may
        # have local files the player no longer wants - ask once per
        # affected edition, same spirit as the tool's older "unchecked an
        # edition" cleanup prompt.
        $oldEditionList = if ($CurrentEditions.ToUpper() -eq 'AUTO') { Get-LocalEditions $GamePath } else { @($CurrentEditions -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' }) }
        $newEditionList = @($browse.Editions -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' })
        $removalPlan = Get-SongRemovalPlan -OldEditions $oldEditionList -OldSongFilters $CurrentSongFilters -NewEditions $newEditionList -NewSongFilters $browse.SongFilters -Catalog $browse.Catalog
        foreach ($item in $removalPlan) {
            $localDir = Join-Path $GamePath "maps\$($item.Edition)"
            if (-not (Test-Path -LiteralPath $localDir)) { continue }
            if ($item.WholeEditionRemoved) {
                if (Confirm-YesNo (T 'maps.delete_or_keep' @{ edition = $item.Edition })) {
                    try {
                        Remove-Item -LiteralPath $localDir -Recurse -Force -ErrorAction Stop
                        Write-Host (T 'maps.deleted' @{ edition = $item.Edition })
                    } catch {
                        Write-Host (T 'maps.cant_delete' @{ edition = $item.Edition }) -ForegroundColor Yellow
                    }
                } else {
                    Write-Host (T 'maps.keeping_untracked' @{ edition = $item.Edition })
                }
            } else {
                if (Confirm-YesNo (T 'maps.delete_songs_or_keep' @{ count = $item.RemovedCodes.Count; edition = $item.Edition })) {
                    $failed = 0
                    foreach ($code in $item.RemovedCodes) {
                        $target = Join-Path $localDir "${code}_pc.ipk"
                        if (Test-Path -LiteralPath $target) {
                            try { Remove-Item -LiteralPath $target -Force -ErrorAction Stop } catch { $failed++ }
                        }
                    }
                    if ($failed -gt 0) { Write-Host (T 'maps.cant_delete_songs' @{ edition = $item.Edition }) -ForegroundColor Yellow }
                    else { Write-Host (T 'maps.songs_deleted' @{ count = $item.RemovedCodes.Count; edition = $item.Edition }) }
                }
            }
        }

        if ($prev.Proceed) {
            Write-Host ""
            Invoke-Update -GamePath $GamePath -Editions $browse.Editions -BaseExcludes $prev.BaseExcludes -SongFilters $browse.SongFilters -Confirmed
        }
        return @{ Editions = $browse.Editions; SongFilters = $browse.SongFilters }
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

if ([string]::IsNullOrWhiteSpace($cfg.GamePath)) {
    $pickedLang = Choose-Language $cfg.Lang
    if ($pickedLang -ne $cfg.Lang) {
        Save-Config -GamePath $cfg.GamePath -Editions $cfg.Editions -Lang $pickedLang
        $cfg = Load-Config
    }

    Write-Host ""
    $gamePath = Run-SetupWizard
    Save-Config -GamePath $gamePath -Editions $cfg.Editions
    $cfg = Load-Config

    Write-Host ""
    $mapsResult = Run-MapsWizard -GamePath $cfg.GamePath -CurrentEditions $cfg.Editions -CurrentSongFilters $cfg.SongFilters
    if ($null -ne $mapsResult) {
        Save-Config -GamePath $cfg.GamePath -Editions $mapsResult.Editions -SongFilters $mapsResult.SongFilters
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
            Save-Config -GamePath $betterPath -Editions $cfg.Editions
            $cfg = Load-Config
            Write-Host (T 'common.updated') -ForegroundColor Green
            Start-Sleep -Seconds 1
        }
    }
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
    Write-Host ("  " + (T 'menu.title'))
    Write-Host (T 'menu.game_folder' @{ path = $cfg.GamePath })
    Write-Host (T 'menu.editions' @{ editions = $edDisplay })
    Write-Host (T 'menu.language_line' @{ language = $langLabel })
    Write-Host (HR)
    Write-Host ""
    Write-Host (T 'menu.safety')
    Write-Host ""
    Write-Host (T 'menu.opt_download')
    Write-Host (T 'menu.opt_choose')
    Write-Host (T 'menu.opt_folder')
    Write-Host (T 'menu.opt_language')
    Write-Host (T 'menu.opt_exit')
    $choice = Read-Host (T 'menu.choose_1_5')

    switch ($choice) {
        '1' {
            Write-Host ""
            $prev = Show-UpdatePreview -GamePath $cfg.GamePath -Editions $cfg.Editions -SongFilters $cfg.SongFilters
            if ($prev.Proceed) {
                Write-Host ""
                Invoke-Update -GamePath $cfg.GamePath -Editions $cfg.Editions -BaseExcludes $prev.BaseExcludes -SongFilters $cfg.SongFilters -Confirmed
                Write-Host ""
                Write-Host (T 'menu.up_to_date_play')
            }
            Pause-Continue
        }
        '2' {
            Write-Host ""
            $mapsResult = Run-MapsWizard -GamePath $cfg.GamePath -CurrentEditions $cfg.Editions -CurrentSongFilters $cfg.SongFilters
            if ($null -ne $mapsResult) {
                Save-Config -GamePath $cfg.GamePath -Editions $mapsResult.Editions -SongFilters $mapsResult.SongFilters
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
                    Save-Config -GamePath $path -Editions $cfg.Editions
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
                Save-Config -GamePath $cfg.GamePath -Editions $cfg.Editions -Lang $pickedLang
                $cfg = Load-Config
            }
            Pause-Brief -Seconds 1
        }
        '5' {
            Write-Host ""
            Write-Host (T 'menu.goodbye')
            Start-Sleep -Seconds 1
            exit 0
        }
        default {
            Pause-Brief (T 'common.not_valid_option')
        }
    }
}
