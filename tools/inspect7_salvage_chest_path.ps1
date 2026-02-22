# inspect7_salvage_chest_path.ps1
#
# Purpose: Determine whether the salvage/repair bench uses CraftingHandler.GetNearbyChests
#          or a completely separate chest-lookup codepath with its own hardcoded range.
#
# Adjust $dll to match your Steam installation path.

$dll = "D:\SteamLibrary\steamapps\common\Core Keeper\CoreKeeper_Data\Managed"
[void][System.Reflection.Assembly]::LoadFile("$dll\Mono.Cecil.dll")

# Search all DLLs that might be relevant
$dlls = @("Pug.Other.dll", "Assembly-CSharp.dll", "Pug.Core.dll")

foreach ($dllName in $dlls) {
    $path = "$dll\$dllName"
    if (-not (Test-Path $path)) { continue }
    $m = [Mono.Cecil.ModuleDefinition]::ReadModule($path)

    Write-Host ""
    Write-Host "========== $dllName =========="

    # 1. Any class named with "Salvage" or "Repair" that isn't CraftingHandler
    Write-Host "--- Types with 'Salvage' or 'Repair' in name ---"
    $m.Types | Where-Object { $_.Name -match 'Salvage|Repair' } | ForEach-Object { Write-Host "  $($_.FullName)" }

    # 2. All methods across all types that call GetNearbyChestsByDistance
    Write-Host "--- Methods calling GetNearbyChestsByDistance ---"
    foreach ($type in $m.Types) {
        foreach ($method in $type.Methods) {
            if ($method.HasBody) {
                $hits = $method.Body.Instructions | Where-Object { $_.Operand -and $_.Operand.ToString() -match 'GetNearbyChestsByDistance|GetNearbyChests' }
                if ($hits) {
                    Write-Host "  $($type.FullName)::$($method.Name)"
                    $hits | ForEach-Object { "    $($_.OpCode)  $($_.Operand)" }
                }
            }
        }
    }

    # 3. All methods that load a float constant near 10 (ldc.r4 10) — finds hardcoded range values
    Write-Host "--- Methods with ldc.r4 near 10 (hardcoded range suspects) ---"
    foreach ($type in $m.Types) {
        foreach ($method in $type.Methods) {
            if ($method.HasBody) {
                $hits = $method.Body.Instructions | Where-Object { $_.OpCode.Code -eq 'Ldc_R4' -and [Math]::Abs([float]$_.Operand - 10.0) -lt 0.01 }
                if ($hits) {
                    Write-Host "  $($type.FullName)::$($method.Name)"
                }
            }
        }
    }

    # 4. SalvageAndRepair handler — full method list
    $sr = $m.Types | Where-Object { $_.Name -match 'SalvageAndRepair|SalvagingHandler|RepairHandler|SalvageHandler' }
    if ($sr) {
        $sr | ForEach-Object {
            Write-Host "--- $($_.FullName) methods ---"
            $_.Methods | ForEach-Object { "  $($_.Name)" }
        }
    }
}
