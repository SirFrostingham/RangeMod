# Load all DLLs from Managed folder so InventoryUtility can be reflected
$managed = "D:\SteamLibrary\steamapps\common\Core Keeper\CoreKeeper_Data\Managed"

Add-Type -Language CSharp @"
using System;
using System.Reflection;
public class AsmLoader {
    public static Assembly LoadFrom(string path) {
        try { return Assembly.LoadFrom(path); } catch { return null; }
    }
}
"@

# Load dependency DLLs first
foreach ($f in Get-ChildItem $managed -Filter "*.dll") {
    [AsmLoader]::LoadFrom($f.FullName) | Out-Null
}

$asm = [AsmLoader]::LoadFrom("$managed\Pug.Other.dll")
if ($null -eq $asm) { Write-Host "Failed to load Pug.Other.dll"; exit }

$type = $asm.GetTypes() | Where-Object { $_.Name -eq "InventoryUtility" } | Select-Object -First 1
if ($null -eq $type) { Write-Host "InventoryUtility not found"; exit }

Write-Host "=== InventoryUtility methods ==="
$flags = [System.Reflection.BindingFlags]::Static -bor [System.Reflection.BindingFlags]::Public -bor [System.Reflection.BindingFlags]::NonPublic
$type.GetMethods($flags) |
    Where-Object { $_.Name -match 'Repair|Reinforce|Chests|Craft|Salvage' } |
    ForEach-Object {
        $params = $_.GetParameters() | ForEach-Object { "$($_.ParameterType.Name) $($_.Name)" }
        Write-Host "$($_.Name)($($params -join ', '))"
    }
