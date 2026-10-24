local mod = RegisterMod("All Items Into One", 1)
local json = require("json")
local items = include("scripts.items")
local replacement = include("scripts.replacement")
local DEFAULT_TARGET = CollectibleType.COLLECTIBLE_SACRED_HEART
local targetID = DEFAULT_TARGET
local loaded = false

local function loadSettings()
    if loaded then return end
    loaded = true
    targetID = DEFAULT_TARGET
    if mod:HasData() then
        local ok, saved = pcall(json.decode, mod:LoadData())
        if ok and type(saved) == "table" and saved.Version == 1
            and items.exists(saved.TargetID) then
            targetID = saved.TargetID
        end
    end
end

local function getTargetID()
    loadSettings()
    return targetID
end

local function selectTarget(id)
    if not items.exists(id) then return false end
    loadSettings()
    targetID = id
    mod:SaveData(json.encode({ Version = 1, TargetID = id }))
    return true
end

-- Item-pool and spawn callbacks can run before MC_POST_GAME_STARTED.
-- Load the selected save slot lazily, before its first replacement.
function mod:OnGetCollectible(selected)
    local target = getTargetID()
    if replacement.shouldReplace(selected, target) then return target end
end
mod:AddPriorityCallback(ModCallbacks.MC_POST_GET_COLLECTIBLE,
    CallbackPriority.LATE, mod.OnGetCollectible)

function mod:OnEntitySpawn(entityType, variant, subtype, position, velocity, spawner, seed)
    if entityType ~= EntityType.ENTITY_PICKUP
        or variant ~= PickupVariant.PICKUP_COLLECTIBLE then return end
    local target = getTargetID()
    if replacement.shouldReplace(subtype, target) then
        return { entityType, variant, target, seed }
    end
end
mod:AddCallback(ModCallbacks.MC_PRE_ENTITY_SPAWN, mod.OnEntitySpawn)

function mod:OnPickupUpdate(pickup)
    replacement.replacePickup(pickup, getTargetID())
end
mod:AddCallback(ModCallbacks.MC_POST_PICKUP_UPDATE, mod.OnPickupUpdate,
    PickupVariant.PICKUP_COLLECTIBLE)

function mod:OnExecuteCommand(command, parameters)
    if command ~= "allitems" then return end
    local requested = (parameters or ""):match("^%s*(.-)%s*$")
    if requested ~= "" then
        local id = tonumber(requested:match("^[cC]?(%d+)$"))
        if not selectTarget(id) then
            Isaac.ConsoleOutput("Invalid collectible ID. Usage: allitems <item ID>, e.g. allitems 329\n")
            return
        end
    end
    Isaac.ConsoleOutput("All Items Into One: item ID " .. getTargetID() .. "\n")
end
mod:AddCallback(ModCallbacks.MC_EXECUTE_CMD, mod.OnExecuteCommand)

local registerMenu = include("scripts.mcm")(items, getTargetID, selectTarget, DEFAULT_TARGET)
registerMenu()
function mod:OnGameStarted()
    loadSettings()
    registerMenu()
end
mod:AddCallback(ModCallbacks.MC_POST_GAME_STARTED, mod.OnGameStarted)

function mod:OnExit()
    -- The next run may use a different game save slot.
    loaded = false
end
mod:AddCallback(ModCallbacks.MC_PRE_GAME_EXIT, mod.OnExit)
