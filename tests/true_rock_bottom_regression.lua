-- Run from the repository root: lua tests/true_rock_bottom_regression.lua
-- Model native form/inventory changes; the isolated game audit covers the
-- engine's actual pointer swaps, cache timing, and abandoned mineshaft.
local function copy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, item in pairs(value) do result[key] = copy(item) end
    return result
end

local function enum(initial)
    local nextValue = 100
    return setmetatable(initial or {}, {__index = function(self, name)
        nextValue = nextValue + 1
        rawset(self, name, nextValue)
        return nextValue
    end})
end

local function fixture()
    local f = {players = {}, entities = {}, roomMist = false, nextHash = 0}
    local C = enum({COLLECTIBLE_ROCK_BOTTOM = 562})
    local P = enum({PLAYER_ISAAC = 0, PLAYER_THEFORGOTTEN = 16,
        PLAYER_THESOUL = 17, PLAYER_LAZARUS_B = 29, PLAYER_LAZARUS2_B = 38})
    local F = {CACHE_DAMAGE = 1, CACHE_FIREDELAY = 2, CACHE_SPEED = 4,
        CACHE_RANGE = 8, CACHE_SHOTSPEED = 16, CACHE_LUCK = 32, CACHE_ALL = 63}
    local M = enum()
    local N = {ID_HUGE_GROWTH = 1, ID_LUNA = 2}
    local callbacks = {}
    local mod = {}
    function mod:AddCallback(id, fn)
        callbacks[id] = callbacks[id] or {}
        table.insert(callbacks[id], fn)
    end
    function mod:AddPriorityCallback(id, _, fn) self:AddCallback(id, fn) end
    function mod:SaveData(data) f.saved = copy(data) end
    function mod:HasData() return f.saved ~= nil end
    function mod:LoadData() return copy(f.saved) end
    local game = {}
    function game:GetNumPlayers() return #f.players end
    function game:GetSeeds() return {GetStartSeed = function() return 123 end} end
    function game:GetRoom() return {HasCurseMist = function() return f.roomMist end} end
    local env = setmetatable({
        RegisterMod = function() return mod end, Game = function() return game end,
        CollectibleType = C, PlayerType = P, CacheFlag = F, ModCallbacks = M,
        NullItemID = N, EntityType = enum(), PickupVariant = enum(),
        GetPtrHash = function(p) return p.hash end,
        Isaac = {GetItemIdByName = function() return 1000 end,
            GetPlayer = function(i) return f.players[i + 1] end,
            DebugString = function(message) error(message) end},
        include = function(path) return dofile("mods/true_rock_bottom/" .. path .. ".lua") end,
        require = function(name)
            assert(name == "json")
            return {encode = copy, decode = copy}
        end,
    }, {__index = _G})
    assert(loadfile("mods/true_rock_bottom/main.lua", "t", env))()
    f.mod, f.C, f.P, f.F, f.M, f.N = mod, C, P, F, M, N
    function f:call(id, ...)
        for _, callback in ipairs(callbacks[id] or {}) do callback(mod, ...) end
    end
    function f:newPlayer(playerType)
        self.nextHash = self.nextHash + 1
        local p = {hash = self.nextHash, InitSeed = self.nextHash, type = playerType,
            items = {}, data = {}, null = {}, bonus = 0, mist = false}
        self.entities[#self.entities + 1] = p
        function p:GetData() return self.data end
        function p:GetPlayerType() return self.type end
        function p:GetSubPlayer() return self.sub end
        function p:HasCurseMistEffect() return self.mist end
        function p:HasCollectible(id)
            return not (self.mist or f.roomMist) and (self.items[id] or 0) > 0
        end
        function p:GetCollectibleNum(id) return self.items[id] or 0 end
        function p:AddCollectible(id) self.items[id] = (self.items[id] or 0) + 1 end
        function p:RemoveCollectible(id)
            self.items[id] = math.max(0, (self.items[id] or 0) - 1)
        end
        local effects = {}
        function effects:GetNullEffectNum(id) return p.null[id] or 0 end
        function effects:AddNullEffect(id, _, count)
            p.null[id] = (p.null[id] or 0) + (count or 1)
        end
        function effects:RemoveNullEffect(id, count)
            p.null[id] = math.max(0, (p.null[id] or 0) - (count or 1))
        end
        function effects:HasCollectibleEffect() return false end
        function p:GetEffects() return effects end
        function p:AddCacheFlags() end
        function p:rawStats()
            local multiplier = (self.type == P.PLAYER_THEFORGOTTEN
                or self.type == P.PLAYER_LAZARUS2_B) and 1.5 or 1
            local tearsMultiplier = self.type == P.PLAYER_THEFORGOTTEN and 0.5 or 1
            self.Damage = 3.5 * multiplier + self.bonus + (self.null[N.ID_HUGE_GROWTH] or 0) * 7
            local tears = (30 / 11 + (self.null[N.ID_LUNA] or 0)) * tearsMultiplier
            if self.mist or f.roomMist then self.Damage, tears = 3.5, 30 / 11 end
            self.MaxFireDelay = 30 / tears - 1
            self.MoveSpeed, self.TearRange, self.ShotSpeed, self.Luck = 1, 260, 1, 0
        end
        function p:EvaluateItems()
            self:rawStats()
            for _, flag in ipairs({1, 2, 4, 8, 16, 32}) do
                f:call(M.MC_EVALUATE_CACHE, self, flag)
            end
        end
        p:rawStats()
        return p
    end
    function f:start(continued)
        if continued then
            for _, p in ipairs(self.entities) do p.data = {}; p:rawStats() end
        end
        mod:OnStart(continued or false)
    end
    function f:refresh(p) p:EvaluateItems(); mod:OnUpdate() end
    function f:save() self:call(M.MC_POST_NEW_ROOM) end
    function f:state(p) return p:GetData().TrueRockBottom_State end
    return f
end

local function near(actual, expected, message)
    assert(math.abs(actual - expected) < 0.00001,
        (message or "stat mismatch") .. ": expected " .. expected .. ", got " .. actual)
end

local f = fixture()
local p = f:newPlayer(f.P.PLAYER_THEFORGOTTEN)
local sub = f:newPlayer(f.P.PLAYER_THESOUL)
p.sub = sub
f.players = {p}
p.items[562] = 1
f:start()
for _ = 1, 5 do
    p.type, sub.type = 17, 16
    f:refresh(p)
    near(p.Damage, 3.5, "Soul damage must not inherit the bone multiplier")
    near(30 / (p.MaxFireDelay + 1), 30 / 11, "Soul tears must not accumulate")
    p.type, sub.type = 16, 17
    f:refresh(p)
    near(p.Damage, 5.25, "Bone damage must not accumulate")
    near(30 / (p.MaxFireDelay + 1), 15 / 11, "Bone tears must not accumulate")
end
p.bonus = 7
f:refresh(p)
p.bonus = 0
f:refresh(p)
near(p.Damage, 12.25, "real gains still persist")
p.type, sub.type = 17, 16
f:refresh(p)
f:save()
assert(f.saved.version == 2)
near(f.saved.players["0:forgotten"].damage.peak, 12.25)
near(f.saved.players["0:soul"].damage.peak, 3.5)
f:start(true)
f:save() -- Save again before revisiting the dormant bone form.
near(f.saved.players["0:forgotten"].damage.peak, 12.25)
p.type, sub.type = 16, 17
f:refresh(p)
near(p.Damage, 12.25, "dormant bone history survives continue")
p.items[1000] = 0
f:refresh(p)
p.items[562] = 1
f:refresh(p)
p.type, sub.type = 17, 16
f:refresh(p)
p.type, sub.type = 16, 17
f:refresh(p)
near(p.Damage, 5.25, "true item loss clears both forms")

f = fixture()
p = f:newPlayer(f.P.PLAYER_ISAAC)
f.players = {p}
p.items[562] = 1
f:start()
p.bonus = 4
f:refresh(p)
p.bonus = 0
f:refresh(p)
near(p.Damage, 7.5)
p.mist = true
f:refresh(p)
near(p.Damage, 3.5, "mine suppression still disables stats")
near(f:state(p).records.damage.peak, 7.5, "mine suppression preserves history")
f:save()
f:start(true)
near(f:state(p).records.damage.peak, 7.5, "continue inside mines preserves history")
p.mist = false
f:refresh(p)
near(p.Damage, 7.5, "leaving mines restores retained stats")
f.roomMist = true
f:refresh(p)
near(f:state(p).records.damage.peak, 7.5, "room mist also preserves history")
f.roomMist = false
f:refresh(p)
near(p.Damage, 7.5)
p.items[1000] = 0
f:refresh(p)
assert(next(f:state(p).records) == nil, "true item loss still clears history")

f = fixture()
local alive, dead = f:newPlayer(f.P.PLAYER_LAZARUS_B), f:newPlayer(f.P.PLAYER_LAZARUS2_B)
alive.items[562], dead.items[562] = 1, 1
f.players = {alive}
f:start()
alive.bonus = 7
f:refresh(alive)
alive.bonus = 0
f:refresh(alive)
f.players = {dead}
f:refresh(dead)
for _ = 1, 3 do
    f.players = {alive}; f:refresh(alive); near(alive.Damage, 10.5)
    f.players = {dead}; f:refresh(dead); near(dead.Damage, 5.25)
end
f:save()
near(f.saved.players["0:lazarus"].damage.peak, 10.5)
near(f.saved.players["0:deadLazarus"].damage.peak, 5.25)
f:start(true)
f:save() -- The still-unvisited alive form must survive a second save.
near(f.saved.players["0:lazarus"].damage.peak, 10.5)
f.players = {alive}
f:refresh(alive)
near(alive.Damage, 10.5, "Flip after continue restores the other form")

f = fixture()
local first, second = f:newPlayer(f.P.PLAYER_ISAAC), f:newPlayer(f.P.PLAYER_ISAAC)
first.items[562], second.items[562] = 1, 1
f.players = {first, second}
f:start()
first.bonus = 7
f:refresh(first)
first.bonus = 0
f:refresh(first)
f.players = {second, first}
f:refresh(second)
near(second.Damage, 3.5, "changing co-op slots must not exchange entity histories")
f:refresh(first)
near(first.Damage, 10.5, "co-op entity retains its own history")

f = fixture()
p = f:newPlayer(f.P.PLAYER_THEFORGOTTEN)
f.players = {p}
p.items[1000] = 1
f.saved = {version = 1, inventoryHudVersion = 1, seed = 123,
    players = {["0"] = {damage = {peak = 12.25, carry = 7 / 1.5, multiplier = 1.5}}}}
f:start(true)
near(p.Damage, 12.25, "legacy slot history migrates to the current form")
f:save()
assert(f.saved.version == 2 and f.saved.players["0"] == nil)
near(f.saved.players["0:forgotten"].damage.peak, 12.25)

print("PASS: Forgotten forms, mine suppression, Flip saves, dormant history, item loss, co-op identity, legacy migration")
