# inspect11_craft_action_system.ps1
#
# Find which system/type actually processes CraftActionData and calls RepairOrReinforce/Craft.
# Also find who builds the NativeList<Entity> (inventoryEntities) passed to RepairOrReinforce.
#
# Adjust $dll to match your Steam installation path.

$dll = "D:\SteamLibrary\steamapps\common\Core Keeper\CoreKeeper_Data\Managed"
[void][System.Reflection.Assembly]::LoadFile("$dll\Mono.Cecil.dll")

$dlls = @("Pug.Other.dll")
foreach ($dllName in $dlls) {
    $m = [Mono.Cecil.ModuleDefinition]::ReadModule("$dll\$dllName")

    # 1. All callers of InventoryUtility.RepairOrReinforce
    Write-Host "=== Callers of InventoryUtility.RepairOrReinforce ==="
    foreach ($type in $m.Types) {
        foreach ($method in $type.Methods) {
            if ($method.HasBody) {
                $hits = $method.Body.Instructions | Where-Object {
                    $_.Operand -and $_.Operand.ToString() -match 'RepairOrReinforce'
                }
                if ($hits) {
                    Write-Host "  $($type.FullName)::$($method.Name)"
                    $hits | ForEach-Object { "    $($_.OpCode)  $($_.Operand)" }
                }
            }
        }
    }

    # 2. All types with "Craft" in name (look for CraftingSystem, CraftActionSystem etc)
    Write-Host ""
    Write-Host "=== Types with 'Craft' in name ==="
    $m.Types | Where-Object { $_.Name -match 'Craft' } | ForEach-Object {
        Write-Host "  $($_.FullName)"
        $_.Methods | Where-Object { $_.Name -notmatch '\$|codegen|__.ctor' } | ForEach-Object { "    $($_.Name)" }
    }

    # 3. Which types/methods process CraftActionData
    Write-Host ""
    Write-Host "=== Callers that reference CraftActionData ==="
    foreach ($type in $m.Types) {
        foreach ($method in $type.Methods) {
            if ($method.HasBody) {
                $hits = $method.Body.Instructions | Where-Object {
                    $_.Operand -and $_.Operand.ToString() -match 'CraftActionData|CraftAction\b'
                }
                if ($hits) {
                    Write-Host "  $($type.FullName)::$($method.Name)"
                }
            }
        }
    }
}
