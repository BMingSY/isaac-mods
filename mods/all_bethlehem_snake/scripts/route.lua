-- Bethlehem's route is stored in FLOOR coordinates, not Entity.Position.
-- Repentance+ J460 reuses these public EntityFamiliar fields:
-- Coins = destination room index; Hearts = packed fractional destination;
-- OrbitAngleOffset = movement speed; OrbitSpeed = special-room fade progress.
-- Verified against the local game's Lua bindings and native Bethlehem AI.
-- Only OrbitAngleOffset is adjusted by the queue's pace controller. Native
-- destinations and portal state remain under the original guide's control.
local route = { WIDTH = 520, HEIGHT = 280 }

function route.copy(p) return { X = p.X, Y = p.Y } end

function route.distance(a, b)
    return math.sqrt((a.X - b.X)^2 + (a.Y - b.Y)^2)
end

function route.step(current, target, speed)
    local length = route.distance(current, target)
    if length <= speed or length < 0.00001 then return route.copy(target) end
    return { X = current.X + (target.X - current.X) * speed / length,
        Y = current.Y + (target.Y - current.Y) * speed / length }
end

function route.roomIndex(index)
    return index < 0 and 168 - index or index
end

function route.offset(index)
    index = route.roomIndex(index)
    return { X = (index % 13) * route.WIDTH - 320,
        Y = math.floor(index / 13) * route.HEIGHT - 280 }
end

function route.toWorld(position, offset)
    return { X = position.X + offset.X, Y = position.Y + offset.Y }
end

function route.toRoom(position, offset)
    return { X = position.X - offset.X, Y = position.Y - offset.Y }
end

function route.destination(star)
    if star.Coins < 0 then return nil end
    local packed = star.Hearts & 0xffffffff
    local x = ((packed & 0xffff) - 32768) / 65536
    local y = (((packed >> 16) & 0xffff) - 32768) / 65536
    return { X = (star.Coins % 13 + x) * route.WIDTH,
        Y = (math.floor(star.Coins / 13) + y) * route.HEIGHT }
end

function route.observe(model, star, offset, frame, canObserve)
    if model and model.Frame == frame then return model end
    local destination = route.destination(star)
    local phase = star.OrbitSpeed
    local observed = { X = star.Position.X + star.Velocity.X,
        Y = star.Position.Y + star.Velocity.Y }
    if not model then
        -- On an old save there is no reliable position for a hidden guide.
        -- Wait to observe it rather than interpreting its stale room position.
        if not star.Visible or not canObserve(observed) then return nil end
        model = { World = route.toWorld(observed, offset) }
    elseif destination then
        if phase < 0 and (model.Phase or 0) >= 0 then
            -- The ORIGINAL star crossed its native special-room portal.
            model.World = route.copy(destination)
        elseif phase == 0 then
            model.World = route.step(model.World, destination, model.Speed or 1)
        end
    end
    if star.Visible and phase == 0 and canObserve(observed) then
        local measured = route.toWorld(observed, offset)
        -- An engine relocation/stale sample must not shift a floor route by
        -- an entire room. Native movement here is continuous; its portal case
        -- is handled explicitly above. Accept only a small position correction.
        if route.distance(model.World, measured) <= math.max(12, (model.Speed or 1) * 2 + 2) then
            model.World = measured
        end
    end
    model.Speed, model.Phase, model.Frame = star.OrbitAngleOffset, phase, frame
    return model
end

-- Critically, arrival never enables a direct snap-to-target branch. The same
-- bounded movement runs before and after joining, including a stopped guide.
function route.follow(node, target, targetSpeed)
    local gap = route.distance(node.World, target)
    local moving = math.max(0, math.min(8, targetSpeed))
    -- Leave catch-up headroom when the native guide uses its 4/8 speed tiers.
    local limit = math.max(3, moving + 2)
    local wanted = math.min(limit, moving + gap * 0.055)
    if gap < 0.05 then wanted = 0 end
    local old = node.Speed or 0
    local acceleration, deceleration = math.max(0.08, moving * 0.08), math.max(0.12, moving * 0.12)
    node.Speed = math.max(0, math.min(old + acceleration, math.max(old - deceleration, wanted)))
    node.World = route.step(node.World, target, math.min(gap, node.Speed))
end

return route
