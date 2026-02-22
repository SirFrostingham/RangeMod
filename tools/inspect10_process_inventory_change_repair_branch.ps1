# inspect10_process_inventory_change_repair_branch.ps1
#
# Dump the full unfiltered IL of ProcessInventoryChange so we can trace exactly
# where it builds the NativeList<Entity> that it passes to RepairOrReinforce/Craft,
# and confirm whether it calls GetNearbyChestsForCraftingByDistance or reads
# cachedNearbyChests from somewhere else.
#
# Also dumps Inventory.Create.RepairOrReinforce to see how CraftActionData is built.
#
# Adjust $dll to match your Steam installation path.

$dll = "D:\SteamLibrary\steamapps\common\Core Keeper\CoreKeeper_Data\Managed"
[void][System.Reflection.Assembly]::LoadFile("$dll\Mono.Cecil.dll")
$m = [Mono.Cecil.ModuleDefinition]::ReadModule("$dll\Pug.Other.dll")

# 1. Exact signature of GetNearbyChestsForCraftingByDistance (confirm what we patched)
Write-Host "=== GetNearbyChestsForCraftingByDistance exact signature ==="
$iu = $m.Types | Where-Object { $_.FullName -eq 'Inventory.InventoryUtility' }
$iu.Methods | Where-Object { $_.Name -match 'GetNearbyChests' } | ForEach-Object {
    Write-Host "  $($_.Name)"
    $_.Parameters | ForEach-Object { "    $($_.ParameterType)  $($_.Name)" }
}

# 2. CraftActionData fields
Write-Host ""
Write-Host "=== CraftActionData fields ==="
$cad = $m.Types | Where-Object { $_.Name -eq 'CraftActionData' }
if ($cad) {
    $cad.Fields | ForEach-Object { "  $($_.FieldType)  $($_.Name)" }
} else {
    # Try Assembly-CSharp
    $m2 = [Mono.Cecil.ModuleDefinition]::ReadModule("$dll\Assembly-CSharp.dll")
    $cad2 = $m2.Types | Where-Object { $_.Name -eq 'CraftActionData' }
    if ($cad2) { $cad2.Fields | ForEach-Object { "  $($_.FieldType)  $($_.Name)" } }
    else { Write-Host "  Not found" }
}

# 3. Inventory.Create.RepairOrReinforce full IL
Write-Host ""
Write-Host "=== Inventory.Create.RepairOrReinforce full IL ==="
$ic = $m.Types | Where-Object { $_.FullName -eq 'Inventory.Create' }
$ror = $ic.Methods | Where-Object { $_.Name -eq 'RepairOrReinforce' }
$ror.Parameters | ForEach-Object { "  param: $($_.ParameterType)  $($_.Name)" }
if ($ror.HasBody) {
    $ror.Body.Instructions | ForEach-Object { "  $($_.OpCode)  $($_.Operand)" }
}

# 4. Full unfiltered IL of ProcessInventoryChange - output to separate file to avoid truncation
Write-Host ""
Write-Host "=== InventoryUpdateSystem::ProcessInventoryChange (writing to temp file) ==="
$sys = $m.Types | Where-Object { $_.FullName -eq 'Inventory.InventoryUpdateSystem' }
$pic = $sys.Methods | Where-Object { $_.Name -eq 'ProcessInventoryChange' }
$picLines = @()
$picLines += "PARAMS:"
$pic.Parameters | ForEach-Object { $picLines += "  $($_.ParameterType)  $($_.Name)" }
$picLines += "IL:"
if ($pic.HasBody) {
    $pic.Body.Instructions | ForEach-Object { $picLines += "  $($_.OpCode)  $($_.Operand)" }
} else {
    $picLines += "  (no body)"
}
$picLines | Out-File "$env:TEMP\pic_il.txt" -Encoding utf8
Write-Host "Written to $env:TEMP\pic_il.txt ($(($picLines).Count) lines)"

# 5. Search the ProcessInventoryChange IL for anything related to chests/nearby/crafting
Write-Host ""
Write-Host "=== ProcessInventoryChange IL lines mentioning chest/nearby/cache/repair/craft ==="
$picLines | Where-Object { $_ -match 'NearbyChest|cache|Repair|Craft|Reinforce|RepairOr|chestsStart|GetNearby|cachedNearby|ForCrafting' }
