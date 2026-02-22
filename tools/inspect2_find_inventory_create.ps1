# inspect2_find_inventory_create.ps1
#
# Purpose: Scan all DLLs in Managed/ to locate which one contains the Inventory.Create type.
#          Needed because the type suspected of handling repair material consumption wasn't in
#          Assembly-CSharp.dll as expected.
#
# Key finding: Inventory.Create (and most relevant crafting types) live in Pug.Other.dll,
#              not Assembly-CSharp.dll.
#
# Adjust $dll to match your Steam installation path.

$dll = "D:\SteamLibrary\steamapps\common\Core Keeper\CoreKeeper_Data\Managed"
[void][System.Reflection.Assembly]::LoadFile("$dll\Mono.Cecil.dll")

# Find which DLL has Inventory.Create
foreach ($file in Get-ChildItem "$dll\*.dll") {
    try {
        $mod = [Mono.Cecil.ModuleDefinition]::ReadModule($file.FullName)
        $hit = $mod.Types | Where-Object { $_.FullName -eq 'Inventory.Create' }
        if ($hit) { Write-Host "Found Inventory.Create in: $($file.Name)" }
    } catch {}
}
