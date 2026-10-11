local C = require "Frontier.Config"

---@class FrontierCell
---@field building number   -- 0 空 / -1 城墙 / >0 建筑 id
---@field solid boolean      -- 是否阻挡通行（非阻挡建筑如仓库为 false）
---@field trail number
---@field wear number
---@field resource number    -- 0 = 无资源点，否则为资源点 id
---@field lastUnit? number
---@field lastTime? number

---@class FrontierBuilding
---@field id number
---@field kind string
---@field x number
---@field y number
---@field timer number
---@field processed number
---@field shot number
---@field visualX? number
---@field visualY? number
---@field visualW? number
---@field visualH? number

---@class FrontierResource
---@field id number
---@field kind string
---@field cells table[]     -- {{x=,y=},...}
---@field stock number
---@field maxStock number
---@field slots number      -- 采集位总数
---@field reserved number   -- 已被农民预留的采集位数

---@class FrontierGrid
---@field cells FrontierCell[][]
---@field buildings FrontierBuilding[]
---@field resources FrontierResource[]
---@field version number
---@field nextId number
---@field nextResource number
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
    self.resources = {} ---@type FrontierResource[]
    self.version = 1
    self.nextId = 1
    self.nextResource = 1
    for y = 1, C.rows do
        self.cells[y] = {}
        for x = 1, C.cols do
            local cell = { building = 0, solid = false, trail = 0, wear = 0, resource = 0 } --[[@as FrontierCell]]
            if x == C.wallCol and not self:IsGateRow(y) then cell.building, cell.solid = -1, true end
            self.cells[y][x] = cell
        end
    end
    -- 开局固定建筑（V3.2 §6.1）：农民营左上、民兵营左侧中央。
    self:AddBuilding("farmerBarracks", 2, 2)
    self:AddBuilding("barracks", 2, 5)
    self:GenerateMap()
    print("[地图] 营地 "..C.campMinX.."-"..C.campMaxX.." 列，资源点 "..#self.resources.." 处")
end

function Grid:IsGateRow(y)
    return y >= C.gateTop and y < C.gateTop + C.gateWidth
end

function Grid:Get(x, y)
    if x < 1 or x > C.cols or y < 1 or y > C.rows then return nil end
    return self.cells[y][x]
end

-- 城墙用 building = -1 标记；资源点与阻挡建筑不可通行；仓库等非阻挡建筑可通行。
function Grid:IsWalkable(x, y)
    local cell = self:Get(x, y)
    if not cell then return false end
    if x == C.wallCol and not self:IsGateRow(y) then return false end
    if cell.resource ~= 0 then return false end
    return not cell.solid
end

function Grid:Footprint(x, y, size)
    for dy = 0, size - 1 do
        for dx = 0, size - 1 do
            if not self:IsWalkable(x + dx, y + dy) then return false end
        end
    end
    return true
end

-- 踩踏等级：0 荒野 … 4 加速通道。传入的是世界坐标，必须取整后才能索引格子。
function Grid:TrailLevel(x, y)
    local cell = self:Get(math.floor(x + 0.5), math.floor(y + 0.5))
    if not cell then return 0 end
    return cell.trail
end

-- 己方单位经过时累积踩踏，走得越多路面越好。
-- 同一单位在 trampleCooldown 秒内重复经过同一格只计 1 次，避免原地抖动刷道路。
---@param unitId number?
---@param time number?
function Grid:Trample(x, y, amount, unitId, time)
    local cell = self:Get(math.floor(x + 0.5), math.floor(y + 0.5))
    if not cell or cell.solid or cell.resource ~= 0 then return end
    if unitId and time and cell.lastUnit == unitId
        and (time - (cell.lastTime or -math.huge)) < C.trampleCooldown then
        return
    end
    cell.lastUnit, cell.lastTime = unitId, time
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
                if not cell or cell.solid or cell.resource ~= 0 then return false end
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
            if cell.resource ~= 0 then
                return false, "资源点上无法建造"
            end
        end
    end
    return true, "可建造"
end

function Grid:AddBuilding(kind, x, y)
    local def = C.buildings[kind]
    local building = { id = self.nextId, kind = kind, x = x, y = y,
        timer = 0, processed = 0, shot = 0 }
    self.nextId = self.nextId + 1
    table.insert(self.buildings, building)
    -- 非阻挡建筑（仓库）可通行，但仍占用格子、不可叠放。
    local solid = def.blocking ~= false
    for dy = 0, def.h - 1 do
        for dx = 0, def.w - 1 do
            self.cells[y + dy][x + dx].building = building.id
            self.cells[y + dy][x + dx].solid = solid
        end
    end
    self.version = self.version + 1
    return building
end

function Grid:FindBuilding(id)
    for _, b in ipairs(self.buildings) do if b.id == id then return b end end
    return nil
end

-- 返回与单位占地正交相邻、且带工序的所有建筑。
-- 单位以左上角 (ux, uy) 表示、占地 size×size；只要单位的任一格与建筑任一格
-- 四邻相接，即视为经过其加工面。多格建筑因此天然拥有多个并行工位。
---@param ux number
---@param uy number
---@param size number
---@return FrontierBuilding[]
function Grid:ProcessorsFor(ux, uy, size)
    local result = {} ---@type FrontierBuilding[]
    for _, b in ipairs(self.buildings) do
        local def = C.buildings[b.kind]
        if def.proc then
            local ux2, uy2 = ux + size - 1, uy + size - 1
            local bx2, by2 = b.x + def.w - 1, b.y + def.h - 1
            local colGap = math.max(b.x - ux2, ux - bx2)
            local rowGap = math.max(b.y - uy2, uy - by2)
            local colOverlap = ux <= bx2 and b.x <= ux2
            local rowOverlap = uy <= by2 and b.y <= uy2
            if (colGap == 1 and rowOverlap) or (rowGap == 1 and colOverlap) then
                result[#result + 1] = b
            end
        end
    end
    return result
end

-- 与给定格子四邻相接、且可作为仓库落点的通行格（供农民选最短仓库）。
function Grid:AdjacentWalkable(x, y)
    local out = {} ---@type table[]
    local dirs = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }
    for _, d in ipairs(dirs) do
        local nx, ny = x + d[1], y + d[2]
        if self:IsWalkable(nx, ny) then out[#out + 1] = { x = nx, y = ny } end
    end
    return out
end

-- 建筑一旦落下就不能拆除：营地规划是单向决策。
-- 唯一的例外是「阻碍墙」的整条移除（供内部布局调整使用）。
function Grid:RemoveBuilding(id)
    for i, b in ipairs(self.buildings) do
        if b.id == id then
            local def = C.buildings[b.kind]
            for dy = 0, def.h - 1 do
                for dx = 0, def.w - 1 do
                    local cell = self.cells[b.y + dy][b.x + dx]
                    cell.building, cell.solid = 0, false
                end
            end
            table.remove(self.buildings, i)
            self.version = self.version + 1
            return def.cost
        end
    end
    return 0
end

------------------------------------------------------------------
-- 资源点
------------------------------------------------------------------

function Grid:AddResource(kind, cells)
    local def = C.resources[kind]
    local stock = def.stockPerCell * #cells
    local res = { id = self.nextResource, kind = kind, cells = cells,
        stock = stock, maxStock = stock, slots = 0, reserved = 0 } --[[@as FrontierResource]]
    self.nextResource = self.nextResource + 1
    -- 采集位：标准 2×2 为 2 位；森林按"每剩余 2 格 1 位、最少 1 位"。
    if kind == "mineral" then
        res.slots = C.resourceSlots.standard
    else
        res.slots = math.max(C.resourceSlots.minSlots,
            math.floor(#cells / C.resourceSlots.cellsPerSlot))
    end
    for _, c in ipairs(cells) do
        local cell = self.cells[c.y][c.x]
        cell.resource = res.id
    end
    self.resources[#self.resources + 1] = res
    self.version = self.version + 1
    return res
end

function Grid:FindResource(id)
    for _, r in ipairs(self.resources) do if r.id == id then return r end end
    return nil
end

-- 枯竭或取消时移除资源点：占地格子恢复为普通营地格，可通行、可建造、可踩踏。
function Grid:RemoveResource(res)
    for i, r in ipairs(self.resources) do
        if r.id == res.id then
            for _, c in ipairs(r.cells) do
                local cell = self.cells[c.y][c.x]
                if cell.resource == r.id then cell.resource = 0 end
            end
            table.remove(self.resources, i)
            self.version = self.version + 1
            return true
        end
    end
    return false
end

---@return FrontierResource?
function Grid:ResourceAt(x, y)
    local cell = self:Get(x, y)
    if not cell or cell.resource == 0 then return nil end
    return self:FindResource(cell.resource)
end

------------------------------------------------------------------
-- 地图生成（V3.2 §6）
------------------------------------------------------------------

-- 该格是否被初始建筑、城墙、已有资源点占用（含 1 格间隔要求）。
function Grid:CellBlockedForResource(x, y, gap)
    if x < 1 or x > C.campMaxX or y < 1 or y > C.rows then return true end
    gap = gap or 0
    for dy = -gap, gap do
        for dx = -gap, gap do
            local cell = self:Get(x + dx, y + dy)
            if not cell or cell.building ~= 0 or cell.resource ~= 0 then return true end
        end
    end
    return false
end

-- 主走廊（第 5-6 行）保留 2 格宽横向直通，禁止生成资源点。
function Grid:InCorridor(y) return y == C.gateTop or y == C.gateTop + 1 end

function Grid:TryPlaceResource(kind, x, y, cells)
    for _, c in ipairs(cells) do
        if self:CellBlockedForResource(c.x, c.y, 1) then return false end
        if self:InCorridor(c.y) then return false end
    end
    return true
end

-- 生成一处森林：2×2 基准，随机缺损 1-2 格，形态不规则。
function Grid:PlaceForest()
    for _ = 1, 60 do
        local bx = math.random(4, C.campMaxX - 2)
        local by = math.random(2, C.rows - 2)
        local quad = { { x = bx, y = by }, { x = bx + 1, y = by },
            { x = bx, y = by + 1 }, { x = bx + 1, y = by + 1 } }
        local drop = math.random(1, 2)
        for _ = 1, drop do table.remove(quad, math.random(1, #quad)) end
        if #quad >= 2 and self:TryPlaceResource("forest", bx, by, quad) then
            return self:AddResource("forest", quad)
        end
    end
    return nil
end

-- 生成一处矿物：标准 2×2，位于主走廊两侧对称位置，不刷在营地正中心。
function Grid:PlaceMinerals()
    local placed = 0
    for _ = 1, 60 do
        local bx = math.random(6, C.campMaxX - 3)
        local top = math.random(2, C.gateTop - 2)          -- 走廊上方
        local bottom = C.rows - (top + 1)                  -- 关于走廊镜像
        if bottom > C.gateTop + 1 and bottom <= C.rows - 1 then
            local upper = { { x = bx, y = top }, { x = bx + 1, y = top },
                { x = bx, y = top + 1 }, { x = bx + 1, y = top + 1 } }
            local lower = { { x = bx, y = bottom }, { x = bx + 1, y = bottom },
                { x = bx, y = bottom + 1 }, { x = bx + 1, y = bottom + 1 } }
            if self:TryPlaceResource("mineral", bx, top, upper)
                and self:TryPlaceResource("mineral", bx, bottom, lower) then
                self:AddResource("mineral", upper)
                self:AddResource("mineral", lower)
                placed = 2
                break
            end
        end
    end
    return placed
end

-- 建筑出口：该建筑周围第一个可通行、且不与其他建筑重叠的落点。
-- 校验与寻路都必须从建筑外部出发，不能拿建筑内部格子当起点。
---@return table?
function Grid:BuildingExit(b)
    local def = C.buildings[b.kind]
    for y = b.y - 1, b.y + def.h do
        for x = b.x - 1, b.x + def.w do
            if self:IsWalkable(x, y) then return { x = x, y = y } end
        end
    end
    return nil
end

-- 校验（V3.2 §6.3）：民兵营可达城门、农民营可达资源点、资源点邻接通行格、无重叠。
function Grid:ValidateMap()
    local barracks, farm
    for _, b in ipairs(self.buildings) do
        if b.kind == "barracks" then barracks = b end
        if b.kind == "farmerBarracks" then farm = b end
    end
    if not barracks or not farm then return false end
    local bExit, fExit = self:BuildingExit(barracks), self:BuildingExit(farm)
    if not bExit or not fExit then return false end
    -- 1) 民兵营 → 城门
    if not self:Path(bExit.x, bExit.y, C.wallCol - 1, C.gateTop, 1) then return false end
    -- 2) 农民营 → 至少一个资源点
    local farmReach = false
    for _, r in ipairs(self.resources) do
        for _, c in ipairs(r.cells) do
            for _, adj in ipairs(self:AdjacentWalkable(c.x, c.y)) do
                if self:Path(fExit.x, fExit.y, adj.x, adj.y, 1) then farmReach = true; break end
            end
            if farmReach then break end
        end
        if farmReach then break end
    end
    if not farmReach then return false end
    -- 3) 每个资源点至少有一个相邻通行格（可采集）
    for _, r in ipairs(self.resources) do
        local ok = false
        for _, c in ipairs(r.cells) do
            if #self:AdjacentWalkable(c.x, c.y) > 0 then ok = true; break end
        end
        if not ok then return false end
    end
    return true
end

-- 保底地图：资源点位置固定、所有路径通畅，校验失败时兜底。
function Grid:FallbackMap()
    for _, r in ipairs(self.resources) do
        for _, c in ipairs(r.cells) do self.cells[c.y][c.x].resource = 0 end
    end
    self.resources = {}
    local function quad(bx, by)
        return { { x = bx, y = by }, { x = bx + 1, y = by }, { x = bx, y = by + 1 }, { x = bx + 1, y = by + 1 } }
    end
    self:AddResource("mineral", quad(9, 3))
    self:AddResource("mineral", quad(9, 8))
    self:AddResource("forest", { { x = 16, y = 2 }, { x = 17, y = 2 }, { x = 16, y = 3 } })
    self:AddResource("forest", { { x = 16, y = 9 }, { x = 17, y = 9 }, { x = 17, y = 10 } })
    self:AddResource("forest", { { x = 20, y = 2 }, { x = 20, y = 3 }, { x = 21, y = 3 } })
end

function Grid:GenerateMap()
    local forestCount = math.random(C.resources.forest.count[1], C.resources.forest.count[2])
    for _ = 1, 5 do
        for _, r in ipairs(self.resources) do
            for _, c in ipairs(r.cells) do self.cells[c.y][c.x].resource = 0 end
        end
        self.resources = {}
        self:PlaceMinerals()
        for _ = 1, forestCount do self:PlaceForest() end
        if self:ValidateMap() then
            self.version = self.version + 1
            return
        end
    end
    -- 随机 5 次仍不通过：加载预设保底地图，确保每局正常开局。
    print("[地图] 随机生成未通过校验，加载保底地图")
    self:FallbackMap()
    self.version = self.version + 1
end

------------------------------------------------------------------
-- 寻路：时间最优 + 确定性选路（V3.2 §1）
------------------------------------------------------------------

-- 四邻域 A*：通行成本 = 每格通行时间（trailCost 即 trailSpeed 的倒数），
-- 因此寻路天然是"时间最优"而非"距离最短"。建筑/资源点为硬障碍。
-- 同代价路径按「上→下、左→右」确定性选取，保证同一布局结果可复现。
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
    -- 方向顺序固定：右、上、下、左。配合下面的 (f, y, x) 平局规则，
    -- 等代价路径永远选"更靠上、再更靠左"的那条。
    local dirs = { { 1, 0 }, { 0, -1 }, { 0, 1 }, { -1, 0 } }
    for _ = 1, C.cols * C.rows * 4 do
        if #open == 0 then return nil end
        local best = 1
        for i = 2, #open do
            local a, b = open[i], open[best]
            if a.f < b.f or (a.f == b.f and (a.y < b.y or (a.y == b.y and a.x < b.x))) then
                best = i
            end
        end
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
                    -- 成本量化到 3 位小数，避免浮点误差破坏"等代价"判定与确定性选路。
                    local step = C.trailCost[self:TrailLevel(x, y) + 1]
                    if size == 2 and x < C.wallCol and not self:LargeRoad(x, y) then step = step + 2 end
                    local cost = math.floor((costs[n.k] + step) * 1000 + 0.5) / 1000
                    if not closed[k] and (not costs[k] or cost < costs[k]) then
                        costs[k], parent[k] = cost, n.k
                        local h = (math.abs(tx - x) + math.abs(ty - y)) * 0.5
                        table.insert(open, { x = x, y = y, k = k,
                            f = math.floor((cost + h) * 1000 + 0.5) / 1000 })
                    end
                end
            end
        end
    end
    return nil
end

-- 营地内单位不走 A*，而是按"直线 + 横线"的最短 L 形折线走向城门。
-- 折线有两种走法：先横后竖、以及先竖后横。略微偏好前者，让不同行的
-- 部队各自成列前进，只在城门口汇合，缓解拥堵。
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
