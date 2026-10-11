-- Concentrated real-engine acceptance fixture. Use only owned isolated labs.
-- Damage calls exercise native HP/callbacks; this is not a normal gameplay run.
-- A UI-only acceptance can set _PartyDPSVerifyFloor = false; report that scope explicitly.
local verifyFloor = _PartyDPSVerifyFloor ~= false
local verifyMCM = _PartyDPSVerifyMCM == true
local native, api = assert(_IsaacLan), assert(IsaacLAN)
local host, port = _IsaacLanTest and _IsaacLanTest.host, _IsaacLanTest and _IsaacLanTest.port
if host == nil then
    local f = assert(io.open("./lan-test-role.txt", "r"))
    host = f:read("*l") == "host"
    f:close()
    f = assert(io.open("./lan-test-menu-port.txt", "r"))
    port = f:read("*l")
    f:close()
end
local function report(text)
    Isaac.DebugString("LAN_NETWORK " .. text)
end
local originalFrame = _IsaacLanFrame
local frames, linked, chosen, finished = 0, false, false, false
local checked, menuOpened, menuClosed = false, false, false
local previewStarted, previewEnded = false, false
local expected, hitTargets = { 0, 0 }, {}
local hpBefore, requested = {}, {}
local function total(snapshot, owner)
    for _, row in ipairs(snapshot.rows) do
        if row.owner == owner then
            return row.total
        end
    end
    return 0
end
function _IsaacLanFrame()
    frames = frames + 1
    if not linked and frames >= (host and 300 or 360) then
        linked = true
        _IsaacLanCommand(host and "host" or "join", host and port or "127.0.0.1:" .. port)
        report("MENU_READY")
    end
    local s = originalFrame()
    if s.phase == 2 and not chosen then
        chosen = true
        _IsaacLanCommand("choose", "0:1")
    end
    if host and s.phase == 2 and s.players == 2 and s.ready0 == 1 and s.ready1 == 1 then
        _IsaacLanCommand("start", "LBCD0G4M:0:0:0:0:0")
    end
    if s.phase == 4 or s.phase == 9 then
        report("FAILED " .. s.error)
    end
    if s.prepared and s.verified >= 200 and not previewStarted and PartyDPSLayoutTest then
        previewStarted = true
        PartyDPSLayoutTest.Show()
        report("CHECK synthetic four-player HUD with native font metrics")
    end
    if s.prepared and s.verified >= 350 and not previewEnded and PartyDPSLayoutTest then
        previewEnded = true
        PartyDPSLayoutTest.Hide()
    end
    if s.prepared and s.verified >= 360 and not checked then
        checked = true
        local mod = assert(PartyDPS, "Party DPS was not loaded")
        local snapshot, reason = mod:GetSnapshot()
        assert(snapshot, "No LAN DPS snapshot: " .. tostring(reason))
        assert(#snapshot.rows == 2, "DPS roster is not the two participants")
        assert(
            total(snapshot, 1) > 0 and total(snapshot, 2) > 0,
            "Missing host or split-room guest damage"
        )
        if host then
            assert(
                math.abs(total(snapshot, 1) - expected[1]) < 0.01,
                "Host HP-loss accounting incorrect"
            )
            assert(
                math.abs(total(snapshot, 2) - expected[2]) < 0.01,
                "Remote HP-loss accounting incorrect"
            )
        end
        assert(not snapshot.active, "Completed encounter remained active after five idle seconds")
        report(
            string.format(
                "DPS_RESULT host=%s p1=%.3f p2=%.3f combat=%d",
                tostring(host),
                total(snapshot, 1),
                total(snapshot, 2),
                snapshot.combat
            )
        )
        if verifyMCM then
            local menu = assert(ModConfigMenu, "Mod Config Menu was not loaded")
            local id = assert(menu.GetCategoryIDByName("Party DPS"), "MCM DPS category missing")
            local category = menu.MenuData[id]
            local options = category.Subcategories[1].Options
            assert(
                #options == 7 and category.NameTranslate == "队伍 DPS",
                "MCM settings incomplete"
            )
            options[3].OnChange(75)
            assert(options[3].CurrentSetting() == 75, "Native MCM size change failed")
            options[3].OnChange(65)
            assert(options[3].DisplayTranslate():find("65%%"), "Native Chinese MCM display failed")
            -- Only the isolated fixture selects our category for the UI capture.
            menu.MenuData[1], menu.MenuData[id] = category, menu.MenuData[1]
            report("CHECK native Chinese MCM registration and shared settings")
        end
    end
    if s.prepared and s.verified >= (verifyFloor and 500 or 400) and not menuOpened then
        menuOpened = true
        PartyDPS:OnCommand("partydps", "settings")
        report("CHECK DPS settings menu open")
    end
    if s.prepared and s.verified >= (verifyFloor and 550 or 450) and not menuClosed then
        menuClosed = true
        PartyDPS:OnCommand("partydps", "settings")
        report("CHECK DPS settings menu close")
        if verifyMCM then
            ModConfigMenu.OpenConfigMenu()
            assert(ModConfigMenu.IsVisible, "Native MCM did not open")
            report("CHECK native Chinese MCM menu open")
        end
    end
    if s.prepared and s.verified >= (verifyFloor and 580 or 480) and not finished then
        local snapshot = assert(PartyDPS:GetSnapshot())
        assert(total(snapshot, 1) > 0 and total(snapshot, 2) > 0, "Lost recorded run DPS")
        if verifyFloor then
            assert(Game():GetLevel():GetStage() == 2, "Native floor transition did not complete")
            report("CHECK native floor transition retained run DPS")
        else
            report("SCOPE native damage, split rooms and settings UI; floor transition excluded")
        end
        finished = true
        if verifyMCM then
            ModConfigMenu.CloseConfigMenu()
        end
        report("PASS Party DPS native damage, split-room synchronization and settings UI")
    end
    return s
end

local gate = native.net_gate
native.net_gate = function(capture, before, collect, restore, present, beginFloor)
    return gate(function()
        return string.rep("\0", 34)
    end, function(t, n, bytes)
        before(t, n, bytes)
        if t == 25 then
            for i = 0, Game():GetNumPlayers() - 1 do
                Isaac.GetPlayer(i):SetMinDamageCooldown(10000)
            end
            for slot = 0, 1 do
                assert(native.rooms_with_player(slot, function()
                    for _, e in ipairs(Isaac.GetRoomEntities()) do
                        if e:IsActiveEnemy(false) or e.Type == EntityType.ENTITY_FIREPLACE then
                            e:Remove()
                        end
                    end
                    Game():GetRoom():SetClear(true)
                end))
            end
            assert(native.rooms_move(1, 71, 0, -1))
        end
        if t == 45 then
            for slot = 0, 1 do
                assert(native.rooms_with_player(slot, function()
                    for _, e in ipairs(Isaac.GetRoomEntities()) do
                        if e:IsActiveEnemy(false) or e.Type == EntityType.ENTITY_FIREPLACE then
                            e:Remove()
                        end
                    end
                    local enemy = Isaac.Spawn(
                        EntityType.ENTITY_GAPER,
                        0,
                        0,
                        Vector(450, 280),
                        Vector.Zero,
                        nil
                    ):ToNPC()
                    enemy.HitPoints, enemy.MaxHitPoints = 50, 50
                    enemy:AddEntityFlags(EntityFlag.FLAG_FREEZE)
                    hitTargets[slot + 1] = enemy
                end))
            end
        end
        if t == 75 then
            for slot = 0, 1 do
                assert(native.rooms_with_player(slot, function()
                    local enemy = assert(hitTargets[slot + 1])
                    enemy.HitPoints, enemy.MaxHitPoints = 50, 50
                end))
            end
        end
        if t == 80 or t == 100 or t == 120 then
            for slot = 0, 1 do
                assert(native.rooms_with_player(slot, function()
                    local target = assert(hitTargets[slot + 1])
                    local player = Isaac.GetPlayer(0)
                    local source = player
                    if t == 100 then
                        source = player:FireTear(Vector(100, 100), Vector.Zero, false, false, false)
                        -- Observe the real tear's initialized parent relationship.
                        PartyDPS:OnSourceUpdate(source)
                    end
                    hpBefore[slot + 1] = target.HitPoints
                    requested[slot + 1] = t == 120 and 1000 or (slot + 1) * 5
                    assert(target:TakeDamage(requested[slot + 1], 0, EntityRef(source), 0))
                    report(
                        string.format(
                            "DPS_BUFFER p%d hp=%.3f requested=%.3f",
                            slot + 1,
                            hpBefore[slot + 1],
                            requested[slot + 1]
                        )
                    )
                end))
            end
        end
        if t == 85 or t == 105 or t == 125 then
            for slot = 0, 1 do
                assert(native.rooms_with_player(slot, function()
                    local target = hitTargets[slot + 1]
                    local remaining = target:Exists() and math.max(0, target.HitPoints) or 0
                    local actual = math.max(0, hpBefore[slot + 1] - remaining)
                    assert(
                        actual == math.min(hpBefore[slot + 1], requested[slot + 1]),
                        "Unexpected fixture HP change"
                    )
                    expected[slot + 1] = expected[slot + 1] + actual
                    report(
                        string.format(
                            "DPS_SETTLED p%d before=%.3f remaining=%.3f actual=%.3f",
                            slot + 1,
                            hpBefore[slot + 1],
                            remaining,
                            actual
                        )
                    )
                end))
            end
        end
        if t == 160 then
            local snapshot = assert(PartyDPS:GetSnapshot())
            report(
                string.format(
                    "DPS_ACCOUNTED p1=%.3f p2=%.3f expected1=%.3f expected2=%.3f",
                    total(snapshot, 1),
                    total(snapshot, 2),
                    expected[1],
                    expected[2]
                )
            )
            assert(
                math.abs(total(snapshot, 1) - expected[1]) < 0.01,
                "Effective host damage mismatch"
            )
            assert(
                math.abs(total(snapshot, 2) - expected[2]) < 0.01,
                "Split-room guest damage mismatch"
            )
            assert(
                expected[1] == 50 and expected[2] > 20 and expected[2] <= 50,
                "Native overkill did not account for the targets' remaining HP"
            )
            report("CHECK native overkill and source attribution")
        end
        if verifyFloor and t == 400 then
            assert(native.rooms_with_player(0, function()
                for _, e in ipairs(Isaac.GetRoomEntities()) do
                    if e:IsActiveEnemy(false) then
                        e:Remove()
                    end
                end
                Game():GetRoom():SetClear(true)
                Game():StartStageTransition(false, 0, Isaac.GetPlayer(0))
            end))
        end
    end, collect, restore, present, beginFloor)
end
