using HarmonyLib;
using Inventory;
using PugMod;
using System;
using System.Collections.Generic;
using System.Linq;
using Unity.Collections;
using Unity.Entities;
using Unity.Mathematics;
using Unity.Physics;
using Unity.Transforms;
using UnityEngine;
using Debug = UnityEngine.Debug;

/// <summary>
/// RangeMod — Extended Crafting Range
/// Extends the crafting workbench nearby-chest search range to 5× the game default.
///
/// Game default (v1.1.2.8): 10f units.  This mod sets it to 50f.
///
/// Implementation notes:
///   - Core Keeper 1.1+ uses ECS — nearby chests are List&lt;Entity&gt;, not List&lt;Chest&gt;.
///   - The game's default scan uses a Burst-compiled physics overlap with a hardcoded
///     10f radius. We replace that scan with InventoryUtility.GetNearbyChestsByDistance,
///     which accepts an explicit maxDistance parameter.
///   - All CraftingHandler methods that accept a nearbyChestsToTakeMaterialsFrom
///     parameter are patched to receive our cached extended list.
/// </summary>
[Harmony]
public class RangeMod : IMod
{
    public const string VERSION = "1.0.0";
    public const string NAME = "RangeMod";
    public const string AUTHOR = "Aaron Reed";

    // Game default crafting chest scan radius (confirmed from IL: ldc.r4 10).
    private const float DEFAULT_RANGE = 10f;
    private const float RANGE_MULTIPLIER = 5f;
    private static readonly float EXTENDED_RANGE = DEFAULT_RANGE * RANGE_MULTIPLIER; // 50f

    // Upper bound on how many chests to include. 200 is generous for any base layout.
    private const int MAX_CHESTS = 200;

    // Per-crafting-session cache. Rebuilt each time the player opens the crafting UI.
    public static List<Entity> cachedNearbyChests = new List<Entity>();

    private LoadedMod modInfo;

    // -------------------------------------------------------------------------
    // IMod lifecycle
    // -------------------------------------------------------------------------

    public void EarlyInit()
    {
        Debug.Log($"[{NAME}] v{VERSION} by {AUTHOR} — loading...");
        modInfo = API.ModLoader.LoadedMods.FirstOrDefault(m => m.Handlers.Contains(this));
        if (modInfo == null)
        {
            Debug.LogError($"[{NAME}]: Could not locate own LoadedMod entry. Mod may not function correctly.");
            return;
        }
        Debug.Log($"[{NAME}]: Loaded! Extended range: {EXTENDED_RANGE}m ({RANGE_MULTIPLIER}× default {DEFAULT_RANGE}m)");
    }

    public void Init() { }
    public void Shutdown() { }
    public void ModObjectLoaded(UnityEngine.Object obj) { }
    public void Update() { }

    // -------------------------------------------------------------------------
    // Chest search — uses the game's own ECS physics API with our range
    // -------------------------------------------------------------------------

    private static List<Entity> SearchForNearbyChests()
    {
        var player = Manager.main?.player;
        if (player == null) return new List<Entity>();

        // Grab ECS-side resources from the player's query system.
        var querySystem    = player.querySystem;
        var collisionWorld = querySystem.GetSingleton<PhysicsWorldSingleton>().CollisionWorld;
        var invLookup      = querySystem.GetComponentLookup<InventoryAutoTransferEnabledCD>(isReadOnly: true);
        var transformLookup = querySystem.GetComponentLookup<LocalTransform>(isReadOnly: true);

        var position = (float3)player.WorldPosition;

        // GetNearbyChestsByDistance is the parameterised version of the game's own
        // chest lookup. We pass EXTENDED_RANGE instead of the default 10f.
        var nativeList = InventoryUtility.GetNearbyChestsByDistance(
            position, collisionWorld, invLookup, transformLookup,
            EXTENDED_RANGE, MAX_CHESTS, Allocator.TempJob);

        var result = new List<Entity>(nativeList.Length);
        foreach (var entity in nativeList)
            result.Add(entity);

        nativeList.Dispose(); // NativeList must be manually disposed

        Debug.Log($"[{NAME}]: Found {result.Count} chest(s) within {EXTENDED_RANGE}m.");
        return result;
    }

    // -------------------------------------------------------------------------
    // Harmony patches
    // -------------------------------------------------------------------------

    // GetNearbyChests() is the source the game reads to know which chests are
    // "nearby". We replace it entirely so it returns our extended list.
    // (Replaces the old GetAnyNearbyChests — renamed in 1.1+)
    [HarmonyPrefix]
    [HarmonyPatch(typeof(CraftingHandler), "GetNearbyChests")]
    public static bool GetNearbyChestsPrefix(ref List<Entity> __result)
    {
        __result = cachedNearbyChests;
        return false; // skip original Burst scan
    }

    // ── HasMaterialsInCraftingInventoryToCraftRecipe (overload: index) ────────
    [HarmonyPrefix]
    [HarmonyPatch(typeof(CraftingHandler), "HasMaterialsInCraftingInventoryToCraftRecipe",
        new Type[] { typeof(int), typeof(bool), typeof(List<Entity>), typeof(int) })]
    public static void HasMaterials1Prefix(ref List<Entity> nearbyChestsToTakeMaterialsFrom)
        => nearbyChestsToTakeMaterialsFrom = cachedNearbyChests;

    // ── HasMaterialsInCraftingInventoryToCraftRecipe (overload: RecipeInfo) ───
    [HarmonyPrefix]
    [HarmonyPatch(typeof(CraftingHandler), "HasMaterialsInCraftingInventoryToCraftRecipe",
        new Type[] { typeof(CraftingHandler.RecipeInfo), typeof(bool), typeof(List<Entity>), typeof(bool), typeof(int) })]
    public static void HasMaterials2Prefix(ref List<Entity> nearbyChestsToTakeMaterialsFrom)
        => nearbyChestsToTakeMaterialsFrom = cachedNearbyChests;

    // ── GetCraftingMaterialInfosForRecipe (overload: index) ──────────────────
    [HarmonyPrefix]
    [HarmonyPatch(typeof(CraftingHandler), "GetCraftingMaterialInfosForRecipe",
        new Type[] { typeof(int), typeof(List<Entity>), typeof(bool), typeof(bool) })]
    public static void GetMaterialInfos1Prefix(ref List<Entity> nearbyChestsToTakeMaterialsFrom)
        => nearbyChestsToTakeMaterialsFrom = cachedNearbyChests;

    // ── GetCraftingMaterialInfosForRecipe (overload: RecipeInfo) ─────────────
    [HarmonyPrefix]
    [HarmonyPatch(typeof(CraftingHandler), "GetCraftingMaterialInfosForRecipe",
        new Type[] { typeof(CraftingHandler.RecipeInfo), typeof(List<Entity>), typeof(bool), typeof(bool), typeof(bool) })]
    public static void GetMaterialInfos2Prefix(ref List<Entity> nearbyChestsToTakeMaterialsFrom)
        => nearbyChestsToTakeMaterialsFrom = cachedNearbyChests;

    // ── MaterialInfoListFromData ──────────────────────────────────────────────
    [HarmonyPrefix]
    [HarmonyPatch(typeof(CraftingHandler), "MaterialInfoListFromData")]
    public static void MaterialInfoListFromDataPrefix(ref List<Entity> nearbyChestsToTakeMaterialsFrom)
        => nearbyChestsToTakeMaterialsFrom = cachedNearbyChests;

    // ── GetCraftingMaterialInfosForUpgrade ────────────────────────────────────
    [HarmonyPrefix]
    [HarmonyPatch(typeof(CraftingHandler), "GetCraftingMaterialInfosForUpgrade")]
    public static void GetMaterialInfosForUpgradePrefix(ref List<Entity> nearbyChestsToTakeMaterialsFrom)
        => nearbyChestsToTakeMaterialsFrom = cachedNearbyChests;

    // ── HasMaterialsToBeUpgraded (new in 1.1+) ────────────────────────────────
    [HarmonyPrefix]
    [HarmonyPatch(typeof(CraftingHandler), "HasMaterialsToBeUpgraded")]
    public static void HasMaterialsToBeUpgradedPrefix(ref List<Entity> nearbyChestsToTakeMaterialsFrom)
        => nearbyChestsToTakeMaterialsFrom = cachedNearbyChests;

    // ── Trigger: rebuild cache when the player opens the crafting/inventory UI ─
    [HarmonyPrefix]
    [HarmonyPatch(typeof(UIManager), "OnPlayerInventoryOpen")]
    public static void OnPlayerInventoryOpenPrefix()
    {
        if (Manager.main?.player?.activeCraftingHandler != null)
        {
            cachedNearbyChests = SearchForNearbyChests();
        }
    }
}
