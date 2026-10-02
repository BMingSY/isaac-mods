local mod = RegisterMod("All Ludovico V2 + Independent Auto Aim", 1)
local game = Game()
local statusFont = Font()
statusFont:Load("font/terminus8.fnt")

local LUDOVICO = CollectibleType.COLLECTIBLE_LUDOVICO_TECHNIQUE -- 329
local COLLECTIBLE = PickupVariant.PICKUP_COLLECTIBLE
local ARRIVAL_DISTANCE = 1
local AIM_SLOWDOWN_DISTANCE = 8
local BALL_DATA = "AllLudovicoV2Ball"
local SATELLITE_DATA = "AllLudovicoV2NativeSatellite"
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
            Balls = {},
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
        if entity:Exists() and not entity:IsDead() and not entity:GetData()[BALL_DATA] then
            local tear = entity:ToTear()
            local laser = entity:ToLaser()
            local isMainTear = tear and tear:HasTearFlags(TearFlags.TEAR_LUDOVICO)
                and not (tear.Parent and tear.Parent.Type == EntityType.ENTITY_TEAR)
            local isLudoRing = laser and laser.SubType == 1 and laser:IsCircleLaser()
                and not (laser.Parent and laser.Parent:ToLaser())
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

local function getTarget(playerState, ballState, origin)
    local current = ballState.Target and ballState.Target.Ref
    if isTargetable(current) then
        return current
    end

    -- Each ball keeps its own target. Prefer enemies with fewer assigned balls,
    -- then the closest one, so a new group immediately spreads out to fight.
    local claims = {}
    local function countClaim(other)
        local target = other ~= ballState and other.Target and other.Target.Ref
        if isTargetable(target) then
            local hash = GetPtrHash(target)
            claims[hash] = (claims[hash] or 0) + 1
        end
    end
    countClaim(playerState)
    for _, ball in ipairs(playerState.Balls) do
        countClaim(ball)
    end
    local nearest
    local nearestDistance = math.huge
    local fewestClaims = math.huge
    for _, entity in ipairs(getRoomEntities()) do
        if isTargetable(entity) then
            local count = claims[GetPtrHash(entity)] or 0
            local distance = entity.Position:DistanceSquared(origin)
            if count < fewestClaims or (count == fewestClaims and distance < nearestDistance) then
                nearest = entity
                nearestDistance = distance
                fewestClaims = count
            end
        end
    end
    ballState.Target = nearest and EntityPtr(nearest) or nil
    return nearest
end

local function aimAt(weapon, target, slot, total, position)
    if not target then
        return Vector.Zero, 0
    end
    local origin = position or weapon.Position
    local goal = target.Position
    local laser = weapon:ToLaser()
    if laser and laser.Radius > 0 then
        local outward = origin - target.Position
        if outward:LengthSquared() < 0.001 then
            outward = Vector.FromAngle(slot * 137.507764)
        end
        goal = target.Position + outward:Resized(laser.Radius)
    elseif total > 1 then
        -- Keep balls visible when several attack the same enemy. The offset
        -- remains inside its hitbox rather than sending the balls into an orbit.
        local radius = math.min(target.Size * 0.5, weapon.Size * 0.8)
        goal = goal + Vector.FromAngle(slot * 137.507764) * radius
    end
    local delta = goal - origin
    local distance = delta:Length()
    if distance > ARRIVAL_DISTANCE then
        return delta:Resized(math.min(1, distance / AIM_SLOWDOWN_DISTANCE)), distance
    end
    return Vector.Zero, 0
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
    local target = getTarget(state, state, origin)
    if weapon then
        state.Aim = aimAt(weapon, target, 0, #state.Balls + 1)
    end
    return state.Aim
end

local function removeBalls(state)
    for _, ball in ipairs(state.Balls) do
        local entity = ball.Entity.Ref
        if entity and entity:Exists() then
            entity:Remove()
        end
    end
    state.Balls = {}
    state.Source = nil
    state.Target = nil
    state.AimFrame = -1
    state.MovementSpeed = nil
    state.LastShotSpeed = nil
end

local function resetTargets(state)
    state.Target = nil
    state.AimFrame = -1
    for _, ball in ipairs(state.Balls) do
        ball.Target = nil
    end
end

local function copyWeaponProperties(source, entity)
    entity.CollisionDamage = source.CollisionDamage
    entity.Color = source.Color
    entity.Size = source.Size
    entity.SizeMulti = source.SizeMulti
    entity.SpriteScale = source.SpriteScale
    entity.EntityCollisionClass = source.EntityCollisionClass
    entity.GridCollisionClass = source.GridCollisionClass
    local tear = entity:ToTear()
    if tear then
        local main = source:ToTear()
        if tear.Variant ~= main.Variant then
            tear:ChangeVariant(main.Variant)
        end
        -- BaseScale/BaseDamage are read-only. Copy the effective native stats
        -- after the engine updates the tear, including temporary tear effects.
        tear.TearFlags = main.TearFlags
        tear.Scale = main.Scale
        tear.Height = main.Height
        tear.FallingSpeed = main.FallingSpeed
        tear.FallingAcceleration = main.FallingAcceleration
        tear.CanTriggerStreakEnd = false
        tear:ResetSpriteScale()
        tear.SpriteScale = main.SpriteScale
    else
        local laser = entity:ToLaser()
        local main = source:ToLaser()
        laser.TearFlags = main.TearFlags
        laser.Radius = main.Radius
        laser.MaxDistance = main.MaxDistance
        laser.DisableFollowParent = true
        laser.ParentOffset = Vector.Zero
        laser.Shrink = false
        laser:SetTimeout(3)
        laser:SetOneHit(false)
    end
end

local function updateBall(player, state, ball)
    local entity = ball.Entity.Ref
    local source = state.Source and state.Source.Ref
    if not entity or not entity:Exists() or entity:IsDead() then
        return
    end
    if not source or not source:Exists() or source:IsDead()
        or not player:HasCollectible(LUDOVICO) or player:IsDead() then
        entity:Remove()
        return
    end
    copyWeaponProperties(source, entity)
    local frame = game:GetFrameCount()
    if ball.MoveFrame == frame then
        entity.Position = ball.Position
        entity.Velocity = ball.Velocity
        return
    end
    ball.MoveFrame = frame
    local velocity = Vector.Zero
    if not game:IsPaused() and player.ControlsEnabled then
        if state.Enabled then
            local target = getTarget(state, ball, ball.Position)
            local speed = state.MovementSpeed or math.max(1, player.ShotSpeed * 10)
            local aim, distance = aimAt(entity, target, ball.Slot, #state.Balls + 1, ball.Position)
            velocity = aim * speed
            if velocity:Length() > distance then
                velocity = velocity:Resized(distance)
            end
        else
            -- All balls share native manual steering while keeping their own
            -- positions. Only auto mode gives each ball a separate target.
            velocity = source.Velocity
        end
    end
    -- Unlinked native Ludovico tears still apply friction and tear effects.
    -- Keep a world-space position so native child movement cannot pull copies
    -- back into an orbit, and mirror-room input cannot flip their path twice.
    ball.Position = game:GetRoom():GetClampedPosition(ball.Position + velocity, 8)
    ball.Velocity = velocity
    entity.Position = ball.Position
    entity.Velocity = velocity
end

local function createBall(player, state, source, slot)
    local spread = Vector.FromAngle(slot * 137.507764) * math.max(24, source.Size * 2)
    local position = game:GetRoom():GetClampedPosition(source.Position + spread, 8)
    local subtype = source.SubType
    if source:ToTear() then
        -- Bit 0 selects native child positioning; independent copies must not
        -- inherit it. Preserve the remaining native Ludovico subtype bits.
        subtype = subtype & ~1
    end
    local entity = Isaac.Spawn(source.Type, source.Variant, subtype,
        position, Vector.Zero, player)
    entity.Parent = source
    local ball = {
        Entity = EntityPtr(entity),
        Owner = EntityPtr(player),
        Slot = slot,
        Position = position,
        Velocity = Vector.Zero,
        MoveFrame = game:GetFrameCount(),
    }
    entity:GetData()[BALL_DATA] = ball
    copyWeaponProperties(source, entity)
    return ball
end

local function updateSource(player, source)
    local state = getState(player)
    if not state.Source or not state.Source.Ref
        or GetPtrHash(state.Source.Ref) ~= GetPtrHash(source) then
        removeBalls(state)
        state.Source = EntityPtr(source)
    end
    local wanted = math.max(0, player:GetCollectibleNum(LUDOVICO, true) - 1)
    if source:ToTear() and state.LastShotSpeed ~= player.ShotSpeed then
        state.LastShotSpeed = player.ShotSpeed
        state.MovementSpeed = nil
    end
    for index = #state.Balls, wanted + 1, -1 do
        local entity = state.Balls[index].Entity.Ref
        if entity and entity:Exists() then
            entity:Remove()
        end
        table.remove(state.Balls, index)
    end
    for index = 1, wanted do
        local ball = state.Balls[index]
        local entity = ball and ball.Entity.Ref
        if not entity or not entity:Exists() or entity:IsDead()
            or entity.Type ~= source.Type
            or (source:ToLaser() and entity.Variant ~= source.Variant) then
            if entity and entity:Exists() then
                entity:Remove()
            end
            state.Balls[index] = createBall(player, state, source, index)
        end
    end
    -- Measure native movement so shot-speed changes and laser steering apply
    -- to the whole group. Divide out analog slowdown close to the main target.
    if state.Enabled then
        local aimLength = getAim(player, state):Length()
        if aimLength > 0.1 then
            local measured = source.Velocity:Length() / aimLength
            if measured > 0.1 and measured < 100 then
                state.MovementSpeed = measured
            end
        end
    end
    for _, ball in ipairs(state.Balls) do
        updateBall(player, state, ball)
    end
end

local function hideNativeSatellite(tear)
    -- The weapon maintains a native child count. Removing these every frame
    -- makes it fire replacement tears (and their shot sounds) continuously.
    -- Keep the linked children alive as invisible, harmless bookkeeping.
    tear:GetData()[SATELLITE_DATA] = true
    tear.Visible = false
    tear.CollisionDamage = 0
    tear.EntityCollisionClass = EntityCollisionClass.ENTCOLL_NONE
    tear.GridCollisionClass = EntityGridCollisionClass.GRIDCOLL_NONE
    tear.TearFlags = TearFlags.TEAR_LUDOVICO | TearFlags.TEAR_SPECTRAL | TearFlags.TEAR_PIERCING
end

function mod:OnWeaponUpdate(entity)
    local ball = entity:GetData()[BALL_DATA]
    if ball then
        -- EntityPtr.Ref exposes Entity, so player methods require ToPlayer().
        local owner = ball.Owner.Ref
        local player = owner and owner:Exists() and owner:ToPlayer()
        if player then
            updateBall(player, getState(player), ball)
        else
            entity:Remove()
        end
        return
    end
    local tear = entity:ToTear()
    if tear and tear:HasTearFlags(TearFlags.TEAR_LUDOVICO)
        and tear.Parent and tear.Parent:ToTear() then
        local parent = tear.Parent:ToTear()
        if parent:HasTearFlags(TearFlags.TEAR_LUDOVICO) then
            hideNativeSatellite(tear)
        end
        return
    end
    if tear and tear:HasTearFlags(TearFlags.TEAR_LUDOVICO) then
        -- Main-tear updates restore child flags and damage before the children
        -- update. Suppress their effects immediately, as well as afterward.
        local child = tear.Child
        local seen = {}
        while child and child:Exists() and not seen[GetPtrHash(child)] do
            seen[GetPtrHash(child)] = true
            local nextChild = child.Child
            local satellite = child:ToTear()
            if satellite and satellite:HasTearFlags(TearFlags.TEAR_LUDOVICO)
                and not satellite:GetData()[BALL_DATA] then
                hideNativeSatellite(satellite)
            end
            child = nextChild
        end
    end
end

mod:AddPriorityCallback(ModCallbacks.MC_POST_TEAR_UPDATE, CallbackPriority.LATE, mod.OnWeaponUpdate)
mod:AddPriorityCallback(ModCallbacks.MC_POST_LASER_UPDATE, CallbackPriority.LATE, mod.OnWeaponUpdate)

function mod:OnTearCollision(tear)
    if tear:GetData()[SATELLITE_DATA] then
        return true
    end
end

mod:AddPriorityCallback(ModCallbacks.MC_PRE_TEAR_COLLISION, CallbackPriority.LATE, mod.OnTearCollision)

function mod:OnUpdate()
    for index = 0, game:GetNumPlayers() - 1 do
        local player = Isaac.GetPlayer(index)
        local state = getState(player)
        local source = player:HasCollectible(LUDOVICO) and not player:IsDead()
            and getControlledWeapon(player)
        if source then
            updateSource(player, source)
        else
            removeBalls(state)
        end
    end
end

mod:AddPriorityCallback(ModCallbacks.MC_POST_UPDATE, CallbackPriority.LATE, mod.OnUpdate)

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
        removeBalls(state)
    elseif not game:IsPaused() and player.ControlsEnabled and not player:IsDead()
        and held and not state.ShootHeld then
        state.Enabled = not state.Enabled
        resetTargets(state)
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
        removeBalls(state)
    end
end

mod:AddCallback(ModCallbacks.MC_POST_NEW_ROOM, mod.OnNewRoom)

function mod:OnGameStarted()
    for _, state in pairs(playerStates) do
        removeBalls(state)
    end
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
