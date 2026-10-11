-- Pure accounting. Time is measured in active 30 Hz simulation ticks.
local Meter = {}
Meter.__index = Meter
local FPS, WINDOW, LIMIT = 30, 150, 1e15

local function number(value)
    return type(value) == "number" and value == value and value >= 0 and value <= LIMIT
end

function Meter.new()
    return setmetatable({ now = 0, rows = {}, closed = 0, active = false }, Meter)
end

function Meter:advance(tick)
    if not number(tick) then
        return
    end
    if self.tick and tick > self.tick then
        self.now = self.now + tick - self.tick
    end
    self.tick = tick
    if self.active and self.now - self.last >= WINDOW then
        self:finish()
    end
end

function Meter:ensure(owner, name)
    if not number(owner) or owner < 1 or owner > 4 or owner % 1 ~= 0 then
        return
    end
    local row = self.rows[owner]
    if not row then
        row = { owner = owner, name = "Player", encounter = 0, total = 0, buckets = {} }
        self.rows[owner] = row
    end
    if type(name) == "string" then
        -- The bundled vanilla HUD font supports these characters on both DLCs.
        local label = name:gsub("[^%w +%-]", ""):sub(1, 20)
        if label ~= "" then
            row.name = label
        end
    end
    return row
end

function Meter:duration()
    if not self.start then
        return 0
    end
    local stop = self.active and self.now or self.last
    return math.max(1, stop - self.start + 1)
end

function Meter:finish()
    if self.active then
        self.active = false
        self.closed = self.closed + self:duration()
    end
end

function Meter:add(owner, amount, at)
    if not number(amount) or amount <= 0 then
        return
    end
    local row = self:ensure(owner)
    if not row then
        return
    end
    at = number(at) and math.min(at, self.now) or self.now
    if not self.active then
        for _, item in pairs(self.rows) do
            item.encounter = 0
        end
        self.start, self.active = at, true
    end
    self.last = math.max(at, self.last or at)
    row.encounter = math.min(LIMIT, row.encounter + amount)
    row.total = math.min(LIMIT, row.total + amount)
    local slot = at % WINDOW
    local bucket = row.buckets[slot]
    if not bucket or bucket.at ~= at then
        bucket = { at = at, amount = 0 }
        row.buckets[slot] = bucket
    end
    bucket.amount = math.min(LIMIT, bucket.amount + amount)
end

function Meter:snapshot()
    local result = {
        active = self.active,
        duration = self:duration(),
        combat = self.closed + (self.active and self:duration() or 0),
        rows = {},
    }
    for owner = 1, 4 do
        local row = self.rows[owner]
        if row then
            local recent = 0
            for _, bucket in pairs(row.buckets) do
                if self.now - bucket.at < WINDOW then
                    recent = recent + bucket.amount
                end
            end
            result.rows[#result.rows + 1] = {
                owner = owner,
                name = row.name,
                encounter = row.encounter,
                total = row.total,
                recent = recent,
            }
        end
    end
    return result
end

function Meter.view(snapshot, mode)
    local rows, total = {}, 0
    local frames = mode == "run" and snapshot.combat or snapshot.duration
    for _, item in ipairs(snapshot.rows) do
        local damage = mode == "run" and item.total or item.encounter
        total = total + damage
        rows[#rows + 1] = {
            owner = item.owner,
            name = item.name,
            damage = damage,
            dps = damage / math.max(1, frames / FPS),
            recent = item.recent / 5,
        }
    end
    table.sort(rows, function(a, b)
        if a.damage ~= b.damage then
            return a.damage > b.damage
        end
        return a.owner < b.owner
    end)
    for _, row in ipairs(rows) do
        row.percent = total > 0 and row.damage / total * 100 or 0
    end
    return {
        rows = rows,
        total = total,
        seconds = frames / FPS,
        dps = total / math.max(1, frames / FPS),
        active = snapshot.active,
    }
end

function Meter:save()
    self:finish()
    return self:snapshot()
end

function Meter.restore(saved)
    local meter = Meter.new()
    if
        type(saved) ~= "table"
        or not number(saved.combat)
        or not number(saved.duration)
        or type(saved.rows) ~= "table"
    then
        return meter
    end
    meter.closed = saved.combat
    for _, item in ipairs(saved.rows) do
        if type(item) == "table" and number(item.total) and number(item.encounter) then
            local row = meter:ensure(item.owner, item.name)
            if row then
                row.total, row.encounter = item.total, item.encounter
            end
        end
    end
    if saved.duration > 0 then
        meter.start, meter.last = -saved.duration + 1, 0
    end
    return meter
end

-- API v1 action results carry a bounded string. A read-only snapshot action uses
-- that documented return field; no private LAN globals or network hooks.
function Meter.encode(snapshot)
    local parts = {
        "D1",
        snapshot.active and "1" or "0",
        string.format("%.0f", snapshot.duration),
        string.format("%.0f", snapshot.combat),
    }
    for _, row in ipairs(snapshot.rows) do
        parts[#parts + 1] = string.format(
            "%d,%s,%.3f,%.3f,%.3f",
            row.owner,
            row.name,
            row.encounter,
            row.total,
            row.recent
        )
    end
    local bytes = table.concat(parts, ";")
    assert(#bytes <= 512, "DPS snapshot exceeds the LAN API string limit")
    return bytes
end

function Meter.decode(bytes)
    if type(bytes) ~= "string" or #bytes > 512 then
        return
    end
    local parts = {}
    for part in (bytes .. ";"):gmatch("(.-);") do
        parts[#parts + 1] = part
    end
    if parts[1] ~= "D1" or (parts[2] ~= "0" and parts[2] ~= "1") or #parts < 4 or #parts > 8 then
        return
    end
    local duration, combat = tonumber(parts[3]), tonumber(parts[4])
    if not number(duration) or not number(combat) or duration > combat then
        return
    end
    local result, seen =
        { active = parts[2] == "1", duration = duration, combat = combat, rows = {} }, {}
    for i = 5, #parts do
        local owner, name, encounter, total, recent =
            parts[i]:match("^(%d),([%w +%-]+),([%d.]+),([%d.]+),([%d.]+)$")
        owner, encounter, total, recent =
            tonumber(owner), tonumber(encounter), tonumber(total), tonumber(recent)
        if
            not owner
            or owner < 1
            or owner > 4
            or seen[owner]
            or #name > 20
            or not number(encounter)
            or not number(total)
            or not number(recent)
            or encounter > total
        then
            return
        end
        seen[owner] = true
        result.rows[#result.rows + 1] = {
            owner = owner,
            name = name,
            encounter = encounter,
            total = total,
            recent = recent,
        }
    end
    return result
end

return Meter
