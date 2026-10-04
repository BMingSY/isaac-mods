-- Pure geometry: walk backwards along the head's trail and intersect each
-- successive circle. Arc-length offsets alone would bunch up at sharp turns.
local chain = {}
local EPSILON = 1e-7

local function point(p)
    return { X = p.X, Y = p.Y }
end

local function distance(a, b)
    local x, y = a.X - b.X, a.Y - b.Y
    return math.sqrt(x * x + y * y)
end

local function clamp(value, low, high)
    return math.max(low, math.min(high, value))
end

function chain.new(head, radius, bounds, backwards)
    local vertical = bounds.Right - bounds.Left < bounds.Bottom - bounds.Top
    local x, y = head.X, head.Y
    if vertical then x, y = y, x end
    local left = vertical and bounds.Top or bounds.Left
    local right = vertical and bounds.Bottom or bounds.Right
    local top = vertical and bounds.Left or bounds.Top
    local bottom = vertical and bounds.Right or bounds.Bottom
    local direction = backwards and (vertical and backwards.Y or backwards.X) or 0
    if math.abs(direction) < EPSILON then
        direction = x < (left + right) / 2 and 1 or -1
    end
    return {
        Points = { point(head) }, Radius = radius, Vertical = vertical,
        Left = left, Right = right, Top = top, Bottom = bottom,
        XDirection = direction >= 0 and 1 or -1,
        YDirection = y < (top + bottom) / 2 and 1 or -1,
        Horizontal = true,
    }
end

local function extend(trail)
    local last = trail.Points[#trail.Points]
    local x, y = last.X, last.Y
    if trail.Vertical then x, y = y, x end
    for _ = 1, 4 do
        local nextX, nextY = x, y
        if trail.Horizontal then
            nextX = trail.XDirection > 0 and trail.Right or trail.Left
            nextY = clamp(y, trail.Top, trail.Bottom)
            trail.Horizontal = false
        else
            nextY = clamp(y + trail.YDirection * trail.Radius * 1.25,
                trail.Top, trail.Bottom)
            if math.abs(nextY - y) < EPSILON then
                trail.YDirection = -trail.YDirection
                nextY = clamp(y + trail.YDirection * trail.Radius * 1.25,
                    trail.Top, trail.Bottom)
            end
            trail.XDirection = -trail.XDirection
            trail.Horizontal = true
        end
        if math.abs(nextX - x) + math.abs(nextY - y) > EPSILON then
            local result = trail.Vertical
                and { X = nextY, Y = nextX } or { X = nextX, Y = nextY }
            trail.Points[#trail.Points + 1] = result
            return
        end
    end
    -- Only reached in a zero-sized room; keep the math finite.
    trail.Points[#trail.Points + 1] = { X = last.X + trail.Radius, Y = last.Y }
end

function chain.push(trail, head)
    local points = trail.Points
    if distance(head, points[1]) < EPSILON then return end
    table.insert(points, 1, point(head))
    if #points >= 3 then
        local a, b, c = points[1], points[2], points[3]
        local ax, ay, bx, by = b.X - a.X, b.Y - a.Y, c.X - b.X, c.Y - b.Y
        -- Merge truly straight movement without erasing corners in the trail.
        if ax * bx + ay * by > 0
            and math.abs(ax * by - ay * bx) < EPSILON then
            table.remove(points, 2)
        end
    end
end

local function nextCenter(trail, center, segment, start)
    local radius = trail.Radius
    for _ = 1, #trail.Points + 32 do
        if segment >= #trail.Points then extend(trail) end
        local a, b = trail.Points[segment], trail.Points[segment + 1]
        local dx, dy, ox, oy = b.X - a.X, b.Y - a.Y, a.X - center.X, a.Y - center.Y
        local aa = dx * dx + dy * dy
        local bb = 2 * (ox * dx + oy * dy)
        local cc = ox * ox + oy * oy - radius * radius
        local discriminant = bb * bb - 4 * aa * cc
        if aa > EPSILON and discriminant >= -EPSILON then
            -- The positive root is the exit from the circle as we walk back.
            local t = (-bb + math.sqrt(math.max(0, discriminant))) / (2 * aa)
            if t >= start - EPSILON and t <= 1 + EPSILON then
                t = clamp(t, start, 1)
                return { X = a.X + dx * t, Y = a.Y + dy * t }, segment, t
            end
        end
        segment, start = segment + 1, 0
    end
    return { X = center.X - radius, Y = center.Y }, segment, 0
end

function chain.targets(trail, count)
    local targets = { point(trail.Points[1]) }
    local segment, start = 1, 0
    for i = 1, count do
        local target
        target, segment, start = nextCenter(trail, targets[#targets], segment, start)
        targets[#targets + 1] = target
    end
    -- Retain one extra turn beyond the tail; future pickups extend the tail
    -- instead of changing the route of the already attached stars.
    for i = #trail.Points, segment + 3, -1 do trail.Points[i] = nil end
    return targets
end

function chain.damage(raw, extraCopies)
    if raw <= 0 or raw >= 1e30 or extraCopies <= 0 then return raw end
    local exponent = math.min(extraCopies * math.log(1.2), math.log(1e30 / raw))
    return math.min(1e30, raw * math.exp(exponent))
end

function chain.fireDelay(raw, extraCopies)
    local minimum = 30 / 120 - 1
    if extraCopies <= 0 or raw <= minimum then return raw end
    return math.max(minimum, (raw + 1) * math.exp(-extraCopies * math.log(2.5)) - 1)
end

return chain
