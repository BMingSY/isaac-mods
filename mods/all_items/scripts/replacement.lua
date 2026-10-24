local replacement = {}
local PICKUP = EntityType.ENTITY_PICKUP
local COLLECTIBLE = PickupVariant.PICKUP_COLLECTIBLE

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

function replacement.shouldReplace(itemID, target)
    if itemID <= 0 or itemID == target or PROTECTED_ITEMS[itemID] then return false end
    local config = Isaac.GetItemConfig():GetCollectible(itemID)
    return config ~= nil and not config:HasTags(ItemConfig.TAG_QUEST)
end

function replacement.replacePickup(pickup, target)
    -- Subtype zero is an empty pedestal, not an item to refill.
    if not replacement.shouldReplace(pickup.SubType, target) then return end
    local optionsIndex = pickup.OptionsPickupIndex
    pickup:Morph(PICKUP, COLLECTIBLE, target, true, true, true)
    pickup.OptionsPickupIndex = optionsIndex
end

return replacement
