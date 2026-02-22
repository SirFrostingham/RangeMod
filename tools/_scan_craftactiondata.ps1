$dll = "D:\SteamLibrary\steamapps\common\Core Keeper\CoreKeeper_Data\Managed\Pug.Other.dll"
$bytes = [System.IO.File]::ReadAllBytes($dll)
$text = [System.Text.Encoding]::ASCII.GetString($bytes)
$chunks = $text -split '[^\x20-\x7E]+'

Write-Host "=== TryPopUIInputActionData context ==="
for ($i = 0; $i -lt $chunks.Count; $i++) {
    if ($chunks[$i] -match 'TryPopUIInput|UIInputActionData') {
        $start = [Math]::Max(0, $i-10)
        $end   = [Math]::Min($chunks.Count-1, $i+10)
        $ctx = $chunks[$start..$end] | Where-Object { $_.Length -gt 2 }
        Write-Host "--- @ $i ---"
        $ctx | ForEach-Object { Write-Host "  [$_]" }
    }
}

Write-Host ""
Write-Host "=== CraftActionData context ==="
for ($i = 0; $i -lt $chunks.Count; $i++) {
    if ($chunks[$i] -match 'CraftActionData|craftActionData') {
        $start = [Math]::Max(0, $i-10)
        $end   = [Math]::Min($chunks.Count-1, $i+10)
        $ctx = $chunks[$start..$end] | Where-Object { $_.Length -gt 2 }
        Write-Host "--- @ $i ---"
        $ctx | ForEach-Object { Write-Host "  [$_]" }
    }
}

Write-Host ""
Write-Host "=== SendRepair / AddCraft / QueueAction / SendAction ==="
$chunks | Where-Object { $_ -match 'SendRepair|SendCraft|QueueRepair|QueueCraft|AddRepair|SetRepair|SendAction|AddUIInput' } |
    Sort-Object -Unique | ForEach-Object { Write-Host "  [$_]" }
