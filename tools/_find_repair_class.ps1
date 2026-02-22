# Find the declaring class of RepairOrReinforce by looking at .NET metadata token patterns
# In IL metadata, method ref tokens store: namespace + class + method name as adjacent strings
$dll = "D:\SteamLibrary\steamapps\common\Core Keeper\CoreKeeper_Data\Managed\Pug.Other.dll"
$bytes = [System.IO.File]::ReadAllBytes($dll)
$text = [System.Text.Encoding]::ASCII.GetString($bytes)

# Split into printable-string tokens, include short ones too
$chunks = $text -split '[^\x20-\x7E]+'

# Find ALL occurrences of RepairOrReinforce
Write-Host "=== All occurrences of RepairOrReinforce with surrounding context ==="
for ($i = 0; $i -lt $chunks.Count; $i++) {
    if ($chunks[$i] -eq 'RepairOrReinforce') {
        $start = [Math]::Max(0, $i-15)
        $end   = [Math]::Min($chunks.Count-1, $i+5)
        $ctx = $chunks[$start..$end] | Where-Object { $_.Length -gt 1 }
        Write-Host ""
        Write-Host "--- occurrence at index $i ---"
        $ctx | ForEach-Object { Write-Host "  [$_]" }
    }
}

# Also search for the class name adjacent to ToggleRepair
Write-Host ""
Write-Host "=== All occurrences of ToggleRepair ==="
for ($i = 0; $i -lt $chunks.Count; $i++) {
    if ($chunks[$i] -match '^ToggleRepair$') {
        $start = [Math]::Max(0, $i-15)
        $end   = [Math]::Min($chunks.Count-1, $i+5)
        $ctx = $chunks[$start..$end] | Where-Object { $_.Length -gt 1 }
        Write-Host ""
        Write-Host "--- occurrence at index $i ---"
        $ctx | ForEach-Object { Write-Host "  [$_]" }
    }
}
