Add-Type -AssemblyName System.IO.Compression.FileSystem

# Bump this for a new release; the zip name and messages follow.
$version = 'V5'

$root    = Split-Path -Parent $PSScriptRoot
$zipPath = Join-Path $root "LegacyDownloader$version.zip"

# drop any older LegacyDownloaderV*.zip so the folder only ever has the current one
Get-ChildItem $root -Filter 'LegacyDownloaderV*.zip' -File |
    Where-Object { $_.FullName -ne $zipPath } |
    ForEach-Object { Write-Host "removing old $($_.Name)"; Remove-Item -Force $_.FullName }

$stageDir = Join-Path $env:TEMP ("legacy_${version}_stage_" + [System.Guid]::NewGuid().ToString('N'))
$tempZip  = Join-Path $env:TEMP ("LegacyDownloader${version}_" + [System.Guid]::NewGuid().ToString('N') + ".zip")

New-Item -ItemType Directory -Path $stageDir -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $stageDir 'lang') -Force | Out-Null

$filesToCopy = @(
    'LegacyDownloader.ps1',
    'LegacyDownloader.vbs',
    'LegacyDownloader.bat',
    'LegacyDownloader-Console.bat',
    'LegacyDownloader.Core.psm1',
    'LegacyDownloader.Console.ps1',
    'LegacyDownloader.Gui.ps1',
    'README.txt',
    'rclone.exe'
)

foreach ($f in $filesToCopy) {
    Copy-Item (Join-Path $root $f) (Join-Path $stageDir $f) -Force
}

Copy-Item (Join-Path $root 'lang\*.json') (Join-Path $stageDir 'lang') -Force

Write-Host "Compressing to temporary zip..."
[System.IO.Compression.ZipFile]::CreateFromDirectory($stageDir, $tempZip, [System.IO.Compression.CompressionLevel]::Optimal, $false)
Remove-Item -Recurse -Force $stageDir

Copy-Item -Path $tempZip -Destination $zipPath -Force
Remove-Item -Path $tempZip -Force

Write-Host "`nVerifying zip contents:"
$zip = [System.IO.Compression.ZipFile]::OpenRead($zipPath)
try {
    $entries = $zip.Entries | Sort-Object FullName
    foreach ($e in $entries) {
        Write-Host ("  {0,-35} ({1,10:N0} bytes)" -f $e.FullName, $e.Length)
    }
    $count = $zip.Entries.Count
} finally {
    $zip.Dispose()
}

Write-Host "`nTotal entries in $(Split-Path -Leaf $zipPath): $count"
$expected = $filesToCopy.Count + (Get-ChildItem (Join-Path $root 'lang') -Filter *.json).Count
if ($count -eq $expected) {
    Write-Host "$version PACKAGE BUILD SUCCESSFUL!" -ForegroundColor Green
} else {
    Write-Host "WARNING: expected $expected entries, got $count" -ForegroundColor Red
}
