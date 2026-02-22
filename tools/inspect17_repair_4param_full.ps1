# inspect17_repair_4param_full.ps1
#
# Full IL of InventoryUtility.RepairOrReinforce (params=4) - the higher-level overload
# that calls GetNearbyChestsForCraftingByDistance internally.
# This is likely the true execution path for repair, called from managed code
# or from the action processing system.
#
# Adjust $dll to match your Steam installation path.

$dll = "D:\SteamLibrary\steamapps\common\Core Keeper\CoreKeeper_Data\Managed"
[void][System.Reflection.Assembly]::LoadFile("$dll\Mono.Cecil.dll")
$m = [Mono.Cecil.ModuleDefinition]::ReadModule("$dll\Pug.Other.dll")
$iu = $m.Types | Where-Object { $_.FullName -eq 'Inventory.InventoryUtility' }

Write-Host "=== All InventoryUtility.RepairOrReinforce overloads ==="
$rors = $iu.Methods | Where-Object { $_.Name -eq 'RepairOrReinforce' }
Write-Host "Count: $($rors.Count)"
foreach ($ror in $rors) {
    Write-Host ""
    Write-Host "--- Overload: $($ror.Parameters.Count) params, hasBody=$($ror.HasBody) ---"
    $ror.Parameters | ForEach-Object { "  param: $($_.ParameterType)  $($_.Name)" }
    if ($ror.HasBody) {
        Write-Host "IL:"
        $ror.Body.Instructions | ForEach-Object { "  $($_.OpCode)  $($_.Operand)" }
    }
}

Write-Host ""
Write-Host "=== InventoryUtility.CraftItem overloads ==="
$cis = $iu.Methods | Where-Object { $_.Name -eq 'CraftItem' }
foreach ($ci in $cis) {
    Write-Host ""
    Write-Host "--- Overload: $($ci.Parameters.Count) params, hasBody=$($ci.HasBody) ---"
    $ci.Parameters | ForEach-Object { "  param: $($_.ParameterType)  $($_.Name)" }
    if ($ci.HasBody) {
        Write-Host "IL:"
        $ci.Body.Instructions | ForEach-Object { "  $($_.OpCode)  $($_.Operand)" }
    }
}

# Also check if any of these call GetNearbyChestsForCraftingByDistance
Write-Host ""
Write-Host "=== Summary: do any InventoryUtility methods call GetNearbyChestsForCraftingByDistance? ==="
foreach ($method in $iu.Methods) {
    if ($method.HasBody) {
        $hits = $method.Body.Instructions | Where-Object {
            $_.Operand -and $_.Operand.ToString() -match 'GetNearbyChestsForCraftingByDistance|GetNearbyChestsByDistance'
        }
        if ($hits) {
            Write-Host "  $($method.Name) (params=$($method.Parameters.Count))"
            $hits | ForEach-Object { "    $($_.OpCode)  $($_.Operand)" }
        }
    }
}
