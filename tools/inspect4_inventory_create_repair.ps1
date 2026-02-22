# inspect4_inventory_create_repair.ps1
#
# Purpose: Inspect Inventory.Create.RepairOrReinforce IL to trace exactly how repair material
#          consumption works, and enumerate all callers of GetNearbyChests across Pug.Other.dll.
#
# Key findings:
#   - Inventory.Create.RepairOrReinforce delegates to InventoryUpdateSystem::ProcessInventoryChange.
#   - All callers of GetNearbyChests are in CraftingHandler itself — no external callers.
#     This means patching GetNearbyChests is sufficient for the display pass, but the
#     consumption pass reads cachedNearbyChests directly (see inspect3).
#
# Adjust $dll to match your Steam installation path.

$dll = "D:\SteamLibrary\steamapps\common\Core Keeper\CoreKeeper_Data\Managed"
[void][System.Reflection.Assembly]::LoadFile("$dll\Mono.Cecil.dll")
$m = [Mono.Cecil.ModuleDefinition]::ReadModule("$dll\Pug.Other.dll")

# Find Inventory.Create type
$ic = $m.Types | Where-Object { $_.FullName -eq 'Inventory.Create' }
Write-Host "=== Inventory.Create methods ==="
$ic.Methods | Select-Object Name | ForEach-Object { $_.Name }

Write-Host ""
Write-Host "=== Inventory.Create.RepairOrReinforce IL ==="
$method = $ic.Methods | Where-Object { $_.Name -eq 'RepairOrReinforce' }
Write-Host "Params:"
$method.Parameters | ForEach-Object { "  $($_.ParameterType) $($_.Name)" }
Write-Host "IL:"
$method.Body.Instructions | ForEach-Object { "  $($_.OpCode) $($_.Operand)" }

# Also look for any type that processes CraftActionData to find where chest-pulling happens
Write-Host ""
Write-Host "=== Types referencing GetNearbyChests ==="
foreach ($type in $m.Types) {
    foreach ($method2 in $type.Methods) {
        if ($method2.HasBody) {
            $refs = $method2.Body.Instructions | Where-Object { $_.Operand -and $_.Operand.ToString() -match 'GetNearbyChests' }
            if ($refs) {
                Write-Host "  $($type.FullName)::$($method2.Name)"
            }
        }
    }
}
