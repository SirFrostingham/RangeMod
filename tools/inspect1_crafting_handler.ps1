# inspect1_crafting_handler.ps1
#
# Purpose: Verify the access modifier on CraftingHandler.entityMonoBehaviour (private vs public),
#          confirm RepairOrReinforce parameters, and inspect the IL of GetNearbyChests to confirm
#          it reads from this.entityMonoBehaviour.WorldPosition (not player position).
#
# Key findings from this script:
#   - entityMonoBehaviour field attributes: Private
#   - GetNearbyChests origin: ldfld EntityMonoBehaviour CraftingHandler::entityMonoBehaviour
#                             callvirt UnityEngine.Vector3 EntityMonoBehaviour::get_WorldPosition()
#   - This proved Bug A: our patch was searching from player.WorldPosition instead of the station.
#
# Adjust $dll to match your Steam installation path.

$dll = "D:\SteamLibrary\steamapps\common\Core Keeper\CoreKeeper_Data\Managed"
[void][System.Reflection.Assembly]::LoadFile("$dll\Mono.Cecil.dll")
$m = [Mono.Cecil.ModuleDefinition]::ReadModule("$dll\Pug.Other.dll")
$ch = $m.Types | Where-Object { $_.Name -eq 'CraftingHandler' }

Write-Host "=== entityMonoBehaviour field attributes ==="
$field = $ch.Fields | Where-Object { $_.Name -eq 'entityMonoBehaviour' }
Write-Host "Attributes: $($field.Attributes)"

Write-Host ""
Write-Host "=== RepairOrReinforce params ==="
$method = $ch.Methods | Where-Object { $_.Name -eq 'RepairOrReinforce' }
$method.Parameters | ForEach-Object { "  $($_.ParameterType) $($_.Name)" }

Write-Host ""
Write-Host "=== RepairOrReinforce IL ==="
$method.Body.Instructions | ForEach-Object { "  $($_.OpCode) $($_.Operand)" }

Write-Host ""
Write-Host "=== GetNearbyChests IL (check position source) ==="
$method2 = $ch.Methods | Where-Object { $_.Name -eq 'GetNearbyChests' }
$method2.Body.Instructions | Where-Object { $_.Operand -match 'Position|WorldPos|entityMono|player' } | ForEach-Object { "  $($_.OpCode) $($_.Operand)" }
