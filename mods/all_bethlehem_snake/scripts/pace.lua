-- Use the LAST logical star for Bethlehem's ahead/behind speed tiers.
-- Native J460 compares floor-route costs: 3 per room, 1 between cells of
-- the same large room. Adjacent occupied map cells form its route graph.
local pace = {}

function pace.costs(cells, goal)
    local costs = {}
    if cells[goal] == nil then return costs end
    local queue, first = { goal }, 1
    costs[goal] = 0
    while first <= #queue do
        local index = queue[first]
        first = first + 1
        local x, y = index % 13, math.floor(index / 13)
        local function visit(nextIndex)
            if cells[nextIndex] == nil then return end
            local cost = costs[index] + (cells[index] == cells[nextIndex] and 1 or 3)
            if costs[nextIndex] == nil or cost < costs[nextIndex] then
                costs[nextIndex] = cost
                queue[#queue + 1] = nextIndex
            end
        end
        if x > 0 then visit(index - 1) end
        if x < 12 then visit(index + 1) end
        if y > 0 then visit(index - 13) end
        if y < 12 then visit(index + 13) end
    end
    return costs
end

function pace.map(level, previous)
    local rooms = level:GetRooms()
    local bossIndex = level:GetLastBossRoomListIndex()
    if previous and previous.Size == rooms.Size and previous.Boss == bossIndex then return previous end
    local cells = {}
    for index = 0, 168 do
        local desc = level:GetRoomByIdx(index, 0)
        if desc.Data then cells[index] = desc.ListIndex end
    end
    local boss = bossIndex >= 0 and bossIndex < rooms.Size and rooms:Get(bossIndex)
    -- SafeGridIndex is inside L-shaped rooms; GridIndex can be their empty corner.
    local goal = boss and boss.Data and boss.SafeGridIndex
    return { Size = rooms.Size, Boss = bossIndex, Cells = cells,
        Costs = goal and pace.costs(cells, goal) or {} }
end

function pace.cell(world)
    local x = math.floor(world.X / 520 + 0.5)
    local y = math.floor(world.Y / 280 + 0.5)
    if x < 0 or x > 12 or y < 0 or y > 12 then return nil end
    return y * 13 + x
end

function pace.speed(world, map, playerIndex, mainDimension, inPlayerRoom)
    if not mainDimension then return 0.25 end
    if inPlayerRoom or playerIndex < 0 then return 1 end
    local index = pace.cell(world)
    if not index then return 1 end
    if map.Cells[index] ~= nil and map.Cells[index] == map.Cells[playerIndex] then return 1 end
    local starCost, playerCost = map.Costs[index], map.Costs[playerIndex]
    -- No comparable path (special/isolated rooms): keep moving at normal pace.
    if starCost == nil or playerCost == nil then return 1 end
    if starCost + 9 < playerCost then return 0.25 end
    if starCost < playerCost then return 0.5 end
    if starCost > playerCost + 9 then return 8 end
    if starCost > playerCost then return 4 end
    return 1
end

return pace
