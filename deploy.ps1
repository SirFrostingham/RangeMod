# ============================================================
# RangeMod — Deploy Script
# Copies mod files to the Core Keeper mods directory,
# clears the compile cache, and publishes to mod.io.
# ============================================================
# SECURITY: Keep this file private — it contains your mod.io API key.

$ModName    = "RangeMod"
$ModsDir    = "$env:USERPROFILE\AppData\LocalLow\Pugstorm\Core Keeper\Steam\10717115\mods"
$Dest       = "$ModsDir\$ModName"
$Source     = $PSScriptRoot   # the folder containing this script
$ZipOut     = "$Source\$ModName.zip"

# mod.io config — credentials live in secrets.ps1 (git-ignored)
# Copy secrets.example.ps1 -> secrets.ps1 and fill in your values.
$secretsFile = Join-Path $PSScriptRoot "secrets.ps1"
if (-not (Test-Path $secretsFile)) {
    Write-Error "Missing secrets.ps1 -- copy secrets.example.ps1 to secrets.ps1 and fill in credentials."
    exit 1
}
. $secretsFile
$ModioGameId  = 5289
$ModioModId   = 5811900

# ---- 1. Read and bump version, then stage layout -------------
# Read the version string from the source file and bump patch automatically on deploy.
$versionLine = Get-Content "$Source\RangeMod.cs" | Select-String 'VERSION\s*=\s*"([^"]+)"'
if (-not $versionLine) { throw "Could not read VERSION from RangeMod.cs" }
$oldVersion = $versionLine.Matches[0].Groups[1].Value
$parts = $oldVersion -split '\.'
if ($parts.Length -lt 3) { throw "VERSION format unexpected: $oldVersion" }
$parts[-1] = [int]$parts[-1] + 1
$newVersion = ($parts -join '.')
# Update RangeMod.cs with the bumped version
# Simpler regex: replace any VERSION = "x.y.z" line
$versionPattern = 'VERSION\s*=\s*"[^"]+"'
$versionReplacement = "VERSION = `"$newVersion`""
(Get-Content "$Source\RangeMod.cs") |
    ForEach-Object { $_ -replace $versionPattern, $versionReplacement } |
    Set-Content "$Source\RangeMod.cs"

Write-Host "[RangeMod] Version bumped: $oldVersion -> $newVersion"

# ---- Build the staged layout
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

# ---- 2b. Delete the compiled mod cache ----------------------
# The game caches the compiled DLL in LocalAppData\Temp. If the cache exists and
# is newer than the .cs source, the game skips recompilation and runs stale code.
# Deleting it forces a fresh Roslyn compile on next game start.
$ModCache = "$env:LOCALAPPDATA\Temp\Pugstorm\Core Keeper\ModLoader\$ModName"
if (Test-Path $ModCache) {
    Remove-Item $ModCache -Recurse -Force
    Write-Host "[RangeMod] Cleared mod compile cache: $ModCache"
} else {
    Write-Host "[RangeMod] No compile cache found (clean slate)."
}

# ---- 3. Create distributable zip ----------------------------
# Use "$Staged\*" (not $Staged) so the zip root contains ModManifest.json + Scripts/
# directly, without a RangeMod\ wrapper folder. mod.io places the zip contents
# into the mod folder automatically, so the extra wrapper causes double-nesting.
# Write to a temp file first, then replace — avoids lock failures when VS Code
# or Explorer has the previous zip open.
$ZipTmp = "$Source\_RangeMod_new.zip"
if (Test-Path $ZipTmp) { Remove-Item $ZipTmp -Force }
Compress-Archive -Path "$Staged\*" -DestinationPath $ZipTmp -Force
if (-not (Test-Path $ZipTmp)) { throw "Zip was not created: $ZipTmp" }
if (Test-Path $ZipOut) { Remove-Item $ZipOut -Force -ErrorAction SilentlyContinue }
Move-Item $ZipTmp $ZipOut -Force
$zipSize = (Get-Item $ZipOut).Length
Write-Host "[RangeMod] Zip created: $ZipOut ($zipSize bytes, $(Get-Date -Format 'HH:mm:ss'))"

# ---- 4. Publish to mod.io ----------------------------------
# Read the version string from the source file.
$versionLine = Get-Content "$Source\RangeMod.cs" | Select-String 'VERSION\s*=\s*"([^"]+)"'
$modVersion  = if ($versionLine) { $versionLine.Matches[0].Groups[1].Value } else { "unknown" }
$changelog   = "Auto-deployed v$modVersion via deploy.ps1"

if (-not $ModioOAuthToken) {
    Write-Warning "[RangeMod] Skipping mod.io publish -- set ModioOAuthToken in deploy.ps1."
    Write-Warning "           Get a token at: https://mod.io/me/access  (OAuth 2 Access -> Generate Token)"
} else {
Write-Host "[RangeMod] Publishing v$modVersion to mod.io..."
try {
    Add-Type -AssemblyName System.Net.Http

    # File uploads require OAuth2 Bearer token (API keys are read-only).
    $uri    = "https://api.mod.io/v1/games/$ModioGameId/mods/$ModioModId/files"
    $client = New-Object System.Net.Http.HttpClient
    $client.DefaultRequestHeaders.Authorization =
        New-Object System.Net.Http.Headers.AuthenticationHeaderValue("Bearer", $ModioOAuthToken)

    $multipart = New-Object System.Net.Http.MultipartFormDataContent

    # Attach zip
    $fileStream   = [System.IO.File]::OpenRead($ZipOut)
    $fileContent  = New-Object System.Net.Http.StreamContent($fileStream)
    $fileContent.Headers.ContentType =
        [System.Net.Http.Headers.MediaTypeHeaderValue]::Parse("application/zip")
    $multipart.Add($fileContent, "filedata", [System.IO.Path]::GetFileName($ZipOut))

    # Other fields
    $multipart.Add([System.Net.Http.StringContent]::new($modVersion), "version")
    $multipart.Add([System.Net.Http.StringContent]::new($changelog),  "changelog")
    $multipart.Add([System.Net.Http.StringContent]::new("1"),          "active")

    $res     = $client.PostAsync($uri, $multipart).Result
    $body    = $res.Content.ReadAsStringAsync().Result
    $fileStream.Close()

    if ($res.IsSuccessStatusCode) {
        $json = $body | ConvertFrom-Json
        Write-Host "[RangeMod] mod.io upload OK - file id: $($json.id), version: $($json.version)"
    } else {
        Write-Warning "[RangeMod] mod.io upload failed (HTTP $([int]$res.StatusCode)): $body"
    }
}
catch {
    Write-Warning "[RangeMod] mod.io upload FAILED: $($_.Exception.Message)"
}
} # end if $ModioOAuthToken

# ---- 5. Cleanup staged folder --------------------------------
Remove-Item "$Source\_staged" -Recurse -Force

Write-Host ""
Write-Host "Done!"
Write-Host "  Local install : $Dest"
Write-Host "  mod.io page   : https://mod.io/g/corekeeper/m/rangemod"
