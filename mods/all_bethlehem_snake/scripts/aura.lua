-- Star of Bethlehem uses the player's internal Hallowed Ground countdown,
-- not a temporary COLLECTIBLE_STAR_OF_BETHLEHEM effect. Track native star
-- contacts so a Lua aura can account for the native multiplier and its short
-- grace period without requiring REPENTOGON or changing the real item.
local aura = { RADIUS = 70 }
local contacts = {}

function aura.contains(player, star)
    if not star or not star:Exists() or star:IsDead() or not star.Visible then return false end
    local radius = aura.RADIUS + player.Size
    return player.Position:DistanceSquared(star.Position) < radius * radius
end

local function remaining(player, frame)
    local contact = contacts[GetPtrHash(player)]
    if not contact then return 0 end
    return math.max(0, contact.Ticks - math.max(0, frame - contact.Frame))
end

function aura.observe(player, star, frame)
    if not aura.contains(player, star) then return end
    local key = GetPtrHash(player)
    local contact = contacts[key]
    if not contact or contact.Frame ~= frame then
        contact = { Frame = frame, Ticks = remaining(player, frame), Sources = {} }
        contacts[key] = contact
    end
    local source = GetPtrHash(star)
    if not contact.Sources[source] then
        -- Native Star adds two ticks, capped at four, on each familiar update.
        contact.Ticks = math.min(4, contact.Ticks + 2)
        contact.Sources[source] = true
    end
end

function aura.nativeActive(player, frame)
    if remaining(player, frame) > 0 then return true end
    -- Native entry can evaluate the cache before MC_FAMILIAR_UPDATE runs.
    -- Read the live familiar positions, not last frame's snake queue state.
    for _, star in ipairs(Isaac.FindByType(EntityType.ENTITY_FAMILIAR,
        FamiliarVariant.STAR_OF_BETHLEHEM, -1, false, false)) do
        if aura.contains(player, star) then return true end
    end
    return false
end

function aura.reset()
    contacts = {}
end

return aura
