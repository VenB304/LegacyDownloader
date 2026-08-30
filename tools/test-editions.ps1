Import-Module (Join-Path (Split-Path -Parent $PSScriptRoot) 'LegacyDownloader.Core.psm1') -Force -DisableNameChecking

$tests = @(
    @{ Ed = '1';    Expected = 'Just Dance' },
    @{ Ed = '2';    Expected = 'Just Dance 2' },
    @{ Ed = '3';    Expected = 'Just Dance 3' },
    @{ Ed = '4';    Expected = 'Just Dance 4' },
    @{ Ed = '2014'; Expected = 'Just Dance 2014' },
    @{ Ed = '2022'; Expected = 'Just Dance 2022' },
    @{ Ed = '2023'; Expected = 'Just Dance 2023 Edition' },
    @{ Ed = '2026'; Expected = 'Just Dance 2026 Edition' },
    @{ Ed = '2027'; Expected = 'Just Dance: Decades of Hits' },
    @{ Ed = '123';  Expected = 'Just Dance Kids' },
    @{ Ed = '1928'; Expected = 'Just Dance: Disney Party' },
    @{ Ed = '2009'; Expected = 'Michael Jackson: The Experience' },
    @{ Ed = '3112'; Expected = 'Just Dance Wii 2' },
    @{ Ed = '4118'; Expected = 'Just Dance Wii U' },
    @{ Ed = '4514'; Expected = 'Just Dance China' },
    @{ Ed = '4884'; Expected = 'ABBA: You Can Dance' },
    @{ Ed = '9999'; Expected = $null }
)

$fail = 0
foreach ($t in $tests) {
    $res = Get-EditionTitle $t.Ed
    if ($res -eq $t.Expected) {
        Write-Host "OK: $($t.Ed) => $res" -ForegroundColor Green
    } else {
        Write-Host "FAIL: $($t.Ed) expected '$($t.Expected)' got '$res'" -ForegroundColor Red
        $fail++
    }
}

Write-Host "`nFormat-EditionDisplay tests:"
$d1 = Format-EditionDisplay '1'
Write-Host "1 => '$d1'"
$d1928 = Format-EditionDisplay '1928'
Write-Host "1928 => '$d1928'"
$dUnknown = Format-EditionDisplay '9999'
Write-Host "9999 => '$dUnknown'"

if ($fail -eq 0) {
    Write-Host "`nALL EDITION TESTS PASSED" -ForegroundColor Green
} else {
    exit 1
}
