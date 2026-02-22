# ============================================================
# RangeMod — Deploy Script
# Copies mod files to the Core Keeper mods directory and
# packages a distributable zip for sharing.
# ============================================================

$ModName  = "RangeMod"
$ModsDir  = "$env:USERPROFILE\AppData\LocalLow\Pugstorm\Core Keeper\Steam\10717115\mods"
$Dest     = "$ModsDir\$ModName"
$Source   = $PSScriptRoot   # the folder containing this script
$ZipOut   = "$Source\$ModName.zip"

# ---- 1. Build the staged layout in the source tree ----------
$Staged = "$Source\_staged\$ModName"
if (Test-Path $Staged) { Remove-Item $Staged -Recurse -Force }
New-Item -ItemType Directory -Path "$Staged\Scripts" | Out-Null

Copy-Item "$Source\ModManifest.json" "$Staged\ModManifest.json"
Copy-Item "$Source\RangeMod.cs"      "$Staged\Scripts\RangeMod.cs"

Write-Host "[RangeMod] Staged to: $Staged"

# ---- 2. Install to local mods directory ---------------------
if (Test-Path $Dest) {
    Write-Host "[RangeMod] Removing existing install at: $Dest"
    Remove-Item $Dest -Recurse -Force
}
# Create dest dir and copy contents directly (avoids double-nesting if Dest survives Remove-Item)
New-Item -ItemType Directory -Path $Dest -Force | Out-Null
Copy-Item "$Staged\*" $Dest -Recurse -Force
Write-Host "[RangeMod] Installed to: $Dest"

# ---- 3. Create distributable zip ----------------------------
# Use "$Staged\*" (not $Staged) so the zip root contains ModManifest.json + Scripts/
# directly, without a RangeMod\ wrapper folder. mod.io places the zip contents
# into the mod folder automatically, so the extra wrapper causes double-nesting.
if (Test-Path $ZipOut) { Remove-Item $ZipOut -Force }
Compress-Archive -Path "$Staged\*" -DestinationPath $ZipOut
Write-Host "[RangeMod] Zip created: $ZipOut"

# ---- 4. Cleanup staged folder --------------------------------
Remove-Item "$Source\_staged" -Recurse -Force

Write-Host ""
Write-Host "Done! To share with others:"
Write-Host "  - Give them $ModName.zip"
Write-Host "  - They extract it so the folder structure is:"
Write-Host "    mods\$ModName\ModManifest.json"
Write-Host "    mods\$ModName\Scripts\RangeMod.cs"
