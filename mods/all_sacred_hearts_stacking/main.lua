-- Keep the legacy registration name so existing mod saves remain accessible.
local mod = RegisterMod("All Sacred Hearts + Stacking", 1)

local SACRED_HEART = CollectibleType.COLLECTIBLE_SACRED_HEART -- 182
local DAMAGE_MULTIPLIER = 2.3
local DAMAGE_BONUS = 1
local COUNT_KEY = "AllSacredHeartsStacking_Count"

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
