local items = {}

function items.maximumID()
    -- Includes custom collectibles from enabled mods, as well as vanilla items.
    return Isaac.GetItemConfig():GetCollectibles().Size - 1
end

function items.exists(id)
    return type(id) == "number" and id >= 1 and id <= items.maximumID()
        and id == math.floor(id) and Isaac.GetItemConfig():GetCollectible(id) ~= nil
end

return items
