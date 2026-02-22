$dll = "D:\SteamLibrary\steamapps\common\Core Keeper\CoreKeeper_Data\Managed\Pug.Other.dll"
$bytes = [System.IO.File]::ReadAllBytes($dll)
$text = [System.Text.Encoding]::ASCII.GetString($bytes)
$chunks = $text -split '[^\x20-\x7E]+'

# Find SalvageAndRepairUI context — get surrounding methods/fields
Write-Host "=== All chunks containing SalvageAndRepair ==="
for ($i = 0; $i -lt $chunks.Count; $i++) {
    if ($chunks[$i] -match 'SalvageAndRepair') {
        $start = [Math]::Max(0, $i-3)
        $end   = [Math]::Min($chunks.Count-1, $i+30)
        $ctx = $chunks[$start..$end] | Where-Object { $_.Length -gt 2 }
        Write-Host "--- @ $i ---"
        $ctx | ForEach-Object { Write-Host "  [$_]" }
        Write-Host ""
    }
}

# Also scan for CraftingHandler methods with Repair in name
Write-Host "=== CraftingHandler Repair methods ==="
for ($i = 0; $i -lt $chunks.Count; $i++) {
    if ($chunks[$i] -eq 'CraftingHandler') {
        $start = $i
        $end   = [Math]::Min($chunks.Count-1, $i+5)
        $ctx = $chunks[$start..$end] | Where-Object { $_ -match 'Repair|repair' }
        if ($ctx) { 
            $all = $chunks[$start..$end] | Where-Object { $_.Length -gt 2 }
            Write-Host "--- @ $i ---"; $all | ForEach-Object { Write-Host "  [$_]" }
        }
    }
}
