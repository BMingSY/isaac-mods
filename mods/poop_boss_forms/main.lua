local mod = RegisterMod("Poop Boss Forms", 1)
local json = require("json")
local forms = include("scripts/forms")
local rules = include("scripts/rules")
local weapons = include("scripts/weapons")
local game, sfx = Game(), SFXManager()
local POOP = CollectibleType.COLLECTIBLE_POOP
local DASH = Isaac.GetItemIdByName("Poop Boss Rush")
local AVATAR = Isaac.GetEntityVariantByName("Poop Boss Avatar")
local POCKET = ActiveSlot.SLOT_POCKET
local KEY = "PoopBossForms"
local MAX_SUMMONS = 18
local runtime, saved = {}, {}
local started, readingInput = false, false
local font = Font()
font:Load("font/cjk/lanapixel.fnt")

if DASH <= 0 or AVATAR <= 0 then
    Isaac.DebugString(string.format("[Poop Boss Forms] Content registration failed: dash=%s, avatar=%s; restart after updating the mod.", tostring(DASH), tostring(AVATAR)))
    mod:AddCallback(ModCallbacks.MC_POST_RENDER, function()
        local width = Isaac.GetScreenWidth()
        font:DrawStringScaledUTF8("坨坨变身：内容加载失败", 0, 45, 1, 1, KColor(1, 0.4, 0.3, 1), width, true)
        font:DrawStringScaledUTF8("请更新 Mod 后完全退出并重启游戏", 0, 61, 1, 1, KColor(1, 1, 1, 1), width, true)
    end)
    return
end

local function eachPlayer(fn)
    for i = 0, game:GetNumPlayers() - 1 do
        local player = Isaac.GetPlayer(i)
        fn(player, tostring(i))
        local sub = player:GetSubPlayer()
        if sub then fn(sub, tostring(i) .. ":sub") end
    end
end

local function playerKey(player)
    local hash, key = GetPtrHash(player), nil
    eachPlayer(function(p, k) if GetPtrHash(p) == hash then key = k end end)
    return key or ("extra:" .. tostring(player.InitSeed))
end

local function stateFor(player)
    local hash = GetPtrHash(player)
    if not runtime[hash] then
        local key = playerKey(player)
        local record = type(saved[key]) == "table" and saved[key] or {}
        -- Revival/character swaps can replace the player object but retain its player slot.
        for oldHash, old in pairs(runtime) do
            if old.key == key then
                record = old
                if old.avatar and old.avatar:Exists() then old.avatar:Remove() end
                runtime[oldHash] = nil
                break
            end
        end
        local dashCharge = type(record.dashCharge) == "number" and record.dashCharge or nil
        -- Migrate the pre-0.5 swap stash once, preserving the rush charge.
        local legacyPocket = record.otherPocket
        if type(legacyPocket) == "table" and legacyPocket.isDash then
            dashCharge = (tonumber(legacyPocket.charge) or 0) + (tonumber(legacyPocket.battery) or 0)
        end
        runtime[hash] = {
            key = key, player = player, selected = rules.validForm(record.selected, #forms) and record.selected or 1,
            form = rules.validForm(record.form, #forms) and record.form or nil,
            dashCharge = dashCharge,
            pocketInstalled = record.pocketInstalled == true,
            volleys = 0, lastAim = Vector(0, 1), dropFrames = 0,
            facingRight = record.facingRight == true,
        }
        saved[key] = nil
        player:GetData()[KEY] = runtime[hash]
    end
    return runtime[hash]
end

local function peek(player)
    return player and runtime[GetPtrHash(player)]
end

local function ownsPoop(player)
    for slot = ActiveSlot.SLOT_PRIMARY, ActiveSlot.SLOT_POCKET2 do
        if player:GetActiveItem(slot) == POOP then return true end
    end
    return false
end

local function alive(player)
    return player:Exists() and not player:IsDead() and not player:IsCoopGhost()
end

local function active(player)
    return alive(player) and player:AreControlsEnabled()
end

local function readAction(player, action)
    readingInput = true
    local value = Input.GetActionValue(action, player.ControllerIndex)
    readingInput = false
    return value
end

local function shootingAim(player)
    -- Use the engine's world-space input, including the mirror world's inversion.
    -- Bypass our dash-only input gate while choosing the next dash direction.
    readingInput = true
    local aim = player:GetShootingInput()
    readingInput = false
    return aim
end

local function direction(player, state)
    local aim = shootingAim(player)
    if aim:LengthSquared() < 0.04 then aim = player:GetMovementInput() end
    if aim:LengthSquared() < 0.04 then aim = state.lastAim end
    return aim:Normalized()
end

local function installPocket(player, state)
    if player:GetActiveItem(POCKET) ~= DASH then
        local charge = state.dashCharge
        if charge == nil then charge = state.pocketInstalled and 0 or 1 end
        -- One permanent pocket active, like Dark Arts. Leave the native card
        -- and pill queue alone and never reinstall just because Ctrl was used.
        player:SetPocketActiveItem(DASH, POCKET, true)
        player:SetActiveCharge(math.max(0, charge), POCKET)
    end
    state.pocketInstalled = true
    state.dashCharge = nil
end

local function save()
    if not started then return end
    local records = {}
    for key, value in pairs(saved) do records[key] = value end
    eachPlayer(function(player)
        local state = stateFor(player)
        records[state.key] = { selected = state.selected, form = state.form,
            pocketInstalled = state.pocketInstalled, dashCharge = state.dashCharge }
    end)
    mod:SaveData(json.encode({ version = 2, seed = game:GetSeeds():GetStartSeed(), players = records }))
end

local function animation(state, name)
    state.animation = name
    if state.avatar and state.avatar:Exists() then state.avatar:GetSprite():Play(name, true) end
end

local function hidePlayer(player, state)
    -- Visible=false also hides the engine's weapon charge indicators. Keep
    -- native rendering enabled and make only the character sprite transparent.
    local color = player:GetColor()
    player:GetSprite().Color = Color(color.R, color.G, color.B, 0, color.RO, color.GO, color.BO)
    player.Visible = true
    state.hidden = true
end

local function showPlayer(player, state)
    if state.hidden then
        local color = player:GetColor()
        player:GetSprite().Color = Color(color.R, color.G, color.B, 1, color.RO, color.GO, color.BO)
        player.Visible = true
        state.hidden = nil
    end
end

local function updateAvatar(player, state)
    if not player:Exists() or player:IsCoopGhost() then
        showPlayer(player, state)
        if state.avatar and state.avatar:Exists() then state.avatar:Remove() end
        state.avatar = nil
        return
    end
    if not state.avatar or not state.avatar:Exists() then
        local avatar = Isaac.Spawn(EntityType.ENTITY_EFFECT, AVATAR, 0, player.Position, Vector.Zero, player):ToEffect()
        avatar.Parent = player
        avatar:GetData()[KEY] = state
        avatar.EntityCollisionClass = EntityCollisionClass.ENTCOLL_NONE
        avatar.GridCollisionClass = EntityGridCollisionClass.GRIDCOLL_NONE
        state.avatar, state.avatarForm = avatar, nil
        state.dead = nil
    end
    local avatar, sprite = state.avatar, state.avatar:GetSprite()
    if state.avatarForm ~= state.form then
        sprite:Load("gfx/poop_boss_forms/" .. forms[state.form].skin .. ".anm2", true)
        sprite:Play("Appear", true)
        state.avatarForm, state.animation = state.form, "Appear"
    end
    avatar.Position, avatar.Velocity = player.Position, player.Velocity
    avatar.SpriteScale = player.SpriteScale * 0.8
    avatar.SpriteOffset = player.SpriteOffset
    -- Keep native action timing/effects, but never reveal Isaac's sprite during
    -- hurt, pickup or item-use animations. These bosses have no matching poses.
    hidePlayer(player, state)
    avatar.Visible = player:IsDead() or player:GetDamageCooldown() <= 0 or game:GetFrameCount() % 4 < 2 or state.dash ~= nil
    local color = player:GetColor()
    sprite.Color = Color(color.R, color.G, color.B, 1, color.RO, color.GO, color.BO)
    if player:IsDead() then
        if not state.dead then sprite:Play("Death", true) end
        state.dead = true
    elseif state.dead then
        state.dead, state.animation = nil, nil
        sprite:Play("Idle", true)
    elseif not player:IsExtraAnimationFinished() then
        state.animation = nil
        if not sprite:IsPlaying("Idle") then sprite:Play("Idle", true) end
    elseif state.dash then
        local target = state.dash.rest > 0 and "Tired" or "Slide"
        if not sprite:IsPlaying(target) then sprite:Play(target, true) end
    elseif state.animation and sprite:IsFinished(state.animation) then
        sprite:Play("Idle", true)
        state.animation = nil
    elseif not state.animation and not sprite:IsPlaying("Idle") then
        sprite:Play("Idle", true)
    end
    -- The native boss sheets face left. Set this after Play/Load as well.
    sprite.FlipX = state.facingRight
end

local function ownerOf(entity)
    for _ = 1, 6 do
        if not entity then return nil end
        local player = entity:ToPlayer()
        if player then return player end
        local familiar = entity:ToFamiliar()
        if familiar and familiar.Player then return familiar.Player end
        local nextEntity = entity.SpawnerEntity or entity.Parent
        if nextEntity == entity then return nil end
        entity = nextEntity
    end
end

local function summonCount(player)
    local count, hash = 0, GetPtrHash(player)
    for _, entity in ipairs(Isaac.FindByType(EntityType.ENTITY_FAMILIAR, -1, -1, false, false)) do
        local familiar = entity:ToFamiliar()
        if familiar.Player and GetPtrHash(familiar.Player) == hash
            and (familiar.Variant == FamiliarVariant.DIP or familiar.Variant == FamiliarVariant.BLUE_SPIDER) then count = count + 1 end
    end
    return count
end

local function addDip(player, subtype, position)
    local dip = player:AddFriendlyDip(subtype, position)
    if dip then dip:GetData()[KEY] = true end
    return dip
end

local function creep(player, variant, position, damage, timeout)
    local effect = Isaac.Spawn(EntityType.ENTITY_EFFECT, variant, 0, position, Vector.Zero, player):ToEffect()
    effect.CollisionDamage = damage
    effect.Timeout = timeout
    effect:Update()
    return effect
end

local function summon(player, state)
    local form = forms[state.form]
    animation(state, "Whistle")
    sfx:Play(form.summon == "corn" and SoundEffect.SOUND_DANGLE_WHISTLE or SoundEffect.SOUND_WHISTLE, 0.7, 0, false, 1)
    local rng = player:GetCollectibleRNG(POOP)
    local count = math.min(1 + rng:RandomInt(3), MAX_SUMMONS - summonCount(player))
    if form.summon == "red" then
        -- Red Dingle really creates red poop; touching it recruits a red Dip.
        local room = game:GetRoom()
        local position = room:GetGridPosition(room:GetGridIndex(player.Position + state.lastAim * 65))
        if room:IsPositionInRoom(position, 25) and not room:GetGridEntityFromPos(position) then
            Isaac.GridSpawn(GridEntityType.GRID_POOP, 1, position, false)
        elseif count > 0 then
            addDip(player, 1, player.Position + state.lastAim * 20)
        end
    else
        for i = 1, math.max(0, count) do
            local position = game:GetRoom():FindFreePickupSpawnPosition(player.Position + state.lastAim:Rotated((i - 2) * 30) * 25, 0, true)
            if form.summon == "spider" then
                local spider = player:AddBlueSpider(position)
                if spider then spider:GetData()[KEY] = true end
            else
                addDip(player, form.summon == "corn" and 20 or 0, position)
            end
        end
    end
end

local function countVolley(player, state)
    state.volleys = state.volleys + 1
    animation(state, "Spit")
    if state.volleys % 4 == 0 then summon(player, state) end
end

local function countNativeVolley(player, state)
    local frame = game:GetFrameCount()
    if state.nativeVolleyFrame == frame then return end
    state.nativeVolleyFrame = frame
    countVolley(player, state)
end

local function convertPoop(player)
    local room = game:GetRoom()
    local center = room:GetGridIndex(player.Position)
    local width = room:GetGridWidth()
    for y = -1, 1 do
        for x = -1, 1 do
            local index = center + x + y * width
            local grid = index >= 0 and index < room:GetGridSize() and room:GetGridEntity(index) or nil
            if grid and grid:GetType() == GridEntityType.GRID_POOP
                and grid.State < 1000 and rules.touchingPoop(player.Position.X, player.Position.Y,
                    grid.Position.X, grid.Position.Y, player.Size) then
                local subtype = grid:GetVariant()
                if subtype < 0 or subtype > 6 then subtype = 0 end
                -- Leave a real broken grid for the engine to save with the room.
                -- Destroy() alone only partly damages gold/white poop.
                grid:Hurt(1000)
                if grid.State >= 1000 then
                    if subtype == 1 then
                        -- The recruited red poop is spent. An ordinary broken
                        -- remnant cannot revive on a timer or on room re-entry.
                        grid:SetVariant(0)
                        grid:ToPoop().ReviveTimer = -1
                    end
                    addDip(player, subtype, grid.Position)
                end
            end
        end
    end
end

local function finishDash(player, state)
    state.dash = nil
    player.Velocity = player.Velocity * 0.25
    animation(state, "Idle")
end

local function startDash(player, state)
    if not state.form or state.dash or not active(player) then return false end
    local form = forms[state.form]
    state.dash = { remaining = form.dashes, timer = form.dashFrames, rest = 0,
        aim = direction(player, state), hits = {}, previous = player.Position,
        damage = rules.dashDamage(player.Damage, form.dashes), bounce = 0 }
    state.lastAim = state.dash.aim
    animation(state, "Slide")
    return true
end

local function updateDash(player, state)
    local dash, form = state.dash, forms[state.form]
    if not active(player) then finishDash(player, state); return end
    player:SetMinDamageCooldown(3)
    if dash.rest > 0 then
        dash.rest = dash.rest - 1
        player.Velocity = player.Velocity * 0.5
        if dash.rest == 0 then
            dash.aim, dash.hits, dash.previous = direction(player, state), {}, player.Position
            dash.timer = form.dashFrames
            state.lastAim = dash.aim
        end
        return
    end
    local position, previous = player.Position, dash.previous
    for _, enemy in ipairs(Isaac.GetRoomEntities()) do
        if enemy:IsVulnerableEnemy() and not enemy:HasEntityFlags(EntityFlag.FLAG_FRIENDLY) then
            local hash = GetPtrHash(enemy)
            local radius = player.Size + enemy.Size + 8
            if not dash.hits[hash] and rules.segmentDistanceSquared(enemy.Position.X, enemy.Position.Y,
                previous.X, previous.Y, position.X, position.Y) <= radius * radius then
                dash.hits[hash] = true
                enemy:TakeDamage(dash.damage, 0, EntityRef(player), 0)
            end
        end
    end
    dash.previous = position
    dash.bounce = math.max(0, dash.bounce - 1)
    if player:CollidesWithGrid() and dash.bounce == 0 then
        local room = game:GetRoom()
        local probe = player.Size + form.dashSpeed
        local function blocked(pos)
            local collision = room:GetGridCollisionAtPos(pos)
            return collision ~= GridCollisionClass.COLLISION_NONE
                and not (player.CanFly and collision == GridCollisionClass.COLLISION_PIT)
        end
        local bx = blocked(position + Vector(dash.aim.X * probe, 0))
        local by = blocked(position + Vector(0, dash.aim.Y * probe))
        if bx or by then
            dash.aim = Vector(bx and -dash.aim.X or dash.aim.X, by and -dash.aim.Y or dash.aim.Y)
        else dash.aim = -dash.aim end
        dash.bounce = 3
    end
    player.Velocity = dash.aim * form.dashSpeed
    if form.skin == "dangle" and dash.timer % 4 == 0 then
        local stain = creep(player, EffectVariant.PLAYER_CREEP_BLACK, position, player.Damage * 0.35, 75)
        stain.Color = Color(0.7, 0.4, 0.18, 1, 0.1, 0.05, 0)
    end
    dash.timer = dash.timer - 1
    if dash.timer <= 0 then
        dash.remaining = dash.remaining - 1
        if dash.remaining <= 0 then finishDash(player, state) else dash.rest = 6 end
    end
end

function mod:OnPrePoop(_, _, player, flags)
    if not started then return end
    if (flags & UseFlag.USE_CARBATTERY) == 0 then
        local state = stateFor(player)
        if state.dash then finishDash(player, state) end
        state.form, state.volleys = state.selected, 0
        state.avatarForm = nil
        installPocket(player, state)
        save()
    end
    return true
end
mod:AddCallback(ModCallbacks.MC_PRE_USE_ITEM, mod.OnPrePoop, POOP)

function mod:OnUsePoop()
    return { Discharge = true, Remove = false, ShowAnim = false }
end
mod:AddCallback(ModCallbacks.MC_USE_ITEM, mod.OnUsePoop, POOP)

function mod:OnUseDash(_, _, player, flags)
    if (flags & UseFlag.USE_CARBATTERY) ~= 0 then return { Discharge = false, ShowAnim = false } end
    local didDash = startDash(player, stateFor(player))
    return { Discharge = didDash, Remove = false, ShowAnim = false }
end
mod:AddCallback(ModCallbacks.MC_USE_ITEM, mod.OnUseDash, DASH)

function mod:OnInput(entity, hook, action)
    if readingInput or not started or not entity then return end
    local player = entity:ToPlayer()
    local state = peek(player)
    if not state then return end
    -- Leave DROP and PILLCARD entirely to the engine: the pocket active uses
    -- the same Ctrl/Q queue as Dark Arts, cards and pills.
    if state.form and state.dash and action >= ButtonAction.ACTION_SHOOTLEFT and action <= ButtonAction.ACTION_SHOOTDOWN then
        if hook == InputHook.GET_ACTION_VALUE then return 0 end
        return false
    end
end
mod:AddCallback(ModCallbacks.MC_INPUT_ACTION, mod.OnInput)

function mod:OnPlayerUpdate(player)
    if not started then return end
    local state = stateFor(player)
    if not active(player) or game:IsPaused() then
        state.dropFrames = 0
    else
        local down = readAction(player, ButtonAction.ACTION_DROP) > 0
        if down then
            state.dropFrames = state.dropFrames + 1
        else
            if state.dropFrames > 0 and state.dropFrames < 18 and ownsPoop(player) then
                state.selected = state.selected % #forms + 1
                save()
            end
            state.dropFrames = 0
        end
    end
    if not state.form then return end
    installPocket(player, state)
    if active(player) and not game:IsPaused() then
        local aim = shootingAim(player)
        if aim:LengthSquared() >= 0.04 then state.lastAim = aim:Normalized() end
        if state.dash then
            player:SetShootingCooldown(2)
            updateDash(player, state)
        end
        local facing = state.dash and state.dash.aim or aim
        if facing:LengthSquared() < 0.04 then facing = player:GetMovementInput() end
        if math.abs(facing.X) >= 0.1 then state.facingRight = facing.X > 0 end
        convertPoop(player)
    else
        if state.dash then finishDash(player, state) end
    end
    updateAvatar(player, state)
end
mod:AddCallback(ModCallbacks.MC_POST_PEFFECT_UPDATE, mod.OnPlayerUpdate)

function mod:OnPlayerVisualUpdate(player)
    if not started then return end
    local state = peek(player)
    -- Some native extra animations change Visible after the effect update.
    if state and state.form and state.hidden and not player:IsCoopGhost() then hidePlayer(player, state) end
end
mod:AddCallback(ModCallbacks.MC_POST_PLAYER_UPDATE, mod.OnPlayerVisualUpdate)

function mod:OnDeathUpdate()
    if not started then return end
    -- Dead players stop receiving the normal effect-update callback.
    for _, state in pairs(runtime) do
        if state.form and state.player:Exists() and state.player:IsDead() then
            updateAvatar(state.player, state)
        end
    end
end
mod:AddCallback(ModCallbacks.MC_POST_UPDATE, mod.OnDeathUpdate)

function mod:OnAvatarUpdate(effect)
    local state, player = effect:GetData()[KEY], effect.Parent and effect.Parent:ToPlayer()
    if not player or not player:Exists() or not state or not state.form then effect:Remove(); return end
    effect.Position, effect.Velocity = player.Position, Vector.Zero
    effect:GetSprite().FlipX = state.facingRight
end
mod:AddCallback(ModCallbacks.MC_POST_EFFECT_UPDATE, mod.OnAvatarUpdate, AVATAR)

function mod:OnPreBomb(type, variant, subtype, position, velocity, spawner, seed)
    if type ~= EntityType.ENTITY_BOMB or variant ~= BombVariant.BOMB_NORMAL then return end
    local state = peek(ownerOf(spawner))
    if state and state.form then return { type, BombVariant.BOMB_BUTT, subtype, seed } end
end
mod:AddCallback(ModCallbacks.MC_PRE_ENTITY_SPAWN, mod.OnPreBomb)

function mod:OnBombUpdate(bomb)
    local state = peek(ownerOf(bomb))
    if state and state.form then bomb:AddTearFlags(TearFlags.TEAR_BUTT_BOMB) end
end
mod:AddCallback(ModCallbacks.MC_POST_BOMB_UPDATE, mod.OnBombUpdate)

-- Native multishot knives/lasers can be parented to the primary weapon.
-- Follow only the same weapon type; fetal/familiar attacks stay independent.
local function weaponOwner(entity)
    local kind = entity.Type
    for _ = 1, 8 do
        local parent = entity.Parent
        if not parent or parent == entity then return end
        local player = parent:ToPlayer()
        if player then return player end
        local data = parent:GetData().PoopBossWeapon
        if parent.Type ~= kind or (data and data.copy) then return end
        entity = parent
    end
end

function mod:OnKnifeUpdate(knife)
    weapons.updateKnife(knife)
    local player = weaponOwner(knife)
    local state = peek(player)
    if state and state.form and not state.dash and active(player)
        and weapons.expandKnife(knife, player, forms[state.form]) then countNativeVolley(player, state) end
end
mod:AddCallback(ModCallbacks.MC_POST_KNIFE_UPDATE, mod.OnKnifeUpdate)

function mod:OnTearFired(tear)
    weapons.observeTearFired(tear)
end
mod:AddCallback(ModCallbacks.MC_POST_FIRE_TEAR, mod.OnTearFired)

function mod:OnTearUpdate(tear)
    local player = tear.Parent and tear.Parent:ToPlayer()
    local state = peek(player)
    if state and state.form and not state.dash and active(player)
        and weapons.expandTear(tear, player, state, forms[state.form]) then countNativeVolley(player, state) end
end
mod:AddCallback(ModCallbacks.MC_POST_TEAR_UPDATE, mod.OnTearUpdate)

function mod:OnLaserUpdate(laser)
    local player = weaponOwner(laser)
    local state = peek(player)
    if state and state.form and not state.dash and active(player)
        and weapons.expandLaser(laser, player, forms[state.form]) then countNativeVolley(player, state) end
end
mod:AddCallback(ModCallbacks.MC_POST_LASER_UPDATE, mod.OnLaserUpdate)

function mod:OnDamage(entity, _, flags)
    local state = peek(entity:ToPlayer())
    if state and state.form and (flags & DamageFlag.DAMAGE_POOP) ~= 0 then return false end
end
mod:AddCallback(ModCallbacks.MC_ENTITY_TAKE_DMG, mod.OnDamage, EntityType.ENTITY_PLAYER)

local icons = {}
for index, form in ipairs(forms) do
    local sprite = Sprite()
    sprite:Load("gfx/poop_boss_forms/" .. form.skin .. ".anm2", true)
    sprite:SetFrame("Idle", 0)
    sprite.Scale = Vector(0.32, 0.32)
    icons[index] = sprite
end

function mod:OnRender()
    if not started or not game:GetHUD():IsVisible() then return end
    local row = 0
    local offset = Options.HUDOffset
    -- Fixed HUD coordinates beside the coin counter; camera/room/player
    -- movement must not affect them. Extra players get separate rows.
    local origin = Vector(62 + 20 * offset, 48 + 12 * offset)
    eachPlayer(function(player)
        local state = peek(player)
        if not state or not alive(player) then return end
        if not ownsPoop(player) then return end
        for index, sprite in ipairs(icons) do
            local chosen = index == state.selected
            sprite.Color = chosen and Color(1, 1, 1, 1) or Color(0.55, 0.55, 0.55, 0.65)
            sprite:Render(origin + Vector((index - 1) * 21, row * 20 + (chosen and -2 or 0)))
        end
        row = row + 1
    end)
end
mod:AddCallback(ModCallbacks.MC_POST_RENDER, mod.OnRender)

function mod:OnNewRoom()
    for _, state in pairs(runtime) do
        if state.player:Exists() then
            if state.dash then finishDash(state.player, state) end
            if state.avatar and state.avatar:Exists() then state.avatar:Remove() end
            state.avatar, state.avatarForm = nil, nil
            state.dropFrames = 0
            if state.form then updateAvatar(state.player, state) end
        end
    end
    save()
end
mod:AddCallback(ModCallbacks.MC_POST_NEW_ROOM, mod.OnNewRoom)

function mod:OnStarted(continued)
    for _, state in pairs(runtime) do
        if state.player:Exists() then showPlayer(state.player, state) end
        if state.avatar and state.avatar:Exists() then state.avatar:Remove() end
    end
    runtime, saved = {}, {}
    started = true
    if continued and mod:HasData() then
        local ok, data = pcall(json.decode, mod:LoadData())
        if ok and type(data) == "table" and (data.version == 1 or data.version == 2) and data.seed == game:GetSeeds():GetStartSeed()
            and type(data.players) == "table" then saved = data.players end
    end
    eachPlayer(function(player)
        local state = stateFor(player)
        if state.form then installPocket(player, state) end
    end)
    if not continued then save() end
end
mod:AddCallback(ModCallbacks.MC_POST_GAME_STARTED, mod.OnStarted)

function mod:OnExit(shouldSave)
    if shouldSave then save() else mod:SaveData("{}") end
    for _, state in pairs(runtime) do
        if state.player:Exists() then showPlayer(state.player, state) end
    end
    started = false
end
mod:AddCallback(ModCallbacks.MC_PRE_GAME_EXIT, mod.OnExit)

function mod:OnCommand(command, parameters)
    if command ~= "poopboss" or not started then return end
    local player = Isaac.GetPlayer(0)
    if parameters == "test" then
        player:AddCollectible(POOP, 1, false)
        Isaac.ConsoleOutput("Poop Boss Forms: The Poop is ready. Tap Ctrl to choose and switch pocket items; Space to transform; Q to use the selected pocket item.\n")
    elseif parameters == "charge" then
        for slot = ActiveSlot.SLOT_PRIMARY, ActiveSlot.SLOT_POCKET2 do
            if player:GetActiveItem(slot) == POOP or player:GetActiveItem(slot) == DASH then player:SetActiveCharge(1, slot) end
        end
    else
        Isaac.ConsoleOutput("poopboss test: give charged The Poop. poopboss charge: charge Poop/Rush.\n")
    end
end
mod:AddCallback(ModCallbacks.MC_EXECUTE_CMD, mod.OnCommand)

Isaac.DebugString(string.format("[Poop Boss Forms] v1.2 loaded; dash=%d, avatar=%d; four forms; no REPENTOGON required.", DASH, AVATAR))
