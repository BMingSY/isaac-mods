-- Offline regression harness. It models the vanilla aura independently of
-- the mod: native contact grants one multiplier, with a 2..4 tick countdown.
-- Run: lua tests/bethlehem_regression.lua [snake mod directory] [stacking mod directory]
-- The unpublished stacking edition is checked only when explicitly provided.
local root = arg[1] or "mods/all_bethlehem_snake"
local checks = 0
local function check(condition, message)
    assert(condition, message)
    checks = checks + 1
end
local function near(actual, expected, message)
    check(math.abs(actual - expected) < 1e-8,
        string.format("%s: expected %.10f, got %.10f", message, expected, actual))
end

local vector = {}
vector.__index = vector
function vector:DistanceSquared(other)
    return (self.X - other.X)^2 + (self.Y - other.Y)^2
end
function vector:Distance(other) return math.sqrt(self:DistanceSquared(other)) end
function vector.__mul(v, n) return Vector(v.X * n, v.Y * n) end
Vector = setmetatable({}, { __call = function(_, x, y)
    return setmetatable({ X = x, Y = y }, vector)
end })
Vector.Zero = Vector(0, 0)

CollectibleType = { COLLECTIBLE_STAR_OF_BETHLEHEM = 651 }
local protected = { "POLAROID", "NEGATIVE", "KEY_PIECE_1", "KEY_PIECE_2",
    "KNIFE_PIECE_1", "KNIFE_PIECE_2", "BROKEN_SHOVEL_1", "BROKEN_SHOVEL_2",
    "MOMS_SHOVEL", "DADS_NOTE", "DOGMA" }
for i, name in ipairs(protected) do CollectibleType["COLLECTIBLE_" .. name] = 100 + i end
FamiliarVariant = { STAR_OF_BETHLEHEM = 236 }
EffectVariant = { HALLOWED_GROUND = 112 }
LevelStage = { STAGE6 = 11 }
PickupVariant = { PICKUP_COLLECTIBLE = 100 }
EntityType = { ENTITY_PLAYER = 1, ENTITY_FAMILIAR = 3, ENTITY_PICKUP = 5, ENTITY_EFFECT = 1000 }
EntityCollisionClass = { ENTCOLL_NONE = 0 }
EntityGridCollisionClass = { GRIDCOLL_NONE = 0 }
EntityFlag = { FLAG_APPEAR = 4, FLAG_RENDER_FLOOR = 8 }
TearFlags = { TEAR_HOMING = 4 }
CacheFlag = { CACHE_DAMAGE = 1, CACHE_FIREDELAY = 2, CACHE_TEARFLAG = 4 }
CallbackPriority = { EARLY = -100, LATE = 100 }
ModCallbacks = setmetatable({}, { __index = function(_, key) return key end })
DamageFlag = {}
for i, name in ipairs({ "FAKE", "DEVIL", "INVINCIBLE", "IV_BAG", "TIMER",
    "PITFALL", "RED_HEARTS" }) do DamageFlag["DAMAGE_" .. name] = 1 << i end
ItemConfig = { TAG_QUEST = 1 }

local clock, entities, allPlayers, currentMod = 0, {}, {}, nil
local roomIndex, dimension = 1, 0
local floorCells, floorBoss, floorSize = {}, -1, 0
-- SaveData boundary: serialize into a string and decode into fresh tables.
local function encode(value)
    if type(value) ~= "table" then return string.format("%q", value) end
    local result = {}
    for key, item in pairs(value) do result[#result + 1] = "[" .. encode(key) .. "]=" .. encode(item) end
    return "{" .. table.concat(result, ",") .. "}"
end
package.preload.json = function()
    return { encode = encode, decode = function(s) return assert(load("return " .. s, "save", "t", {}))() end }
end
local nextID, eidChanges, followerSpawns = 0, 0, 0
local entity = {}
entity.__index = entity
function entity:Exists() return not self.removed end
function entity:IsDead() return false end
function entity:GetData() return self.data end
function entity:Remove() self.removed = true end
function entity:ToFamiliar() return self.Type == 3 and self or nil end
function entity:ToEffect() return self.Type == 1000 and self or nil end
function entity:ToPlayer() return self.Type == 1 and self or nil end
function entity:ClearEntityFlags() end
function entity:AddEntityFlags() end
function entity:FollowParent(parent) self.Parent = parent end
function entity:GetSprite() return { Play = function() end } end
local function newEntity(kind, variant, pos, player)
    nextID = nextID + 1
    local e = setmetatable({ Type = kind, Variant = variant, Position = pos,
        Velocity = Vector.Zero, InitSeed = nextID, id = nextID, data = {},
        Visible = true, Player = player, SpriteScale = Vector(1, 1), Color = {},
        Coins = roomIndex, Hearts = 0x80008000, OrbitAngleOffset = 1, OrbitSpeed = 0 }, entity)
    entities[#entities + 1] = e
    return e
end
function GetPtrHash(e) return e.id end
local rngSeed = 100
local rng = { Next = function() rngSeed = rngSeed + 1; return rngSeed end,
    RandomFloat = function() return 0.6 end }
local game = {}
function Game() return game end
function game:GetNumPlayers() return #allPlayers end
function game:GetFrameCount() return clock end
function game:GetSeeds() return { GetStartSeed = function() return 1234 end } end
function game:IsGreedMode() return false end
function game:GetLevel()
    return { GetCurrentRoomIndex = function() return roomIndex end,
        GetStage = function() return 1 end,
        GetLastBossRoomListIndex = function() return floorBoss end,
        GetRooms = function() return { Size = floorSize, Get = function(_, index)
            for cell, listIndex in pairs(floorCells) do
                if listIndex == index then return { Data = {}, SafeGridIndex = cell } end
            end
        end } end,
        GetCurrentRoomDesc = function() return { ListIndex = roomIndex + 1000 * dimension, GridIndex = roomIndex } end,
        GetRoomByIdx = function(_, id, dim) return { ListIndex = floorCells[id] or id + 1000 * dim,
            Data = floorCells[id] ~= nil and {} or nil } end }
end
function game:GetRoom()
    return { GetTopLeftPos = function() return Vector(0, 0) end,
        GetBottomRightPos = function() return Vector(640, 480) end,
        GetGridWidth = function() return 15 end,
        GetGridSize = function() return 135 end,
        IsPositionInRoom = function(_, p, margin)
            return p.X >= margin and p.X <= 640 - margin and p.Y >= margin and p.Y <= 480 - margin
        end }
end
function game:Spawn(kind, variant, position, velocity, spawner, subtype, seed)
    if kind == 3 and variant == 1001 then followerSpawns = followerSpawns + 1 end
    local e = newEntity(kind, variant, Vector(position.X, position.Y), spawner)
    e.InitSeed = seed or e.InitSeed
    return e
end
Isaac = {}
function Isaac.GetPlayer(index) return allPlayers[index + 1] end
function Isaac.GetEntityVariantByName(name) return name:find("Follower") and 1001 or 1002 end
function Isaac.FindByType(kind, variant)
    local found = {}
    for _, e in ipairs(entities) do
        if e:Exists() and e.Type == kind and (variant == -1 or e.Variant == variant) then
            found[#found + 1] = e
        end
    end
    return found
end
function Isaac.GetItemConfig()
    return { GetCollectible = function(_, id)
        return { HasTags = function() return id == 900 end }
    end }
end
function Isaac.DebugString(message) error(message) end
EID = { addCollectible = function() eidChanges = eidChanges + 1 end }
function include(name) return dofile(root .. "/" .. name:gsub("%.", "/") .. ".lua") end
function RegisterMod()
    local mod = {}
    function mod:AddCallback() end
    function mod:AddPriorityCallback() end
    function mod:HasData() return self.saved ~= nil end
    function mod:LoadData() return self.saved end
    function mod:SaveData(data) self.saved = data end
    currentMod = mod
    return mod
end
local function newPlayer(x, y)
    local p = newEntity(1, 0, Vector(x, y))
    p.Count, p.Size, p.NativeTicks, p.Recalculations = 0, 10, 0, 0
    p.BaseDamage, p.BaseDelay = 3.5, 10
    function p:GetCollectibleNum() return self.Count end
    function p:GetCollectibleRNG() return rng end
    function p:GetSubPlayer() return nil end
    function p:GetEffects()
        return { HasCollectibleEffect = function() return false end }
    end
    function p:AddCacheFlags() end
    function p:EvaluateItems()
        self.Recalculations = self.Recalculations + 1
        self.Damage, self.MaxFireDelay, self.TearFlags = self.BaseDamage, self.BaseDelay, 0
        if self.NativeTicks > 0 then
            self.Damage = self.Damage * 1.2
            self.MaxFireDelay = (self.MaxFireDelay + 1) / 2.5 - 1
            self.TearFlags = TearFlags.TEAR_HOMING
        end
        for _, flag in ipairs({ CacheFlag.CACHE_DAMAGE, CacheFlag.CACHE_FIREDELAY,
            CacheFlag.CACHE_TEARFLAG }) do currentMod:OnEvaluateCache(self, flag) end
    end
    allPlayers[#allPlayers + 1] = p
    return p
end
local function tick()
    clock = clock + 1
    for _, p in ipairs(allPlayers) do
        local wasActive = p.NativeTicks > 0
        p.NativeTicks = math.max(0, p.NativeTicks - 1)
        if wasActive and p.NativeTicks == 0 then p:EvaluateItems() end
    end
    for _, star in ipairs(Isaac.FindByType(3, 236)) do
        for _, p in ipairs(allPlayers) do
            if star.Visible and p.Position:DistanceSquared(star.Position) < (70 + p.Size)^2 then
                local wasActive = p.NativeTicks > 0
                p.NativeTicks = math.min(4, p.NativeTicks + 2)
                if not wasActive then p:EvaluateItems() end
            end
        end
        if currentMod.OnNativeStarUpdate then currentMod:OnNativeStarUpdate(star) end
    end
    if currentMod.OnUpdate then currentMod:OnUpdate() end
    if currentMod.OnPlayerUpdate then
        for _, p in ipairs(allPlayers) do currentMod:OnPlayerUpdate(p) end
    end
end
local function advance(n) for _ = 1, n or 1 do tick() end end
local function expectStats(p, copies, label)
    near(p.Damage, p.BaseDamage * 1.2^copies, label .. " damage")
    near(30 / (p.MaxFireDelay + 1), math.min(120, 30 / (p.BaseDelay + 1) * 2.5^copies),
        label .. " tears")
    check((p.TearFlags & TearFlags.TEAR_HOMING ~= 0) == (copies > 0), label .. " homing")
end

dofile(root .. "/main.lua")
local mod = currentMod
local p = newPlayer(300, 200)
mod:OnGameStarted()
p.Count = 1
local head = newEntity(3, 236, Vector(300, 200), p)
advance(8)
expectStats(p, 1, "one Star must be 6.82 TPS, not 17.05")
check(eidChanges == 0, "vanilla item name and EID description must remain intact")
local evaluations = p.Recalculations
advance(8)
check(p.Recalculations == evaluations, "stationary aura must not reevaluate stats every frame")
for _ = 1, 10 do p:EvaluateItems() end
expectStats(p, 1, "repeated cache evaluation must not compound")

p.Count = 2
advance(80)
expectStats(p, 2, "two Stars at guide")
local tails = Isaac.FindByType(3, 1001)
check(#tails == 1, "two items need one tail")
check(#Isaac.FindByType(1000, 112) == 1, "one native effect per tail; no duplicate guide halo")
p.Position = Vector(tails[1].Position.X + 40, tails[1].Position.Y)
for i = 1, 6 do
    tick()
    expectStats(p, 2, "guide to tail, native grace tick " .. i)
end
check(p.NativeTicks == 0, "tail-only test must be outside the native guide")
check(mod:OnPlayerDamage(p, 1, 0) == false, "tail must supply the full 75% block chance")
check(mod:OnPlayerDamage(p, 1, DamageFlag.DAMAGE_DEVIL) == nil, "scripted payments stay unchanged")

p.Count = 3
advance(80)
expectStats(p, 3, "new pickup updates tail immediately")
tails = Isaac.FindByType(3, 1001)
check(#tails == 2, "three items need two tails")
for _, star in ipairs({ head, tails[1], tails[2] }) do
    p.Position = star.Position
    advance(6)
    expectStats(p, 3, "all three aura centers and overlaps have equal bonuses")
end
check(#Isaac.FindByType(1000, 112) == 2, "each tail retains its halo")
p.Position = Vector(20, 440)
advance(6)
expectStats(p, 0, "leave every aura")

mod:OnNewRoom()
advance(80)
check(#Isaac.FindByType(3, 1001) == 2, "room change does not duplicate tails")
check(#Isaac.FindByType(1000, 112) == 2, "room change recreates both halos")
mod:OnExit(true)
for _, e in ipairs(entities) do e.data = {} end
mod:OnGameStarted(true)
advance(80)
check(#Isaac.FindByType(3, 1001) == 2, "Continue adopts restored tails")
check(#Isaac.FindByType(1000, 112) == 2, "Continue does not leave orphaned halos")
p.Count, p.Position = 1, head.Position
advance(6)
expectStats(p, 1, "remove duplicate items")
check(#Isaac.FindByType(3, 1001) == 0, "remove surplus tails")
check(#Isaac.FindByType(1000, 112) == 0, "remove surplus halos")

-- Hidden native stars retain stale room-local coordinates. They must not
-- grant bonuses or cause the queue to reset to the player in a different room.
p.Count = 3
advance(120)
tails = Isaac.FindByType(3, 1001)
local nodes, before = {}, {}
for i, tail in ipairs(tails) do
    nodes[i] = tail:GetData().BethlehemSnakeFollower
    before[i] = { X = nodes[i].World.X, Y = nodes[i].World.Y, Index = nodes[i].Index }
end
-- Engine transition: a native callback from the old room can still be
-- pending; familiar bodies are relocated/recreated around the entering player.
clock = clock + 1
mod:OnNativeStarUpdate(head)
head.Visible, roomIndex = false, 100
head.Coins, head.OrbitAngleOffset = 2, 1
p.Position = Vector(300, 200)
for _, tail in ipairs(tails) do tail.Position, tail.Visible = p.Position, true end
mod:OnNewRoom()
check(#Isaac.FindByType(3, 1001) == 0,
    "room entry must remove engine-relocated tail bodies before they can render")
local spawnCount = followerSpawns
local savedGuideBefore = { X = 0, Y = 0 }
mod:OnExit(true)
local snapshot = package.loaded.json.decode(mod.saved)
savedGuideBefore = snapshot.Players["1"].Guide.World
mod:OnUpdate() -- before any native callback from the new room
mod:OnExit(true)
snapshot = package.loaded.json.decode(mod.saved)
near(snapshot.Players["1"].Guide.World.X, savedGuideBefore.X, "old-room sample cannot re-anchor guide X")
near(snapshot.Players["1"].Guide.World.Y, savedGuideBefore.Y, "old-room sample cannot re-anchor guide Y")
-- A different userdata pointer for the same player slot must retain its queue.
p.id = p.id + 100000
advance(8)
check(followerSpawns == spawnCount, "unrelated room must not spawn off-room familiar proxies")
check(#Isaac.FindByType(3, 1001) == 0, "unrelated room has no tail bodies to pull toward player")
expectStats(p, 0, "hidden native star's stale position grants no buff")
for i, tail in ipairs(tails) do
    local node = tail:GetData().BethlehemSnakeFollower
    check(node.Index == before[i].Index, "room change preserves sequence ID")
    check(not tail.Visible, "tail stays with guide's route, not player room")
    check(math.sqrt((node.World.X-before[i].X)^2+(node.World.Y-before[i].Y)^2) <= 24.001,
        "room change does not teleport logical queue positions")
end
check(#Isaac.FindByType(1000, 112) == 0, "off-room followers leave no ghost halos")
p.Count = 4
tick()
check(followerSpawns == spawnCount, "pickup while away joins logical queue without spawning at player")
p.Count = 3
tick()
-- Returning to the original room projects the same saved floor positions.
roomIndex, head.Visible = 1, true
mod:OnNewRoom()
advance(120)
tails = Isaac.FindByType(3, 1001)
check(#tails == 2, "returning restores only proxies for the existing two queue slots")
for i, tail in ipairs(tails) do
    check(tail.Visible, "returning reveals the existing queue")
    check(tail:GetData().BethlehemSnakeFollower.Index == before[i].Index, "return preserves original queue IDs")
end
-- Dimension changes cannot bring normal-floor stars into the mirror/mineshaft.
dimension = 1
mod:OnNewRoom()
tick()
for _, tail in ipairs(tails) do check(not tail.Visible, "queue hidden in another dimension") end
dimension = 0
mod:OnNewRoom()
advance(120)
tails = Isaac.FindByType(3, 1001)
-- Stable IDs survive shuffled FindByType order and serialized Continue.
local duplicate = newEntity(3, 1001, tails[1].Position, p)
duplicate.InitSeed = tails[1].InitSeed
tick()
check(not duplicate:Exists(), "engine-restored duplicate body cannot create a new queue slot")
local ids = {}
for _, tail in ipairs(tails) do ids[tail.InitSeed] = tail:GetData().BethlehemSnakeFollower.Index end
mod:OnExit(true)
for _, e in ipairs(entities) do e.data = {} end
mod:OnGameStarted(true)
local reversed = {}
for i = #entities, 1, -1 do reversed[#reversed + 1] = entities[i] end
entities = reversed
tick()
for _, tail in ipairs(tails) do
    check(tail:GetData().BethlehemSnakeFollower.Index == ids[tail.InitSeed], "Continue preserves numbered order")
end
-- Follow a moving native guide, turn, stop, and pick up a new tail. No frame
-- may jump directly to the final queue slot, including already joined tails.
for frame = 1, 220 do
    local old = {}
    for _, tail in ipairs(Isaac.FindByType(3, 1001)) do
        local world = tail:GetData().BethlehemSnakeFollower.World
        old[tail.InitSeed] = { X = world.X, Y = world.Y }
    end
    if frame < 70 then head.Position = Vector(head.Position.X + 1, head.Position.Y)
    elseif frame < 140 then head.Position = Vector(head.Position.X, head.Position.Y + 1) end
    if frame == 90 then p.Count = 4 end
    tick()
    for _, tail in ipairs(Isaac.FindByType(3, 1001)) do
        local world, previous = tail:GetData().BethlehemSnakeFollower.World, old[tail.InitSeed]
        if previous then
            check(math.sqrt((world.X-previous.X)^2+(world.Y-previous.Y)^2) <= 3.00001,
                "joining/turning/stopping speed bounded to three units per tick")
        end
    end
end
-- Restore a separated single-copy guide for the co-op stat tests below.
p.Count, head.Position, head.Coins = 1, Vector(300, 200), 1
advance(8)
p.Position = head.Position
advance(8)

local second = newPlayer(500, 400)
second.Count = 2
newEntity(3, 236, Vector(500, 400), second)
advance(80)
expectStats(p, 1, "separate player retains one-copy strength")
expectStats(second, 2, "second player has its own two-copy strength")
second.Position = head.Position
advance(6)
-- Native engine effects apply to both players. A shared aura's stack strength
-- must come from its owner, not the inventory of the visiting player.
expectStats(second, 1, "visitor uses the guide owner's stack")

for _, id in pairs(CollectibleType) do
    check(mod:OnGetCollectible(id) == nil, "preserve Star and protected route item " .. id)
end
check(mod:OnGetCollectible(900) == nil, "preserve quest-tagged mod item")
check(mod:OnGetCollectible(1) == 651, "replace ordinary item")
local chain = include("scripts.chain")
near(chain.fireDelay(10, 10000), -0.75, "extreme stacks cap at 120 TPS")
near(chain.fireDelay(-0.9, 10), -0.9, "preserve an existing rate above cap")
check(chain.damage(3.5, 10000) <= 1e30, "damage remains finite")

-- Independently known floor positions, including the guide moving while the
-- player is in an unrelated room. No stale Entity.Position may be used there.
local route = include("scripts.route")
local guide = { Position = Vector(320, 280), Velocity = Vector.Zero, Visible = true,
    Coins = 2, Hearts = 0x80008000, OrbitSpeed = 0, OrbitAngleOffset = 1 }
local model = route.observe(nil, guide, route.offset(1), 0, function() return true end)
near(model.World.X, 520, "native room-center floor X")
near(model.World.Y, 0, "native room-center floor Y")
guide.Visible = false
for frame = 1, 520 do
    model = route.observe(model, guide, route.offset(100), frame, function() return true end)
end
near(model.World.X, 1040, "hidden guide reaches next room center")
near(model.World.Y, 0, "unrelated player room cannot alter native path")
guide.Coins = 15
for frame = 521, 800 do
    model = route.observe(model, guide, route.offset(100), frame, function() return true end)
end
near(model.World.X, 1040, "hidden guide turns at its native waypoint")
near(model.World.Y, 280, "hidden guide reaches vertical next room")
for frame = 801, 900 do
    model = route.observe(model, guide, route.offset(100), frame, function() return true end)
end
near(model.World.Y, 280, "guide stops at final native waypoint offscreen")
guide.Hearts = 0xc000c000
local destination = route.destination(guide)
near(destination.X, 1170, "packed native destination X quarter-room offset")
near(destination.Y, 350, "packed native destination Y quarter-room offset")
check(route.observe(nil, guide, route.offset(100), 901, function() return true end) == nil,
    "old save with unknown hidden guide must wait, not adopt player room")

-- Reject a relocated-but-visible native body after a room transition. Its
-- room-local position cannot pull the authoritative floor route to that room.
guide.Visible, guide.Hearts = true, 0x80008000
local expectedX, expectedY = model.World.X, model.World.Y
model = route.observe(model, guide, route.offset(100), 901, function() return true end)
near(model.World.X, expectedX, "relocated visible native body cannot warp guide X")
near(model.World.Y, expectedY, "relocated visible native body cannot warp guide Y")

-- Upgrade the previous save schema while preserving its logical IDs/positions.
mod:OnExit(true)
local legacy = package.loaded.json.decode(mod.saved)
legacy.Version = 3
mod.saved = package.loaded.json.encode(legacy)
for _, tail in ipairs(Isaac.FindByType(3, 1001)) do tail:Remove() end
mod:OnGameStarted(true)
tick()
mod:OnExit(true)
local upgraded = package.loaded.json.decode(mod.saved)
check(upgraded.Version == 4, "0.3 Continue upgrades to the stable-owner save schema")
for slot, state in pairs(legacy.Players) do
    local recovered = upgraded.Players[slot]
    check(recovered.NextIndex == state.NextIndex, "upgrade retains sequence allocator")
    for i, node in ipairs(state.Followers) do
        local restoredNode = recovered.Followers[i]
        check(restoredNode.Index == node.Index, "upgrade retains queue ID")
        check(route.distance(restoredNode.World, node.World) <= 3.00001,
            "upgrade continues existing path instead of resetting to the entering room")
    end
end

-- Tail-based pace: route distance, not straight-line distance or head position.
local pace = include("scripts.pace")
local function worldAt(index)
    return { X = index % 13 * 520, Y = math.floor(index / 13) * 280 }
end
local cells = {}
for index = 0, 8 do cells[index] = index end
local map = { Cells = cells, Costs = pace.costs(cells, 8) }
near(pace.speed(worldAt(1), map, 4, true, false), 4, "tail behind player speeds up")
near(pace.speed(worldAt(0), map, 4, true, false), 8, "distant tail uses fast catch-up tier")
near(pace.speed(worldAt(4), map, 4, true, false), 1, "tail in player's room uses normal tier")
near(pace.speed(worldAt(5), map, 4, true, false), 0.5, "tail ahead slows down")
near(pace.speed(worldAt(8), map, 4, true, false), 0.25, "tail far ahead slows further")
near(pace.speed(worldAt(0), map, 4, false, false), 0.25, "other dimension preserves native slow tier")
near(pace.speed(worldAt(0), map, -1, true, false), 1, "off-map player keeps normal pace")
near(pace.speed(worldAt(100), map, 4, true, false), 1, "disconnected positions keep moving")
near(pace.speed({ X = -1000, Y = 0 }, map, 4, true, false), 1, "off-map tail keeps moving")
local bend = { [0] = 0, [1] = 1, [2] = 2, [15] = 15, [28] = 28, [27] = 27, [26] = 26 }
local bentMap = { Cells = bend, Costs = pace.costs(bend, 26) }
near(pace.speed(worldAt(0), bentMap, 28, true, false), 8,
    "U-shaped path must not confuse geometrically near with ahead along route")
local large = { [0] = 10, [1] = 10, [2] = 12 }
local largeMap = { Cells = large, Costs = pace.costs(large, 2) }
near(largeMap.Costs[0], 4, "large-room cells cost one, room crossings cost three")
near(pace.speed(worldAt(0), largeMap, 1, true, false), 1, "same large room stays at normal pace")
check(pace.costs({ [12] = 1, [13] = 2 }, 13)[12] == nil, "map rows cannot wrap into false neighbors")

-- At native 4/8 speed, followers must close the gap without jumping.
for _, speed in ipairs({ 4, 8 }) do
    local node, target = { World = { X = 0, Y = 0 }, Speed = 0 }, { X = 200, Y = 0 }
    local maxStep = 0
    for _ = 1, 500 do
        local beforeStep = route.copy(node.World)
        target.X = target.X + speed
        route.follow(node, target, speed)
        maxStep = math.max(maxStep, route.distance(beforeStep, node.World))
    end
    check(route.distance(node.World, target) < 0.01, "followers catch a guide traveling at speed " .. speed)
    check(maxStep <= speed + 2.00001, "fast followers still have a bounded per-tick step")
    local stationary = route.copy(target)
    for _ = 1, 100 do route.follow(node, stationary, 0) end
    near(route.distance(node.World, stationary), 0, "stopping cannot overshoot the target")
end

-- Exercise the actual callback and Continue wiring with a known floor layout.
-- All positions are deliberately separated across rooms, so using the last
-- rendered entity, stale room coordinates or the guide would give wrong tiers.
floorCells, floorBoss, floorSize = cells, 8, 9
local function paceFixture(headCell, tailCells, playerCell)
    entities, allPlayers, dimension = {}, {}, 0
    roomIndex = playerCell
    local owner = newPlayer(320, 280)
    owner.Count = #tailCells + 1
    local leader = newEntity(3, 236, Vector(320, 280), owner)
    leader.Visible, leader.Coins, leader.OrbitAngleOffset = false, headCell, 0.5
    local queue = { NextIndex = #tailCells + 2, HeadSeed = leader.InitSeed,
        Guide = { World = worldAt(headCell), Speed = 0.5, Phase = 0, Frame = clock },
        Followers = {} }
    for i, cell in ipairs(tailCells) do
        queue.Followers[i] = { Index = i + 1, Seed = 1000 + i, World = worldAt(cell), Speed = 0 }
    end
    mod.saved = encode({ Version = 4, Seed = 1234, Players = { ["1"] = queue } })
    mod:OnGameStarted(true)
    mod:OnUpdate()
    return owner, leader
end
local owner, leader = paceFixture(6, { 4, 1 }, 4)
near(leader.OrbitAngleOffset, 4, "last hidden star controls pace despite head ahead and middle visible")
check(#Isaac.FindByType(3, 1001) == 1, "pace does not spawn the off-room tail")
mod:OnExit(true)
local paceSave = package.loaded.json.decode(mod.saved)
near(paceSave.Players["1"].Guide.Speed, 4, "hidden guide prediction uses assigned speed")
check(paceSave.Players["1"].PaceActive, "Continue records active pace override")
owner.Count = 4
mod:OnUpdate()
near(leader.OrbitAngleOffset, 0.5, "new last star becomes the pace reference at its true position")
owner.Count = 3
mod:OnUpdate()
near(leader.OrbitAngleOffset, 4, "removing last copy returns reference to previous tail")
mod:OnExit(true)
owner.Count = 1
mod:OnGameStarted(true)
mod:OnUpdate()
near(leader.OrbitAngleOffset, 0.5, "single-copy Continue releases tail override to head's own tier")
leader.OrbitAngleOffset = 8
mod:OnUpdate()
near(leader.OrbitAngleOffset, 8, "single-copy native speed remains untouched afterwards")

owner, leader = paceFixture(6, { 5, 4 }, 4)
near(leader.OrbitAngleOffset, 1, "head ahead cannot slow queue while last star is with player")
owner, leader = paceFixture(8, { 7, 5 }, 4)
near(leader.OrbitAngleOffset, 0.5, "queue slows only after tail moves ahead")
owner, leader = paceFixture(2, { 1, 0 }, 4)
near(leader.OrbitAngleOffset, 8, "off-room far-behind tail enables fast pace")
leader.Coins = 3
tick()
mod:OnExit(true)
paceSave = package.loaded.json.decode(mod.saved)
near(paceSave.Players["1"].Guide.World.X, worldAt(2).X + 8, "offscreen route advances at overridden speed")
mod:OnNewRoom()
tick()
near(leader.OrbitAngleOffset, 8, "room transition retains logical tail as pace reference")
advance(24)
mod:OnExit(true)
paceSave = package.loaded.json.decode(mod.saved)
check(paceSave.Players["1"].Followers[2].Speed > 3,
    "callback feed-forward must not cap the moving guide's speed at three")
check(paceSave.Players["1"].Followers[2].Speed <= 10,
    "callback fast catch-up remains bounded")

-- Separate owners must select their own tail even in the same room.
owner, leader = paceFixture(6, { 1 }, 4)
mod:OnExit(true)
paceSave = package.loaded.json.decode(mod.saved)
local paceVisitor = newPlayer(320, 280)
paceVisitor.Count = 2
local visitorGuide = newEntity(3, 236, Vector(320, 280), paceVisitor)
visitorGuide.Visible, visitorGuide.Coins = false, 7
paceSave.Players["2"] = { NextIndex = 3, HeadSeed = visitorGuide.InitSeed,
    Guide = { World = worldAt(7), Speed = 1, Phase = 0, Frame = clock },
    Followers = { { Index = 2, Seed = 2001, World = worldAt(5), Speed = 0 } } }
mod.saved = encode(paceSave)
mod:OnGameStarted(true)
mod:OnUpdate()
near(leader.OrbitAngleOffset, 4, "co-op owner behind uses own tail")
near(visitorGuide.OrbitAngleOffset, 0.5, "co-op owner ahead independently uses own tail")

-- The original stacking edition must recognize the same native aura too.
if arg[2] then
    root = arg[2]
    entities, allPlayers, clock = {}, {}, 0
    dofile(root .. "/main.lua")
    local old = currentMod
    local holder = newPlayer(300, 200)
    holder.Count = 2
    newEntity(3, 236, Vector(300, 200), holder)
    old:OnGameStarted()
    advance(8)
    expectStats(holder, 2, "stacking edition recognizes a native aura")
    holder.Position = Vector(20, 440)
    advance(6)
    expectStats(holder, 0, "stacking edition removes expired bonuses")
end
print(string.format("PASS: %d Bethlehem regression checks (offline; no game launched)", checks))
