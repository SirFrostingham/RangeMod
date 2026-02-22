$dll = "D:\SteamLibrary\steamapps\common\Core Keeper\CoreKeeper_Data\Managed\Pug.Other.dll"
$bytes = [System.IO.File]::ReadAllBytes($dll)
$text = [System.Text.Encoding]::ASCII.GetString($bytes)
$chunks = $text -split '[^\x20-\x7E]+'

# CraftingHandler repair methods
Write-Host "=== CraftingHandler methods ==="
$chunks | Where-Object { $_ -match '^Craft|^craft' } |
    Sort-Object -Unique | Select-Object -First 60 |
    ForEach-Object { Write-Host "  [$_]"}

Write-Host ""
Write-Host "=== Repair in CraftingHandler context ==="
for ($i = 0; $i -lt $chunks.Count; $i++) {
    if ($chunks[$i] -match 'CraftingHandler') {
        $start = [Math]::Max(0, $i-2)
        $end   = [Math]::Min($chunks.Count-1, $i+3)
        $ctx = $chunks[$start..$end] | Where-Object { $_ -match 'Repair|Reinforce|repair|reinforce' }
        if ($ctx.Count -gt 0) {
            $all = $chunks[$start..$end] | Where-Object { $_.Length -gt 2 }
            Write-Host "--- @ $i ---"
            $all | ForEach-Object { Write-Host "  [$_]" }
        }
    }
}

Write-Host ""
Write-Host "=== SalvageAndRepairUI fields/methods ==="
for ($i = 0; $i -lt $chunks.Count; $i++) {
    if ($chunks[$i] -match 'SalvageAndRepairUI') {
        $start = [Math]::Max(0, $i-5)
        $end   = [Math]::Min($chunks.Count-1, $i+20)
        $ctx = $chunks[$start..$end] | Where-Object { $_.Length -gt 2 }
        Write-Host "--- @ $i ---"
        $ctx | ForEach-Object { Write-Host "  [$_]" }
        Write-Host ""
    }
}
