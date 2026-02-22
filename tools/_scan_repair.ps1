$dll = "D:\SteamLibrary\steamapps\common\Core Keeper\CoreKeeper_Data\Managed\Pug.Other.dll"
$bytes = [System.IO.File]::ReadAllBytes($dll)
$text = [System.Text.Encoding]::ASCII.GetString($bytes)

$repair = $text -split '[^\x20-\x7E]+' |
    Where-Object { $_.Length -gt 4 -and $_ -match 'Repair|Salvage|Reinforce|RepairHandler|SalvageHandler' } |
    Sort-Object -Unique

Write-Host "=== Repair/Salvage symbols ==="
$repair

$inv = $text -split '[^\x20-\x7E]+' |
    Where-Object { $_.Length -gt 4 -and $_ -match 'GetNearbyChests' } |
    Sort-Object -Unique

Write-Host ""
Write-Host "=== GetNearbyChests symbols ==="
$inv
