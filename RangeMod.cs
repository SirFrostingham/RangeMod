using HarmonyLib;
using Inventory;
using PugMod;
using System;
using System.Collections;
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
    public const string VERSION = "1.1.2";
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
    private static int    _lastCachedFrame = -1;
    private static float3 _lastCachedPos   = float3.zero;

    // Repair-range extension: tracks items temporarily moved from far chests
    // to player inventory so the Burst repair job can find them.
    private struct MovedItemRecord
    {
        public Entity                sourceChest;
        public int                   chestSlotIndex;
        public ContainedObjectsBuffer slotData;   // full struct copy (objectData + auxDataIndex)
        public int                   playerBufAbsoluteIndex;
    }
    private static readonly List<MovedItemRecord> _pendingRestores = new List<MovedItemRecord>();

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

    // Returns the search origin for the nearby-chest scan.
    // The game's Roslyn sandbox blocks System.Reflection entirely, so we cannot
    // read CraftingHandler.entityMonoBehaviour directly. We use the player's
    // position instead — at 50f range the ≤3-block station-vs-player offset is
    // negligible and the cache is invalidated whenever the player moves.
    private static float3 GetStationPosition(CraftingHandler instance)
    {
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
    //   2. Origin: player's WorldPosition (station position is in a private field the
    //      sandbox forbids reading; at 50f range the ≤3-block offset is negligible).
    //   3. The actual material consumption path (InventoryUpdateSystem → RepairOrReinforce)
    //      is covered by the GetNearbyChestsForCraftingByDistance prefix below, so
    //      no write-back to CraftingHandler.cachedNearbyChests is needed.
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

        }

        __result = cachedNearbyChests;
        return false; // skip original Burst scan
    }

    // EXECUTION PATH FIX:
    // InventoryUpdateSystem::ProcessInventoryChange calls
    //   InventoryUtility.GetNearbyChestsForCraftingByDistance(pos&, world&, invLookup&, transformLookup&, inventories&)
    // directly — a Burst-compiled method with a HARDCODED 10f range and NO maxDistance parameter.
    // This call happens server-side to build the inventoryEntities list that is then passed to
    //   InventoryUtility.RepairOrReinforce / InventoryUtility.Craft
    // It completely bypasses CraftingHandler.GetNearbyChests (our other patch), which is only
    // used client-side for the UI display pass.
    //
    // By prefixing here we intercept BOTH the display call (GetNearbyChests → here) AND the
    // execution call (ProcessInventoryChange → here) in a single patch.  The position,
    // physics world, and component lookups are already provided as parameters, so we can do
    // a 50f scan without any reference to Manager.main or the player.
    [HarmonyPrefix]
    [HarmonyPatch(typeof(InventoryUtility), "GetNearbyChestsForCraftingByDistance")]
    public static bool GetNearbyChestsForCraftingByDistancePrefix(
        ref float3 position,
        ref CollisionWorld collisionWorld,
        ref ComponentLookup<InventoryAutoTransferEnabledCD> inventoryAutoTransferEnabledLookup,
        ref ComponentLookup<LocalTransform> localTransformLookup,
        ref NativeList<Entity> inventories)
    {
        if (!inventories.IsCreated) return true; // safety: let Burst handle unexpected state

        var extended = InventoryUtility.GetNearbyChestsByDistance(
            position, collisionWorld,
            inventoryAutoTransferEnabledLookup, localTransformLookup,
            EXTENDED_RANGE, MAX_CHESTS, Allocator.TempJob);

        inventories.Clear();
        for (int i = 0; i < extended.Length; i++)
            inventories.Add(extended[i]);
        extended.Dispose();

        Debug.Log($"[{NAME}]: Crafting execution scan: {inventories.Length} chest(s) in {EXTENDED_RANGE}u @ {position}.");
        return false; // skip the Burst 10f scan
    }

    // GetNearbyChestsForAutoStackingByDistance is the managed (non-Burst) method
    // that builds the chest list for the Q quick-deposit action. It has no
    // maxDistance parameter (range is hard-coded inside). We replace it entirely
    // with a 50f scan using GetNearbyChestsByDistance.
    [HarmonyPrefix]
    [HarmonyPatch(typeof(InventoryUtility), "GetNearbyChestsForAutoStackingByDistance")]
    public static bool GetNearbyChestsForAutoStackingByDistancePrefix(
        float3 position,
        CollisionWorld collisionWorld,
        ComponentLookup<InventoryAutoTransferEnabledCD> inventoryAutoTransferEnabledLookup,
        ComponentLookup<LocalTransform> localTransformLookup,
        Allocator allocator,
        ref NativeList<Entity> __result)
    {
        __result = InventoryUtility.GetNearbyChestsByDistance(
            position, collisionWorld,
            inventoryAutoTransferEnabledLookup, localTransformLookup,
            EXTENDED_RANGE, MAX_CHESTS, allocator);
        Debug.Log($"[{NAME}]: Quick-deposit scan: {__result.Length} chest(s) in {EXTENDED_RANGE}u @ {position}.");
        return false; // skip the hardcoded-range original
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

    // ---- Repair range extension ---------------------------------------------
    //
    // After probing, the vanilla repair path is confirmed as:
    //   ToggleRepair (managed, patchable)
    //     -> ECB command
    //       -> ProcessInventoryChangesJob (Burst ISystem)
    //         -> GetNearbyChestsForCraftingByDistance (Burst, hardcoded 10f)
    //           -> RepairOrReinforce
    //
    // Since everything downstream of ToggleRepair is Burst-compiled and
    // Harmony-unpatchable, the fix is "inventory stuffing":
    //   Prefix:  detect which scrap parts are short; move whole slots from
    //            far chests (10-50f) into the player's main inventory.
    //   Vanilla: repair Burst job runs, finds the parts in player inventory.
    //   Postfix: coroutine (3 frames later) moves any unconsumed parts back
    //            to their original chest slots.
    //
    // ToggleReinforce is NOT patched -- reinforce already works because it
    // draws only from player inventory (no chest scan involved).

    [HarmonyPrefix]
    [HarmonyPatch(typeof(SalvageAndRepairUI), "ToggleRepair")]
    public static void ToggleRepairExtendPrefix(SalvageAndRepairUI __instance)
    {
        _pendingRestores.Clear();
        try   { ToggleRepairExtendImpl(__instance); }
        catch (Exception ex)
            { Debug.LogWarning($"[{NAME}]: ToggleRepairPrefix error: {ex.Message}"); }
    }

    private static void ToggleRepairExtendImpl(SalvageAndRepairUI __instance)
    {
        var player = Manager.main?.player;
        if (player == null) { Debug.Log($"[{NAME}]: ToggleRepair: no player"); return; }

        var mats = __instance.GetRequiredMaterials(false, false);
        if (mats == null || mats.Count == 0)
        {
            Debug.Log($"[{NAME}]: ToggleRepair: no required materials returned");
            return;
        }

        Debug.Log($"[{NAME}]: ToggleRepair: {mats.Count} material type(s) needed");

        var em              = player.querySystem.EntityManager;
        var invHandler      = player.playerInventoryHandler;
        var playerInvEntity = invHandler.inventoryEntity;
        if (!em.HasBuffer<ContainedObjectsBuffer>(playerInvEntity))
        {
            Debug.LogWarning($"[{NAME}]: ToggleRepair: no ContainedObjectsBuffer on player inventory entity");
            return;
        }

        var playerBuf = em.GetBuffer<ContainedObjectsBuffer>(playerInvEntity);
        int startPos  = invHandler.startPosInBuffer;
        int invSize   = invHandler.size;

        // Count how much of each required material the player currently holds.
        // We do NOT trust mat.amountAvailable because our GetNearbyChests patch
        // makes it count the full 50f radius, but the repair Burst job only
        // scans 10f - so the game shows "enough" even when the actual job fails.
        var playerHas = new Dictionary<ObjectID, int>();
        for (int s = startPos; s < startPos + invSize && s < playerBuf.Length; s++)
        {
            var slot = playerBuf[s];
            if (slot.amount <= 0) continue;
            int cur;
            playerHas.TryGetValue(slot.objectID, out cur);
            playerHas[slot.objectID] = cur + slot.amount;
        }

        // Also count what's in near chests (<=10f) so we don't over-stage.
        var playerPos  = (float3)player.WorldPosition;
        var allChests  = SearchForNearbyChests(playerPos); // 50f scan (cached)
        var nearHas    = new Dictionary<ObjectID, int>();
        foreach (var chestEntity in allChests)
        {
            if (!em.Exists(chestEntity)) continue;
            if (!em.HasComponent<LocalTransform>(chestEntity)) continue;
            var ct = em.GetComponentData<LocalTransform>(chestEntity);
            if (math.distance(playerPos, ct.Position) > DEFAULT_RANGE + 0.5f) continue;
            if (!em.HasBuffer<ContainedObjectsBuffer>(chestEntity)) continue;
            var cb = em.GetBuffer<ContainedObjectsBuffer>(chestEntity);
            foreach (var slot in cb)
            {
                if (slot.amount <= 0) continue;
                int cur;
                nearHas.TryGetValue(slot.objectID, out cur);
                nearHas[slot.objectID] = cur + slot.amount;
            }
        }

        bool staged = false;
        foreach (var mat in mats)
        {
            if (mat.amountNeeded <= 0) continue;

            int playerHasCount, nearHasCount;
            playerHas.TryGetValue(mat.objectID, out playerHasCount);
            nearHas.TryGetValue(mat.objectID, out nearHasCount);
            int alreadyReachable = playerHasCount + nearHasCount;
            int deficit = mat.amountNeeded - alreadyReachable;

            Debug.Log($"[{NAME}]: ToggleRepair: {mat.objectID} need={mat.amountNeeded} playerHas={playerHasCount} nearHas={nearHasCount} deficit={deficit}");

            if (deficit <= 0) continue;

            // Pull from far chests to cover the deficit
            foreach (var chestEntity in allChests)
            {
                if (deficit <= 0) break;
                if (!em.Exists(chestEntity)) continue;
                if (!em.HasComponent<LocalTransform>(chestEntity)) continue;
                var ct = em.GetComponentData<LocalTransform>(chestEntity);
                if (math.distance(playerPos, ct.Position) <= DEFAULT_RANGE + 0.5f) continue;
                if (!em.HasBuffer<ContainedObjectsBuffer>(chestEntity)) continue;
                var chestBuf = em.GetBuffer<ContainedObjectsBuffer>(chestEntity);

                for (int i = chestBuf.Length - 1; i >= 0 && deficit > 0; i--)
                {
                    var slot = chestBuf[i];
                    if (slot.objectID != mat.objectID || slot.amount <= 0) continue;

                    int freeAbs = -1;
                    for (int s = startPos; s < startPos + invSize && s < playerBuf.Length; s++)
                        if (playerBuf[s].amount == 0) { freeAbs = s; break; }
                    if (freeAbs < 0)
                    {
                        Debug.LogWarning($"[{NAME}]: ToggleRepair: player inventory full.");
                        break;
                    }

                    var saved       = chestBuf[i];
                    chestBuf[i]     = default;
                    playerBuf[freeAbs] = saved;

                    _pendingRestores.Add(new MovedItemRecord
                    {
                        sourceChest            = chestEntity,
                        chestSlotIndex         = i,
                        slotData               = saved,
                        playerBufAbsoluteIndex = freeAbs
                    });

                    deficit -= saved.amount;
                    staged   = true;
                    Debug.Log($"[{NAME}]: Repair staged: {saved.amount}x {saved.objectID} -> player[{freeAbs}], deficit now={deficit}");
                }
            }
        }

        if (staged)
            Debug.Log($"[{NAME}]: Repair: staged {_pendingRestores.Count} slot(s) from far chests into player inventory.");
        else
            Debug.Log($"[{NAME}]: Repair: nothing to stage (all materials already reachable within 10f).");
    }

    [HarmonyPostfix]
    [HarmonyPatch(typeof(SalvageAndRepairUI), "ToggleRepair")]
    public static void ToggleRepairExtendPostfix(SalvageAndRepairUI __instance)
    {
        if (_pendingRestores.Count > 0)
            __instance.StartCoroutine(RestoreUnconsumedMaterialsCoroutine());
    }

    private static IEnumerator RestoreUnconsumedMaterialsCoroutine()
    {
        // Wait several frames for the repair ECB / Burst job to run and consume items.
        yield return null;
        yield return null;
        yield return null;

        var player = Manager.main?.player;
        if (player == null) { _pendingRestores.Clear(); yield break; }

        try
        {
            var em              = player.querySystem.EntityManager;
            var playerInvEntity = player.playerInventoryHandler.inventoryEntity;
            if (!em.HasBuffer<ContainedObjectsBuffer>(playerInvEntity))
                { _pendingRestores.Clear(); yield break; }

            var playerBuf = em.GetBuffer<ContainedObjectsBuffer>(playerInvEntity);

            foreach (var rec in _pendingRestores)
            {
                if (rec.playerBufAbsoluteIndex >= playerBuf.Length) continue;
                var cur = playerBuf[rec.playerBufAbsoluteIndex];

                // If our item is still present (wasn't fully consumed), return it
                if (cur.objectID != rec.slotData.objectID || cur.amount <= 0) continue;

                bool returned = false;
                if (em.Exists(rec.sourceChest) &&
                    em.HasBuffer<ContainedObjectsBuffer>(rec.sourceChest))
                {
                    var chestBuf = em.GetBuffer<ContainedObjectsBuffer>(rec.sourceChest);

                    // Prefer the original slot index
                    if (rec.chestSlotIndex < chestBuf.Length &&
                        chestBuf[rec.chestSlotIndex].amount == 0)
                    {
                        chestBuf[rec.chestSlotIndex] = cur;
                        returned = true;
                    }
                    else
                    {
                        for (int i = 0; i < chestBuf.Length; i++)
                        {
                            if (chestBuf[i].amount == 0)
                                { chestBuf[i] = cur; returned = true; break; }
                        }
                        if (!returned)
                            { chestBuf.Add(cur); returned = true; }
                    }
                }

                if (returned)
                {
                    playerBuf[rec.playerBufAbsoluteIndex] = default;
                    Debug.Log($"[{NAME}]: Repair: returned {cur.amount}x {cur.objectID} to chest.");
                }
                else
                {
                    Debug.LogWarning($"[{NAME}]: Repair: source chest gone; {cur.amount}x {cur.objectID} kept in player inventory.");
                }
            }
        }
        catch (Exception ex)
        {
            Debug.LogWarning($"[{NAME}]: RestoreUnconsumedMaterials error: {ex.Message}");
        }

        _pendingRestores.Clear();
    }
}
