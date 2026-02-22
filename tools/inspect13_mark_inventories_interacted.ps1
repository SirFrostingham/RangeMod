# inspect13_mark_inventories_interacted.ps1
#
# Full IL of InventoryUpdateSystem::MarkInventoriesInteracted - this is where CraftActionData
# is actually processed server-side and likely where RepairOrReinforce is truly dispatched.
#
# Adjust $dll to match your Steam installation path.

$dll = "D:\SteamLibrary\steamapps\common\Core Keeper\CoreKeeper_Data\Managed"
[void][System.Reflection.Assembly]::LoadFile("$dll\Mono.Cecil.dll")
$m = [Mono.Cecil.ModuleDefinition]::ReadModule("$dll\Pug.Other.dll")
$sys = $m.Types | Where-Object { $_.FullName -eq 'Inventory.InventoryUpdateSystem' }

foreach ($method in $sys.Methods | Where-Object { $_.Name -match 'MarkInventories' }) {
    Write-Host "=== $($method.Name) ==="
    Write-Host "Params:"; $method.Parameters | ForEach-Object { "  $($_.ParameterType)  $($_.Name)" }
    if ($method.HasBody) {
        Write-Host "IL:"
        $method.Body.Instructions | ForEach-Object { "  $($_.OpCode)  $($_.Operand)" }
    } else {
        Write-Host "  (no body - Burst)"
    }
}

# Also dump GetNearbyChests-related calls from CraftingHandler.Use / OnActive / ManagedLateUpdate
# These might do the actual server-side nearby chest detection
Write-Host ""
Write-Host "=== CraftingHandler.Use / OnActive full IL ==="
$ch = $m.Types | Where-Object { $_.Name -eq 'CraftingHandler' }
foreach ($methodName in @('Use', 'OnActive', 'OnOccupied', 'ManagedLateUpdate')) {
    $method = $ch.Methods | Where-Object { $_.Name -eq $methodName }
    if ($method -and $method.HasBody) {
        Write-Host "--- $methodName ---"
        $method.Parameters | ForEach-Object { "  param: $($_.ParameterType)  $($_.Name)" }
        $method.Body.Instructions | ForEach-Object { "  $($_.OpCode)  $($_.Operand)" }
    }
}
