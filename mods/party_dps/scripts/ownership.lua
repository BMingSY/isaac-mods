local Ownership = {}
Ownership.__index = Ownership
function Ownership.new(identify, generation, clock)
    return setmetatable(
        { identify = identify, generation = generation, clock = clock, cache = {}, lastPrune = 0 },
        Ownership
    )
end

function Ownership:prune(now)
    if now - self.lastPrune < 150 then
        return
    end
    self.lastPrune = now
    for hash, entry in pairs(self.cache) do
        if now - entry.seen > 300 then
            self.cache[hash] = nil
        end
    end
end

function Ownership:resolve(entity)
    local visited = {}
    local function visit(current, depth)
        if not current or depth > 12 then
            return
        end
        local hash = GetPtrHash(current)
        if visited[hash] then
            return
        end
        visited[hash] = true
        if not current:Exists() then
            return
        end
        local cached = self.cache[hash]
        local now = self.clock and self.clock() or 0
        if cached and cached.seed == current.InitSeed then
            cached.seen = now
            return cached.owner
        end
        local owner
        local player = current:ToPlayer()
        if player then
            owner = self.identify(player)
        end
        if not owner then
            local familiar = current:ToFamiliar()
            if familiar then
                owner = visit(familiar.Player, depth + 1)
            end
        end
        owner = owner or visit(current.SpawnerEntity, depth + 1) or visit(current.Parent, depth + 1)
        if owner then
            self.cache[hash] = { owner = owner, seed = current.InitSeed, seen = now }
        end
        return owner
    end
    return visit(entity, 0)
end

return Ownership
