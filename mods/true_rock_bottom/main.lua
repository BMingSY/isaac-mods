local mod = RegisterMod("True Rock Bottom", 1)
local json = require("json")
local rebase = include("scripts/rebase")
local game = Game()
local ROCK = CollectibleType.COLLECTIBLE_ROCK_BOTTOM
local TRUE_ROCK = Isaac.GetItemIdByName("True Rock Bottom")
if TRUE_ROCK <= 0 then
    Isaac.DebugString("[True Rock Bottom] Item definition was not loaded")
    return
end
local KEY = "TrueRockBottom_State"
local PRIORITY = 1000000
local started = false
local savedPlayers = {}
local runtime = {}
local repairInventoryOnContinue = false

-- Work in tears per second, where a higher number is always better.
local stats = {
    {name = "damage", flag = CacheFlag.CACHE_DAMAGE, field = "Damage"},
    {name = "tears", flag = CacheFlag.CACHE_FIREDELAY, field = "MaxFireDelay"},
    {name = "speed", flag = CacheFlag.CACHE_SPEED, field = "MoveSpeed"},
    {name = "range", flag = CacheFlag.CACHE_RANGE, field = "TearRange"},
    {name = "shotSpeed", flag = CacheFlag.CACHE_SHOTSPEED, field = "ShotSpeed"},
    {name = "luck", flag = CacheFlag.CACHE_LUCK, field = "Luck"},
}
local byFlag = {}
for _, stat in ipairs(stats) do
    byFlag[stat.flag] = stat
end

local function readStat(player, stat)
    local value = player[stat.field]
    if stat.name == "tears" then
        return 30 / math.max(0.01, value + 1)
    end
    return value
end

local function writeStat(player, stat, value)
    if not rebase.isFinite(value) then
        return
    end
    if stat.name == "tears" then
        player.MaxFireDelay = math.max(-0.99, 30 / math.max(0.000001, value) - 1)
    elseif stat.name == "speed" or stat.name == "shotSpeed" then
        -- Keep the engine's ordinary movement/shot-speed limits.
        player[stat.field] = math.min(2, value)
    else
        player[stat.field] = value
    end
end

local function snapshot(player)
    local result = {}
    for _, stat in ipairs(stats) do
        result[stat.name] = readStat(player, stat)
    end
    return result
end

local function ownsRock(player)
    return player:HasCollectible(TRUE_ROCK) or player:HasCollectible(ROCK)
end

local function playerKey(player)
    local hash = GetPtrHash(player)
    for index = 0, game:GetNumPlayers() - 1 do
        local main = Isaac.GetPlayer(index)
        if GetPtrHash(main) == hash then
            return tostring(index)
        end
        local sub = main:GetSubPlayer()
        if sub and GetPtrHash(sub) == hash then
            return tostring(index) .. ":sub"
        end
    end
    return "extra:" .. tostring(player.InitSeed)
end

local function getState(player)
    local data = player:GetData()
    local state = data[KEY]
    if not state or runtime[GetPtrHash(player)] ~= state then
        local key = playerKey(player)
        state = {key = key, records = savedPlayers[key] or {}, pending = true,
            needsHistoryRepair = repairInventoryOnContinue}
        savedPlayers[key] = nil
        data[KEY] = state
        runtime[GetPtrHash(player)] = state
    end
    return state
end

local function evaluate(player, flags)
    player:AddCacheFlags(flags or CacheFlag.CACHE_ALL)
    player:EvaluateItems()
end

-- Huge Growth adds a flat +7 after the nonlinear damage formula. Measuring
-- that difference includes later vanilla multipliers AND other Lua mods.
-- These multipliers precede that flat bonus and must be included separately.
local characterDamage = {
    [PlayerType.PLAYER_MAGDALENE_B] = 0.75,
    [PlayerType.PLAYER_BLUEBABY] = 1.05,
    [PlayerType.PLAYER_KEEPER] = 1.2,
    [PlayerType.PLAYER_CAIN] = 1.2,
    [PlayerType.PLAYER_CAIN_B] = 1.2,
    [PlayerType.PLAYER_EVE_B] = 1.2,
    [PlayerType.PLAYER_JUDAS] = 1.35,
    [PlayerType.PLAYER_AZAZEL] = 1.5,
    [PlayerType.PLAYER_THEFORGOTTEN] = 1.5,
    [PlayerType.PLAYER_AZAZEL_B] = 1.5,
    [PlayerType.PLAYER_THEFORGOTTEN_B] = 1.5,
    [PlayerType.PLAYER_LAZARUS2_B] = 1.5,
    [PlayerType.PLAYER_LAZARUS2] = 1.4,
    [PlayerType.PLAYER_THELOST_B] = 1.3,
    [PlayerType.PLAYER_BLACKJUDAS] = 2,
}

local function earlyDamageMultiplier(player)
    local multiplier = characterDamage[player:GetPlayerType()] or 1
    local effects = player:GetEffects()
    if player:GetPlayerType() == PlayerType.PLAYER_EVE
        and not effects:HasCollectibleEffect(CollectibleType.COLLECTIBLE_WHORE_OF_BABYLON) then
        multiplier = multiplier * 0.75
    end
    if player:HasCollectible(CollectibleType.COLLECTIBLE_ODD_MUSHROOM_THIN) then
        multiplier = multiplier * 0.9
    end
    if player:HasCollectible(CollectibleType.COLLECTIBLE_POLYPHEMUS)
        and not player:HasCollectible(CollectibleType.COLLECTIBLE_20_20)
        and not player:HasCollectible(CollectibleType.COLLECTIBLE_INNER_EYE)
        and not player:HasCollectible(CollectibleType.COLLECTIBLE_MUTANT_SPIDER) then
        multiplier = multiplier * 2
    end
    if effects:HasCollectibleEffect(CollectibleType.COLLECTIBLE_MEGA_MUSH) then
        multiplier = multiplier * 4
    end
    return multiplier
end

local function restoreEffectCount(effects, id, original)
    local difference = effects:GetNullEffectNum(id) - original
    if difference > 0 then
        effects:RemoveNullEffect(id, difference)
    elseif difference < 0 then
        effects:AddNullEffect(id, false, -difference)
    end
end

local function sample(player, state)
    local effects = player:GetEffects()
    local growthCount = effects:GetNullEffectNum(NullItemID.ID_HUGE_GROWTH)
    local lunaCount = effects:GetNullEffectNum(NullItemID.ID_LUNA)
    state.sampling = true
    local raw, damageMultiplier, tearsMultiplier
    local ok, err = pcall(function()
        evaluate(player)
        raw = snapshot(player)
        if growthCount > 0 then
            effects:RemoveNullEffect(NullItemID.ID_HUGE_GROWTH, growthCount)
            evaluate(player, CacheFlag.CACHE_DAMAGE)
        end
        local damageBefore = player.Damage
        effects:AddNullEffect(NullItemID.ID_HUGE_GROWTH, false, 1)
        evaluate(player, CacheFlag.CACHE_DAMAGE)
        damageMultiplier = (player.Damage - damageBefore) / 7 * earlyDamageMultiplier(player)
        restoreEffectCount(effects, NullItemID.ID_HUGE_GROWTH, growthCount)
        evaluate(player)
        local tearsBefore = readStat(player, stats[2])
        effects:AddNullEffect(NullItemID.ID_LUNA, false, 1)
        evaluate(player, CacheFlag.CACHE_FIREDELAY)
        tearsMultiplier = readStat(player, stats[2]) - tearsBefore
    end)

    -- Always remove ONLY the probes we added, including on a Lua error.
    local cleaned, cleanupError = pcall(function()
        restoreEffectCount(effects, NullItemID.ID_HUGE_GROWTH, growthCount)
        restoreEffectCount(effects, NullItemID.ID_LUNA, lunaCount)
        evaluate(player)
    end)
    state.sampling = false
    if not ok or not cleaned then
        Isaac.DebugString("[True Rock Bottom] " .. tostring(err or cleanupError))
        for _, stat in ipairs(stats) do
            local record = state.records[stat.name]
            if record then
                writeStat(player, stat, record.peak)
            end
        end
        return nil
    end
    return raw, {damage = damageMultiplier, tears = tearsMultiplier}
end

function mod:OnCache(player, cacheFlag)
    if not started or not byFlag[cacheFlag] then
        return
    end
    local existing = player:GetData()[KEY]
    if existing and (existing.sampling or existing.converting) then
        return
    end
    if not ownsRock(player) then
        if existing then
            existing.records = {}
            existing.pending = false
            existing.wasOwned = false
            existing.seedPeak = nil
        end
        return
    end
    local state = getState(player)
    if state.applying then
        local record = state.records[byFlag[cacheFlag].name]
        if record then
            writeStat(player, byFlag[cacheFlag], record.peak)
        end
        return
    end
    state.pending = true
    local stat = byFlag[cacheFlag]
    local record = state.records[stat.name]
    if record and player:HasCollectible(TRUE_ROCK) and not player:HasCollectible(ROCK) then
        -- Keep the current value until the multiplier is sampled after player
        -- updates. Do not commit an estimate based on an outdated multiplier.
        writeStat(player, stat, record.peak)
    end
end

mod:AddPriorityCallback(ModCallbacks.MC_EVALUATE_CACHE, PRIORITY, mod.OnCache)

local function updatePlayer(player)
    local state = getState(player)
    if not ownsRock(player) then
        state.records = {}
        state.pending = false
        state.seedPeak = nil
        state.wasOwned = false
        return
    end
    if not state.wasOwned then
        state.wasOwned = true
        state.pending = true
        state.seedPeak = snapshot(player)
    end

    local originalCount = player:GetCollectibleNum(ROCK, true)
    if state.needsHistoryRepair then
        -- Version 0.1 used a hidden clone. Re-register existing copies once
        -- so old continued runs also get real entries in the item HUD.
        -- The clone grants no consumables and has no transformation tags.
        local count = player:GetCollectibleNum(TRUE_ROCK, true)
        state.converting = true
        for _ = 1, count do
            player:RemoveCollectible(TRUE_ROCK, true)
        end
        for _ = 1, count do
            player:AddCollectible(TRUE_ROCK, 0, true)
        end
        state.converting = false
        state.needsHistoryRepair = false
        if count > 0 then
            state.pending = true
        end
    end
    if originalCount > 0 then
        -- Convert once, rather than remove/add 562 on every recalculation.
        -- Pedestals stay vanilla for collection progress and Spindown Dice.
        -- The clone has no native clamp, so we can read the real raw stats.
        state.converting = true
        for _ = 1, originalCount do
            player:RemoveCollectible(ROCK, true)
            -- A real, visible inventory entry is needed for the normal HUD.
            -- This clone has no first-pickup bonuses to duplicate.
            player:AddCollectible(TRUE_ROCK, 0, true)
        end
        state.converting = false
        state.pending = true
    end
    if not state.pending or player:HasCollectible(ROCK) then
        -- Do not sample through native clamps granted by a temporary fake
        -- item. Sampling resumes once the real inventory can be converted.
        return
    end
    local raw, multipliers = sample(player, state)
    if not raw then
        return
    end
    for _, stat in ipairs(stats) do
        local name = stat.name
        state.records[name] = rebase.update(state.records[name], raw[name],
            multipliers[name] or 1, state.seedPeak and state.seedPeak[name])
    end
    state.seedPeak = nil
    state.pending = false
    state.applying = true
    local ok, err = pcall(evaluate, player)
    state.applying = false
    if not ok then
        state.pending = true
        Isaac.DebugString("[True Rock Bottom] " .. tostring(err))
    end
end

function mod:OnUpdate()
    if not started then
        return
    end
    for index = 0, game:GetNumPlayers() - 1 do
        local player = Isaac.GetPlayer(index)
        updatePlayer(player)
        local sub = player:GetSubPlayer()
        if sub then
            updatePlayer(sub)
        end
    end
end

mod:AddCallback(ModCallbacks.MC_POST_UPDATE, mod.OnUpdate)

local function save()
    if not started then
        return
    end
    local players = {}
    for _, state in pairs(runtime) do
        players[state.key] = state.records
    end
    mod:SaveData(json.encode({version = 1, inventoryHudVersion = 1,
        seed = game:GetSeeds():GetStartSeed(), players = players}))
end

function mod:OnStart(isContinued)
    runtime = {}
    savedPlayers = {}
    repairInventoryOnContinue = isContinued
    if isContinued and mod:HasData() then
        local ok, data = pcall(json.decode, mod:LoadData())
        if ok and type(data) == "table" and data.version == 1
            and data.seed == game:GetSeeds():GetStartSeed()
            and type(data.players) == "table" then
            repairInventoryOnContinue = data.inventoryHudVersion ~= 1
            for key, records in pairs(data.players) do
                if type(records) == "table" then
                    local valid = {}
                    for _, stat in ipairs(stats) do
                        local record = records[stat.name]
                        if type(record) == "table" and rebase.isFinite(record.peak)
                            and rebase.isFinite(record.carry) and record.carry >= 0
                            and rebase.isFinite(record.multiplier) and record.multiplier > 0 then
                            valid[stat.name] = record
                        end
                    end
                    savedPlayers[key] = valid
                end
            end
        end
    end
    started = true
    self:OnUpdate()
end

mod:AddCallback(ModCallbacks.MC_POST_GAME_STARTED, mod.OnStart)
mod:AddCallback(ModCallbacks.MC_POST_NEW_ROOM, save)
mod:AddCallback(ModCallbacks.MC_PRE_GAME_EXIT, function(_, shouldSave)
    if shouldSave then
        mod:OnUpdate()
        save()
    else
        mod:SaveData("{}")
    end
    started = false
end)

-- Return dropped/internal clones to 562 before spawning; never replace other
-- collectibles or touch ordinary item pools.
mod:AddCallback(ModCallbacks.MC_PRE_ENTITY_SPAWN,
    function(_, entityType, variant, subtype, _, _, _, seed)
        if entityType == EntityType.ENTITY_PICKUP
            and variant == PickupVariant.PICKUP_COLLECTIBLE and subtype == TRUE_ROCK then
            return {entityType, variant, ROCK, seed}
        end
    end)
mod:AddCallback(ModCallbacks.MC_POST_PICKUP_UPDATE, function(_, pickup)
    if pickup.SubType == TRUE_ROCK then
        local options = pickup.OptionsPickupIndex
        pickup:Morph(EntityType.ENTITY_PICKUP, PickupVariant.PICKUP_COLLECTIBLE,
            ROCK, true, true, true)
        pickup.OptionsPickupIndex = options
    end
end, PickupVariant.PICKUP_COLLECTIBLE)

if EID then
    local description = "保留的最高属性作为后续加成的计算基准"
        .. "#属性降低后，新的加成仍能继续提升属性"
        .. "#临时加成消失后保留，再次获得可继续提升"
    EID:addCollectible(ROCK, description, "谷底石", "zh_cn")
    EID:addCollectible(TRUE_ROCK, description, "谷底石", "zh_cn")
end
