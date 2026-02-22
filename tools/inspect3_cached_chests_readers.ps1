# inspect3_cached_chests_readers.ps1
#
# Purpose: Confirm which CraftingHandler methods read the private cachedNearbyChests field
#          directly (via ldfld), and inspect HasMaterialsToBeUpgraded / CanBeRepaired signatures.
#
# Key findings:
#   - cachedNearbyChests is read directly (ldfld) by methods OTHER than GetNearbyChests,
#     including paths triggered during actual material consumption. This proved Bug B:
#     returning the list from GetNearbyChests alone isn't enough — the instance field
#     must also be written back via Traverse so those direct-field-read paths see our list.
#   - HasMaterialsToBeUpgraded accepts nearbyChestsToTakeMaterialsFrom: List<Entity> (new in 1.1+).
#   - CanBeRepaired does NOT take a chest list — it's a readonly check, safe to leave unpatched.
#
# Adjust $dll to match your Steam installation path.

$dll = "D:\SteamLibrary\steamapps\common\Core Keeper\CoreKeeper_Data\Managed"
[void][System.Reflection.Assembly]::LoadFile("$dll\Mono.Cecil.dll")
$m = [Mono.Cecil.ModuleDefinition]::ReadModule("$dll\Pug.Other.dll")
$ch = $m.Types | Where-Object { $_.Name -eq 'CraftingHandler' }

Write-Host "=== CanBeRepaired params ==="
$cbr = $ch.Methods | Where-Object { $_.Name -eq 'CanBeRepaired' }
$cbr.Parameters | ForEach-Object { "  $($_.ParameterType) $($_.Name)" }
Write-Host "=== CanBeRepaired IL ==="
$cbr.Body.Instructions | ForEach-Object { "  $($_.OpCode) $($_.Operand)" }

Write-Host ""
Write-Host "=== HasMaterialsToBeUpgraded params ==="
$hmu = $ch.Methods | Where-Object { $_.Name -eq 'HasMaterialsToBeUpgraded' }
$hmu.Parameters | ForEach-Object { "  $($_.ParameterType) $($_.Name)" }
Write-Host "=== HasMaterialsToBeUpgraded IL ==="
$hmu.Body.Instructions | ForEach-Object { "  $($_.OpCode) $($_.Operand)" }

# Check if anything reads cachedNearbyChests field directly
Write-Host ""
Write-Host "=== Methods that read cachedNearbyChests field directly ==="
foreach ($method in $ch.Methods) {
    if ($method.HasBody) {
        $reads = $method.Body.Instructions | Where-Object { $_.Operand -and $_.Operand.ToString() -match 'cachedNearbyChests' }
        if ($reads) {
            Write-Host "  $($method.Name)"
            $reads | ForEach-Object { "    $($_.OpCode) $($_.Operand)" }
        }
    }
}
