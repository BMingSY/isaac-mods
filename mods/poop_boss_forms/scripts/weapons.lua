-- The engine owns input, charging, multishot and the original weapon. Add the
-- boss pattern to each actual shot, preserving its rolled damage and effects.
local weapons = {}
local KEY, WEAPON_KEY = "PoopBossForms", "PoopBossWeapon"
local creatingCopy = false

local function mark(shot, kind, player, copy)
    shot:GetData()[KEY] = true
    shot:GetData()[WEAPON_KEY] = { kind = kind, player = player, copy = copy }
end

local function eachExtraAngle(form, fn)
    if form.shots == 8 then for i = 1, 7 do fn(i * 45) end
    else fn(-13); fn(13) end
end

function weapons.observeTearFired(tear)
    if not creatingCopy then tear:GetData().PoopBossPrimaryTear = true end
end

function weapons.expandTear(tear, player, state, form)
    if creatingCopy or tear:GetData()[WEAPON_KEY] or tear.FrameCount ~= 1 then return false end
    if player:HasWeaponType(WeaponType.WEAPON_FETUS) and tear.Variant ~= TearVariant.FETUS then return false end
    if player:HasWeaponType(WeaponType.WEAPON_LUDOVICO_TECHNIQUE) then return false end
    local sword = player:HasWeaponType(WeaponType.WEAPON_SPIRIT_SWORD)
    -- Split offspring are also parented/spawned by the player, but do not
    -- receive POST_FIRE_TEAR. Native sword beams use a separate firing path.
    if not tear:GetData().PoopBossPrimaryTear and not (sword and tear.Variant == TearVariant.SWORD_BEAM) then return false end
    mark(tear, "tear", player)
    eachExtraAngle(form, function(angle)
        -- FireTear invokes update callbacks synchronously before returning.
        creatingCopy = true
        local extra = player:FireTear(tear.Position, tear.Velocity:Rotated(angle), false, false, false, player, 1)
        creatingCopy = false
        if extra then
            mark(extra, "tear", player, true)
            extra:ChangeVariant(tear.Variant)
            extra.TearFlags, extra.CollisionDamage = tear.TearFlags, tear.CollisionDamage
            extra.Scale, extra.Color = tear.Scale, tear.Color
            extra.Height, extra.FallingSpeed, extra.FallingAcceleration = tear.Height, tear.FallingSpeed, tear.FallingAcceleration
        end
    end)
    return not sword
end

function weapons.expandLaser(laser, player, form)
    local data = laser:GetData()[WEAPON_KEY]
    if data and data.original then
        if data.original:Exists() then
            laser.AngleDegrees = data.original.AngleDegrees + data.angle
        end
        return false
    end
    if creatingCopy or data or laser.FrameCount ~= 1 then return false end
    -- Only primary player weapons: exclude Maw rings, reflected beams, fetus
    -- lasers and effects belonging to other entities.
    local ring = laser:IsCircleLaser()
    if ring and (laser.SubType ~= 2 or not player:HasWeaponType(WeaponType.WEAPON_TECH_X)) then return false end
    if not ring and not player:HasWeaponType(WeaponType.WEAPON_BRIMSTONE)
        and not player:HasWeaponType(WeaponType.WEAPON_LASER) then return false end
    if laser.DisableFollowParent and laser.Parent and laser.Parent.Type == EntityType.ENTITY_LASER then return false end
    mark(laser, "laser", player)
    eachExtraAngle(form, function(angle)
        creatingCopy = true
        local extra
        if ring then
            extra = player:FireTechXLaser(laser.Position, laser.Velocity:Rotated(angle), laser.Radius, player, 1)
        else
            extra = EntityLaser.ShootAngle(laser.Variant, laser.Position, laser.AngleDegrees + angle,
                laser.Timeout, laser.PositionOffset, player)
        end
        creatingCopy = false
        if extra then
            mark(extra, "laser", player, true)
            if not ring then
                local copy = extra:GetData()[WEAPON_KEY]
                copy.original, copy.angle = laser, angle
            end
            extra.TearFlags, extra.CollisionDamage = laser.TearFlags, laser.CollisionDamage
            extra.Color, extra.Size = laser.Color, laser.Size
            extra.SpriteScale = laser.SpriteScale
            extra.ParentOffset = laser.ParentOffset
            extra.DisableFollowParent = laser.DisableFollowParent
            extra:SetMaxDistance(laser.MaxDistance)
            extra:SetOneHit(laser.OneHit)
        end
    end)
    return true
end

function weapons.expandKnife(knife, player, form)
    if creatingCopy then return false end
    local data = knife:GetData()
    if data[WEAPON_KEY] then return false end
    if player:HasWeaponType(WeaponType.WEAPON_SPIRIT_SWORD) then
        -- Keep the native sword hitbox/spin; duplicate its emitted beams only.
        if knife.FrameCount ~= 1 or knife.SubType ~= 4 or (knife.Variant ~= 10 and knife.Variant ~= 11) then return false end
        mark(knife, "sword", player)
        return true
    end
    if not player:HasWeaponType(WeaponType.WEAPON_KNIFE) or knife.Variant ~= 0 then return false end
    local flying = knife:IsFlying()
    local started = flying and not data.PoopBossWasFlying
    data.PoopBossWasFlying = flying
    if not started then return false end
    eachExtraAngle(form, function(angle)
        creatingCopy = true
        local extra = player:FireKnife(player, 0, true, 0, 0)
        if extra then
            mark(extra, "knife", player, true)
            extra.Rotation = knife.Rotation + knife.RotationOffset + angle
            extra.Position = knife.Position
            extra:Shoot(math.max(0.05, knife.Charge), player.TearRange)
            extra.MaxDistance = knife.MaxDistance
            extra.TearFlags, extra.CollisionDamage = knife.TearFlags, knife.CollisionDamage
            extra.Scale, extra.Color = knife.Scale, knife.Color
        end
        creatingCopy = false
    end)
    return true
end

function weapons.updateKnife(knife)
    local data = knife:GetData()[WEAPON_KEY]
    if not data or data.kind ~= "knife" or not data.copy then return end
    if not data.player:Exists() or data.player:IsDead() or not knife:IsFlying() then knife:Remove() end
end

return weapons
