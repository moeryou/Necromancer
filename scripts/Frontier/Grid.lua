local C = require "Frontier.Config"

---@class FrontierCell
---@field terrain string
---@field building number
---@field boost boolean

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
---@field rockRatio number
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
    self.rockRatio = 0
    -- 随机重试保证通路，不铺设脚本走廊；所有实际路线由 A* 计算。
    for attempt = 1, 200 do
        self.cells = {}
        local rocks = 0
        for y = 1, C.rows do
            self.cells[y] = {}
            for x = 1, C.cols do
                local kind = "empty" ---@type string
                if x == C.wallCol then kind = self:IsGateRow(y) and "road" or "wall" end
                if x < C.wallCol and math.random() < 0.30 then kind = "rock" end
                -- 左侧保留首座营房及出口，其他区域完全随机。
                if x >= 2 and x <= 5 and y >= 5 and y <= 7 then kind = "empty" end
                if kind == "rock" then rocks = rocks + 1 end
                self.cells[y][x] = { terrain = kind, building = 0, boost = false } --[[@as FrontierCell]]
            end
        end
        self.rockRatio = rocks / ((C.wallCol - 1) * C.rows)
        if self.rockRatio >= 0.25 and self.rockRatio <= 0.35
            and self:Path(4, 6, C.wallCol + 1, 6, 1) then
            print(string.format("[地图] 随机岩石 %.1f%%，第 %d 次生成，通路已验证", self.rockRatio * 100, attempt))
            break
        end
        if attempt == 200 then error("地图生成未获得有效随机通路") end
    end
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
    return cell ~= nil and cell.building == 0 and cell.terrain ~= "rock" and cell.terrain ~= "wall"
end

function Grid:Footprint(x, y, size)
    for dy = 0, size - 1 do
        for dx = 0, size - 1 do
            if not self:IsWalkable(x + dx, y + dy) then return false end
        end
    end
    return true
end

function Grid:LargeRoad(x, y, tech)
    if x > C.wallCol then return true end
    if tech < 1 then return false end
    for dy = 0, 1 do
        for dx = 0, 1 do
            if x + dx <= C.wallCol then
                local cell = self:Get(x + dx, y + dy)
                if not cell or cell.building > 0 or cell.terrain ~= "road" then return false end
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
        if x ~= C.wallCol or self:IsGateRow(y) or not cell or cell.building > 0 then
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
            if not cell or cell.terrain ~= "empty" or cell.building > 0 then
                return false, "需要空地：先清理岩石或拆除道路"
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

function Grid:Edit(tool, x, y)
    local cell = self:Get(x, y)
    if not cell then return false, "地图外不可操作", 0 end
    if tool == "erase" and cell.building > 0 then
        return true, "拆除建筑，返还 55% 资源", -math.floor(self:RemoveBuilding(cell.building) * C.refundRate)
    end
    if x >= C.wallCol then return false, "战场不可建造，城墙仅允许箭塔", 0 end
    if cell.building > 0 then return false, "此格被建筑占用", 0 end
    local cost, text = 0, ""
    if tool == "clear" and cell.terrain == "rock" then
        cell.terrain, cost, text = "empty", C.clearCost, "岩石已清除"
    elseif tool == "road" and cell.terrain == "empty" then
        cell.terrain, cost, text = "road", C.roadCost, "土路已铺设"
    elseif tool == "boost" and cell.terrain == "road" and not cell.boost then
        cell.boost, cost, text = true, C.boostCost, "加速带已铺设"
    elseif tool == "erase" and cell.terrain == "road" then
        cost = -math.floor((C.roadCost + (cell.boost and C.boostCost or 0)) * C.refundRate)
        cell.terrain, cell.boost, text = "empty", false, "道路已拆除"
    else return false, "请选择符合操作条件的格子", 0 end
    self.version = self.version + 1
    return true, text, cost
end

-- 四邻域 A*，道路低成本、向右偏好；建筑与岩石均为硬障碍。
-- 大体型节点以 2×2 左上角表示；优先寻找可通行硬化路，无完整路才显示卡滞。
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
                if self:Footprint(x, y, size) and (not strictLarge or self:LargeRoad(x, y, 1)) then
                    local k = key(x, y)
                    local cell = self:Get(x, y)
                    local step = (cell and cell.terrain == "road") and 0.55 or 1
                    -- 仅营地向右偏置；返程与采集仍遵从实际目标方向。
                    if x < C.wallCol and tx > sx and d[1] < 0 then step = step + 0.35 end
                    if size == 2 and x < C.wallCol and not self:LargeRoad(x, y, 1) then step = step + 2 end
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
