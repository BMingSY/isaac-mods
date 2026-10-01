local mod = RegisterMod("All Sacred Hearts + Stacking", 1)

local SACRED_HEART = CollectibleType.COLLECTIBLE_SACRED_HEART -- 182
local PICKUP = EntityType.ENTITY_PICKUP
local COLLECTIBLE = PickupVariant.PICKUP_COLLECTIBLE
local DAMAGE_MULTIPLIER = 2.3
local DAMAGE_BONUS = 1
local COUNT_KEY = "AllSacredHeartsStacking_Count"

-- Keep progression items even if another mod changes their quest tags.
local PROTECTED_ITEMS = {
    [CollectibleType.COLLECTIBLE_POLAROID] = true,
    [CollectibleType.COLLECTIBLE_NEGATIVE] = true,
    [CollectibleType.COLLECTIBLE_KEY_PIECE_1] = true,
    [CollectibleType.COLLECTIBLE_KEY_PIECE_2] = true,
    [CollectibleType.COLLECTIBLE_KNIFE_PIECE_1] = true,
    [CollectibleType.COLLECTIBLE_KNIFE_PIECE_2] = true,
    [CollectibleType.COLLECTIBLE_BROKEN_SHOVEL_1] = true,
    [CollectibleType.COLLECTIBLE_BROKEN_SHOVEL_2] = true,
    [CollectibleType.COLLECTIBLE_MOMS_SHOVEL] = true,
    [CollectibleType.COLLECTIBLE_DADS_NOTE] = true,
    [CollectibleType.COLLECTIBLE_DOGMA] = true,
}

local function shouldReplace(itemId)
    if itemId <= 0 or itemId == SACRED_HEART or PROTECTED_ITEMS[itemId] then
        return false
    end

    local config = Isaac.GetItemConfig():GetCollectible(itemId)
    return not (config and config:HasTags(ItemConfig.TAG_QUEST))
end

-- Inspect the selected item so quest items can pass through unchanged.
function mod:OnGetCollectible(selectedCollectible)
    if shouldReplace(selectedCollectible) then
        return SACRED_HEART
    end
end

mod:AddPriorityCallback(
    ModCallbacks.MC_POST_GET_COLLECTIBLE,
    CallbackPriority.LATE,
    mod.OnGetCollectible
)

-- Also cover fixed drops and explicitly spawned collectible pedestals.
function mod:OnEntitySpawn(entityType, variant, subtype, position, velocity, spawner, seed)
    if entityType == PICKUP and variant == COLLECTIBLE
        and shouldReplace(subtype) then
        return { entityType, variant, SACRED_HEART, seed }
    end
end

mod:AddCallback(ModCallbacks.MC_PRE_ENTITY_SPAWN, mod.OnEntitySpawn)

-- Catch existing pedestals, continued runs, and in-place rerolls.
function mod:OnPickupUpdate(pickup)
    -- Subtype 0 is an empty pedestal; never refill an already collected item.
    if not shouldReplace(pickup.SubType) then
        return
    end

    local optionsIndex = pickup.OptionsPickupIndex
    -- Keep prices and RNG seeds; force the selected item despite modifiers.
    pickup:Morph(PICKUP, COLLECTIBLE, SACRED_HEART, true, true, true)
    pickup.OptionsPickupIndex = optionsIndex
end

mod:AddCallback(
    ModCallbacks.MC_POST_PICKUP_UPDATE,
    mod.OnPickupUpdate,
    COLLECTIBLE
)

function mod:OnEvaluateCache(player, cacheFlag)
    if cacheFlag ~= CacheFlag.CACHE_DAMAGE then
        return
    end

    local count = player:GetCollectibleNum(SACRED_HEART, true)
    -- The engine already applies the first copy. Apply only the extra copies.
    -- Each extra copy means: damage = damage * 2.3 + 1.
    for _ = 2, count do
        player.Damage = player.Damage * DAMAGE_MULTIPLIER + DAMAGE_BONUS
    end
end

mod:AddPriorityCallback(
    ModCallbacks.MC_EVALUATE_CACHE,
    CallbackPriority.LATE,
    mod.OnEvaluateCache,
    CacheFlag.CACHE_DAMAGE
)

-- Re-evaluate after inventory changes, including item removal and loading a run.
-- Damage itself is only modified in the cache callback, so it cannot grow
-- merely because another frame passes or the player enters another room.
function mod:OnPlayerUpdate(player)
    local data = player:GetData()
    local count = player:GetCollectibleNum(SACRED_HEART, true)
    if data[COUNT_KEY] ~= count then
        data[COUNT_KEY] = count
        player:AddCacheFlags(CacheFlag.CACHE_DAMAGE)
        player:EvaluateItems()
    end
end

mod:AddCallback(ModCallbacks.MC_POST_PEFFECT_UPDATE, mod.OnPlayerUpdate)
