-- Weapon replacement for the boss volley. Native projectiles retain their
-- damage/flags; the mod supplies the boss pattern and charge/release timing.
local weapons = {}
local KEY, WEAPON_KEY = "PoopBossForms", "PoopBossWeapon"
local creatingNativeCopy = false
local chargeBar = Sprite()
chargeBar:Load("gfx/chargebar.anm2", true)

function weapons.kind(player)
    if player:HasWeaponType(WeaponType.WEAPON_FETUS) then return "fetus" end
    if player:HasWeaponType(WeaponType.WEAPON_SPIRIT_SWORD) then return "sword" end
    if player:HasWeaponType(WeaponType.WEAPON_KNIFE) then return "knife" end
    if player:HasWeaponType(WeaponType.WEAPON_TECH_X) then return "techx" end
    if player:HasWeaponType(WeaponType.WEAPON_BRIMSTONE) then return "brimstone" end
    if player:HasWeaponType(WeaponType.WEAPON_LASER) then return "technology" end
    for _, weaponType in ipairs({ WeaponType.WEAPON_BOMBS, WeaponType.WEAPON_ROCKETS,
        WeaponType.WEAPON_MONSTROS_LUNGS, WeaponType.WEAPON_LUDOVICO_TECHNIQUE, WeaponType.WEAPON_BONE,
        WeaponType.WEAPON_NOTCHED_AXE, WeaponType.WEAPON_URN_OF_SOULS, WeaponType.WEAPON_UMBILICAL_WHIP }) do
        if player:HasWeaponType(weaponType) then return "native" end
    end
    return "tears"
end

function weapons.native(kind)
    return kind == "fetus" or kind == "sword" or kind == "native"
end

function weapons.charged(kind)
    return kind == "brimstone" or kind == "knife" or kind == "techx"
end

function weapons.chargeFrames(player, kind, form)
    -- Brimstone's weapon penalty is already reflected in MaxFireDelay.
    local multiplier = kind == "brimstone" and 1 or kind == "knife" and 2 or 1.5
    return math.max(6, math.ceil((player.MaxFireDelay + 1) * multiplier * form.interval / 2.2))
end

function weapons.cancelCharge(state)
    state.weaponCharge, state.weaponChargeTarget, state.weaponAim = 0, nil, nil
end

local function knivesOut(state)
    local flying = {}
    for _, knife in ipairs(state.weaponKnives or {}) do
        if knife:Exists() and knife:IsFlying() then flying[#flying + 1] = knife end
    end
    state.weaponKnives = flying
    return #flying > 0
end

-- Return one requested volley; holding a charged weapon never fires tears.
function weapons.request(player, state, form, aim)
    local kind = weapons.kind(player)
    if state.weaponKind ~= kind then
        weapons.cancelCharge(state)
        state.weaponKind = kind
    end
    if weapons.native(kind) then return end
    local held = aim:LengthSquared() >= 0.04
    if not weapons.charged(kind) then
        if held and state.cooldown == 0 then return kind, 1, aim:Normalized() end
        return
    end
    if state.cooldown > 0 or (kind == "knife" and knivesOut(state)) then return end
    local target = weapons.chargeFrames(player, kind, form)
    state.weaponChargeTarget = target
    if held then
        state.weaponCharge = math.min(target, (state.weaponCharge or 0) + 1)
        state.weaponAim = aim:Normalized()
    elseif (state.weaponCharge or 0) > 0 then
        local charge = math.min(1, state.weaponCharge / target)
        local direction = state.weaponAim or state.lastAim
        weapons.cancelCharge(state)
        -- Brimstone needs a full charge; knives and rings permit a short throw.
        if kind ~= "brimstone" or charge >= 1 then return kind, charge, direction end
    end
end

local function mark(shot, kind, player)
    shot:GetData()[KEY] = true
    shot:GetData()[WEAPON_KEY] = { kind = kind, player = player }
end

local function eachExtraAngle(form, fn)
    if form.shots == 8 then for i = 1, 7 do fn(i * 45) end
    else fn(-13); fn(13) end
end

-- Expand the engine's actual fetus/beam, after its initialization is complete.
-- Copy the original flags (including fetus weapon synergies) and its rolled
-- damage instead of reimplementing the collectible combinations.
function weapons.expandTear(tear, player, state, form)
    if creatingNativeCopy or tear:GetData()[WEAPON_KEY] or tear.FrameCount ~= 1 then return false end
    local kind = weapons.kind(player)
    if not weapons.native(kind) then return false end
    if kind == "fetus" and tear.Variant ~= TearVariant.FETUS then return false end
    -- A floating Ludovico tear is controlled as a single native weapon.
    if player:HasWeaponType(WeaponType.WEAPON_LUDOVICO_TECHNIQUE) then return false end
    mark(tear, kind, player)
    eachExtraAngle(form, function(angle)
        -- FireTear invokes tear update callbacks before it returns the entity.
        creatingNativeCopy = true
        local extra = player:FireTear(tear.Position, tear.Velocity:Rotated(angle), false, false, false, player, 1)
        creatingNativeCopy = false
        if extra then
            mark(extra, kind, player)
            extra:ChangeVariant(tear.Variant)
            extra.TearFlags, extra.CollisionDamage = tear.TearFlags, tear.CollisionDamage
            extra.Scale, extra.Color = tear.Scale, tear.Color
            extra.Height, extra.FallingSpeed, extra.FallingAcceleration = tear.Height, tear.FallingSpeed, tear.FallingAcceleration
        end
    end)
    return kind ~= "sword" -- sword swings count once; their beams do not count again
end

-- Observe the native sword swing once. Its melee hitbox, charge/spin and
-- synergies remain native; the emitted sword beams receive the boss pattern.
function weapons.observeSword(knife, player)
    if knife:GetData()[WEAPON_KEY] or knife.FrameCount ~= 1 or knife.SubType ~= 4
        or (knife.Variant ~= 10 and knife.Variant ~= 11) or weapons.kind(player) ~= "sword" then return false end
    mark(knife, "sword", player)
    return true
end

function weapons.fire(player, state, form, aim, kind, charge)
    local count = 0
    for i = 1, form.shots do
        local offset = form.shots == 8 and (i - 1) * 45 or (i - 2) * 13
        local direction = aim:Rotated(offset)
        local shot
        if kind == "brimstone" then
            shot = player:FireBrimstone(direction, player, 1)
            if shot then shot.AngleDegrees = direction:GetAngleDegrees() end
        elseif kind == "knife" then
            -- RotationOffset is added to Rotation by the engine: use only one
            -- of them or the intended fan angle is doubled.
            shot = player:FireKnife(player, 0, true, 0, 0)
            if shot then
                shot.Rotation = direction:GetAngleDegrees()
                shot:Shoot(math.max(0.05, charge), player.TearRange)
                state.weaponKnives = state.weaponKnives or {}
                state.weaponKnives[#state.weaponKnives + 1] = shot
            end
        elseif kind == "technology" then
            shot = player:FireTechLaser(player.Position, LaserOffset.LASER_TECH1_OFFSET, direction, false, true, player, 1)
        elseif kind == "techx" then
            shot = player:FireTechXLaser(player.Position, direction * math.max(5, player.ShotSpeed * 10),
                20 + 60 * charge, player, 0.25 + 0.75 * charge)
        else
            shot = player:FireTear(player.Position + aim * 12, direction * math.max(5, player.ShotSpeed * 10),
                true, false, true, player, 1)
        end
        if shot then
            mark(shot, kind, player)
            count = count + 1
        end
    end
    return count
end

function weapons.updateKnife(knife)
    local data = knife:GetData()[WEAPON_KEY]
    if not data or data.kind ~= "knife" then return end
    -- CantOverwrite keeps the player's original knife intact. Remove only
    -- these additional thrown knives after they have completed their flight.
    if not data.player:Exists() or data.player:IsDead() or not knife:IsFlying() then knife:Remove() end
end

function weapons.renderCharge(player, state)
    if not Options.ChargeBars or (state.weaponCharge or 0) <= 0 or not state.weaponChargeTarget then return end
    local fraction = math.min(1, state.weaponCharge / state.weaponChargeTarget)
    if fraction >= 1 then chargeBar:SetFrame("Charged", Game():GetFrameCount() % 6)
    else chargeBar:SetFrame("Charging", math.floor(fraction * 100)) end
    chargeBar:Render(Isaac.WorldToScreen(player.Position) + Vector(18, -40) + player.SpriteOffset)
end

return weapons
