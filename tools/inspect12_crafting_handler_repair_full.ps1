# inspect12_crafting_handler_repair_full.ps1
#
# Full IL of CraftingHandler.RepairOrReinforce — this is the actual repair execution
# that calls InventoryUtility.RepairOrReinforce. Find exactly how it builds the
# NativeList<Entity> (inventoryEntities + chestsStartIndex) it passes in.
#
# Adjust $dll to match your Steam installation path.

$dll = "D:\SteamLibrary\steamapps\common\Core Keeper\CoreKeeper_Data\Managed"
[void][System.Reflection.Assembly]::LoadFile("$dll\Mono.Cecil.dll")
$m = [Mono.Cecil.ModuleDefinition]::ReadModule("$dll\Pug.Other.dll")
$ch = $m.Types | Where-Object { $_.Name -eq 'CraftingHandler' }

Write-Host "=== CraftingHandler.RepairOrReinforce overloads ==="
$methods = $ch.Methods | Where-Object { $_.Name -eq 'RepairOrReinforce' }
foreach ($method in $methods) {
    Write-Host "--- overload ---"
    Write-Host "Params:"; $method.Parameters | ForEach-Object { "  $($_.ParameterType)  $($_.Name)" }
    if ($method.HasBody) {
        Write-Host "IL:"
        $method.Body.Instructions | ForEach-Object { "  $($_.OpCode)  $($_.Operand)" }
    } else {
        Write-Host "  (no body)"
    }
}

# Also dump InventoryHandler.CraftItem since it's in the CraftActionData callers list
Write-Host ""
Write-Host "=== InventoryHandler.CraftItem IL ==="
$ih = $m.Types | Where-Object { $_.Name -eq 'InventoryHandler' }
$ci = $ih.Methods | Where-Object { $_.Name -eq 'CraftItem' }
foreach ($method in $ci) {
    Write-Host "Params:"; $method.Parameters | ForEach-Object { "  $($_.ParameterType)  $($_.Name)" }
    if ($method.HasBody) {
        $method.Body.Instructions | ForEach-Object { "  $($_.OpCode)  $($_.Operand)" }
    }
}

# UIMouse UpdateMouseUIInput - what does it do with RepairOrReinforce?
Write-Host ""
Write-Host "=== UIMouse.UpdateMouseUIInput RepairOrReinforce call context ==="
$um = $m.Types | Where-Object { $_.Name -eq 'UIMouse' }
$umi = $um.Methods | Where-Object { $_.Name -eq 'UpdateMouseUIInput' }
if ($umi -and $umi.HasBody) {
    # get surrounding instructions around RepairOrReinforce call
    $insts = $umi.Body.Instructions
    for ($i = 0; $i -lt $insts.Count; $i++) {
        if ($insts[$i].Operand -and $insts[$i].Operand.ToString() -match 'RepairOrReinforce') {
            $start = [Math]::Max(0, $i - 20)
            $end = [Math]::Min($insts.Count - 1, $i + 5)
            for ($j = $start; $j -le $end; $j++) {
                "  [$j] $($insts[$j].OpCode)  $($insts[$j].Operand)"
            }
        }
    }
}
