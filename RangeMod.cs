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

    // Nearby-chest cache. Rebuilt at most once per frame, or when position changes.
    // Mirrors the vanilla GetNearbyChests frame+position caching logic.
    public static List<Entity> cachedNearbyChests = new List<Entity>();
    private static int   _lastCachedFrame = -1;
    private static float3 _lastCachedPos  = float3.zero;

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

    private static List<Entity> SearchForNearbyChests(float3 originPosition)
    {
        var player = Manager.main?.player;
        if (player == null) return new List<Entity>();

        var querySystem     = player.querySystem;
        var collisionWorld  = querySystem.GetSingleton<PhysicsWorldSingleton>().CollisionWorld;
        var invLookup       = querySystem.GetComponentLookup<InventoryAutoTransferEnabledCD>(isReadOnly: true);
        var transformLookup = querySystem.GetComponentLookup<LocalTransform>(isReadOnly: true);

        // GetNearbyChestsByDistance is the parameterised version of the game's own
        // chest lookup. We pass EXTENDED_RANGE instead of the default 10f.
        var nativeList = InventoryUtility.GetNearbyChestsByDistance(
            originPosition, collisionWorld, invLookup, transformLookup,
            EXTENDED_RANGE, MAX_CHESTS, Allocator.TempJob);

        var result = new List<Entity>(nativeList.Length);
        foreach (var entity in nativeList)
            result.Add(entity);

        nativeList.Dispose();

        Debug.Log($"[{NAME}]: Found {result.Count} chest(s) within {EXTENDED_RANGE} units of {originPosition}.");
        return result;
    }

    // Returns the world position of the crafting station this CraftingHandler belongs to.
    // Falls back to the player's position if the private field is inaccessible.
    private static float3 GetStationPosition(CraftingHandler instance)
    {
        var emb = Traverse.Create(instance)
                          .Field("entityMonoBehaviour")
                          .GetValue<EntityMonoBehaviour>();
        if (emb != null)
            return (float3)emb.WorldPosition;

        var player = Manager.main?.player;
        return player != null ? (float3)player.WorldPosition : float3.zero;
    }

    // -------------------------------------------------------------------------
    // Harmony patches
    // -------------------------------------------------------------------------

    // GetNearbyChests() is the source the game reads to know which chests are
    // "nearby". We replace it entirely so it returns our extended list.
    //
    // Critical fixes vs vanilla:
    //   1. Range: 50f instead of hardcoded 10f.
    //   2. Origin: station's WorldPosition (from entityMonoBehaviour), not the player's.
    //      These differ when the player walks away while the UI is open, or the
    //      cached position check uses player pos to gate the scan.
    //   3. Write-back: vanilla stores the result in the private instance field
    //      `cachedNearbyChests`. Our prefix skips the original, so we must write it
    //      back ourselves via Traverse. InventoryUpdateSystem::ProcessInventoryChange
    //      reads that field directly during the actual material consumption — it does
    //      NOT call GetNearbyChests() again. Without write-back, the repair/craft
    //      action always sees an empty list even if the display showed materials available.
    [HarmonyPrefix]
    [HarmonyPatch(typeof(CraftingHandler), "GetNearbyChests")]
    public static bool GetNearbyChestsPrefix(CraftingHandler __instance, ref List<Entity> __result)
    {
        int    currentFrame  = Time.frameCount;
        float3 stationPos    = GetStationPosition(__instance);
        bool   sameFrame     = currentFrame == _lastCachedFrame;
        bool   samePosition  = math.all(stationPos == _lastCachedPos);

        if (!sameFrame || !samePosition)
        {
            cachedNearbyChests = SearchForNearbyChests(stationPos);
            _lastCachedFrame   = currentFrame;
            _lastCachedPos     = stationPos;

            // Write into the private instance field so ECS systems that read it
            // directly (e.g. InventoryUpdateSystem) see the extended list too.
            Traverse.Create(__instance)
                    .Field("cachedNearbyChests")
                    .SetValue(cachedNearbyChests);
        }

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

    // ── Eager cache refresh: rebuild when any crafting-related UI opens ──────
    // These ensure the cache is warm before the first GetNearbyChests call.
    // (GetNearbyChests is now self-sufficient, but pre-warming avoids a hitch
    // on the first frame of a crafting session.)

    // Invalidates the per-frame/position sentinels so the next call to
    // GetNearbyChests() triggers a fresh physics scan from the station's
    // WorldPosition. We call this from UI-open patches where we don't have
    // a CraftingHandler __instance, so we can't run the scan here directly.
    // GetNearbyChestsPrefix handles the actual search and write-back on its
    // next invocation.
    private static void RefreshCache()
    {
        _lastCachedFrame = -1;
        _lastCachedPos   = new float3(float.MaxValue, float.MaxValue, float.MaxValue);
    }

    [HarmonyPrefix]
    [HarmonyPatch(typeof(UIManager), "OnPlayerInventoryOpen")]
    public static void OnPlayerInventoryOpenPrefix() => RefreshCache();

    [HarmonyPrefix]
    [HarmonyPatch(typeof(UIManager), "OnSalvageAndRepairOpen")]
    public static void OnSalvageAndRepairOpenPrefix() => RefreshCache();

    [HarmonyPrefix]
    [HarmonyPatch(typeof(UIManager), "OnUpgradeForgeOpen")]
    public static void OnUpgradeForgeOpenPrefix() => RefreshCache();
}
