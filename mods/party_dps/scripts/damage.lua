-- Vanilla buffers accepted damage and changes HP on the following NPC frame.
-- Keep one bounded batch per target until that HP loss becomes visible.
local Damage = {}
Damage.__index = Damage

function Damage.new(meter)
    return setmetatable({ meter = meter, pending = {} }, Damage)
end

function Damage:flush(hash)
    local hit = self.pending[hash]
    if not hit then
        return
    end
    local target = hit.target
    -- Removed entities have no readable HP; do not invent a successful hit.
    if not target:Exists() then
        self.pending[hash] = nil
        return
    end
    local remaining = math.max(0, target.HitPoints)
    local lost = math.max(0, hit.before - remaining)
    if lost > 0 then
        self.pending[hash] = nil
        -- Shared damage buffers expose only the final loss. Divide it using the
        -- accepted callback amounts, including unowned/environmental sources.
        for owner, source in pairs(hit.sources) do
            if owner ~= 0 then
                self.meter:add(owner, lost * source.amount / hit.amount, source.at)
            end
        end
    elseif target.FrameCount - hit.frame > 1 then
        self.pending[hash] = nil
    end
end

function Damage:flushAll()
    local hashes = {}
    for hash in pairs(self.pending) do
        hashes[#hashes + 1] = hash
    end
    for _, hash in ipairs(hashes) do
        self:flush(hash)
    end
end

function Damage:begin(target, owner, amount)
    local hash = GetPtrHash(target)
    self:flush(hash)
    if
        target.HitPoints <= 0
        or type(amount) ~= "number"
        or amount <= 0
        or amount ~= amount
        or amount == math.huge
    then
        return
    end
    local hit = self.pending[hash]
    if not hit then
        hit = {
            target = target,
            before = target.HitPoints,
            frame = target.FrameCount,
            amount = 0,
            sources = {},
        }
        self.pending[hash] = hit
    end
    owner = owner or 0
    local source = hit.sources[owner] or { amount = 0, at = self.meter.now }
    hit.sources[owner] = source
    source.amount, hit.amount = source.amount + amount, hit.amount + amount
end

return Damage
