-- lua tests/party_dps_regression.lua [optional isaac-lan checkout]
local root = "mods/party_dps/"
local Meter = dofile(root .. "scripts/meter.lua")
local Damage = dofile(root .. "scripts/damage.lua")
local Ownership = dofile(root .. "scripts/ownership.lua")
local checks = 0
local function check(value, reason)
    assert(value, reason)
    checks = checks + 1
end
local function near(a, b)
    return math.abs(a - b) < 0.001
end
local meter = Meter.new()
meter:advance(100)
meter:ensure(1, "Isaac")
meter:ensure(2, "Jacob+Esau")
meter:add(1, 30)
meter:advance(130)
meter:add(2, 60)
local view = Meter.view(meter:snapshot(), "encounter")
check(view.rows[1].owner == 2 and near(view.rows[1].percent, 200 / 3), "Sorting/share wrong")
check(near(view.rows[1].dps, 60 * 30 / 31), "DPS is not based on 30 Hz simulation")
check(near(view.rows[1].recent, 12), "Rolling window wrong")
meter:advance(130)
check(meter.now == 30, "Repeated/paused simulation ticks advanced time")
meter:advance(280)
check(
    not meter.active and meter:snapshot().duration == 31,
    "Idle encounter did not freeze at last hit"
)
check(
    Meter.view(meter:snapshot(), "encounter").rows[1].recent == 0,
    "Rolling window did not expire"
)
meter:advance(1000)
meter:add(1, 15)
check(
    meter.rows[2].encounter == 0 and meter.rows[2].total == 60,
    "New fight did not reset only the encounter"
)
check(meter:snapshot().combat == 32, "Exploration counted towards combat time")
meter:finish()
meter:advance(1)
check(meter.now == 900, "Rebuilt world tick broke the monotonic clock")
local saved = meter:save()
local restored = Meter.restore(saved)
check(
    restored.rows[1].total == 45 and restored.closed == 32,
    "Continue lost run damage/combat time"
)
restored:advance(5)
restored:add(2, 5)
check(restored:snapshot().combat == 33, "Continue counted old elapsed game ticks")
check(Meter.restore({}).closed == 0, "Malformed save not handled")
restored:add(1, math.huge)
restored:add(1, 0 / 0)
check(restored.rows[1].total == 45, "Non-finite damage accepted")
local wire = Meter.encode(restored:snapshot())
local decoded = assert(Meter.decode(wire))
check(decoded.rows[2].total == 65 and decoded.combat == 33, "Snapshot round trip failed")
for _, bad in ipairs({
    "",
    "D1;2;0;0",
    "D1;1;3;2",
    "D1;0;0;0;1,A,2,1,0",
    "D1;0;0;0;1,A,0,0,0;1,A,0,0,0",
    "D1;0;nan;0",
    string.rep("a", 513),
}) do
    check(Meter.decode(bad) == nil, "Malformed snapshot accepted: " .. bad:sub(1, 30))
end
local maximum = Meter.new()
for i = 1, 4 do
    maximum:ensure(i, string.rep("A", 20))
    maximum:add(i, 1e15)
end
check(#Meter.encode(maximum:snapshot()) <= 512, "Four-player maximum exceeds LAN result bounds")

-- Models the engine applying (or cancelling) each call after the pre callback.
local hash = 0
GetPtrHash = function(entity)
    return entity.hash
end
local function entity(hp)
    hash = hash + 1
    local e = { hash = hash, HitPoints = hp or 10, FrameCount = 0, data = {}, alive = true }
    function e:Exists()
        return self.alive
    end
    function e:GetData()
        return self.data
    end
    function e:ToPlayer()
        return self.player and self
    end
    function e:ToFamiliar()
        return self.familiar and self
    end
    return e
end
local counted, damage = Meter.new()
damage = Damage.new(counted)
local npc = entity(10)
damage:begin(npc, 1, 5)
npc.HitPoints = 8 -- e.g. 5 nominal damage reduced by boss armor to 2.
damage:flushAll()
check(counted.rows[1].total == 2, "Armor did not use effective HP loss")
damage:begin(npc, 2, 5) -- A later damage callback cancels this hit.
damage:flushAll()
check(not counted.rows[2], "Cancelled hit attributed damage")
npc.FrameCount = npc.FrameCount + 2
damage:flushAll()
damage:begin(npc, 1, 3)
npc.HitPoints = 5
damage:begin(npc, 2, 100) -- Second player strikes the same enemy in the same frame.
npc.HitPoints = -100
damage:flushAll()
check(
    counted.rows[1].total == 5 and counted.rows[2].total == 5,
    "Same-frame attribution/overkill wrong"
)
damage:flushAll()
check(counted.rows[2].total == 5, "Completed hit counted twice")
local removed = entity(10)
damage:begin(removed, 1, 5)
removed.alive = false
damage:flushAll()
check(counted.rows[1].total == 5, "Removed entity invented a successful hit")
local buffered, bufferedMeter = entity(30), Meter.new()
local bufferDamage = Damage.new(bufferedMeter)
bufferDamage:begin(buffered, 1, 10)
bufferDamage:flushAll()
check(
    bufferDamage.pending[buffered.hash] ~= nil,
    "Pre-update flush discarded vanilla buffered damage"
)
bufferDamage:begin(buffered, 2, 20)
bufferDamage:begin(buffered, nil, 30)
buffered.FrameCount, buffered.HitPoints = 1, 0
bufferDamage:flushAll()
check(
    bufferedMeter.rows[1].total == 5 and bufferedMeter.rows[2].total == 10,
    "Buffered same-frame damage was not split proportionally with unowned damage excluded"
)

local player = entity()
player.player, player.owner = true, 2
local familiar, tear, laser, bomb = entity(), entity(), entity(), entity()
familiar.familiar, familiar.Player = true, player
tear.SpawnerEntity, laser.Parent, bomb.SpawnerEntity = familiar, tear, player
local ownership = Ownership.new(function(p)
    return p.owner
end, 1)
player.GetData = function()
    error("Owner tracking must not mutate native Mod data")
end
check(ownership:resolve(tear) == 2, "Familiar tear lost owner")
check(ownership:resolve(laser) == 2 and ownership:resolve(bomb) == 2, "Laser/bomb ownership wrong")
tear.SpawnerEntity = nil
check(ownership:resolve(tear) == 2, "Persistent effect lost cached owner")
local a, b = entity(), entity()
a.Parent, b.Parent = b, a
check(ownership:resolve(a) == nil, "Parent cycle not bounded")
check(
    Ownership.new(function() end, 2):resolve(tear) == nil,
    "Ownership leaked across world generation"
)
ownership:prune(301)
check(ownership:resolve(tear) == nil, "Expired source cache was not bounded")

-- Execute the production Mod callbacks in a vanilla-shaped environment.
local function fixture(preparingLAN)
    local f = { frame = 0, renders = {}, draws = {}, paints = {}, saved = nil }
    local callbacks, names = {}, 0
    local M = setmetatable({}, {
        __index = function(t, k)
            names = names + 1
            t[k] = names
            return names
        end,
    })
    local mod = {}
    function mod:AddCallback(id, fn)
        callbacks[id] = callbacks[id] or {}
        table.insert(callbacks[id], fn)
    end
    function mod:AddPriorityCallback(id, _, fn)
        self:AddCallback(id, fn)
    end
    function mod:HasData()
        return false
    end
    function mod:SaveData(value)
        f.saved = value
    end
    local game = {}
    function game:GetNumPlayers()
        return #f.players
    end
    function game:GetFrameCount()
        return f.frame
    end
    function game:GetSeeds()
        return {
            GetStartSeed = function()
                return 100
            end,
        }
    end
    local env = setmetatable({
        _G = {},
        RegisterMod = function()
            return mod
        end,
        Game = function()
            return game
        end,
        GetPtrHash = GetPtrHash,
        ModCallbacks = M,
        DamageFlag = { DAMAGE_FAKE = 1 },
        EntityFlag = { FLAG_FRIENDLY = 1 },
        CallbackPriority = { LATE = 100 },
        PlayerType = { PLAYER_JACOB = 19 },
        Options = { FoundHUD = false, HUDOffset = 0 },
        Keyboard = {
            KEY_F6 = 6,
            KEY_F7 = 7,
            KEY_F8 = 8,
            KEY_F9 = 9,
            KEY_ESCAPE = 27,
            KEY_UP = 38,
            KEY_DOWN = 40,
            KEY_LEFT = 37,
            KEY_RIGHT = 39,
            KEY_ENTER = 13,
        },
        KColor = function(...)
            return { ... }
        end,
        Color = function(...)
            return { ... }
        end,
        Vector = setmetatable({ Zero = { X = 0, Y = 0 } }, {
            __call = function(_, x, y)
                return { X = x, Y = y }
            end,
        }),
        Font = function()
            return {
                Load = function() end,
                GetStringWidth = function(_, s)
                    return #s * (f.charWidth or 5)
                end,
                GetLineHeight = function()
                    return f.lineHeight or 12
                end,
                GetBaselineHeight = function()
                    return (f.lineHeight or 12) - 2
                end,
                DrawStringScaled = function(_, s, x, y, sx, sy, _, box)
                    f.renders[#f.renders + 1] = s
                    local width = #s * (f.charWidth or 5)
                    local draw = {
                        kind = "text",
                        label = s,
                        x = x + ((box or 0) > 0 and box - width or 0),
                        y = y,
                        w = width,
                        h = f.lineHeight or 12,
                        sx = sx,
                        sy = sy,
                    }
                    f.draws[#f.draws + 1] = draw
                    f.paints[#f.paints + 1] = draw
                end,
            }
        end,
        Sprite = function()
            return {
                Load = function() end,
                Play = function() end,
                Render = function(sprite, position)
                    f.paints[#f.paints + 1] = {
                        kind = "rectangle",
                        x = position.X,
                        y = position.Y,
                        w = sprite.Scale.X,
                        h = sprite.Scale.Y,
                    }
                end,
            }
        end,
        Input = {
            IsButtonPressed = function(key)
                return f.key == key
            end,
            GetMousePosition = function()
                return { X = 0, Y = 0 }
            end,
            IsMouseBtnPressed = function()
                return false
            end,
        },
        Isaac = {
            GetPlayer = function(i)
                return f.players[i + 1]
            end,
            GetScreenWidth = function()
                return 480
            end,
            GetScreenHeight = function()
                return 270
            end,
            WorldToScreen = function(p)
                return p
            end,
            ConsoleOutput = function() end,
        },
        require = function(name)
            assert(name == "json")
            return {
                encode = function(v)
                    return v
                end,
            }
        end,
    }, { __index = _G })
    env._G = env
    if preparingLAN then
        local handle = {
            IsActive = function()
                return true
            end,
            IsReady = function()
                return false
            end,
            IsAuthority = function()
                return true
            end,
            GetContext = function()
                return nil
            end,
            RegisterAction = function() end,
            On = function() end,
        }
        env.IsaacLAN = {
            API_VERSION = 1,
            RegisterMod = function()
                return handle
            end,
        }
    end
    env.include = function(path)
        return assert(loadfile(root .. path .. ".lua", "t", env))()
    end
    local p1, p2, sub = entity(), entity(), entity()
    for i, p in ipairs({ p1, p2, sub }) do
        p.player, p.ControllerIndex, p.character = true, (i == 2 and 1 or 0), 0
        function p:GetName()
            return "Isaac"
        end
        function p:GetPlayerType()
            return self.character
        end
        function p:GetSubPlayer()
            return self.sub
        end
    end
    p1.sub, f.players = sub, { p1, p2 }
    f.p1, f.p2, f.sub, f.M = p1, p2, sub, M
    assert(loadfile(root .. "main.lua", "t", env))()
    f.mod, f.env = mod, env
    function f:call(id, ...)
        for _, fn in ipairs(callbacks[id] or {}) do
            check(fn(mod, ...) == nil, "Observer altered a callback return")
        end
    end
    function f:hit(source, requested, actual, flags)
        local target = entity(10)
        function target:ToNPC()
            return self
        end
        function target:IsActiveEnemy()
            return true
        end
        function target:IsVulnerableEnemy()
            return true
        end
        function target:HasEntityFlags()
            return false
        end
        self:call(M.MC_ENTITY_TAKE_DMG, target, requested, flags or 0, { Entity = source })
        target.HitPoints = 10 - actual
        self:call(M.MC_POST_UPDATE)
    end
    return f
end
local f = fixture()
f:call(f.M.MC_POST_GAME_STARTED, false)
f:call(f.M.MC_POST_UPDATE)
f:hit(f.p1, 10, 3)
f.frame = 30
f:hit(f.p2, 30, 5)
f:hit(f.sub, 20, 2)
f:hit(f.p1, 10, 10, 1)
check(
    f.mod:GetSnapshot().rows[1].total == 5 and f.mod:GetSnapshot().rows[2].total == 5,
    "Production callbacks failed co-op/sub-character/FAKE attribution"
)
f:call(f.M.MC_POST_RENDER)
check(table.concat(f.renders, " "):find("PARTY DPS", 1, true), "UI did not render")
f.key = 6
f:call(f.M.MC_POST_RENDER)
check(
    table.concat(f.renders, " "):find("PARTY DPS SETTINGS", 1, true),
    "Built-in settings menu missing"
)
f.key = 0
f:call(f.M.MC_POST_RENDER)
f.key = 40
f:call(f.M.MC_POST_RENDER)
f.key = 0
f:call(f.M.MC_POST_RENDER)
f.key = 40
f:call(f.M.MC_POST_RENDER)
f.key = 39
f:call(f.M.MC_POST_RENDER)
check(
    near(f.saved.settings.scale, 0.7) and f.saved.settings.anchor == "bottom_left",
    "Settings menu did not adjust/save the small lower-left default"
)
f.key = 0
f:call(f.M.MC_POST_RENDER)
f.key = 6
f:call(f.M.MC_POST_RENDER)
f.key = 7
f:call(f.M.MC_POST_RENDER)
check(f.saved.settings.mode == "run", "F7 did not switch and persist mode")
f.frame = 31
f:call(f.M.MC_POST_NEW_LEVEL)
check(f.mod:GetSnapshot().rows[1].total == 5, "Floor transition lost run totals")
f:call(f.M.MC_PRE_GAME_EXIT)
f:call(f.M.MC_POST_GAME_STARTED, true)
check(
    f.mod:GetSnapshot().rows[2].total == 5,
    "Production continue did not restore persisted damage"
)
f:call(f.M.MC_POST_GAME_STARTED, false)
check(#f.mod:GetSnapshot().rows == 0, "New game with same seed reused previous results")
local preparing = fixture(true)
preparing:call(preparing.M.MC_POST_GAME_STARTED, false)
preparing:call(preparing.M.MC_POST_RENDER)
check(#preparing.renders == 0, "UI read native input before the LAN view was ready")

-- Small panels must preserve font pixels, and optional MCM must load in either order.
for _, draw in ipairs(f.draws) do
    assert(draw.sx == 1 and draw.sy == 1, "Small HUD resampled the pixel font")
    assert(draw.x % 1 == 0 and draw.y % 1 == 0, "HUD text landed between pixels")
end
check(true, "Native font size and integer text positions")
local configured = fixture()
configured:call(configured.M.MC_POST_GAME_STARTED, false)
local options, meta, registrations = {}, {}, 0
local mcm = {
    OptionType = { BOOLEAN = 4, NUMBER = 5 },
    RemoveCategory = function() end,
    UpdateCategory = function(name, data)
        assert(name == "Party DPS")
        meta = data
    end,
    UpdateSubcategory = function(name, section, data)
        assert(name == "Party DPS" and section == "Display" and data.NameTranslate == "面板")
    end,
    AddSetting = function(name, section, option)
        assert(name == "Party DPS" and section == "Display")
        options[#options + 1] = option
        registrations = registrations + 1
    end,
}
configured.env.ModConfigMenu = mcm
configured:call(configured.M.MC_POST_RENDER)
check(
    #options == 7 and meta.NameTranslate == "队伍 DPS",
    "Late-loaded Chinese MCM not registered"
)
configured:call(configured.M.MC_POST_RENDER)
check(registrations == 7, "MCM settings duplicated on render")
options[3].OnChange(85)
options[4].OnChange(75)
options[5].OnChange(4)
check(
    near(configured.saved.settings.scale, 0.85)
        and near(configured.saved.settings.opacity, 0.75)
        and configured.saved.settings.anchor == "top_right",
    "MCM changes did not persist the shared HUD settings"
)
check(options[3].CurrentSetting() == 85, "MCM reads stale settings")
check(options[5].DisplayTranslate():find("右上角", 1, true), "Chinese setting display missing")
configured.key = 6
configured:call(configured.M.MC_POST_RENDER)
check(table.concat(configured.renders, " "):find("85%%"), "F6 menu did not reflect MCM change")
options[3].OnChange(40)
check(near(configured.saved.settings.scale, 0.65), "MCM allowed unreadable tiny panel size")
options[7].OnChange(true)
check(configured.saved.settings.anchor == "bottom_left", "MCM reset position failed")
local rendered = #configured.renders
mcm.IsVisible, configured.key = true, 7
configured:call(configured.M.MC_POST_RENDER)
check(
    #configured.renders == rendered and configured.saved.settings.mode == "encounter",
    "DPS overlay/shortcuts interfered with the open MCM"
)
options[2].OnChange(2)
check(configured.saved.settings.mode == "run", "MCM statistics selector failed")
mcm.IsVisible = false
options[1].OnChange(false)
rendered = #configured.renders
configured.key = 0
configured:call(configured.M.MC_POST_RENDER)
check(#configured.renders == rendered, "MCM visibility setting ignored")

-- Reproduce the crowded HUD with four players, long names and large values.
-- Validate actual draw bounds/order rather than copying the layout calculations.
local crowded = fixture()
crowded.charWidth, crowded.lineHeight = 7, 18
local crowdedView = { rows = {}, seconds = 5999, dps = 1e15, active = true }
for i = 1, 4 do
    crowdedView.rows[i] = {
        owner = i,
        name = "Jacob+Esau TheForgotten",
        dps = 1e15 / i,
        damage = 1e15 / i,
        percent = i == 1 and 100 or 99.9,
    }
end
for _, scale in ipairs({ 0.65, 0.7, 0.85, 1, 1.25 }) do
    crowded.draws, crowded.paints = {}, {}
    local hud = crowded.env.include("scripts/ui")({
        visible = true,
        mode = "encounter",
        scale = scale,
        opacity = 0.9,
        anchor = "bottom_left",
    }, function() end)
    hud:render(crowdedView, { [1] = true })
    local frame = assert(crowded.paints[2])
    local sawText = false
    for _, paint in ipairs(crowded.paints) do
        if paint.kind == "text" then
            sawText = true
        else
            assert(not sawText, "A background covered text already drawn")
        end
    end
    for i, a in ipairs(crowded.draws) do
        assert(a.sx == 1 and a.sy == 1, "Crowded HUD resampled the font")
        assert(
            a.x >= frame.x + 2
                and a.y >= frame.y + 2
                and a.x + a.w <= frame.x + frame.w - 2
                and a.y + a.h <= frame.y + frame.h - 2,
            "HUD text escaped its panel: " .. a.label
        )
        for j = i + 1, #crowded.draws do
            local b = crowded.draws[j]
            local overlap = a.x < b.x + b.w
                and b.x < a.x + a.w
                and a.y < b.y + b.h
                and b.y < a.y + a.h
            assert(not overlap, "HUD text overlaps: " .. a.label .. " / " .. b.label)
        end
    end
    check(sawText, "Crowded HUD not drawn at scale " .. scale)
end
crowded.env.Options.FoundHUD = true
crowded.draws, crowded.paints = {}, {}
local reserved = crowded.env.include("scripts/ui")({
    visible = true,
    mode = "encounter",
    scale = 0.65,
    opacity = 0.9,
    anchor = "bottom_left",
}, function() end)
reserved:render(crowdedView, { [1] = true })
check(crowded.paints[2].x >= 96, "Left HUD did not avoid vanilla stats drawn over the panel")

-- Optional: use the real isaac-lan API modules/transport codec, not a fake API.
if arg[1] then
    local runtime = assert(loadfile(arg[1] .. "/tests/fixtures/api_runtime.lua"))()(arg[1])
    local host, guest = runtime.peer(0), runtime.peer(1)
    local function adapter(peer, snapshot)
        return assert(loadfile(root .. "scripts/lan.lua", "t", peer.env))()({}, Meter, {
            snapshot = function()
                return snapshot
            end,
            reset = function() end,
            view = function() end,
        })
    end
    local hm = Meter.new()
    hm:ensure(1, "Isaac")
    hm:ensure(2, "Jacob+Esau")
    hm:add(1, 33)
    hm:add(2, 66)
    local h, g = adapter(host, hm:snapshot()), adapter(guest, Meter.new():snapshot())
    host.bridge.commit()
    guest.bridge.commit()
    host.bridge.actions.poll()
    guest.bridge.actions.poll()
    guest.tick = 15
    guest.bridge.commit()
    host.bridge.actions.poll()
    host.bridge.actions.step()
    guest.bridge.actions.poll()
    local snapshot = assert(g:snapshot(15))
    check(
        snapshot.rows[1].total == 33 and snapshot.rows[2].total == 66,
        "Real LAN API failed read-only result synchronization"
    )
    check(#host.logs == 0 and #guest.logs == 0, "LAN API logged integration/codec error")
    guest.epoch = 1
    guest.bridge.poll()
    check(not g.received, "Old snapshot survived world reset")
    host.api:SetActionEnabled("isaac-mods.party-dps", "snapshot", false)
    host.bridge.actions.poll()
    guest.bridge.actions.poll()
    guest.bridge.commit()
    check(g.status == "Host needs Party DPS", "Missing host capability did not show a clear status")
end
print("PASS Party DPS: " .. checks .. " checks")
