# inspect15_repair_overloads_and_chest_builder.ps1
#
# Find ALL overloads of CraftingHandler.RepairOrReinforce and their exact signatures.
# Find what calls InventoryUtility.RepairOrReinforce and the 20 instructions BEFORE that call
# (to see how inventoryEntities NativeList is built).
#
# Adjust $dll to match your Steam installation path.

$dll = "D:\SteamLibrary\steamapps\common\Core Keeper\CoreKeeper_Data\Managed"
[void][System.Reflection.Assembly]::LoadFile("$dll\Mono.Cecil.dll")
$m = [Mono.Cecil.ModuleDefinition]::ReadModule("$dll\Pug.Other.dll")

# 1. ALL overloads of CraftingHandler.RepairOrReinforce
Write-Host "=== All CraftingHandler.RepairOrReinforce overloads ==="
$ch = $m.Types | Where-Object { $_.Name -eq 'CraftingHandler' }
$rors = $ch.Methods | Where-Object { $_.Name -eq 'RepairOrReinforce' }
Write-Host "Count: $($rors.Count)"
foreach ($ror in $rors) {
    Write-Host "  Sig: $($ror.FullName)"
    $ror.Parameters | ForEach-Object { "    param: $($_.ParameterType)  $($_.Name)" }
    Write-Host "  HasBody: $($ror.HasBody)"
    if ($ror.HasBody) {
        Write-Host "  IL count: $($ror.Body.Instructions.Count)"
    }
}

# 2. ALL callers of InventoryUtility.RepairOrReinforce - show 25 instructions BEFORE the call
Write-Host ""
Write-Host "=== Context before InventoryUtility.RepairOrReinforce call ==="
foreach ($type in $m.Types) {
    foreach ($method in $type.Methods) {
        if (-not $method.HasBody) { continue }
        $insts = $method.Body.Instructions
        for ($i = 0; $i -lt $insts.Count; $i++) {
            if ($insts[$i].Operand -and $insts[$i].Operand.ToString() -match 'InventoryUtility::RepairOrReinforce') {
                Write-Host "--- $($type.FullName)::$($method.Name) at offset $($insts[$i].Offset) ---"
                $start = [Math]::Max(0, $i - 30)
                for ($j = $start; $j -le $i; $j++) {
                    "  [$j] $($insts[$j].OpCode)  $($insts[$j].Operand)"
                }
            }
        }
    }
}

# 3. Also check InventoryUtility.RepairOrReinforce signature
Write-Host ""
Write-Host "=== InventoryUtility.RepairOrReinforce ALL overloads ==="
$iu = $m.Types | Where-Object { $_.FullName -eq 'Inventory.InventoryUtility' }
$iu.Methods | Where-Object { $_.Name -eq 'RepairOrReinforce' } | ForEach-Object {
    Write-Host "  Sig: $($_.FullName)"
    $_.Parameters | ForEach-Object { "    $($_.ParameterType)  $($_.Name)" }
}
