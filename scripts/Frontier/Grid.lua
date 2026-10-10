local C = require "Frontier.Config"

---@class FrontierCell
---@field building number
---@field trail number
---@field wear number

---@class FrontierBuilding
---@field id number
---@field kind string
---@field x number
---@field y number
---@field timer number
---@field stock number
---@field shot number

---@class FrontierGrid
---@field cells FrontierCell[][]
---@field buildings FrontierBuilding[]
---@field version number
---@field nextId number
local Grid = {}
Grid.__index = Grid
setmetatable(Grid, { __call = function() return Grid.New() end })

---@return FrontierGrid
function Grid.New()
    local self = setmetatable({}, Grid) --[[@as FrontierGrid]]
    self:Init()
    return self
end

function Grid:Init()
    self.cells = {} ---@type FrontierCell[][]
    self.buildings = {} ---@type FrontierBuilding[]
    self.version = 1
    self.nextId = 1
    -- 地图不再生成岩石，也没有任何铺设/清除操作：所有格子初始都是荒野，
    -- 唯一会改变通行条件的是建筑占地，以及部队踩踏累积出来的道路等级。
    for y = 1, C.rows do
        self.cells[y] = {}
        for x = 1, C.cols do
            local cell = { building = 0, trail = 0, wear = 0 } --[[@as FrontierCell]]
            if x == C.wallCol and not self:IsGateRow(y) then cell.building = -1 end
            self.cells[y][x] = cell
        end
    end
    print("[地图] 无岩石空旷战场，通路全部由部队踩踏形成")
    self:AddBuilding("barracks", 2, 5)
end

function Grid:IsGateRow(y)
    return y >= C.gateTop and y < C.gateTop + C.gateWidth
end

function Grid:Get(x, y)
    if x < 1 or x > C.cols or y < 1 or y > C.rows then return nil end
    return self.cells[y][x]
end

function Grid:IsWalkable(x, y)
    local cell = self:Get(x, y)
    if not cell then return false end
    -- 城墙用 building = -1 标记：它不是建筑，也不可通行。
    if x == C.wallCol and not self:IsGateRow(y) then return false end
    return cell.building == 0
end

function Grid:Footprint(x, y, size)
    for dy = 0, size - 1 do
        for dx = 0, size - 1 do
            if not self:IsWalkable(x + dx, y + dy) then return false end
        end
    end
    return true
end

-- 踩踏等级：0 荒野 … 4 加速通道。没有科技封顶，走得够多就能一路升到加速通道。
-- 传入的是世界坐标，必须取整后才能索引格子。
function Grid:TrailLevel(x, y)
    local cell = self:Get(math.floor(x + 0.5), math.floor(y + 0.5))
    if not cell then return 0 end
    return cell.trail
end

-- 己方单位经过时累积踩踏，走得越多路面越好。
function Grid:Trample(x, y, amount)
    local cell = self:Get(math.floor(x + 0.5), math.floor(y + 0.5))
    if not cell or cell.building ~= 0 then return end
    local before = cell.trail
    cell.wear = cell.wear + (amount or 1)
    local level = 0
    for i = 1, 4 do if cell.wear >= C.trailThresholds[i] then level = i end end
    if level ~= before then
        cell.trail = level
        self.version = self.version + 1
    end
end

-- 大象需要 2×2 的「硬化路面」及以上；城门允许半跨，因为墙外禁止建造。
function Grid:LargeRoad(x, y)
    if x > C.wallCol then return true end
    for dy = 0, 1 do
        for dx = 0, 1 do
            if x + dx <= C.wallCol then
                local cell = self:Get(x + dx, y + dy)
                if not cell or cell.building ~= 0 then return false end
                if cell.trail < 3 then return false end
            end
        end
    end
    return true
end

function Grid:CanPlace(kind, x, y)
    local def = C.buildings[kind]
    if not def then return false, "未知建筑" end
    if kind == "tower" then
        local cell = self:Get(x, y)
        if x ~= C.wallCol or self:IsGateRow(y) or not cell or cell.building ~= -1 then
            return false, "箭塔只能建在城墙上，不能占用城门"
        end
        return true, "可建造"
    end
    if x < 1 or y < 1 or x + def.w - 1 >= C.wallCol or y + def.h - 1 > C.rows then
        return false, "只能建在城墙左侧的完整网格内"
    end
    for dy = 0, def.h - 1 do
        for dx = 0, def.w - 1 do
            local cell = self:Get(x + dx, y + dy)
            if not cell or cell.building ~= 0 then
                return false, "此格已被建筑占用"
            end
        end
    end
    return true, "可建造"
end

function Grid:AddBuilding(kind, x, y)
    local def = C.buildings[kind]
    local building = { id = self.nextId, kind = kind, x = x, y = y,
        timer = 0, stock = 0, shot = 0 }
    self.nextId = self.nextId + 1
    table.insert(self.buildings, building)
    for dy = 0, def.h - 1 do
        for dx = 0, def.w - 1 do
            self.cells[y + dy][x + dx].building = building.id
        end
    end
    self.version = self.version + 1
    return building
end

function Grid:FindBuilding(id)
    for _, b in ipairs(self.buildings) do if b.id == id then return b end end
    return nil
end

-- 建筑一旦落下就不能拆除：营地规划是单向决策。
-- 唯一的例外是「阻碍墙」的整条移除（供内部布局调整使用）。
function Grid:RemoveBuilding(id)
    for i, b in ipairs(self.buildings) do
        if b.id == id then
            local def = C.buildings[b.kind]
            for dy = 0, def.h - 1 do
                for dx = 0, def.w - 1 do self.cells[b.y + dy][b.x + dx].building = 0 end
            end
            table.remove(self.buildings, i)
            self.version = self.version + 1
            return def.cost
        end
    end
    return 0
end

-- 四邻域 A*：通行成本由踩踏等级决定（路越好越省代价），建筑为硬障碍。
-- 大体型节点以 2×2 左上角表示；优先寻找完整硬化路，无完整路才显示卡滞。
function Grid:Path(sx, sy, tx, ty, size, strictLarge)
    size = size or 1
    sx = math.max(1, math.min(C.cols - size + 1, math.floor(sx)))
    sy = math.max(1, math.min(C.rows - size + 1, math.floor(sy)))
    tx = math.max(1, math.min(C.cols - size + 1, math.floor(tx)))
    ty = math.max(1, math.min(C.rows - size + 1, math.floor(ty)))
    if not self:Footprint(sx, sy, size) or not self:Footprint(tx, ty, size) then return nil end
    local function key(x, y) return (y - 1) * C.cols + x end
    local start, goal = key(sx, sy), key(tx, ty)
    local open = { { x = sx, y = sy, k = start, f = 0 } }
    local costs, parent, closed = { [start] = 0 }, {}, {}
    local dirs = { { 1, 0 }, { 0, -1 }, { 0, 1 }, { -1, 0 } }
    for _ = 1, C.cols * C.rows * 3 do
        if #open == 0 then return nil end
        local best = 1
        for i = 2, #open do if open[i].f < open[best].f then best = i end end
        local n = table.remove(open, best)
        if n.k == goal then
            local path = {}
            local k = goal
            while k ~= start do
                local y = math.floor((k - 1) / C.cols) + 1
                local x = (k - 1) % C.cols + 1
                table.insert(path, 1, { x = x, y = y })
                k = parent[k]
                if not k then return nil end
            end
            return path
        end
        if not closed[n.k] then
            closed[n.k] = true
            for _, d in ipairs(dirs) do
                local x, y = n.x + d[1], n.y + d[2]
                if self:Footprint(x, y, size) and (not strictLarge or self:LargeRoad(x, y)) then
                    local k = key(x, y)
                    local step = C.trailCost[self:TrailLevel(x, y) + 1]
                    -- 营地内略向右偏置，返程与采集仍遵从实际目标方向。
                    if x < C.wallCol and tx > sx and d[1] < 0 then step = step + 0.35 end
                    if size == 2 and x < C.wallCol and not self:LargeRoad(x, y) then step = step + 2 end
                    local cost = costs[n.k] + step
                    if not closed[k] and (not costs[k] or cost < costs[k]) then
                        costs[k], parent[k] = cost, n.k
                        table.insert(open, { x = x, y = y, k = k,
                            f = cost + (math.abs(tx - x) + math.abs(ty - y)) * 0.5 })
                    end
                end
            end
        end
    end
    return nil
end

-- 营地内单位不走 A*，而是按"直线 + 横线"的最短 L 形折线走向城门。
-- 折线有两种走法：先横后竖（沿自己所在行前进，最后在城门附近并线），
-- 以及先竖后横（先并到城门行，再整条队伍挤过去）。
-- 略微偏好前者，让不同行的部队各自成列前进，只在城门口汇合，缓解拥堵。
-- 若折线被建筑挡住则返回 nil，由调用方回退到 A*。
function Grid:LCost(x1, y1, x2, y2)
    local cost = 0
    for x = math.min(x1, x2), math.max(x1, x2) do cost = cost + C.trailCost[self:TrailLevel(x, y1) + 1] end
    for y = math.min(y1, y2), math.max(y1, y2) do cost = cost + C.trailCost[self:TrailLevel(x2, y) + 1] end
    return cost
end

function Grid:LRoute(sx, sy, tx, ty)
    local hFirst = self:LCost(sx, sy, tx, sy) + self:LCost(tx, sy, tx, ty)
    local vFirst = self:LCost(sx, sy, sx, ty) + self:LCost(sx, ty, tx, ty)
    local horizontalFirst = hFirst <= vFirst + 1.2
    local cells, x, y = {}, sx, sy
    local function step(nx, ny)
        if not self:IsWalkable(nx, ny) then return false end
        x, y = nx, ny
        table.insert(cells, { x = x, y = y })
        return true
    end
    if horizontalFirst then
        while x ~= tx do if not step(x + (tx > x and 1 or -1), y) then return nil end end
        while y ~= ty do if not step(x, y + (ty > y and 1 or -1)) then return nil end end
    else
        while y ~= ty do if not step(x, y + (ty > y and 1 or -1)) then return nil end end
        while x ~= tx do if not step(x + (tx > x and 1 or -1), y) then return nil end end
    end
    return cells
end

function Grid:SpawnSpot(b, size)
    local def = C.buildings[b.kind]
    -- 从建筑出口附近的完整可通行占地寻找空间，不凭空挤出单位。
    local candidates = {}
    for y = b.y - size, b.y + def.h do
        for x = b.x - size, b.x + def.w do
            if self:Footprint(x, y, size) and x + size - 1 < C.wallCol then
                table.insert(candidates, { x = x, y = y,
                    score = math.abs(x - (b.x + def.w)) + math.abs(y - b.y) * 0.5 })
            end
        end
    end
    table.sort(candidates, function(a, z) return a.score < z.score end)
    return candidates
end
return Grid
