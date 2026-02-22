# inspect14_player_command_server.ps1
#
# Dump PlayerCommand.ServerSystem::OnUpdate to find where it uses ldc.r4 10 (the range),
# and what it does with CraftActionData / UIInputActionData (the repair/craft actions).
#
# Adjust $dll to match your Steam installation path.

$dll = "D:\SteamLibrary\steamapps\common\Core Keeper\CoreKeeper_Data\Managed"
[void][System.Reflection.Assembly]::LoadFile("$dll\Mono.Cecil.dll")
$m = [Mono.Cecil.ModuleDefinition]::ReadModule("$dll\Pug.Other.dll")

# Find PlayerCommand.ServerSystem
$pcs = $m.Types | Where-Object { $_.FullName -match 'PlayerCommand.*ServerSystem|ServerSystem.*PlayerCommand' }
Write-Host "=== Matching types ==="
$pcs | ForEach-Object { "  $($_.FullName)" }

$sys = $pcs | Select-Object -First 1
if ($sys) {
    Write-Host ""
    Write-Host "=== $($sys.FullName) methods ==="
    $sys.Methods | ForEach-Object { "  $($_.Name)" }

    Write-Host ""
    Write-Host "=== OnUpdate full IL ==="
    $onUpdate = $sys.Methods | Where-Object { $_.Name -eq 'OnUpdate' }
    if ($onUpdate -and $onUpdate.HasBody) {
        $onUpdate.Body.Instructions | ForEach-Object { "  $($_.OpCode)  $($_.Operand)" }
    } else {
        Write-Host "  (no body)"
    }
}

# Also check PlayerState namespace for the ServerSystem
Write-Host ""
Write-Host "=== PlayerState types ==="
$m.Types | Where-Object { $_.FullName -match 'PlayerState|PlayerCommand' } | ForEach-Object { "  $($_.FullName)" }

# Find all types whose OnUpdate method has ldc.r4 10
Write-Host ""
Write-Host "=== ALL OnUpdate methods with ldc.r4 10 ==="
foreach ($type in $m.Types) {
    $onUpd = $type.Methods | Where-Object { $_.Name -eq 'OnUpdate' -and $_.HasBody }
    foreach ($method in $onUpd) {
        $hits = $method.Body.Instructions | Where-Object { $_.OpCode.Code -eq 'Ldc_R4' -and [Math]::Abs([float]$_.Operand - 10.0) -lt 0.01 }
        if ($hits) {
            Write-Host "  $($type.FullName)"
        }
    }
}
