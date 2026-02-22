# RangeMod — Extended Crafting Range

A mod for **Core Keeper** that extends the crafting workbench's nearby-chest search radius to **5× the vanilla range** (50 units vs. the default 10), so you can craft from materials stored in chests without carrying them in your inventory.

## What it does

When you open a crafting station (workbench, cooking pot, furnace, anvil, etc.), Core Keeper normally searches for chests within **10 units** of the workstation. This mod expands that radius to **50 units**, letting you keep your materials stored neatly in nearby chests and craft directly from them.

Works with all crafting station types:
- Workbenches (all tiers)
- Cooking Pots
- Furnaces
- Anvils
- Salvage & Repair Stations
- Alchemist's, Distillery, Painter's, Carpenter's, Railway Forge, Electronics, Automation, Key Casting Tables, Looms

## Compatibility

| Game version | Status |
|---|---|
| 1.1.2.8+ | ✅ Supported |
| 0.7.x | ❌ Use [futroo's mod](https://mod.io/g/corekeeper/m/extended-crafting-range) instead |

> This mod was written specifically for the ECS rewrite in Core Keeper 1.1+. The older mods on mod.io target the pre-1.1 API and will not work on current game versions.

## No dependencies

All libraries this mod uses (`0Harmony`, `PugMod.SDK`, `Pug.Other`, `Assembly-CSharp`) are bundled inside the game itself. No third-party mods (e.g. CoreLib) required.

## Installation

### Manual

1. Download `RangeMod.zip` from [Releases](../../releases).
2. Extract it so the folder structure is:
   ```
   %USERPROFILE%\AppData\LocalLow\Pugstorm\Core Keeper\Steam\<SteamID>\mods\RangeMod\
       ModManifest.json
       Scripts\
           RangeMod.cs
   ```
3. Launch the game. The mod is compiled and loaded automatically on startup.

### Via mod.io

*(Coming soon — subscribe in-game once published.)*

## Building from source

No Unity editor build is required. Core Keeper compiles `.cs` mod scripts at runtime using its embedded Roslyn compiler.

To install locally and produce a fresh distributable zip, run:

```powershell
.\deploy.ps1
```

This will:
1. Copy `ModManifest.json` and `Scripts/RangeMod.cs` into the correct mods directory.
2. Create `RangeMod.zip` ready to share.

The `RangeMod.asmdef` file is only needed if you open this project inside the [CoreKeeperModSDK](https://github.com/Pugstorm/CoreKeeperModSDK) Unity project for IDE autocomplete. It is not deployed.

## Configuration

To change the range multiplier, edit the constants at the top of `RangeMod.cs`:

```csharp
private const float DEFAULT_RANGE    = 10f;  // vanilla game value — don't change
private const float RANGE_MULTIPLIER = 5f;   // change this  →  50f total range
private const int   MAX_CHESTS       = 200;  // max chests scanned per open
```

Then re-run `deploy.ps1`.

## How it works

Core Keeper 1.1+ is fully ECS-based. Nearby chests are tracked as `List<Entity>` rather than `List<Chest>`. The game uses a Burst-compiled physics sphere overlap (`InventoryUtility.GetNearbyChestsByDistance`) with a hardcoded `10f` radius.

This mod uses **Harmony** to:

1. **Replace `CraftingHandler.GetNearbyChests()`** — patched to skip the original Burst scan entirely and return our pre-built list instead.
2. **Inject the extended list** into every `CraftingHandler` method that accepts a `nearbyChestsToTakeMaterialsFrom` parameter.
3. **Rebuild the cache** each time the player opens the crafting UI (`UIManager.OnPlayerInventoryOpen`), calling `InventoryUtility.GetNearbyChestsByDistance` with `50f` instead of `10f`.

## License

MIT — free to use, modify, and redistribute.
