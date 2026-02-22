# Scan for which class(es) contain RepairOrReinforce by examining method references in DLL metadata strings
$dll = "D:\SteamLibrary\steamapps\common\Core Keeper\CoreKeeper_Data\Managed\Pug.Other.dll"
$bytes = [System.IO.File]::ReadAllBytes($dll)
$text = [System.Text.Encoding]::ASCII.GetString($bytes)
$chunks = $text -split '[^\x20-\x7E]+'

# Find all chunks that mention a class + RepairOrReinforce pattern
$results = @()
for ($i = 0; $i -lt $chunks.Count; $i++) {
    if ($chunks[$i] -match 'RepairOrReinforce|ToggleRepair|ToggleReinforce') {
        $start = [Math]::Max(0, $i-8)
        $end   = [Math]::Min($chunks.Count-1, $i+8)
        $ctx = $chunks[$start..$end] | Where-Object { $_.Length -gt 2 }
        $results += "--- @ $i ---"
        $results += $ctx
    }
}
$results | Select-Object -Unique
