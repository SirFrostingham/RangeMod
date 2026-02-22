# inspect16_input_action_processor.ps1
#
# Find where UIInputActionData / CraftBuffer gets dequeued and processed,
# specifically which system builds the NativeList<Entity> (inventoryEntities)
# before passing it to InventoryUtility.RepairOrReinforce.
# Also look at GetNearbyChestsForCraftingByDistance to understand what
# hardcoded range it uses internally.
#
# Adjust $dll to match your Steam installation path.

$dll = "D:\SteamLibrary\steamapps\common\Core Keeper\CoreKeeper_Data\Managed"
[void][System.Reflection.Assembly]::LoadFile("$dll\Mono.Cecil.dll")
$m = [Mono.Cecil.ModuleDefinition]::ReadModule("$dll\Pug.Other.dll")

# 1. All callers of CraftingHandler.GetNearbyChests - these are the paths we DO patch
Write-Host "=== All callers of CraftingHandler.GetNearbyChests ==="
foreach ($type in $m.Types) {
    foreach ($method in $type.Methods) {
        if ($method.HasBody) {
            $hits = $method.Body.Instructions | Where-Object {
                $_.Operand -and $_.Operand.ToString() -match 'CraftingHandler::GetNearbyChests'
            }
            if ($hits) {
                Write-Host "  $($type.FullName)::$($method.Name)"
            }
        }
    }
}

# 2. Types that contain CraftBuffer or UIInputActionData
Write-Host ""
Write-Host "=== Types containing CraftBuffer field or methods ==="
$m.Types | Where-Object { $_.Name -eq 'CraftBuffer' } | ForEach-Object {
    Write-Host "  $($_.FullName)"
    $_.Fields | ForEach-Object { "    field: $($_.FieldType)  $($_.Name)" }
    $_.Methods | ForEach-Object { "    method: $($_.Name)" }
}

# 3. Find all methods that call GetNearbyChestsForCraftingByDistance (not BurstDirectCall)
Write-Host ""
Write-Host "=== Callers of GetNearbyChestsForCraftingByDistance (managed wrapper) ==="
foreach ($type in $m.Types) {
    foreach ($method in $type.Methods) {
        if ($method.HasBody) {
            $hits = $method.Body.Instructions | Where-Object {
                $_.Operand -and $_.Operand.ToString() -match 'GetNearbyChestsForCraftingByDistance' -and $_.Operand.ToString() -notmatch '\$BurstDirectCall|\$BurstManaged'
            }
            if ($hits) {
                Write-Host "  $($type.FullName)::$($method.Name)"
                $hits | ForEach-Object { "    $($_.OpCode)  $($_.Operand)" }
            }
        }
    }
}

# 4. Find method that calls BOTH GetNearbyChests* AND RepairOrReinforce (the key execution method)
Write-Host ""
Write-Host "=== Methods calling both GetNearbyChests* AND something with inventory/entity lists ==="
foreach ($type in $m.Types) {
    foreach ($method in $type.Methods) {
        if (-not $method.HasBody) { continue }
        $insts = $method.Body.Instructions
        $hasNearby = $insts | Where-Object { $_.Operand -and $_.Operand.ToString() -match 'GetNearbyChests' }
        $hasRepair = $insts | Where-Object { $_.Operand -and $_.Operand.ToString() -match 'RepairOrReinforce|CraftItem|Craft\b' }
        if ($hasNearby -and $hasRepair) {
            Write-Host "  $($type.FullName)::$($method.Name)"
        }
    }
}

# 5. CraftingSystem or system that processes CraftBuffer - look in __codegen methods
Write-Host ""
Write-Host "=== All systems with 'Craft' or 'RepairOrReinforce' in their method names ==="
foreach ($type in $m.Types) {
    $hits = $type.Methods | Where-Object { $_.Name -match 'RepairOrReinforce|CraftItem|ProcessCraft' }
    if ($hits) {
        Write-Host "  $($type.FullName)"
        $hits | ForEach-Object { "    $($_.Name): params=$($_.Parameters.Count), hasBody=$($_.HasBody)" }
    }
}
