# LegacyDownloader.Console.ps1 - the text / menu interface.
#
# Dot-sourced by LegacyDownloader.ps1 once the shared core module is loaded,
# Initialize-LegacyCore has run and Initialize-Language has set the interface
# language. Do not launch this file on its own - it relies on $Core (and
# $Rclone / $Conn / $CommonArgs / $ScanArgs / $RcloneConfigArgs) already being
# set by the entry script.
$ErrorActionPreference = 'Stop'

if (-not $Core) {
    Write-Host "Please run LegacyDownloader.bat (or LegacyDownloader.ps1) - not this file directly." -ForegroundColor Yellow
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
        New-Item -ItemType Directory -Force -Path $Path -ErrorAction Stop | Out-Null
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
        $argLine = (@('copy', $quotedSource, $quotedDest) + $quotedCommonArgs + $ExtraArgs) -join ' '
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
    if (Test-Path ([System.IO.Path]::Combine($GamePath, 'config.xml'))) {
        $excludeArgs += @('--exclude', '/config.xml')
    }
    foreach ($e in $ExtraExcludes) { $excludeArgs += @('--exclude', $e) }
    Invoke-RcloneCopy "$Conn`LegacyPC - Game" $GamePath $excludeArgs
    Write-Host ""
}

function Invoke-EditionSync([string]$GamePath, [string]$Edition) {
    Write-Host (T 'sync.edition' @{ edition = (Format-EditionDisplay $Edition) })
    Invoke-RcloneCopy "$Conn`maps/$Edition" (Join-Path $GamePath "maps\$Edition")
    Write-Host ""
}

function Invoke-AllMapsSync([string]$GamePath, [switch]$Confirmed) {
    $mapsDir = Join-Path $GamePath 'maps'
    if (-not $Confirmed -and (Test-GameFolder $GamePath) -and -not (Test-Path $mapsDir)) {
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

function Invoke-Update([string]$GamePath, [string]$Editions, [string[]]$BaseExcludes = @(), [switch]$Confirmed) {
    Invoke-BaseSync $GamePath $BaseExcludes
    if ($Editions.ToUpper() -eq 'AUTO') {
        Invoke-AllMapsSync $GamePath -Confirmed:$Confirmed
    } else {
        $list = $Editions -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' }
        foreach ($ed in $list) { Invoke-EditionSync $GamePath $ed }
    }
    Write-Host (HR)
    Write-Host ("  " + (T 'common.done'))
    Write-Host (HR)
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

    Write-Host (T 'preview.checking')

    $plan = Get-UpdatePlan -GamePath $GamePath -Editions $Editions

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
        $plan = Get-UpdatePlan -GamePath $GamePath -Editions $Editions -IgnoreWrongLevel
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

function Show-Checklist([string[]]$Items, [string[]]$PreChecked) {
    $checked = New-Object System.Collections.Generic.HashSet[string]
    foreach ($p in $PreChecked) { [void]$checked.Add($p) }

    # Internal sentinel rows - kept out of the item namespace so a translated
    # label can never collide with a real edition name or a comparison.
    $rows = @()
    $rows += $Items
    $rows += '__SEP__'
    $rows += '__BACK__'
    $rows += '__CANCEL__'
    $rows += '__CONTINUE__'

    $cursor = 0
    while ($rows[$cursor] -eq '__SEP__') { $cursor++ }

    $savedBuffer = Enter-NoScrollBuffer
    [Console]::CursorVisible = $false

    try {
        while ($true) {
            Clear-Host
            Write-Host (T 'checklist.help')
            Write-Host ""
            for ($i = 0; $i -lt $rows.Count; $i++) {
                $row = $rows[$i]
                $pointer = if ($i -eq $cursor) { '>' } else { ' ' }
                if ($row -eq '__SEP__') {
                    $line = ''
                } elseif ($row -eq '__BACK__') {
                    $line = "$pointer  " + (T 'checklist.back')
                } elseif ($row -eq '__CANCEL__') {
                    $line = "$pointer  " + (T 'checklist.cancel')
                } elseif ($row -eq '__CONTINUE__') {
                    $line = "$pointer  " + (T 'checklist.continue')
                } else {
                    $mark = if ($checked.Contains($row)) { 'x' } else { ' ' }
                    $disp = Format-EditionDisplay $row
                    $line = "$pointer  [$mark] $disp"
                }
                Write-Host $line
            }

            $key = [Console]::ReadKey($true)
            switch ($key.Key) {
                'UpArrow' {
                    do { $cursor--; if ($cursor -lt 0) { $cursor = $rows.Count - 1 } } while ($rows[$cursor] -eq '__SEP__')
                }
                'DownArrow' {
                    do { $cursor++; if ($cursor -ge $rows.Count) { $cursor = 0 } } while ($rows[$cursor] -eq '__SEP__')
                }
                'Enter' {
                    $row = $rows[$cursor]
                    if ($row -eq '__BACK__')     { return @{ Action = 'Back' } }
                    if ($row -eq '__CANCEL__')   { return @{ Action = 'Cancel' } }
                    if ($row -eq '__CONTINUE__') { return @{ Action = 'Continue'; Selected = @($checked) } }
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

function Run-MapsWizard([string]$GamePath, [string]$CurrentEditions) {
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
            return 'AUTO'
        }

        if ($choice -ne '2') {
            Pause-Brief (T 'common.not_valid_option')
            continue
        }

        Write-Host ""
        Write-Host (T 'maps.checking_available')
        $remote = Get-RemoteEditions
        if (-not $remote -or $remote.Count -eq 0) {
            Write-Host (T 'maps.net_fail')
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

            Write-Host (HR)
            Write-Host ("  " + (T 'maps.summary_header'))
            Write-Host (HR)
            if ($selected.Count -eq 0) {
                Write-Host (T 'maps.no_editions_selected')
            } else {
                $label = if ($selected.Count -eq 1) { T 'maps.selected_edition' } else { T 'maps.selected_editions' }
                Write-Host $label
                foreach ($ed in $selected) {
                    $disp = Format-EditionDisplay $ed
                    Write-Host "  $disp"
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
                Write-Host (T 'maps.stop_getting' @{ list = ($removed -join ', ') })
            }
            Write-Host ""

            if ($selected.Count -eq 0) {
                Write-Host (T 'maps.nothing_checked') -ForegroundColor Yellow
                if (-not (Confirm-YesNo (T 'maps.go_back_list'))) { return $null }
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
                    if (Confirm-YesNo (T 'maps.delete_or_keep' @{ edition = $ed })) {
                        try {
                            Remove-Item -Recurse -Force $localDir -ErrorAction Stop
                            Write-Host (T 'maps.deleted' @{ edition = $ed })
                        } catch {
                            Write-Host (T 'maps.cant_delete' @{ edition = $ed }) -ForegroundColor Yellow
                        }
                    } else {
                        Write-Host (T 'maps.keeping_untracked' @{ edition = $ed })
                    }
                }
            }

            if ($prev.Proceed) {
                Write-Host ""
                foreach ($ed in $selected) { Invoke-EditionSync $GamePath $ed }
                Invoke-BaseSync $GamePath $prev.BaseExcludes
            }

            return if ($selected.Count -eq $remote.Count) { 'AUTO' } else { ($selected -join ',') }
        }

        if ($backToTop) { continue }
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
    $mapsResult = Run-MapsWizard -GamePath $cfg.GamePath -CurrentEditions $cfg.Editions
    if ($null -ne $mapsResult) {
        Save-Config -GamePath $cfg.GamePath -Editions $mapsResult
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

    $edDisplay = if ($cfg.Editions.ToUpper() -eq 'AUTO') {
        'AUTO'
    } else {
        ($cfg.Editions -split ',' | ForEach-Object {
            Format-EditionDisplay $_.Trim()
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
            $prev = Show-UpdatePreview -GamePath $cfg.GamePath -Editions $cfg.Editions
            if ($prev.Proceed) {
                Write-Host ""
                Invoke-Update -GamePath $cfg.GamePath -Editions $cfg.Editions -BaseExcludes $prev.BaseExcludes -Confirmed
                Write-Host ""
                Write-Host (T 'menu.up_to_date_play')
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
