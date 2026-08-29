$ErrorActionPreference = 'Stop'
$langDir = 'C:\LegacyOffline\lang'
$en = ([IO.File]::ReadAllText((Join-Path $langDir 'en.json'), [Text.Encoding]::UTF8)) | ConvertFrom-Json
$enKeys = [System.Collections.Generic.HashSet[string]]::new()
foreach ($p in $en.PSObject.Properties) { [void]$enKeys.Add($p.Name) }
$ph = @{}
foreach ($p in $en.PSObject.Properties) {
    $s = [System.Collections.Generic.SortedSet[string]]::new()
    foreach ($m in [regex]::Matches([string]$p.Value, '\{([A-Za-z0-9_]+)\}')) { [void]$s.Add($m.Groups[1].Value) }
    $ph[$p.Name] = ($s -join ',')
}
$fail = $false
foreach ($f in (Get-ChildItem $langDir -Filter *.json | Where-Object { $_.Name -ne 'en.json' } | Sort-Object Name)) {
    $errs = @()
    try { $j = ([IO.File]::ReadAllText($f.FullName, [Text.Encoding]::UTF8)) | ConvertFrom-Json }
    catch { Write-Host ("{0,-14} JSON PARSE ERROR: {1}" -f $f.Name, $_.Exception.Message) -ForegroundColor Red; $fail = $true; continue }
    $keys = [System.Collections.Generic.HashSet[string]]::new()
    foreach ($p in $j.PSObject.Properties) { [void]$keys.Add($p.Name) }
    $missing = @($enKeys | Where-Object { -not $keys.Contains($_) })
    $extra   = @($keys   | Where-Object { -not $enKeys.Contains($_) })
    if ($missing.Count) { $errs += "MISSING $($missing.Count): $($missing -join ', ')" }
    if ($extra.Count)   { $errs += "EXTRA $($extra.Count): $($extra -join ', ')" }
    $phErr = @()
    foreach ($p in $j.PSObject.Properties) {
        if (-not $ph.ContainsKey($p.Name)) { continue }
        $s = [System.Collections.Generic.SortedSet[string]]::new()
        foreach ($m in [regex]::Matches([string]$p.Value, '\{([A-Za-z0-9_]+)\}')) { [void]$s.Add($m.Groups[1].Value) }
        if (($s -join ',') -ne $ph[$p.Name]) { $phErr += "$($p.Name) en:{$($ph[$p.Name])} got:{$($s -join ',')}" }
    }
    if ($phErr.Count) { $errs += "PLACEHOLDER MISMATCH:`n    " + ($phErr -join "`n    ") }
    foreach ($mk in '_meta.code', '_meta.name', '_meta.nativeName') { if (-not $keys.Contains($mk)) { $errs += "no $mk" } }
    if ($j.'common.rule' -ne '============================================') { $errs += "common.rule altered" }
    if ($errs.Count) { Write-Host ("{0,-14} FAIL" -f $f.Name) -ForegroundColor Red; $errs | ForEach-Object { Write-Host "   $_" }; $fail = $true }
    else { Write-Host ("{0,-14} OK ({1} keys)" -f $f.Name, $keys.Count) -ForegroundColor Green }
}
if ($fail) { exit 1 } else { Write-Host "`nALL LANG FILES VALID" -ForegroundColor Green }
