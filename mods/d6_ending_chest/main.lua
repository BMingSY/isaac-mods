local mod = RegisterMod("D6 Ending Chest", 1)
local game = Game()
local D6 = CollectibleType.COLLECTIBLE_D6
local COLLECTIBLE = PickupVariant.PICKUP_COLLECTIBLE
local BIG_CHEST = PickupVariant.PICKUP_BIGCHEST
-- A persistent marker on the native big chest, not a new pickup variant.
-- Native big-chest AI does not use SubType to choose its ending (J460).
local D6_CHEST_SUBTYPE = 105340
local DELIRIUM_ENDING = 11 -- Game:End's documented Delirium / Ending 20 ID.
local READY_FRAME = "D6EndingChestReadyFrame"
local endingRequested = false

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

local function canConvert(pickup)
    if not pickup or not pickup:Exists() or pickup:IsDead()
        or pickup.Variant ~= COLLECTIBLE or pickup.SubType <= 0
        or PROTECTED_ITEMS[pickup.SubType] or not pickup:CanReroll() then return false end
    local config = Isaac.GetItemConfig():GetCollectible(pickup.SubType)
    return not (config and config:HasTags(ItemConfig.TAG_QUEST))
end

function mod:OnPreUseD6(item, rng, player, flags)
    if item ~= D6 then return end
    if (flags & UseFlag.USE_CARBATTERY) == 0 then
        for _, entity in ipairs(Isaac.FindByType(EntityType.ENTITY_PICKUP, COLLECTIBLE, -1, false, false)) do
            local pickup = entity:ToPickup()
            if canConvert(pickup) then
                local options = pickup.OptionsPickupIndex
                local price, shopId = pickup.Price, pickup.ShopItemId
                pickup:Morph(EntityType.ENTITY_PICKUP, BIG_CHEST, D6_CHEST_SUBTYPE, true, true, true)
                pickup.OptionsPickupIndex = options
                pickup.Price, pickup.ShopItemId = price, shopId
                pickup.State = 0
                -- Prevent a pedestal underneath the player from ending the run
                -- on the same frame it is rerolled. Native interaction follows.
                pickup:GetData()[READY_FRAME] = game:GetFrameCount() + 30
            end
        end
    end
    -- PRE_USE_ITEM cancels vanilla rerolling but retains normal charge usage.
    return true
end
mod:AddCallback(ModCallbacks.MC_PRE_USE_ITEM, mod.OnPreUseD6, D6)

function mod:OnUseD6(item, rng, player, flags)
    if item ~= D6 then return end
    return { Discharge = true, Remove = false,
        ShowAnim = (flags & (UseFlag.USE_NOANIM | UseFlag.USE_CARBATTERY)) == 0 }
end
mod:AddCallback(ModCallbacks.MC_USE_ITEM, mod.OnUseD6, D6)

function mod:OnChestCollision(pickup, collider)
    if pickup.SubType ~= D6_CHEST_SUBTYPE then return end
    local ready = pickup:GetData()[READY_FRAME]
    if ready and game:GetFrameCount() < ready then return true end
    local player = collider:ToPlayer()
    if player and (player:IsDead() or player:IsCoopGhost()) then return true end
    -- Let the native chest validate and accept contact. Its State becomes 1
    -- only after acceptance; prices, appearance and collisions stay native.
end
mod:AddCallback(ModCallbacks.MC_PRE_PICKUP_COLLISION, mod.OnChestCollision, BIG_CHEST)

function mod:OnUpdate()
    if endingRequested then return end
    for _, entity in ipairs(Isaac.FindByType(EntityType.ENTITY_PICKUP, BIG_CHEST, D6_CHEST_SUBTYPE, false, false)) do
        local pickup = entity:ToPickup()
        if pickup and pickup:Exists() and not pickup:IsDead() and pickup.State > 0 then
            -- Run after collision handling, before the next native chest update
            -- can choose an ending or next floor from the current stage.
            endingRequested = true
            game:End(DELIRIUM_ENDING)
            return
        end
    end
end
mod:AddCallback(ModCallbacks.MC_POST_UPDATE, mod.OnUpdate)

function mod:OnGameStarted()
    endingRequested = false
end
mod:AddCallback(ModCallbacks.MC_POST_GAME_STARTED, mod.OnGameStarted)
