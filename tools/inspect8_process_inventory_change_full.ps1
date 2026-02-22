# inspect8_process_inventory_change_full.ps1
#
# Purpose: Dump full IL of InventoryUpdateSystem::ProcessInventoryChange to see exactly
#          how it pulls materials during repair/craft — does it read cachedNearbyChests
#          from a CraftingHandler, or does it do its own independent chest search?
#          Also inspect GetNearbyChestsForCraftingByDistance to find its hardcoded range.
#
# Adjust $dll to match your Steam installation path.

$dll = "D:\SteamLibrary\steamapps\common\Core Keeper\CoreKeeper_Data\Managed"
[void][System.Reflection.Assembly]::LoadFile("$dll\Mono.Cecil.dll")
$m = [Mono.Cecil.ModuleDefinition]::ReadModule("$dll\Pug.Other.dll")

# 1. Full IL of GetNearbyChestsForCraftingByDistance (find its hardcoded range)
Write-Host "=== InventoryUtility::GetNearbyChestsForCraftingByDistance full IL ==="
$iu = $m.Types | Where-Object { $_.FullName -eq 'Inventory.InventoryUtility' }
$method = $iu.Methods | Where-Object { $_.Name -eq 'GetNearbyChestsForCraftingByDistance' }
if ($method -and $method.HasBody) {
    $method.Body.Instructions | ForEach-Object { "  $($_.OpCode)  $($_.Operand)" }
} else {
    Write-Host "  (no body - likely delegates to Burst direct call)"
}
Write-Host "  Return type: $($method.ReturnType)"
Write-Host "  Params:"; $method.Parameters | ForEach-Object { "    $($_.ParameterType)  $($_.Name)" }

# 1b. BurstManaged version
Write-Host ""
Write-Host "=== GetNearbyChestsForCraftingByDistance`$BurstManaged full IL ==="
$bm = $iu.Methods | Where-Object { $_.Name -match 'GetNearbyChestsForCraftingByDistance.*BurstManaged' }
if ($bm -and $bm.HasBody) {
    $bm.Body.Instructions | ForEach-Object { "  $($_.OpCode)  $($_.Operand)" }
}

# 2. Full IL of ProcessInventoryChange — every instruction
Write-Host ""
Write-Host "=== InventoryUpdateSystem::ProcessInventoryChange full IL ==="
$sys = $m.Types | Where-Object { $_.FullName -eq 'Inventory.InventoryUpdateSystem' }
$pic = $sys.Methods | Where-Object { $_.Name -eq 'ProcessInventoryChange' }
Write-Host "  Params:"; $pic.Parameters | ForEach-Object { "    $($_.ParameterType)  $($_.Name)" }
Write-Host "  IL:"
$pic.Body.Instructions | ForEach-Object { "  $($_.OpCode)  $($_.Operand)" }
