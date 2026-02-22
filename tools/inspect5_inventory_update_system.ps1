# inspect5_inventory_update_system.ps1
#
# Purpose: Inspect InventoryUpdateSystem::ProcessInventoryChange to confirm it reads the
#          cachedNearbyChests instance field directly rather than calling GetNearbyChests().
#          Also checks CraftingUIBase::ActivateRecipeSlot to understand how chestsStartIndex
#          is computed when building the recipe display.
#
# Key finding: ProcessInventoryChange does NOT call GetNearbyChests() — it reads
#              `this.cachedNearbyChests` via ldfld. This is the definitive proof of Bug B:
#              our Harmony prefix must write the extended list back to that instance field
#              (via Traverse) or the actual craft/repair action always uses an empty list.
#
# Adjust $dll to match your Steam installation path.

$dll = "D:\SteamLibrary\steamapps\common\Core Keeper\CoreKeeper_Data\Managed"
[void][System.Reflection.Assembly]::LoadFile("$dll\Mono.Cecil.dll")
$m = [Mono.Cecil.ModuleDefinition]::ReadModule("$dll\Pug.Other.dll")

# CraftingUIBase::ActivateRecipeSlot — how does it build chestsStartIndex?
Write-Host "=== CraftingUIBase::ActivateRecipeSlot IL ==="
$t = $m.Types | Where-Object { $_.Name -eq 'CraftingUIBase' }
$method = $t.Methods | Where-Object { $_.Name -eq 'ActivateRecipeSlot' }
Write-Host "Params:"; $method.Parameters | ForEach-Object { "  $($_.ParameterType) $($_.Name)" }
Write-Host "IL:"; $method.Body.Instructions | ForEach-Object { "  $($_.OpCode) $($_.Operand)" }

Write-Host ""
Write-Host "=== InventoryUpdateSystem::ProcessInventoryChange relevant refs ==="
$sys = $m.Types | Where-Object { $_.FullName -eq 'Inventory.InventoryUpdateSystem' }
$method2 = $sys.Methods | Where-Object { $_.Name -eq 'ProcessInventoryChange' }
Write-Host "Params:"; $method2.Parameters | ForEach-Object { "  $($_.ParameterType) $($_.Name)" }
# Just show instructions that reference GetNearbyChests, Craft, nearby, chest
$method2.Body.Instructions | Where-Object {
    $op = $_.Operand -as [string]
    $op -match 'NearbyChest|GetNearby|craftingEntity|CraftAction|int0|int1|chestsStart'
} | ForEach-Object { "  $($_.OpCode) $($_.Operand)" }
