# Find methods called near ToggleRepair and RepairOrReinforce in the binary
# Look for PlayerController repair/action queue methods too
$dll = "D:\SteamLibrary\steamapps\common\Core Keeper\CoreKeeper_Data\Managed\Pug.Other.dll"
$bytes = [System.IO.File]::ReadAllBytes($dll)
$text = [System.Text.Encoding]::ASCII.GetString($bytes)
$chunks = $text -split '[^\x20-\x7E]+'

# Find context around ToggleRepair (larger window)
Write-Host "=== ToggleRepair context (large window) ==="
for ($i = 0; $i -lt $chunks.Count; $i++) {
    if ($chunks[$i] -eq 'ToggleRepair') {
        $start = [Math]::Max(0, $i-30)
        $end   = [Math]::Min($chunks.Count-1, $i+30)
        $ctx = $chunks[$start..$end] | Where-Object { $_.Length -gt 2 }
        Write-Host "--- @ $i ---"
        $ctx | ForEach-Object { Write-Host "  [$_]" }
    }
}

# Also look for PlayerController methods that might queue repair
Write-Host ""
Write-Host "=== PlayerController repair-related ==="
$chunks | Where-Object { $_ -match 'PlayerController' } |
    Where-Object { $_ -match 'Repair|Reinforce|Craft|Action|Queue' } |
    Sort-Object -Unique |
    ForEach-Object { Write-Host "  [$_]" }

# Look for CraftActionData / RepairActionData structs
Write-Host ""
Write-Host "=== Action/Input data types ==="
$chunks | Where-Object { $_ -match 'CraftAction|RepairAction|ActionData|ActionInput|CraftInput' } |
    Sort-Object -Unique |
    ForEach-Object { Write-Host "  [$_]" }
