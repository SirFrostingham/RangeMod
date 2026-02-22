$dll = "D:\SteamLibrary\steamapps\common\Core Keeper\CoreKeeper_Data\Managed\Pug.Other.dll"
try {
    $asm = [System.Reflection.Assembly]::ReflectionOnlyLoadFrom($dll)
    Write-Host "Assembly loaded: $($asm.FullName)"
} catch {
    Write-Host "Load error: $_"; exit 1
}

try { $types = $asm.GetTypes() }
catch [System.Reflection.ReflectionTypeLoadException] {
    $types = $_.Exception.Types | Where-Object { $_ -ne $null }
}

Write-Host "Total types: $($types.Count)"
$types | Where-Object { $_.Name -match 'Inventory' } | Select-Object -First 30 | ForEach-Object { Write-Host $_.FullName }
