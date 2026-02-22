# Scan InventoryUtility for RepairOrReinforce method signature via Mono reflection at runtime.
# Instead, use Cecil (or just read raw IL strings) to find parameter types.

$dll = "D:\SteamLibrary\steamapps\common\Core Keeper\CoreKeeper_Data\Managed\Pug.Other.dll"

# Try loading the assembly and reflecting on InventoryUtility
try {
    $asm = [System.Reflection.Assembly]::LoadFile($dll)
    $type = $asm.GetType("Inventory.InventoryUtility")
    if ($null -eq $type) { $type = $asm.GetTypes() | Where-Object { $_.Name -eq "InventoryUtility" } | Select-Object -First 1 }

    Write-Host "=== InventoryUtility methods matching Repair/Reinforce/Nearby ==="
    $type.GetMethods([System.Reflection.BindingFlags]::Static -bor [System.Reflection.BindingFlags]::Public -bor [System.Reflection.BindingFlags]::NonPublic) |
        Where-Object { $_.Name -match 'Repair|Reinforce|Nearby|Chests' } |
        ForEach-Object {
            $params = $_.GetParameters() | ForEach-Object { "$($_.ParameterType.Name) $($_.Name)" }
            Write-Host "$($_.Name)($($params -join ', '))"
        }
}
catch {
    Write-Host "Load failed: $_"
    Write-Host "Falling back to string scan..."
    $bytes = [System.IO.File]::ReadAllBytes($dll)
    $text = [System.Text.Encoding]::ASCII.GetString($bytes)
    $chunks = $text -split '[^\x20-\x7E]+'
    # Find chunks near RepairOrReinforce
    for ($i = 0; $i -lt $chunks.Count; $i++) {
        if ($chunks[$i] -match 'RepairOrReinforce') {
            $start = [Math]::Max(0, $i-5)
            $end   = [Math]::Min($chunks.Count-1, $i+10)
            Write-Host "Context around RepairOrReinforce:"
            $chunks[$start..$end] | ForEach-Object { Write-Host "  [$_]" }
        }
    }
}
