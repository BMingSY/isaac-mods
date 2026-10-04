-- Offline callback checks; does not launch Isaac or simulate its native UI.
-- Run: lua tests/d6_ending_chest_regression.lua [optional mod directory]
local root = arg[1] or "mods/d6_ending_chest"
local checks = 0
local function check(condition, message)
    assert(condition, message)
    checks = checks + 1
end

CollectibleType = { COLLECTIBLE_D6 = 105 }
local protected = { "POLAROID", "NEGATIVE", "KEY_PIECE_1", "KEY_PIECE_2",
    "KNIFE_PIECE_1", "KNIFE_PIECE_2", "BROKEN_SHOVEL_1", "BROKEN_SHOVEL_2",
    "MOMS_SHOVEL", "DADS_NOTE", "DOGMA" }
for i, name in ipairs(protected) do CollectibleType["COLLECTIBLE_" .. name] = 200 + i end
EntityType = { ENTITY_PICKUP = 5 }
PickupVariant = { PICKUP_COLLECTIBLE = 100, PICKUP_BIGCHEST = 340 }
UseFlag = { USE_NOANIM = 1, USE_CARBATTERY = 32, USE_VOID = 64 }
ItemConfig = { TAG_QUEST = 1 }
ModCallbacks = setmetatable({}, { __index = function(_, k) return k end })
local callbacks, entities, endings, frame, registered = {}, {}, {}, 0
local game = {}
function Game() return game end
function game:GetFrameCount() return frame end
function game:End(id) endings[#endings + 1] = id end
function RegisterMod(name)
    registered = { Name = name }
    function registered:AddCallback(id, callback, filter)
        callbacks[id] = { Function = callback, Filter = filter }
    end
    return registered
end
Isaac = {}
function Isaac.FindByType(kind, variant, subtype)
    local result = {}
    for _, entity in ipairs(entities) do
        if entity:Exists() and entity.Type == kind and entity.Variant == variant
            and (subtype == -1 or subtype == entity.SubType) then
            result[#result + 1] = entity
        end
    end
    return result
end
function Isaac.GetItemConfig()
    return { GetCollectible = function(_, id)
        return { HasTags = function(_, tag) return id == 900 and tag == 1 end }
    end }
end
local function pickup(variant, subtype, reroll)
    local p = { Type = 5, Variant = variant, SubType = subtype,
        OptionsPickupIndex = 0, Price = 0, ShopItemId = -1, State = 0,
        InitSeed = 123 + #entities, Data = {}, Rerollable = reroll ~= false,
        Position = { X = 200, Y = 100 }, MorphCount = 0 }
    function p:Exists() return not self.Removed end
    function p:IsDead() return self.Dead or false end
    function p:ToPickup() return self end
    function p:GetData() return self.Data end
    function p:CanReroll() return self.Rerollable end
    function p:Morph(kind, newVariant, newSubtype, keepPrice, keepSeed, ignoreModifiers)
        check(keepPrice and keepSeed and ignoreModifiers, "conversion preserves price/seed and ignores pickup modifiers")
        self.Type, self.Variant, self.SubType = kind, newVariant, newSubtype
        self.MorphCount = self.MorphCount + 1
        self.OptionsPickupIndex, self.State = 0, 99
    end
    entities[#entities + 1] = p
    return p
end
local player = {}
function player:ToPlayer() return self end
function player:IsDead() return self.Dead or false end
function player:IsCoopGhost() return self.Ghost or false end
local familiar = { ToPlayer = function() return nil end }

dofile(root .. "/main.lua")
local mod = registered
check(callbacks.MC_PRE_USE_ITEM.Filter == 105, "only D6's native effect is replaced")
check(callbacks.MC_USE_ITEM.Filter == 105, "use animation callback is D6-only")
check(callbacks.MC_PRE_PICKUP_COLLISION.Filter == 340, "only big chests receive collision handling")
mod:OnGameStarted(false)
local ordinary = pickup(100, 1)
local shop = pickup(100, 2)
shop.Price, shop.ShopItemId, shop.OptionsPickupIndex = 15, 3, 7
local devil = pickup(100, 3)
devil.Price, devil.ShopItemId = -2, -2
local seed, position = ordinary.InitSeed, ordinary.Position
local untouched = { pickup(100, 0), pickup(100, 4, false), pickup(100, 900),
    pickup(20, 1), pickup(50, 1), pickup(340, 0) }
for _, name in ipairs(protected) do
    untouched[#untouched + 1] = pickup(100, CollectibleType["COLLECTIBLE_" .. name])
end
local dead = pickup(100, 5)
dead.Dead = true
untouched[#untouched + 1] = dead
check(mod:OnPreUseD6(106, nil, player, 0) == nil, "other actives pass through")
check(ordinary.Variant == 100, "other actives do not change pedestals")
check(mod:OnPreUseD6(105, nil, player, 0) == true, "D6 cancels normal item rerolling")
local chestSubtype = ordinary.SubType
check(ordinary.Variant == 340 and chestSubtype ~= 0, "ordinary item becomes a marked native big chest")
check(shop.Variant == 340 and devil.Variant == 340, "shop and devil pedestals convert too")
check(shop.Price == 15 and shop.ShopItemId == 3 and shop.OptionsPickupIndex == 7, "shop and option metadata retained")
check(devil.Price == -2 and devil.ShopItemId == -2, "devil price metadata retained")
check(ordinary.InitSeed == seed and ordinary.Position == position, "morph retains seed and position")
check(ordinary.State == 0, "pedestal state cannot be mistaken for an already opened chest")
for _, entity in ipairs(untouched) do check(entity.MorphCount == 0, "noneligible and quest pickups are preserved") end
local used = mod:OnUseD6(105, nil, player, 0)
check(used.Discharge and not used.Remove and used.ShowAnim, "normal D6 charge/ownership/animation behavior")
check(not mod:OnUseD6(105, nil, player, 1).ShowAnim, "scripted no-animation use respected")
check(not mod:OnUseD6(105, nil, player, 32).ShowAnim, "Car Battery does not repeat use animation")
local late = pickup(100, 6)
check(mod:OnPreUseD6(105, nil, player, 32) == true and late.Variant == 100,
    "Car Battery second activation cannot create another chest wave")
mod:OnPreUseD6(105, nil, player, 64)
check(late.Variant == 340, "an actual D6 effect invoked through Void still converts")
check(ordinary.MorphCount == 1, "repeated D6 cannot convert an existing ending chest again")
mod:OnUpdate()
check(#endings == 0, "rolling a chest never ends the run by itself")
check(mod:OnChestCollision(ordinary, player) == true, "new chest blocks immediate contact under player")
frame = 29
check(mod:OnChestCollision(ordinary, player) == true, "appearance grace lasts a full second")
frame = 30
check(mod:OnChestCollision(ordinary, player) == nil, "ready chest returns contact to native validation")
mod:OnUpdate()
check(#endings == 0, "a collision attempt alone is not accepted as a successful opening")
player.Ghost = true
check(mod:OnChestCollision(ordinary, player) == true, "co-op ghost cannot finish a run")
player.Ghost, player.Dead = false, true
check(mod:OnChestCollision(ordinary, player) == true, "dead player cannot finish a run")
player.Dead = false
check(mod:OnChestCollision(ordinary, familiar) == nil, "native non-player handling remains intact")
local vanilla = untouched[6]
vanilla.State = 1
check(mod:OnChestCollision(vanilla, player) == nil, "vanilla ending chest has no mod collision override")
mod:OnUpdate()
check(#endings == 0, "vanilla endings and stage transitions are untouched")
ordinary.State = 1 -- Native big-chest collision accepts the player.
mod:OnUpdate()
check(#endings == 1 and endings[1] == 11, "accepted D6 chest explicitly selects Delirium ending")
shop.State = 1
mod:OnUpdate()
check(#endings == 1, "multiple co-op collisions request only one ending")

-- The engine persists Type/Variant/SubType/State, but clears GetData on reload.
entities = {}
local continuedChest = pickup(340, chestSubtype)
mod:OnGameStarted(true)
mod:OnUpdate()
check(#endings == 1, "Continue does not open an untouched chest")
check(mod:OnChestCollision(continuedChest, player) == nil, "restored chest does not require transient Lua data")
continuedChest.State = 1
mod:OnUpdate()
check(#endings == 2 and endings[2] == 11, "restored chest still ends with Delirium")
entities = {}
mod:OnGameStarted(false)
check(mod:OnPreUseD6(105, nil, player, 0) == true, "empty-room use does not invent chests")
mod:OnUpdate()
check(#endings == 2, "empty room cannot end a run")
print(string.format("PASS: %d D6 Ending Chest checks (offline; no game launched)", checks))
