Add-Type -AssemblyName System.IO.Compression.FileSystem

$root = 'C:\LegacyOffline'
$zipPath = Join-Path $root 'LegacyDownloaderV4.zip'
$oldZip = Join-Path $root 'LegacyDownloaderV3.zip'
$handoff = Join-Path $root 'HANDOFF-phase4-5.md'

if (Test-Path $oldZip) { Remove-Item -Force $oldZip }
if (Test-Path $handoff) { Remove-Item -Force $handoff }

$stageDir = Join-Path $env:TEMP ("legacy_v4_stage_" + [System.Guid]::NewGuid().ToString('N'))
$tempZip  = Join-Path $env:TEMP ("LegacyDownloaderV4_" + [System.Guid]::NewGuid().ToString('N') + ".zip")

New-Item -ItemType Directory -Path $stageDir -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $stageDir 'lang') -Force | Out-Null

$filesToCopy = @(
    'LegacyDownloader.ps1',
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

Write-Host "`nTotal entries in LegacyDownloaderV4.zip: $count"
if ($count -eq 20) {
    Write-Host "V4 PACKAGE BUILD SUCCESSFUL!" -ForegroundColor Green
} else {
    Write-Host "WARNING: Unexpected entry count: $count" -ForegroundColor Red
}
