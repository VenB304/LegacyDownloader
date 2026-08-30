$flags = @(
    @{ Code = 'en';      Country = 'gb' },
    @{ Code = 'fr';      Country = 'fr' },
    @{ Code = 'de';      Country = 'de' },
    @{ Code = 'es';      Country = 'es' },
    @{ Code = 'it';      Country = 'it' },
    @{ Code = 'pt';      Country = 'pt' },
    @{ Code = 'nl';      Country = 'nl' },
    @{ Code = 'ja';      Country = 'jp' },
    @{ Code = 'ko';      Country = 'kr' },
    @{ Code = 'zh-Hans'; Country = 'cn' },
    @{ Code = 'zh-Hant'; Country = 'tw' },
    @{ Code = 'ru';      Country = 'ru' }
)
$wc = New-Object System.Net.WebClient
$out = @{}
foreach ($f in $flags) {
    $url = "https://flagcdn.com/20x15/$($f.Country).png"
    try {
        $bytes = $wc.DownloadData($url)
        $out[$f.Code] = [Convert]::ToBase64String($bytes)
        Write-Host "OK $($f.Code) ($($bytes.Length) bytes)"
    } catch { Write-Host "FAIL $($f.Code): $_" }
}
$wc.Dispose()

$lines = @()
$lines += '$script:FlagB64 = @{'
foreach ($key in ($out.Keys | Sort-Object)) {
    $lines += "    '$key' = '$($out[$key])'"
}
$lines += '}'
$lines -join "`r`n" | Set-Content -Encoding UTF8 -Path (Join-Path $PSScriptRoot 'flag-data.txt')
Write-Host "Written to flag-data.txt"
