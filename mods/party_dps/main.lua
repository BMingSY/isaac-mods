local mod = RegisterMod("Party DPS", 1)
local game, json = Game(), require("json")
local Meter = include("scripts/meter")
local Ownership = include("scripts/ownership")
local Damage = include("scripts/damage")
local meter = Meter.new()
local damage = Damage.new(meter)
local lan, ownership, seed, runId
local generation, inGame = 0, false
local owners, controllers, localOwners = {}, {}, {}
local settings =
    { visible = true, mode = "encounter", scale = 0.65, opacity = 0.9, anchor = "bottom_left" }
local stored = {}

if mod:HasData() then
    local ok, value = pcall(json.decode, mod:LoadData())
    if ok and type(value) == "table" and value.version == 1 then
        stored = value
        local config = type(value.settings) == "table" and value.settings or {}
        if type(config.visible) == "boolean" then
            settings.visible = config.visible
        end
        if config.mode == "run" then
            settings.mode = "run"
        end
        if type(config.scale) == "number" and config.scale >= 0.5 and config.scale <= 1.25 then
            settings.scale = math.max(0.65, config.scale)
        end
        if type(config.opacity) == "number" and config.opacity >= 0.3 and config.opacity <= 1 then
            settings.opacity = config.opacity
        end
        for _, anchor in ipairs({ "bottom_left", "bottom_right", "top_left", "top_right" }) do
            if config.anchor == anchor then
                settings.anchor = anchor
            end
        end
        for _, axis in ipairs({ "x", "y" }) do
            local n = config[axis]
            if type(n) == "number" and n >= 0 and n <= 1 then
                settings[axis] = n
            end
        end
    end
end

local function authority()
    return not lan or lan:authority()
end

local function ready()
    return not lan or not lan:active() or lan.handle:IsReady()
end

local function persist()
    stored.version, stored.settings = 1, settings
    if inGame and authority() then
        stored.seed, stored.meter = seed, meter:snapshot()
    end
    mod:SaveData(json.encode(stored))
end

local ui = include("scripts/ui")(settings, persist)
local registerMCM = include("scripts/mcm")(settings, ui, persist)
registerMCM()

local function identify(player)
    local hash = GetPtrHash(player)
    local owner
    if lan and lan:active() then
        if not lan.handle:IsReady() then
            return
        end
        owner = lan.handle:GetOwnerId(player)
    else
        owner = owners[hash]
        if not owner then
            local controller = player.ControllerIndex
            owner = controllers[controller]
            if not owner then
                local count = 0
                for _ in pairs(controllers) do
                    count = count + 1
                end
                owner = count + 1
                controllers[controller] = owner
            end
        end
    end
    if not owner or owner > 4 then
        return
    end
    owners[hash] = owner
    local role = lan and lan:active() and lan.handle:GetPlayerId(player)
    if not role or role:match(":1$") then
        local name = player:GetName()
        if player:GetPlayerType() == PlayerType.PLAYER_JACOB then
            name = "Jacob+Esau"
        end
        meter:ensure(owner, name)
    else
        meter:ensure(owner)
    end
    return owner
end

local function clearReferences()
    generation = generation + 1
    owners, controllers = {}, {}
    damage = Damage.new(meter)
    ownership = Ownership.new(identify, generation, function()
        return meter.now
    end)
end
clearReferences()

local function tick()
    if lan and lan:active() then
        local context = lan.handle:GetContext()
        return context and context.tick or nil
    end
    return game:GetFrameCount()
end

local function updateMeter()
    if not authority() or not ready() then
        return
    end
    -- Attribute the last completed native calls before advancing the idle timer.
    damage:flushAll()
    meter:advance(tick())
    ownership:prune(meter.now)
end

lan = include("scripts/lan")(mod, Meter, {
    snapshot = function()
        updateMeter()
        return meter:snapshot()
    end,
    reset = function(context)
        if context.reason == "session_ended" and inGame and authority() then
            damage:flushAll()
            meter:finish()
            persist()
        end
        meter:finish()
        localOwners = {}
        clearReferences()
        if context.reason == "session_ended" then
            inGame = false
        end
    end,
    view = function(context, handle)
        if runId and runId ~= context.runId then
            meter = Meter.new()
            clearReferences()
        end
        runId = context.runId
        localOwners = {}
        for _, player in ipairs(handle:GetLocalPlayers()) do
            local owner = identify(player)
            if owner then
                localOwners[owner] = true
            end
        end
        updateMeter()
    end,
})

function mod:OnGameStarted(continued)
    registerMCM()
    inGame, seed, runId = true, game:GetSeeds():GetStartSeed(), nil
    meter = continued and stored.seed == seed and Meter.restore(stored.meter) or Meter.new()
    localOwners = {}
    clearReferences()
end
mod:AddCallback(ModCallbacks.MC_POST_GAME_STARTED, mod.OnGameStarted)

function mod:OnPlayerUpdate(player)
    if inGame and authority() then
        identify(player)
    end
end
mod:AddCallback(ModCallbacks.MC_POST_PLAYER_UPDATE, mod.OnPlayerUpdate)

function mod:OnSourceUpdate(entity)
    if inGame and authority() and ready() then
        ownership:resolve(entity)
    end
end
for _, callback in ipairs({
    ModCallbacks.MC_POST_TEAR_UPDATE,
    ModCallbacks.MC_FAMILIAR_UPDATE,
    ModCallbacks.MC_POST_LASER_UPDATE,
    ModCallbacks.MC_POST_KNIFE_UPDATE,
    ModCallbacks.MC_POST_BOMB_UPDATE,
    ModCallbacks.MC_POST_EFFECT_UPDATE,
}) do
    mod:AddCallback(callback, mod.OnSourceUpdate)
end

function mod:OnDamage(target, amount, flags, source)
    if not inGame or not authority() or not ready() then
        return
    end
    -- Flush an earlier hit even if this one has no player source.
    damage:flush(GetPtrHash(target))
    if
        amount <= 0
        or (flags & DamageFlag.DAMAGE_FAKE) ~= 0
        or not target:ToNPC()
        or not target:IsActiveEnemy(false)
        or not target:IsVulnerableEnemy()
        or target:HasEntityFlags(EntityFlag.FLAG_FRIENDLY)
    then
        return
    end
    meter:advance(tick())
    local owner = ownership:resolve(source and source.Entity)
    damage:begin(target, owner, amount)
    -- This observer must return nil, preserving all damage callback behavior.
end
mod:AddPriorityCallback(ModCallbacks.MC_ENTITY_TAKE_DMG, CallbackPriority.LATE, mod.OnDamage)

function mod:OnNPCUpdate(npc)
    if inGame and authority() and ready() then
        damage:flush(GetPtrHash(npc))
    end
end
mod:AddPriorityCallback(ModCallbacks.MC_NPC_UPDATE, CallbackPriority.LATE, mod.OnNPCUpdate)
mod:AddCallback(ModCallbacks.MC_POST_NPC_DEATH, mod.OnNPCUpdate)

function mod:OnUpdate()
    if not inGame then
        return
    end
    updateMeter()
    if not lan or not lan:active() then
        localOwners = {}
        for i = 0, game:GetNumPlayers() - 1 do
            local player = Isaac.GetPlayer(i)
            local owner = identify(player)
            if owner then
                localOwners[owner] = true
            end
            local sub = player:GetSubPlayer()
            if sub then
                owners[GetPtrHash(sub)] = owner
                ownership:resolve(sub)
            end
        end
    end
end
mod:AddCallback(ModCallbacks.MC_POST_UPDATE, mod.OnUpdate)

function mod:OnNewLevel()
    if authority() then
        meter:finish()
    end
    clearReferences()
end
mod:AddCallback(ModCallbacks.MC_POST_NEW_LEVEL, mod.OnNewLevel)

function mod:OnRender()
    registerMCM()
    if not inGame or not ready() then
        return
    end
    local snapshot, status
    if lan and lan:active() then
        snapshot, status = lan:snapshot(tick() or 0)
    else
        snapshot = meter:snapshot()
    end
    snapshot = snapshot or { rows = {}, duration = 0, combat = 0, active = false }
    ui:render(Meter.view(snapshot, settings.mode), localOwners, status)
end
mod:AddCallback(ModCallbacks.MC_POST_RENDER, mod.OnRender)

function mod:OnExit()
    if inGame and authority() then
        updateMeter()
        meter:finish()
    end
    persist()
    inGame = false
    clearReferences()
end
mod:AddCallback(ModCallbacks.MC_PRE_GAME_EXIT, mod.OnExit)

function mod:OnCommand(command, argument)
    if command ~= "partydps" then
        return
    end
    if argument == "position" then
        ui:resetPosition()
    elseif argument == "show" then
        settings.visible = true
        persist()
    elseif argument == "hide" then
        settings.visible = false
        persist()
    elseif argument == "settings" then
        ui.menuOpen = not ui.menuOpen
    else
        Isaac.ConsoleOutput(
            "partydps settings | show | hide | position\nF6 settings, F7 mode, F8 visibility, F9 unlock panel.\n"
        )
    end
end
mod:AddCallback(ModCallbacks.MC_EXECUTE_CMD, mod.OnCommand)

-- Read-only accessor for companion tools and isolated gameplay checks.
function mod:GetSnapshot()
    if lan and lan:active() then
        return lan:snapshot(tick() or 0)
    end
    return meter:snapshot()
end
_G.PartyDPS = mod
