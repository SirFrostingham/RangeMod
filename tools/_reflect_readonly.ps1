# Load assembly, ignore loader exceptions, just grab InventoryUtility methods
$dll = "D:\SteamLibrary\steamapps\common\Core Keeper\CoreKeeper_Data\Managed\Pug.Other.dll"
try {
    $asm = [System.Reflection.Assembly]::ReflectionOnlyLoadFrom($dll)
} catch {
    Write-Host "ReflectionOnly failed: $_"
    exit 1
}

try {
    $types = $asm.GetTypes()
} catch [System.Reflection.ReflectionTypeLoadException] {
    $types = $_.Exception.Types | Where-Object { $_ -ne $null }
}

$type = $types | Where-Object { $_.FullName -eq "Inventory.InventoryUtility" } | Select-Object -First 1
if ($null -eq $type) {
    Write-Host "Types found:"
    $types | Where-Object { $_.Name -match 'Inventory' } | Select-Object -First 20 | ForEach-Object { Write-Host "  $($_.FullName)" }
    exit 1
}

Write-Host "=== InventoryUtility methods (ReflectionOnly) ==="
$flags = [System.Reflection.BindingFlags]::Static -bor [System.Reflection.BindingFlags]::Public -bor [System.Reflection.BindingFlags]::NonPublic -bor [System.Reflection.BindingFlags]::Instance
$type.GetMethods($flags) |
    Where-Object { $_.Name -match 'Repair|Reinforce|Nearby|Chests|Salvage|Craft' } |
    ForEach-Object {
        try {
            $params = $_.GetParameters() | ForEach-Object { "$($_.ParameterType.Name) $($_.Name)" }
            Write-Host "$($_.Name)($($params -join ', '))"
        } catch {
            Write-Host "$($_.Name)(ERROR reading params)"
        }
    }
