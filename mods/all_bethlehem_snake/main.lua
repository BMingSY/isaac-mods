local mod = RegisterMod("All Bethlehem + Snake", 1)
local game = Game()
local chain = include("scripts.chain")
local route = include("scripts.route")
local pace = include("scripts.pace")
local json = require("json")
local auraState = include("scripts.aura")
local STAR = CollectibleType.COLLECTIBLE_STAR_OF_BETHLEHEM -- 651: keep the real item.
local NATIVE_STAR = FamiliarVariant.STAR_OF_BETHLEHEM
local FOLLOWER = Isaac.GetEntityVariantByName("Bethlehem Snake Follower")
local LEGACY_AURA = Isaac.GetEntityVariantByName("Bethlehem Snake Aura")
local AURA = EffectVariant.HALLOWED_GROUND
if FOLLOWER <= 0 or AURA <= 0 then
    Isaac.DebugString("[Bethlehem Snake] Entity definitions were not loaded")
    return
end
local COLLECTIBLE = PickupVariant.PICKUP_COLLECTIBLE
local RADIUS = auraState.RADIUS
local FOLLOWER_DATA = "BethlehemSnakeFollower"
local AURA_DATA = "BethlehemSnakeAura"
local BUFF_DATA = "BethlehemSnakeBuff"
local STAT_FLAGS = CacheFlag.CACHE_DAMAGE | CacheFlag.CACHE_FIREDELAY | CacheFlag.CACHE_TEARFLAG
local states = {}
local restored = {}
local guideSamples = {}
local paceMap

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
    if itemId <= 0 or itemId == STAR or PROTECTED_ITEMS[itemId] then return false end
    local config = Isaac.GetItemConfig():GetCollectible(itemId)
    return not (config and config:HasTags(ItemConfig.TAG_QUEST))
end

function mod:OnGetCollectible(selected)
    if shouldReplace(selected) then return STAR end
end
mod:AddPriorityCallback(ModCallbacks.MC_POST_GET_COLLECTIBLE, CallbackPriority.LATE, mod.OnGetCollectible)

function mod:OnEntitySpawn(entityType, variant, subtype, position, velocity, spawner, seed)
    if entityType == EntityType.ENTITY_PICKUP and variant == COLLECTIBLE and shouldReplace(subtype) then
        return { entityType, variant, STAR, seed }
    end
end
mod:AddCallback(ModCallbacks.MC_PRE_ENTITY_SPAWN, mod.OnEntitySpawn)

function mod:OnPickupUpdate(pickup)
    if not shouldReplace(pickup.SubType) then return end
    local options = pickup.OptionsPickupIndex
    pickup:Morph(EntityType.ENTITY_PICKUP, COLLECTIBLE, STAR, true, true, true)
    pickup.OptionsPickupIndex = options
end
mod:AddCallback(ModCallbacks.MC_POST_PICKUP_UPDATE, mod.OnPickupUpdate, COLLECTIBLE)

local function valid(entity)
    return entity and entity:Exists() and not entity:IsDead()
end

local function players()
    local result, seen, slots = {}, {}, {}
    local function add(player, slot)
        if not valid(player) or seen[GetPtrHash(player)] then return end
        seen[GetPtrHash(player)] = true
        slots[GetPtrHash(player)] = slot
        result[#result + 1] = player
    end
    for i = 0, game:GetNumPlayers() - 1 do
        local player = Isaac.GetPlayer(i)
        add(player, tostring(i + 1))
        add(player:GetSubPlayer(), tostring(i + 1) .. ".sub")
    end
    return result, slots
end

local function context()
    local level, room = game:GetLevel(), game:GetRoom()
    local current = level:GetCurrentRoomDesc()
    local index = current.GridIndex
    -- Native Bethlehem maps Mega Satan's room above the floor's start room.
    if index == -7 and level:GetStage() == LevelStage.STAGE6 and not game:IsGreedMode() then
        index = level:GetStartingRoomIndex() - 13
    end
    local offset = route.offset(index)
    if level:GetCurrentRoomIndex() == -7 then offset.Y = offset.Y - 280 end
    local width = room:GetGridWidth()
    if width <= 7 or room:GetGridSize() / width <= 4 then
        offset.X, offset.Y = offset.X + 320, offset.Y + 160
    end
    local normal = level:GetRoomByIdx(level:GetCurrentRoomIndex(), 0)
    return { Offset = offset, Room = room, Stamp = current.ListIndex,
        Index = level:GetCurrentRoomIndex(),
        Main = normal.ListIndex == current.ListIndex }
end

local function removeAura(entity)
    if not valid(entity) then return end
    local data = entity:GetData()[FOLLOWER_DATA]
    if data and valid(data.Aura) then data.Aura:Remove() end
    if data then data.Aura = nil end
end

local function removeFollower(node)
    if valid(node.Entity) then
        removeAura(node.Entity)
        node.Entity.Visible = false
        node.Entity:Remove()
    end
    node.Entity, node.Aura = nil, nil
end

local function configureFollower(familiar, player, node)
    familiar.Player = player
    familiar.EntityCollisionClass = EntityCollisionClass.ENTCOLL_NONE
    familiar.GridCollisionClass = EntityGridCollisionClass.GRIDCOLL_NONE
    familiar.CollisionDamage = 0
    familiar:ClearEntityFlags(EntityFlag.FLAG_APPEAR)
    familiar:GetSprite():Play("Float", false)
    familiar:GetData()[FOLLOWER_DATA] = node
    node.Entity = familiar
    node.Seed = familiar.InitSeed
end

local function syncFollowers(state, player, existing)
    local bySeed, adopted = {}, {}
    for _, familiar in ipairs(existing) do bySeed[familiar.InitSeed] = familiar end
    for _, node in ipairs(state.Followers) do
        if not valid(node.Entity) then node.Entity = bySeed[node.Seed] end
        if valid(node.Entity) then
            configureFollower(node.Entity, player, node)
            adopted[GetPtrHash(node.Entity)] = true
        end
    end
    -- Migration from 0.2: assign an ID once, not from FindByType order each tick.
    table.sort(existing, function(a, b) return a.InitSeed < b.InitSeed end)
    for _, familiar in ipairs(existing) do
        if not adopted[GetPtrHash(familiar)] then
            local duplicate = false
            for _, node in ipairs(state.Followers) do
                if node.Seed == familiar.InitSeed then duplicate = true; break end
            end
            if duplicate then
                removeAura(familiar)
                familiar:Remove()
            else
                local node = { Index = state.NextIndex, Speed = 0 }
                state.NextIndex = state.NextIndex + 1
                state.Followers[#state.Followers + 1] = node
                configureFollower(familiar, player, node)
            end
        end
    end
    local wanted = math.max(0, state.Count - 1)
    while #state.Followers > wanted do
        local node = table.remove(state.Followers)
        removeFollower(node)
    end
    while #state.Followers < wanted do
        state.Followers[#state.Followers + 1] = { Index = state.NextIndex, Speed = 0 }
        state.NextIndex = state.NextIndex + 1
    end
    for _, node in ipairs(state.Followers) do
        if not node.World and state.Guide then
            -- New stars originate at the guide, even when it is in another room.
            node.World = route.copy(state.Guide.World)
        end
    end
end

local function updateAura(star)
    local data = star:GetData()[FOLLOWER_DATA]
    if not star.Visible then removeAura(star); return end
    if not valid(data.Aura) then
        -- Use the real effect variant and its initialization/rendering, not
        -- a generic effect which merely loads the same .anm2 file.
        local aura = game:Spawn(EntityType.ENTITY_EFFECT, AURA, star.Position,
            Vector.Zero, star, 0, math.max(1, star.InitSeed)):ToEffect()
        aura:GetData()[AURA_DATA] = true
        aura:FollowParent(star)
        aura.ParentOffset = Vector.Zero
        aura.SpriteOffset = Vector(0, -12)
        aura.DepthOffset = 10000
        data.Aura = aura
    end
    data.Aura.Position = star.Position
    data.Aura.Velocity = Vector.Zero
    data.Aura.Color = star.Color
end

local function observeGuide(state, ctx)
    if not valid(state.Head) then return end
    local sample = guideSamples[GetPtrHash(state.Head)]
    -- A room transition can leave the entity at the player's entrance position
    -- before native AI runs. Only consume a fresh observation from this room.
    if not sample or sample.Stamp ~= ctx.Stamp or sample.Frame ~= game:GetFrameCount() then return end
    state.Guide = route.observe(state.Guide, sample, ctx.Offset,
        game:GetFrameCount(), function(p)
            return ctx.Main and ctx.Room:IsPositionInRoom(Vector(p.X, p.Y), 20)
        end)
end

local function updateQueue(state, ctx)
    local guide = state.Guide
    if guide and not state.Trail then
        local top = route.toWorld(ctx.Room:GetTopLeftPos(), ctx.Offset)
        local bottom = route.toWorld(ctx.Room:GetBottomRightPos(), ctx.Offset)
        state.Trail = chain.new(guide.World, RADIUS,
            { Left = top.X + 24, Right = bottom.X - 24,
                Top = top.Y + 24, Bottom = bottom.Y - 24 },
            valid(state.Head) and state.Head.Velocity * -1 or Vector.Zero)
    end
    local speed = 0
    if guide and state.Trail then
        speed = math.min(8, route.distance(guide.World, state.Trail.Points[1]))
        chain.push(state.Trail, guide.World)
    end
    local targets = state.Trail and chain.targets(state.Trail, #state.Followers)
    for i, node in ipairs(state.Followers) do
        if node.World and targets then route.follow(node, targets[i + 1], speed) end
        local p = node.World and route.toRoom(node.World, ctx.Offset)
        local visible = p and ctx.Main and ctx.Room:IsPositionInRoom(Vector(p.X, p.Y), 0)
        if not visible then
            -- Do not keep an off-room familiar alive for the engine to relocate.
            -- World, Index, Speed and Seed belong to the queue, not this body.
            removeFollower(node)
        else
            if not valid(node.Entity) then
                local seed = node.Seed or math.max(1, state.Player:GetCollectibleRNG(STAR):Next())
                local familiar = game:Spawn(EntityType.ENTITY_FAMILIAR, FOLLOWER,
                    Vector(p.X, p.Y), Vector.Zero, state.Player, 0, seed):ToFamiliar()
                configureFollower(familiar, state.Player, node)
            end
            local familiar = node.Entity
            familiar.Position = Vector(p.X, p.Y)
            familiar.Velocity = Vector.Zero
            familiar.Visible = true
            updateAura(familiar)
        end
    end
end

local function updatePace(state, ctx)
    if not valid(state.Head) or not state.Guide then return end
    local tail = state.Followers[#state.Followers]
    if not tail and not state.PaceActive then return end
    -- The last numbered node owns the reference position even offscreen.
    -- Losing copies restores the head's own speed decision once, then leaves
    -- single-copy native AI alone. New copies become the reference immediately.
    local world = tail and tail.World or state.Guide.World
    if not world then return end
    paceMap = pace.map(game:GetLevel(), paceMap)
    local p = route.toRoom(world, ctx.Offset)
    local speed = pace.speed(world, paceMap, ctx.Index, ctx.Main,
        ctx.Room:IsPositionInRoom(Vector(p.X, p.Y), 0))
    state.Head.OrbitAngleOffset = speed
    -- Hidden-guide prediction must use the speed assigned for its next tick.
    state.Guide.Speed = speed
    state.PaceActive = tail ~= nil
end

local function buffState(player)
    local native = auraState.nativeActive(player, game:GetFrameCount())
    -- Every halo shares its owner's stack, including in local co-op. A
    -- visitor's own inventory must not change another player's halo strength.
    local count = 0
    for _, state in pairs(states) do
        if valid(state.Player) then
            local owned = state.Player:GetCollectibleNum(STAR, true)
            if owned > count then
                local inside = auraState.contains(player, state.Head)
                if not inside then
                    for _, node in ipairs(state.Followers) do
                        local follower = node.Entity
                        if valid(follower) and auraState.contains(player, follower) then
                            inside = true
                            break
                        end
                    end
                end
                if inside then count = owned end
            end
        end
    end
    -- Away from every star, only the native engine's short grace can remain.
    return math.max(count, native and 1 or 0), native
end

function mod:OnEvaluateCache(player, cacheFlag)
    if cacheFlag ~= CacheFlag.CACHE_DAMAGE and cacheFlag ~= CacheFlag.CACHE_FIREDELAY
        and cacheFlag ~= CacheFlag.CACHE_TEARFLAG then return end
    local count, native = buffState(player)
    if count <= 0 then return end
    -- The original head may already grant one native multiplier. Followers
    -- grant the entire stack too, without adding/removing engine item effects.
    local extraCopies = math.max(0, count - (native and 1 or 0))
    if cacheFlag == CacheFlag.CACHE_DAMAGE then
        player.Damage = chain.damage(player.Damage, extraCopies)
    elseif cacheFlag == CacheFlag.CACHE_FIREDELAY then
        player.MaxFireDelay = chain.fireDelay(player.MaxFireDelay, extraCopies)
    else
        player.TearFlags = player.TearFlags | TearFlags.TEAR_HOMING
    end
end
mod:AddPriorityCallback(ModCallbacks.MC_EVALUATE_CACHE, CallbackPriority.LATE, mod.OnEvaluateCache)

function mod:OnNativeStarUpdate(star)
    -- Snapshot directly after native AI computes its movement. POST_UPDATE
    -- may run after the engine has integrated Velocity into Position.
    guideSamples[GetPtrHash(star)] = { Stamp = game:GetLevel():GetCurrentRoomDesc().ListIndex,
        Frame = game:GetFrameCount(), Position = route.copy(star.Position),
        Velocity = route.copy(star.Velocity), Visible = star.Visible,
        Coins = star.Coins, Hearts = star.Hearts,
        OrbitAngleOffset = star.OrbitAngleOffset, OrbitSpeed = star.OrbitSpeed }
    for _, player in ipairs(players()) do
        auraState.observe(player, star, game:GetFrameCount())
    end
end
mod:AddCallback(ModCallbacks.MC_FAMILIAR_UPDATE, mod.OnNativeStarUpdate, NATIVE_STAR)

function mod:OnUpdate()
    local allPlayers, ownerSlots = players()
    local ctx = context()
    local nativeStars, savedFollowers, preferred = {}, {}, {}
    for _, player in ipairs(allPlayers) do
        local key = GetPtrHash(player)
        local slot = ownerSlots[key]
        local state = states[slot] or restored[slot]
        preferred[key] = state and state.HeadSeed
    end
    for _, entity in ipairs(Isaac.FindByType(EntityType.ENTITY_FAMILIAR, -1, -1, false, false)) do
        local familiar = entity:ToFamiliar()
        if familiar and valid(familiar.Player) then
            local key = GetPtrHash(familiar.Player)
            if familiar.Variant == NATIVE_STAR then
                local current = nativeStars[key]
                if not current or familiar.InitSeed == preferred[key]
                    or (current.InitSeed ~= preferred[key] and familiar.InitSeed < current.InitSeed) then
                    nativeStars[key] = familiar
                end
            elseif familiar.Variant == FOLLOWER then
                savedFollowers[key] = savedFollowers[key] or {}
                savedFollowers[key][#savedFollowers[key] + 1] = familiar
            end
        end
    end
    local present = {}
    for _, player in ipairs(allPlayers) do
        local key = GetPtrHash(player)
        local slot = ownerSlots[key]
        present[slot] = true
        local state = states[slot]
        if not state then
            state = restored[slot] or { Followers = {}, NextIndex = 2 }
            restored[slot] = nil
            states[slot] = state
        end
        state.Player, state.OwnerSlot = player, slot
        state.Count = player:GetCollectibleNum(STAR, true)
        state.Head = nativeStars[key]
        if valid(state.Head) then state.HeadSeed = state.Head.InitSeed end
        observeGuide(state, ctx)
        syncFollowers(state, player, savedFollowers[key] or {})
        updateQueue(state, ctx)
        updatePace(state, ctx)
        if state.Count == 0 then state.Guide, state.Trail = nil, nil end
    end
    for key, state in pairs(states) do
        if not present[key] then
            for _, node in ipairs(state.Followers) do
                removeFollower(node)
            end
            states[key] = nil
        end
    end
    guideSamples = {}
    for _, player in ipairs(allPlayers) do
        local count, native = buffState(player)
        local old = player:GetData()[BUFF_DATA]
        if not old or old.Count ~= count or old.Native ~= native then
            player:GetData()[BUFF_DATA] = { Count = count, Native = native }
            player:AddCacheFlags(STAT_FLAGS)
            player:EvaluateItems()
        end
    end
end
mod:AddCallback(ModCallbacks.MC_POST_UPDATE, mod.OnUpdate)

local SPECIAL_DAMAGE = DamageFlag.DAMAGE_FAKE | DamageFlag.DAMAGE_DEVIL
    | DamageFlag.DAMAGE_INVINCIBLE | DamageFlag.DAMAGE_IV_BAG
    | DamageFlag.DAMAGE_TIMER | DamageFlag.DAMAGE_PITFALL | DamageFlag.DAMAGE_RED_HEARTS

function mod:OnPlayerDamage(entity, amount, flags)
    local player = entity:ToPlayer()
    if not player or amount <= 0 or (flags & SPECIAL_DAMAGE) ~= 0 then return end
    local count, native = buffState(player)
    local rolls = count - (native and 1 or 0)
    if rolls > 0 and player:GetCollectibleRNG(STAR):RandomFloat() < 1 - 0.5 ^ rolls then
        return false
    end
end
mod:AddPriorityCallback(ModCallbacks.MC_ENTITY_TAKE_DMG, CallbackPriority.EARLY,
    mod.OnPlayerDamage, EntityType.ENTITY_PLAYER)

function mod:OnAuraUpdate(aura)
    if aura:GetData()[AURA_DATA] and (not valid(aura.Parent) or not aura.Parent.Visible) then
        aura:Remove()
    end
end
mod:AddCallback(ModCallbacks.MC_POST_EFFECT_UPDATE, mod.OnAuraUpdate, AURA)

local function clearAuraVisuals()
    for _, aura in ipairs(Isaac.FindByType(EntityType.ENTITY_EFFECT, -1, -1, false, false)) do
        if aura.Variant == LEGACY_AURA or aura:GetData()[AURA_DATA]
            or (aura.Variant == AURA and valid(aura.Parent) and aura.Parent.Variant == FOLLOWER) then
            aura:Remove()
        end
    end
end

function mod:OnNewRoom()
    clearAuraVisuals()
    guideSamples = {}
    paceMap = nil
    -- The engine carries/relocates familiar bodies on entry. Remove those
    -- bodies before rendering; recreate only the queue members whose saved
    -- floor positions are actually inside this room. Never reset their model.
    for _, state in pairs(states) do
        for _, node in ipairs(state.Followers) do removeFollower(node) end
    end
    -- Also cover engine-restored bodies without a live Lua reference yet.
    for _, familiar in ipairs(Isaac.FindByType(EntityType.ENTITY_FAMILIAR, FOLLOWER, -1, false, false)) do
        familiar.Visible = false
        familiar:Remove()
    end
end
mod:AddCallback(ModCallbacks.MC_POST_NEW_ROOM, mod.OnNewRoom)

function mod:OnNewLevel()
    paceMap = nil
    for _, state in pairs(states) do
        state.Guide, state.Trail = nil, nil
        for _, node in ipairs(state.Followers) do
            node.World, node.Speed = nil, 0
            removeFollower(node)
        end
    end
end
mod:AddCallback(ModCallbacks.MC_POST_NEW_LEVEL, mod.OnNewLevel)

function mod:OnGameStarted(continued)
    clearAuraVisuals()
    states, restored, guideSamples = {}, {}, {}
    paceMap = nil
    auraState.reset()
    if continued and mod:HasData() then
        local ok, saved = pcall(json.decode, mod:LoadData())
        if ok and type(saved) == "table" and (saved.Version == 3 or saved.Version == 4)
            and saved.Seed == game:GetSeeds():GetStartSeed() then
            if saved.Version == 3 then
                local allPlayers, ownerSlots = players()
                for ordinal, player in ipairs(allPlayers) do
                    restored[ownerSlots[GetPtrHash(player)]] = (saved.Players or {})[tostring(ordinal)]
                end
            else
                restored = saved.Players or {}
            end
        end
    end
end
mod:AddCallback(ModCallbacks.MC_POST_GAME_STARTED, mod.OnGameStarted)

function mod:OnExit(shouldSave)
    if not shouldSave then return end
    local saved = { Version = 4, Seed = game:GetSeeds():GetStartSeed(), Players = {} }
    for _, state in pairs(states) do
        local queue = { NextIndex = state.NextIndex, Trail = state.Trail,
            Guide = state.Guide, HeadSeed = state.HeadSeed,
            PaceActive = state.PaceActive, Followers = {} }
        for _, node in ipairs(state.Followers) do
            queue.Followers[#queue.Followers + 1] = { Index = node.Index,
                Seed = node.Seed, World = node.World, Speed = node.Speed }
        end
        saved.Players[state.OwnerSlot] = queue
    end
    mod:SaveData(json.encode(saved))
end
mod:AddCallback(ModCallbacks.MC_PRE_GAME_EXIT, mod.OnExit)
