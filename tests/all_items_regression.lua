-- Offline checks of replacement, persistence, configuration, and effect isolation.
-- Run: lua tests/all_items_regression.lua
local checks = 0
local function check(condition, message)
    assert(condition, message)
    checks = checks + 1
end
local function near(actual, expected, message)
    check(math.abs(actual - expected) < 1e-8, message)
end

CollectibleType = { COLLECTIBLE_SACRED_HEART = 182,
    COLLECTIBLE_LUDOVICO_TECHNIQUE = 329, COLLECTIBLE_STAR_OF_BETHLEHEM = 651 }
local protected = { "POLAROID", "NEGATIVE", "KEY_PIECE_1", "KEY_PIECE_2",
    "KNIFE_PIECE_1", "KNIFE_PIECE_2", "BROKEN_SHOVEL_1", "BROKEN_SHOVEL_2",
    "MOMS_SHOVEL", "DADS_NOTE", "DOGMA" }
for i, name in ipairs(protected) do CollectibleType["COLLECTIBLE_" .. name] = 200 + i end
EntityType = { ENTITY_PICKUP = 5, ENTITY_PLAYER = 1, ENTITY_TEAR = 2 }
PickupVariant = { PICKUP_COLLECTIBLE = 100 }
CacheFlag = { CACHE_DAMAGE = 1, CACHE_FIREDELAY = 2, CACHE_TEARFLAG = 4 }
ItemConfig = { TAG_QUEST = 1 }
CallbackPriority = { EARLY = -100, LATE = 100 }
ModCallbacks = setmetatable({}, { __index = function(_, key) return key end })
ButtonAction = { ACTION_SHOOTLEFT = 0, ACTION_SHOOTRIGHT = 1,
    ACTION_SHOOTUP = 2, ACTION_SHOOTDOWN = 3 }
FamiliarVariant = { STAR_OF_BETHLEHEM = 236 }
EffectVariant = { HALLOWED_GROUND = 112 }
DamageFlag = { DAMAGE_FAKE = 1, DAMAGE_DEVIL = 2, DAMAGE_IV_BAG = 4,
    DAMAGE_INVINCIBLE = 8, DAMAGE_TIMER = 16, DAMAGE_PITFALL = 32, DAMAGE_RED_HEARTS = 64 }
local frame, held = 0, false
local game = { GetFrameCount = function() return frame end, IsPaused = function() return false end }
function Game() return game end
function Font() return { Load = function() end } end
Vector = { Zero = { X = 0, Y = 0 } }
Input = { IsActionPressed = function() return held end }
InputHook = { IS_ACTION_TRIGGERED = 0 }
function GetPtrHash(player) return player end

-- Use serialized strings across the save boundary, not live table references.
local function encode(value)
    if type(value) ~= "table" then return string.format("%q", value) end
    local parts = {}
    for key, item in pairs(value) do
        parts[#parts + 1] = "[" .. encode(key) .. "]=" .. encode(item)
    end
    return "{" .. table.concat(parts, ",") .. "}"
end
local json = { encode = encode,
    decode = function(value) return assert(load("return " .. value, "save", "t", {}))() end }
package.preload.json = function() return json end

local valid = { [1] = true, [2] = true, [3] = true, [5] = true, [6] = true,
    [105] = true, [182] = true, [329] = true, [331] = true, [651] = true,
    [900] = true, [1000] = true, [1001] = true }
for _, id in pairs(CollectibleType) do valid[id] = true end
local output = {}
Isaac = {
    GetItemConfig = function() return {
        GetCollectibles = function() return { Size = 1002 } end,
        GetCollectible = function(_, id)
            if valid[id] then return { HasTags = function(_, tag)
                return id == 900 and tag == ItemConfig.TAG_QUEST
            end } end
        end,
    } end,
    ConsoleOutput = function(message) output[#output + 1] = message end,
    GetEntityVariantByName = function() return 1001 end,
    DebugString = function(message) error(message) end,
}

local saveSlot, saves, root, currentMod = 1, {}, nil, nil
function RegisterMod(name)
    local mod = { Name = name, Callbacks = {}, SaveWrites = 0 }
    function mod:AddCallback(id, callback, filter)
        self.Callbacks[id] = { Function = callback, Filter = filter }
    end
    function mod:AddPriorityCallback(id, _, callback, filter)
        self:AddCallback(id, callback, filter)
    end
    function mod:HasData() return saves[self.Name .. saveSlot] ~= nil end
    function mod:LoadData() return saves[self.Name .. saveSlot] end
    function mod:SaveData(value)
        check(type(value) == "string", "save boundary uses a string")
        saves[self.Name .. saveSlot] = value
        self.SaveWrites = self.SaveWrites + 1
    end
    currentMod = mod
    return mod
end
function include(name) return dofile(root .. "/" .. name:gsub("%.", "/") .. ".lua") end
local function loadMod(directory)
    root = "mods/" .. directory
    dofile(root .. "/main.lua")
    return currentMod
end
local function poolResult(mods, item)
    for _, mod in ipairs(mods) do
        local callback = mod.Callbacks.MC_POST_GET_COLLECTIBLE
        if callback then item = callback.Function(mod, item) or item end
    end
    return item
end
local function pickup(id, price, options)
    local entity = { Type = 5, Variant = 100, SubType = id, Price = price or 0,
        InitSeed = 12345, ShopItemId = 7, OptionsPickupIndex = options or 0, Morphs = 0 }
    function entity:Morph(kind, variant, subtype, keepPrice, keepSeed, ignoreModifiers)
        check(keepPrice and keepSeed and ignoreModifiers,
            "pedestal replacement keeps price and seed, bypassing pickup modifiers")
        self.Type, self.Variant, self.SubType = kind, variant, subtype
        self.OptionsPickupIndex = 0
        self.Morphs = self.Morphs + 1
    end
    return entity
end

local converter = loadMod("all_items")
check(converter.Callbacks.MC_POST_PICKUP_UPDATE.Filter == 100, "only collectible pedestals update")
check(converter.Callbacks.MC_EVALUATE_CACHE == nil, "replacement alone adds no stat bonuses")
check(converter.Callbacks.MC_POST_PEFFECT_UPDATE == nil, "replacement never edits starting inventories")
check(poolResult({ converter }, 1) == 182, "fresh installation defaults to Sacred Heart")
check(converter:OnExecuteCommand("allitems", "329") == nil, "console callback returns nil")
check(poolResult({ converter }, 1) == 329, "console selects Ludovico")
converter:OnExecuteCommand("allitems", "651")
check(poolResult({ converter }, 1) == 651, "console selects Bethlehem")
converter:OnExecuteCommand("allitems", "c105")
check(poolResult({ converter }, 1) == 105, "arbitrary active items work without a preset")
converter:OnExecuteCommand("allitems", " 1000 ")
check(poolResult({ converter }, 1) == 1000, "custom mod item IDs are accepted")
local writes = converter.SaveWrites
for _, invalid in ipairs({ "0", "-1", "4", "9999999999999999999999", "3.5",
    "1e999", "nan", "sacredheart", "329 extra", "c" }) do
    converter:OnExecuteCommand("allitems", invalid)
    check(poolResult({ converter }, 1) == 1000, "invalid ID keeps selected target: " .. invalid)
end
converter:OnExecuteCommand("othermod", "182")
converter:OnExecuteCommand("allitems", "")
check(converter.SaveWrites == writes, "invalid input and status queries never write settings")
check(output[#output]:find("1000", 1, true) ~= nil, "status reports the selected ID")

-- Load before game-start, as first-room generation can request items earlier.
converter = loadMod("all_items")
check(poolResult({ converter }, 1) == 1000, "selected target restores before game-start callback")
converter:OnGameStarted(true)
check(poolResult({ converter }, 1) == 1000, "continuing does not overwrite selected target")
converter:OnExit(false)
saveSlot = 2
check(poolResult({ converter }, 1) == 182, "new save slot has independent default")
converter:OnExecuteCommand("allitems", "331")
converter:OnExit(true)
saveSlot = 1
check(poolResult({ converter }, 1) == 1000, "returning to first slot restores its own target")
for _, badSave in ipairs({ "not json", "false", encode({ Version = 1, TargetID = 4 }),
    encode({ Version = 1, TargetID = "329" }), encode({ Version = 999, TargetID = 329 }) }) do
    saves[converter.Name .. saveSlot] = badSave
    converter = loadMod("all_items")
    check(poolResult({ converter }, 1) == 182, "malformed or obsolete settings use a valid default")
end
converter:OnExecuteCommand("allitems", "1001")
valid[1001] = nil
converter = loadMod("all_items")
check(poolResult({ converter }, 1) == 182, "removed custom item cannot become an invalid target")

-- Protection is identical for pool results, fixed spawns, and existing pedestals.
local untouched = { 0, -1, 182, 900, 4 }
for _, name in ipairs(protected) do untouched[#untouched + 1] = CollectibleType["COLLECTIBLE_" .. name] end
for _, id in ipairs(untouched) do
    check(converter:OnGetCollectible(id) == nil, "preserve pool item " .. id)
    check(converter:OnEntitySpawn(5, 100, id, nil, nil, nil, 12) == nil, "preserve fixed item " .. id)
    local entity = pickup(id)
    converter:OnPickupUpdate(entity)
    check(entity.SubType == id and entity.Morphs == 0, "preserve existing item " .. id)
end
local spawn = converter:OnEntitySpawn(5, 100, 1, nil, nil, nil, 12345)
check(spawn[1] == 5 and spawn[2] == 100 and spawn[3] == 182 and spawn[4] == 12345,
    "fixed spawns keep the original seed")
check(converter:OnEntitySpawn(5, 20, 1) == nil, "coins are unchanged")
check(converter:OnEntitySpawn(5, 350, 1) == nil, "trinkets are unchanged")
check(converter:OnEntitySpawn(2, 100, 1) == nil, "non-pickup entities are unchanged")
for _, price in ipairs({ 0, 15, -1, -2 }) do
    local entity = pickup(1, price, 23)
    converter:OnPickupUpdate(entity)
    converter:OnPickupUpdate(entity)
    check(entity.SubType == 182 and entity.Morphs == 1, "replacement is idempotent")
    check(entity.Price == price and entity.InitSeed == 12345 and entity.ShopItemId == 7
        and entity.OptionsPickupIndex == 23, "shop/devil prices and choice group survive")
    entity.SubType = 2
    converter:OnPickupUpdate(entity)
    check(entity.SubType == 182 and entity.Morphs == 2, "in-place rerolls are converted")
    entity.SubType = 0
    converter:OnPickupUpdate(entity)
    check(entity.SubType == 0 and entity.Morphs == 2, "collected pedestal stays empty")
end

-- An optional menu loaded after this mod must still register once at game start.
local options, registrations = nil, 0
ModConfigMenu = { OptionType = { NUMBER = 1 }, AddSetting = function(_, _, setting)
    options, registrations = setting, registrations + 1
end }
converter:OnGameStarted(false)
converter:OnGameStarted(true)
check(registrations == 1, "late-loaded menu registers only once")
check(options.Minimum == 1 and options.Maximum == 1001, "menu range includes custom IDs")
options.OnChange(3)
check(poolResult({ converter }, 1) == 3, "menu accepts ordinary items beyond the former presets")
options.OnChange(4)
check(options.CurrentSetting() == 5, "menu skips unused IDs upward")
options.OnChange(4)
check(options.CurrentSetting() == 3, "menu skips unused IDs downward")
converter:OnExecuteCommand("allitems", "329")
check(options.CurrentSetting() == 329, "menu and console share settings")
options.OnChange(651)
converter = loadMod("all_items")
check(poolResult({ converter }, 1) == 651, "menu configuration survives reload")
ModConfigMenu = nil

local effects = {}
for _, name in ipairs({ "all_sacred_hearts_stacking", "all_ludovico_autoaim",
    "all_ludovico_autoaim_v2", "all_bethlehem_snake" }) do
    local effect = loadMod(name)
    effects[#effects + 1] = effect
    for _, callback in ipairs({ "MC_POST_GET_COLLECTIBLE", "MC_PRE_ENTITY_SPAWN", "MC_POST_PICKUP_UPDATE" }) do
        check(effect.Callbacks[callback] == nil, name .. " no longer overrides " .. callback)
    end
    check(poolResult({ effect }, 1) == 1, name .. " leaves ordinary drops alone when enabled alone")
    check(poolResult({ converter, effect }, 1) == 651, name .. " can load after the converter")
    check(poolResult({ effect, converter }, 1) == 651, name .. " can load before the converter")
end

-- Item effects are still based on owned items, independently of the replacement ID.
local heart = effects[1]
local function player(count)
    local p = { Count = count, Data = {}, Recalculations = 0, ControlsEnabled = true, ControllerIndex = 0 }
    function p:GetData() return self.Data end
    function p:GetCollectibleNum() return self.Count end
    function p:HasCollectible() return self.Count > 0 end
    function p:IsDead() return false end
    function p:ToPlayer() return self end
    function p:AddCacheFlags(flag) check(flag == CacheFlag.CACHE_DAMAGE, "only damage cache is refreshed") end
    function p:EvaluateItems()
        self.Recalculations = self.Recalculations + 1
        self.Damage = self.Count > 0 and 9.05 or 3.5 -- Engine applies the first Sacred Heart.
        heart:OnEvaluateCache(self, CacheFlag.CACHE_DAMAGE)
    end
    return p
end
local first, second = player(3), player(1)
heart:OnPlayerUpdate(first)
heart:OnPlayerUpdate(second)
near(first.Damage, 51.1745, "three Sacred Hearts keep the original stacking formula")
near(second.Damage, 9.05, "second player gets only their owned copy")
heart:OnPlayerUpdate(first)
check(first.Recalculations == 1, "unchanged inventory does not repeatedly multiply damage")
first.Count = 2
heart:OnPlayerUpdate(first)
near(first.Damage, 21.815, "losing a copy removes its multiplier")
first.Count = 0
heart:OnPlayerUpdate(first)
near(first.Damage, 3.5, "losing all copies restores base damage")
for index = 2, 3 do
    local effect, owner = effects[index], player(0)
    held, frame = true, frame + 1
    effect:OnPlayerUpdate(owner)
    check(effect:OnInputAction(owner, InputHook.IS_ACTION_TRIGGERED, ButtonAction.ACTION_SHOOTLEFT) == nil,
        "Ludovico input stays untouched without the item")
    held, frame = false, frame + 1
    owner.Count = 1
    effect:OnPlayerUpdate(owner)
    held, frame = true, frame + 1
    effect:OnPlayerUpdate(owner)
    check(effect:OnInputAction(owner, InputHook.IS_ACTION_TRIGGERED, ButtonAction.ACTION_SHOOTLEFT) == false,
        "acquired Ludovico still enables automatic aiming")
    owner.Count, frame = 0, frame + 1
    effect:OnPlayerUpdate(owner)
    check(effect:OnInputAction(owner, InputHook.IS_ACTION_TRIGGERED, ButtonAction.ACTION_SHOOTLEFT) == nil,
        "losing Ludovico stops input injection")
end

print(string.format("All Items split regression: %d checks passed", checks))
