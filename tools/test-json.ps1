$content = [IO.File]::ReadAllText('C:\LegacyOffline\lang\zh-Hans.json', [Text.Encoding]::UTF8)
# Find all positions of ASCII double-quote
$pos = 0
$inKey = $false
$inString = $false
$escaped = $false
$problems = @()
$lineNum = 1

for ($i = 0; $i -lt $content.Length; $i++) {
    $c = $content[$i]
    if ($c -eq "`n") { $lineNum++ }
    if ($escaped) { $escaped = $false; continue }
    if ($c -eq '\') { $escaped = $true; continue }
    if ($c -eq '"') {
        $inString = -not $inString
        if (-not $inString) {
            # Closing quote - fine
        }
    }
}

# Simpler: just find lines with unescaped quotes using regex
$lines = $content -split "`n"
for ($i = 0; $i -lt $lines.Count; $i++) {
    $line = $lines[$i]
    # Remove properly escaped \" sequences
    $stripped = $line -replace '\\"', '##'
    # Count remaining quotes - should be 4: key open, key close, value open, value close
    $quoteCount = ($stripped.ToCharArray() | Where-Object { $_ -eq '"' }).Count
    if ($quoteCount -gt 4 -or ($quoteCount -gt 2 -and $quoteCount % 2 -ne 0)) {
        Write-Host "Line $($i+1) ($quoteCount quotes): $line"
    }
}
Write-Host "Done"
