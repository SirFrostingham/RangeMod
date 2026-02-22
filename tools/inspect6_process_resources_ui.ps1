# inspect6_process_resources_ui.ps1
#
# Purpose: Inspect ProcessResourcesCraftingUI::ActivateRecipeSlot (the salvage/repair UI
#          variant) and confirm EntityMonoBehaviour.WorldPosition is accessible as a property.
#          Also verifies entityMonoBehaviour field type and attributes on CraftingHandler.
#
# Key findings:
#   - CraftingHandler.entityMonoBehaviour: Private, type EntityMonoBehaviour — must use
#     Traverse to access it from a Harmony patch.
#   - EntityMonoBehaviour.WorldPosition has a public getter — safe to call once we have
#     the instance via Traverse.
#   - ProcessResourcesCraftingUI::ActivateRecipeSlot calls GetNearbyChests() on the
#     CraftingHandler, confirming the display path goes through our prefix patch.
#
# Adjust $dll to match your Steam installation path.

$dll = "D:\SteamLibrary\steamapps\common\Core Keeper\CoreKeeper_Data\Managed"
[void][System.Reflection.Assembly]::LoadFile("$dll\Mono.Cecil.dll")
$m = [Mono.Cecil.ModuleDefinition]::ReadModule("$dll\Pug.Other.dll")

Write-Host "=== ProcessResourcesCraftingUI::ActivateRecipeSlot IL ==="
$t = $m.Types | Where-Object { $_.Name -eq 'ProcessResourcesCraftingUI' }
$method = $t.Methods | Where-Object { $_.Name -eq 'ActivateRecipeSlot' }
Write-Host "Params:"; $method.Parameters | ForEach-Object { "  $($_.ParameterType) $($_.Name)" }
Write-Host "IL (relevant lines only):"
$method.Body.Instructions | Where-Object {
    $op = $_.Operand -as [string]
    $op -match 'NearbyChest|GetNearby|Repair|Craft|Salvage|Material|chest'
} | ForEach-Object { "  $($_.OpCode) $($_.Operand)" }

Write-Host ""
Write-Host "=== CraftingHandler.entityMonoBehaviour field ==="
$ch = $m.Types | Where-Object { $_.Name -eq 'CraftingHandler' }
$field = $ch.Fields | Where-Object { $_.Name -eq 'entityMonoBehaviour' }
Write-Host "Name: $($field.Name), Type: $($field.FieldType), Attributes: $($field.Attributes)"

Write-Host ""
Write-Host "=== EntityMonoBehaviour.WorldPosition ==="
$emb = $m.Types | Where-Object { $_.Name -eq 'EntityMonoBehaviour' }
$wp = $emb.Properties | Where-Object { $_.Name -eq 'WorldPosition' }
Write-Host "WorldPosition getter: $($wp.GetMethod)"
