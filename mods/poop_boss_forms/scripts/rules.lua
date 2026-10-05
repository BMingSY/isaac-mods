-- Pure geometry/balance functions, also used by the regression harness.
local rules = {}

function rules.clamp(value, low, high)
    return math.max(low, math.min(high, value))
end

function rules.interval(maxFireDelay, multiplier)
    return math.max(8, math.floor((maxFireDelay + 1) * multiplier + 0.5))
end

function rules.dashDamage(damage, count)
    -- A complete combo hitting the same enemy once per dash totals 25x + 10.
    return (25 * damage + 10) / count
end

function rules.segmentDistanceSquared(px, py, ax, ay, bx, by)
    local dx, dy = bx - ax, by - ay
    local length = dx * dx + dy * dy
    local t = length > 0 and rules.clamp(((px - ax) * dx + (py - ay) * dy) / length, 0, 1) or 0
    local x, y = px - ax - dx * t, py - ay - dy * t
    return x * x + y * y
end

function rules.touchingPoop(px, py, gx, gy, radius)
    local x, y = math.max(0, math.abs(px - gx) - 20), math.max(0, math.abs(py - gy) - 20)
    return x * x + y * y <= (radius + 3) ^ 2
end

function rules.validForm(value, count)
    return type(value) == "number" and value == math.floor(value) and value >= 1 and value <= count
end

return rules
