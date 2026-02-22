# inspect9_repair_action_trace.ps1
#
# Purpose: Trace the full repair/salvage execution path.
#   1. SalvageAndRepairUI.Salvage / ToggleRepair - what InventoryAction is sent?
#   2. ProcessInventoryChange repair branch - does it scan chests independently?
#   3. CraftingHandler.RepairOrReinforce - what calls GetNearbyChests?
#
# Adjust $dll to match your Steam installation path.

$dll = "D:\SteamLibrary\steamapps\common\Core Keeper\CoreKeeper_Data\Managed"
[void][System.Reflection.Assembly]::LoadFile("$dll\Mono.Cecil.dll")
$m = [Mono.Cecil.ModuleDefinition]::ReadModule("$dll\Pug.Other.dll")

# 1. SalvageAndRepairUI methods full IL
Write-Host "=== SalvageAndRepairUI full method list and IL ==="
$t = $m.Types | Where-Object { $_.Name -eq 'SalvageAndRepairUI' }
foreach ($method in $t.Methods | Sort-Object Name) {
    Write-Host "--- $($method.Name) ---"
    if ($method.HasBody) {
        $method.Body.Instructions | ForEach-Object { "  $($_.OpCode)  $($_.Operand)" }
    } else {
        Write-Host "  (no body)"
    }
}

# 2. InventoryAction enum values - find Repair/Reinforce/Salvage
Write-Host ""
Write-Host "=== InventoryAction enum values ==="
$enum = $m.Types | Where-Object { $_.Name -eq 'InventoryAction' }
if ($enum) {
    $enum.Fields | ForEach-Object { "  $($_.Name) = $($_.Constant)" }
} else {
    Write-Host "  Not found in Pug.Other.dll"
}

# 3. CraftingHandler.RepairOrReinforce full IL
Write-Host ""
Write-Host "=== CraftingHandler.RepairOrReinforce ==="
$ch = $m.Types | Where-Object { $_.Name -eq 'CraftingHandler' }
$ror = $ch.Methods | Where-Object { $_.Name -eq 'RepairOrReinforce' }
if ($ror) {
    Write-Host "Params:"; $ror.Parameters | ForEach-Object { "  $($_.ParameterType)  $($_.Name)" }
    Write-Host "IL:"
    $ror.Body.Instructions | ForEach-Object { "  $($_.OpCode)  $($_.Operand)" }
} else {
    Write-Host "  Not found"
}

# 4. Find what methods in ProcessInventoryChange call chain lead to chest searching for Craft/Repair actions
Write-Host ""
Write-Host "=== InventoryUpdateSystem methods ==="
$sys = $m.Types | Where-Object { $_.FullName -eq 'Inventory.InventoryUpdateSystem' }
$sys.Methods | Select-Object Name | ForEach-Object { "  $($_.Name)" }

# 5. Any method named with Craft/Repair/Salvage/Reinforce in InventoryUpdateSystem
Write-Host ""
Write-Host "=== InventoryUpdateSystem Craft/Repair/Salvage related methods full IL ==="
foreach ($method in $sys.Methods | Where-Object { $_.Name -match 'Craft|Repair|Salvage|Reinforce|Material' }) {
    Write-Host "--- $($method.Name) ---"
    Write-Host "Params:"; $method.Parameters | ForEach-Object { "  $($_.ParameterType)  $($_.Name)" }
    if ($method.HasBody) {
        $method.Body.Instructions | ForEach-Object { "  $($_.OpCode)  $($_.Operand)" }
    }
}

# 6. Look for Craft/Repair in InventoryUtility
Write-Host ""
Write-Host "=== InventoryUtility Craft/Repair methods ==="
$iu = $m.Types | Where-Object { $_.FullName -eq 'Inventory.InventoryUtility' }
foreach ($method in $iu.Methods | Where-Object { $_.Name -match 'Craft|Repair|Salvage|Reinforce' }) {
    Write-Host "--- $($method.Name) ---"
    Write-Host "Params:"; $method.Parameters | ForEach-Object { "  $($_.ParameterType)  $($_.Name)" }
    if ($method.HasBody) {
        $method.Body.Instructions | Where-Object { $_.Operand -match 'NearbyChest|GetNearby|range|distance|10' } | ForEach-Object { "  $($_.OpCode)  $($_.Operand)" }
    }
}
