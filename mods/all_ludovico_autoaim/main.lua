local mod = RegisterMod("All Ludovico + Auto Aim", 1)
local game = Game()
local statusFont = Font()
statusFont:Load("font/terminus8.fnt")

local LUDOVICO = CollectibleType.COLLECTIBLE_LUDOVICO_TECHNIQUE -- 329
local COLLECTIBLE = PickupVariant.PICKUP_COLLECTIBLE
local ARRIVAL_DISTANCE = 1
local AIM_SLOWDOWN_DISTANCE = 8
local SHOOT_ACTIONS = {
    ButtonAction.ACTION_SHOOTLEFT,
    ButtonAction.ACTION_SHOOTRIGHT,
    ButtonAction.ACTION_SHOOTUP,
    ButtonAction.ACTION_SHOOTDOWN,
}
local SHOOT_ACTION_SET = {}
for _, action in ipairs(SHOOT_ACTIONS) do
    SHOOT_ACTION_SET[action] = true
end

local playerStates = {}
local roomEntities = {}
local roomEntitiesFrame = -1
local readingPhysicalInput = false

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

local function shouldReplace(itemId)
    if itemId <= 0 or itemId == LUDOVICO or PROTECTED_ITEMS[itemId] then
        return false
    end
    local config = Isaac.GetItemConfig():GetCollectible(itemId)
    return not (config and config:HasTags(ItemConfig.TAG_QUEST))
end

function mod:OnGetCollectible(selectedCollectible)
    if shouldReplace(selectedCollectible) then
        return LUDOVICO
    end
end

mod:AddPriorityCallback(
    ModCallbacks.MC_POST_GET_COLLECTIBLE,
    CallbackPriority.LATE,
    mod.OnGetCollectible
)

function mod:OnEntitySpawn(entityType, variant, subtype, position, velocity, spawner, seed)
    if entityType == EntityType.ENTITY_PICKUP and variant == COLLECTIBLE
        and shouldReplace(subtype) then
        return { entityType, variant, LUDOVICO, seed }
    end
end

mod:AddCallback(ModCallbacks.MC_PRE_ENTITY_SPAWN, mod.OnEntitySpawn)

function mod:OnPickupUpdate(pickup)
    if not shouldReplace(pickup.SubType) then
        return
    end
    local optionsIndex = pickup.OptionsPickupIndex
    pickup:Morph(EntityType.ENTITY_PICKUP, COLLECTIBLE, LUDOVICO, true, true, true)
    pickup.OptionsPickupIndex = optionsIndex
end

mod:AddCallback(ModCallbacks.MC_POST_PICKUP_UPDATE, mod.OnPickupUpdate, COLLECTIBLE)

local function getState(player)
    local hash = GetPtrHash(player)
    if not playerStates[hash] then
        playerStates[hash] = {
            Enabled = false,
            ShootHeld = false,
            InputFrame = -1,
            AimFrame = -1,
            Aim = Vector.Zero,
        }
    end
    return playerStates[hash]
end

local function getRoomEntities()
    local frame = game:GetFrameCount()
    if roomEntitiesFrame ~= frame then
        roomEntities = Isaac.GetRoomEntities()
        roomEntitiesFrame = frame
    end
    return roomEntities
end

local function getOwner(entity)
    local queue = { entity }
    local seen = {}
    local index = 1
    while index <= #queue and index <= 16 do
        local current = queue[index]
        index = index + 1
        if current and current:Exists() then
            local hash = GetPtrHash(current)
            if not seen[hash] then
                seen[hash] = true
                local player = current:ToPlayer()
                if player then
                    return player
                end
                local familiar = current:ToFamiliar()
                if familiar and familiar.Player then
                    return familiar.Player
                end
                if current.Parent then
                    queue[#queue + 1] = current.Parent
                end
                if current.SpawnerEntity then
                    queue[#queue + 1] = current.SpawnerEntity
                end
            end
        end
    end
end

local function isTargetable(entity)
    return entity and entity:Exists() and not entity:IsDead()
        and entity:IsActiveEnemy(false) and entity:IsVulnerableEnemy()
        and not entity:HasEntityFlags(EntityFlag.FLAG_FRIENDLY)
        and not entity:HasEntityFlags(EntityFlag.FLAG_CHARM)
end

local function getControlledWeapon(player)
    local ownerHash = GetPtrHash(player)
    local mainTear
    for _, entity in ipairs(getRoomEntities()) do
        if entity:Exists() and not entity:IsDead() then
            local tear = entity:ToTear()
            local laser = entity:ToLaser()
            local isMainTear = tear and tear:HasTearFlags(TearFlags.TEAR_LUDOVICO)
                and not (tear.Parent and tear.Parent.Type == EntityType.ENTITY_TEAR)
            local isLudoRing = laser and laser.SubType == 1 and laser:IsCircleLaser()
            if isMainTear or isLudoRing then
                local owner = getOwner(entity)
                if owner and GetPtrHash(owner) == ownerHash then
                    -- Aim a laser ring by its edge instead of its empty center.
                    if isLudoRing then
                        return laser
                    end
                    if not mainTear or (tear.Parent and tear.Parent:ToPlayer()) then
                        mainTear = tear
                    end
                end
            end
        end
    end
    return mainTear
end

local function getTarget(state, origin)
    local current = state.Target and state.Target.Ref
    if isTargetable(current) then
        return current
    end

    local nearest
    local nearestDistance = math.huge
    for _, entity in ipairs(getRoomEntities()) do
        if isTargetable(entity) then
            local distance = entity.Position:DistanceSquared(origin)
            if distance < nearestDistance then
                nearest = entity
                nearestDistance = distance
            end
        end
    end
    state.Target = nearest and EntityPtr(nearest) or nil
    return nearest
end

local function getAim(player, state)
    local frame = game:GetFrameCount()
    if state.AimFrame == frame then
        return state.Aim
    end

    state.AimFrame = frame
    state.Aim = Vector.Zero
    local weapon = getControlledWeapon(player)
    local origin = weapon and weapon.Position or player.Position
    local target = getTarget(state, origin)
    if not target then
        return state.Aim
    end

    local goal = target.Position
    local laser = weapon and weapon:ToLaser()
    if laser and laser.Radius > 0 then
        local outward = origin - target.Position
        if outward:LengthSquared() < 0.001 then
            outward = Vector(1, 0)
        end
        goal = target.Position + outward:Resized(laser.Radius)
    end

    local delta = goal - origin
    local distance = delta:Length()
    if distance > ARRIVAL_DISTANCE then
        -- Native analog steering slows near the target and keeps all tear
        -- collision, satellite orbit, damage, and movement rules in the engine.
        state.Aim = delta:Resized(math.min(1, distance / AIM_SLOWDOWN_DISTANCE))
    end
    return state.Aim
end

local function readShootHeld(controllerIndex)
    -- Input.IsActionPressed can itself invoke MC_INPUT_ACTION. Only physical
    -- input may toggle the mode; generated auto-aim must not toggle itself.
    readingPhysicalInput = true
    local ok, held = pcall(function()
        for _, action in ipairs(SHOOT_ACTIONS) do
            if Input.IsActionPressed(action, controllerIndex) then
                return true
            end
        end
        return false
    end)
    readingPhysicalInput = false
    if not ok then
        error(held)
    end
    return held
end

function mod:OnPlayerUpdate(player)
    local state = getState(player)
    local frame = game:GetFrameCount()
    if state.InputFrame == frame then
        return
    end
    state.InputFrame = frame
    local held = readShootHeld(player.ControllerIndex)

    if not player:HasCollectible(LUDOVICO) then
        state.Enabled = false
        state.Target = nil
    elseif not game:IsPaused() and player.ControlsEnabled and not player:IsDead()
        and held and not state.ShootHeld then
        state.Enabled = not state.Enabled
        state.Target = nil
    end

    -- A diagonal press and a held key each count as one press. Release all
    -- shooting directions before pressing again to change the mode.
    state.ShootHeld = held
    state.AimFrame = -1
end

mod:AddCallback(ModCallbacks.MC_POST_PEFFECT_UPDATE, mod.OnPlayerUpdate)

function mod:OnInputAction(entity, inputHook, action)
    if readingPhysicalInput or not SHOOT_ACTION_SET[action] or not entity
        or game:IsPaused() then
        return
    end
    local player = entity:ToPlayer()
    if not player or not player.ControlsEnabled or player:IsDead()
        or not player:HasCollectible(LUDOVICO) then
        return
    end
    local state = getState(player)
    if not state.Enabled then
        return
    end

    if inputHook == InputHook.IS_ACTION_TRIGGERED then
        return false
    end
    local aim = getAim(player, state)
    -- The engine flips horizontal shooting input after MC_INPUT_ACTION in
    -- mirror rooms. Compensate here while keeping cached aim in world space.
    local aimX = aim.X
    if game:GetRoom():IsMirrorWorld() then
        aimX = -aimX
    end
    local value = 0
    if action == ButtonAction.ACTION_SHOOTLEFT then
        value = math.max(0, -aimX)
    elseif action == ButtonAction.ACTION_SHOOTRIGHT then
        value = math.max(0, aimX)
    elseif action == ButtonAction.ACTION_SHOOTUP then
        value = math.max(0, -aim.Y)
    elseif action == ButtonAction.ACTION_SHOOTDOWN then
        value = math.max(0, aim.Y)
    end

    if inputHook == InputHook.GET_ACTION_VALUE then
        return value
    elseif inputHook == InputHook.IS_ACTION_PRESSED then
        return value > 0
    end
end

mod:AddPriorityCallback(
    ModCallbacks.MC_INPUT_ACTION,
    CallbackPriority.LATE,
    mod.OnInputAction
)

function mod:OnNewRoom()
    roomEntitiesFrame = -1
    roomEntities = {}
    for _, state in pairs(playerStates) do
        state.Target = nil
        state.AimFrame = -1
    end
end

mod:AddCallback(ModCallbacks.MC_POST_NEW_ROOM, mod.OnNewRoom)

function mod:OnGameStarted()
    playerStates = {}
    readingPhysicalInput = false
    self:OnNewRoom()
end

mod:AddCallback(ModCallbacks.MC_POST_GAME_STARTED, mod.OnGameStarted)

function mod:OnRender()
    if game:IsPaused() then
        return
    end
    for index = 0, game:GetNumPlayers() - 1 do
        local player = Isaac.GetPlayer(index)
        if player:HasCollectible(LUDOVICO) and not player:IsDead() then
            local enabled = getState(player).Enabled
            local text = enabled and "AUTO ON" or "AUTO OFF"
            local position = Isaac.WorldToScreen(player.Position) + Vector(0, -45)
            -- Font draws in screen space without mirrored glyphs, whereas
            -- Isaac.RenderText is flipped with the room. Mirror only the anchor.
            if game:GetRoom():IsMirrorWorld() then
                position.X = Isaac.GetScreenWidth() - position.X
            end
            local red, green, blue = 0.8, 0.8, 0.8
            if enabled then
                red, green, blue = 0.35, 1, 0.45
            end
            statusFont:DrawString(text, position.X - statusFont:GetStringWidth(text) / 2,
                position.Y, KColor(red, green, blue, 1), 0, false)
        end
    end
end

mod:AddCallback(ModCallbacks.MC_POST_RENDER, mod.OnRender)
