$dll = "D:\SteamLibrary\steamapps\common\Core Keeper\CoreKeeper_Data\Managed\Pug.Other.dll"
$bytes = [System.IO.File]::ReadAllBytes($dll)
$text = [System.Text.Encoding]::ASCII.GetString($bytes)
$chunks = $text -split '[^\x20-\x7E]+'

# Look for InventoryUpdateSystem and nearby base class indicators
Write-Host "=== InventoryUpdateSystem context ==="
for ($i = 0; $i -lt $chunks.Count; $i++) {
    if ($chunks[$i] -eq 'InventoryUpdateSystem') {
        $start = [Math]::Max(0, $i-20)
        $end   = [Math]::Min($chunks.Count-1, $i+20)
        $ctx = $chunks[$start..$end] | Where-Object { $_.Length -gt 2 }
        Write-Host "--- @ $i ---"
        $ctx | ForEach-Object { Write-Host "  [$_]" }
        Write-Host ""
    }
}

# SystemBase vs ISystem
Write-Host "=== SystemBase/ISystem refs near InventoryUpdate ==="
$chunks | Where-Object { $_ -match 'SystemBase|ISystem|ComponentSystem' } |
    Where-Object { $_ -match 'Inventory' } |
    Sort-Object -Unique |
    ForEach-Object { Write-Host "  [$_]" }

# What methods does InventoryUpdateSystem have?
Write-Host ""
Write-Host "=== Methods around ProcessInventoryChange ==="
for ($i = 0; $i -lt $chunks.Count; $i++) {
    if ($chunks[$i] -eq 'ProcessInventoryChange') {
        $start = [Math]::Max(0, $i-20)
        $end   = [Math]::Min($chunks.Count-1, $i+20)
        $ctx = $chunks[$start..$end] | Where-Object { $_.Length -gt 2 }
        Write-Host "--- @ $i ---"
        $ctx | ForEach-Object { Write-Host "  [$_]" }
        Write-Host ""
    }
}
