local C = require "Frontier.Config"
local Grid = require "Frontier.Grid"

---@class FrontierUnit
---@field id number
---@field kind string
---@field team string
---@field x number
---@field y number
---@field hp number
---@field maxHp number
---@field armor number
---@field size number
---@field cooldown number
---@field path table[]
---@field pathVersion number
---@field goalX number
---@field goalY number
---@field repath number
---@field blocked number
---@field state string
---@field upgraded boolean
---@field commandVersion number
---@field passedGate boolean
---@field ticket number
---@field gateLane number
---@field gateSlots number
---@field facing number
---@field moving boolean
---@field flash number
---@field active boolean

---@class FrontierShot
---@field x number
---@field y number
---@field target number
---@field team string
---@field damage number
---@field speed number
---@field life number

---@class FrontierEffect
---@field x number
---@field y number
---@field life number
---@field maxLife number
---@field kind string
---@field color number[]
---@field radius number

---@class FrontierSim
---@field grid FrontierGrid
---@field units FrontierUnit[]
---@field shots FrontierShot[]
---@field effects FrontierEffect[]
---@field gold number
---@field wallHp number
---@field phase string
---@field phaseTime number
---@field wave number
---@field waveQueue string[]
---@field spawnTimer number
---@field command string
---@field commandTimer number
---@field commandVersion number
---@field time number
---@field paused boolean
---@field speed number
---@field nextUnit number
---@field nextTicket number
---@field kills number
---@field converted number
---@field produced number
---@field notice string
---@field noticeTime number
---@field gateUsed number
---@field blockedCount number
---@field diagnosticTimer number
---@field roadTimer number
---@field roadProgress number
---@field roadLevelValue number
local Sim = {}
Sim.__index = Sim

---@return FrontierSim
function Sim.New()
    local self = setmetatable({}, Sim) --[[@as FrontierSim]]
    self:Init()
    return self
end

function Sim:Init()
    self.grid = Grid.New()
    self.units = {} ---@type FrontierUnit[]
    self.shots = {} ---@type FrontierShot[]
    self.effects = {} ---@type FrontierEffect[]
    self.gold = C.startGold
    self.wallHp = C.wallHealth
    self.phase, self.phaseTime, self.wave = "develop", C.developTime, 1
    self.waveQueue = {} ---@type string[]
    self.spawnTimer = 0
    self.command, self.commandTimer, self.commandVersion = "wait", 0, 1
    self.time, self.paused, self.speed = 0, false, 1
    self.nextUnit, self.nextTicket = 1, 1
    self.kills, self.converted, self.produced = 0, 0, 0
    -- 每帧重算一次双方兵力，供生产/转职/胜负判定复用，避免在 O(N) 循环里反复全表扫描。
    self.allyCount, self.enemyCount = 0, 0
    self.notice = "首座民兵营已就绪。让部队在营地与城门之间反复行军，道路会自己长出来。"
    self.noticeTime, self.gateUsed, self.blockedCount = 8, 0, 0
    self.diagnosticTimer = 0
    self.roadTimer, self.roadProgress, self.roadLevelValue = 0, 0, 0
    print("[游戏] 单机初始化，90秒发育，3波普通敌军后直接进入Boss战；兵力上限" .. C.armyLimit)
end

function Sim:Notify(text)
    self.notice, self.noticeTime = text, 4
    print("[操作] " .. text)
end

function Sim:Active(u)
    return u.active and u.hp > 0
end

-- 双方兵力在每帧开头统一统计（见 RefreshCounts），循环内直接读缓存字段。
function Sim:ArmyCount()
    return self.allyCount
end

function Sim:EnemyCount()
    return self.enemyCount
end

function Sim:RefreshCounts()
    local ally, enemy = 0, 0
    for _, u in ipairs(self.units) do
        if u.active and u.hp > 0 then
            if u.team == "ally" then ally = ally + 1 else enemy = enemy + 1 end
        end
    end
    self.allyCount, self.enemyCount = ally, enemy
end

function Sim:AddUnit(kind, team, x, y)
    local t = C.units[kind]
    local u = { id = self.nextUnit, kind = kind, team = team, x = x, y = y,
        hp = t.hp, maxHp = t.hp, armor = t.armor, size = t.size, cooldown = 0,
        path = {}, pathVersion = 0, goalX = -1, goalY = -1, repath = 0, blocked = 0,
        state = "行军", upgraded = kind ~= "militia",
        commandVersion = 0, passedGate = team ~= "ally", ticket = 0,
        gateLane = 0, gateSlots = 0, facing = team == "ally" and 1 or -1,
        moving = false, flash = 0, active = true }
    self.nextUnit = self.nextUnit + 1
    self.units[#self.units + 1] = u
    if u.active and u.hp > 0 then
        if team == "ally" then self.allyCount = self.allyCount + 1
        else self.enemyCount = self.enemyCount + 1 end
    end
    return u
end

function Sim:Perform(tool, x, y)
    if self.phase == "victory" or self.phase == "defeat" then return false end
    local def = C.buildings[tool]
    if def then
        local ok, reason = self.grid:CanPlace(tool, x, y)
        if not ok then self:Notify(reason); return false end
        if self.gold < def.cost then self:Notify("基础资源不足"); return false end
        -- 不能覆盖单位，避免单位被建筑夹在不可通行格内。
        for _, u in ipairs(self.units) do
            if self:Active(u) and u.x + u.size * 0.42 > x - 0.5 and u.x - u.size * 0.42 < x + def.w - 0.5
                and u.y + u.size * 0.42 > y - 0.5 and u.y - u.size * 0.42 < y + def.h - 0.5 then
                self:Notify("有单位正在经过，请等待空位"); return false
            end
        end
        self.grid:AddBuilding(tool, x, y)
        self.gold = self.gold - def.cost
        self:Notify(def.name .. "建造完成；路径已重新计算")
        return true
    end
    return false
end

function Sim:SetCommand(command)
    if self.phase == "victory" or self.phase == "defeat" then return end
    if self.commandTimer > 0 then self:Notify("全局指令冷却中"); return end
    if self.gold < C.commandCost then self:Notify("发布指令需要15基础资源"); return end
    self.gold = self.gold - C.commandCost
    self.command, self.commandTimer = command, C.commandCooldown
    self.commandVersion = self.commandVersion + 1
    self:Notify(C.commandNames[command] .. "：" .. C.commandNotes[command])
end

function Sim:StartWave(early)
    if self.phase ~= "develop" then return end
    if early and self.phaseTime > 0 then
        local reward = math.floor(self.phaseTime * 0.65)
        self.gold = self.gold + reward
        self:Notify("提前迎敌！奖励 " .. reward .. " 基础资源；趁敌人还没到，先摆好产线")
    end
    self.phase, self.phaseTime, self.spawnTimer = "battle", 0, 0.2
    self.waveQueue = {}
    for i = 1, 8 + self.wave * 5 do
        local kind = "raider"
        if i % 5 == 0 then kind = "brute"
        elseif i % 4 == 0 then kind = "shooter" end
        table.insert(self.waveQueue, kind)
    end
    self.commandVersion = self.commandVersion + 1
    print("[波次] 普通波次 " .. self.wave .. "，敌军总量 " .. #self.waveQueue)
end

function Sim:StartBoss()
    self.phase, self.phaseTime, self.wave, self.spawnTimer = "boss", 0, 4, 0.1
    self.waveQueue = { "boss", "brute", "shooter", "brute", "shooter", "brute" }
    self:Notify("最终决战：破城巨兽。分散部队，避免城门密集受击。")
end

function Sim:WaveComplete()
    self.gold = self.gold + 100 + self.wave * 30
    self:Notify("第 " .. self.wave .. " 波击退！获得基础资源补给")
    if self.wave == 3 then self:StartBoss(); return end
    self.wave = self.wave + 1
    self.phase, self.phaseTime = "develop", C.developTime
    self.command, self.commandTimer = "wait", 0
    self.commandVersion = self.commandVersion + 1
end

function Sim:Effect(x, y, kind, color, radius)
    table.insert(self.effects, { x = x, y = y, kind = kind, color = color,
        radius = radius or 0.5, life = 0.5, maxLife = 0.5 })
end

function Sim:FindUnit(id)
    for _, u in ipairs(self.units) do if u.id == id then return u end end
    return nil
end

function Sim:Damage(target, amount)
    if self.phase == "victory" or self.phase == "defeat" then return end
    if not self:Active(target) then return end
    target.hp = target.hp - math.max(1, amount - target.armor)
    target.flash = 0.12
    if target.hp <= 0 then
        self:Effect(target.x, target.y, "death", C.units[target.kind].color, target.size * 0.5)
        target.active = false
        if target.team == "enemy" then self.kills = self.kills + 1 end
        if target.kind == "boss" then
            self.phase = "victory"
            self:Notify("破城巨兽已倒下，边境守住了！")
        end
    end
end

function Sim:Attack(u, target)
    local t = C.units[u.kind]
    if u.cooldown > 0 then return end
    u.cooldown = t.interval
    u.facing = target.x > u.x and 1 or -1
    if t.ranged then
        table.insert(self.shots, { x = u.x, y = u.y, target = target.id, team = u.team,
            damage = t.damage, speed = 13, life = 2 })
    elseif t.aoe then
        self:Effect(target.x, target.y, "aoe", t.color, t.aoe)
        for _, v in ipairs(self.units) do
            if self:Active(v) and v.team ~= u.team and (v.x - target.x)^2 + (v.y - target.y)^2 <= t.aoe^2 then
                self:Damage(v, t.damage)
            end
        end
    else
        self:Effect((u.x + target.x) / 2, (u.y + target.y) / 2, "hit", t.color, 0.4)
        self:Damage(target, t.damage)
    end
end

function Sim:Target(u)
    local t = C.units[u.kind]
    local best = nil ---@type FrontierUnit?
    local bestScore = math.huge
    local sight2 = t.sight * t.sight
    for _, v in ipairs(self.units) do
        -- 先用平方距离剔除视野外的目标，避免每个单位都开一次 sqrt。
        if v.active and v.hp > 0 and v.team ~= u.team
            and (v.x - u.x)^2 + (v.y - u.y)^2 <= sight2 then
            local dx, dy = v.x - u.x, v.y - u.y
            local dist = math.sqrt(dx * dx + dy * dy)
            local visible = true
            -- 城墙实体阻断穿墙接战；在门外才允许攻守交互。
            if u.x < C.wallCol - 0.5 or v.x < C.wallCol - 0.5 then visible = false end
            if u.team == "ally" and (self.command == "defend" or self.command == "wait") then
                if v.x > C.wallCol + 4.2 and dist > t.range then visible = false end
            end
            if visible then
                local score = dist
                if u.kind == "cavalry" and C.units[v.kind].ranged then score = score - 2.5 end
                if u.kind == "boss" then
                    local clustered = 0
                    for _, ally in ipairs(self.units) do
                        if self:Active(ally) and ally.team ~= u.team and (ally.x-v.x)^2+(ally.y-v.y)^2 < 4 then clustered = clustered + 1 end
                    end
                    score = score - clustered * 0.45
                end
                if score < bestScore then best, bestScore = v, score end
            end
        end
    end
    return best
end

-- 碰撞设计（网格单位）：
-- 普通：中心 [ ● ]，轴向半径0.36；大象：2×2，半径0.88。
-- 岩石/建筑占满格；普通行军沿格心，大象沿2×2中心，禁止对角穿角。
-- 相邻单位的包围盒不能重叠。候选侧移同样检测地形，避免穿墙超车。
-- 城门：3行可通行位；按票据先到先得，普通占1、大象占2，不可超配。
function Sim:CollisionRadius(u, x, y)
    if u.size == 2 then return 0.87 end
    return 0.36
end

-- passAllies：长时间僵持时的解结通道，允许穿过同阵营单位。
-- 没有它，密集队形会卡在"恰好等于碰撞间距"的晶格上，谁也无法挪动半步。
function Sim:PositionClear(u, x, y, passAllies)
    local radius = self:CollisionRadius(u, x, y)
    local minX, maxX = math.floor(x - radius + 0.5), math.floor(x + radius + 0.5)
    local minY, maxY = math.floor(y - radius + 0.5), math.floor(y + radius + 0.5)
    for cy = minY, maxY do
        for cx = minX, maxX do
            if not self.grid:IsWalkable(cx, cy) then return false end
        end
    end
    for _, other in ipairs(self.units) do
        if other ~= u and other.active and other.hp > 0 then
            local r = self:CollisionRadius(other, other.x, other.y)
            if math.abs(x - other.x) < radius + r and math.abs(y - other.y) < radius + r then
                -- 只有同阵营才允许解结穿越；敌方永远视为实心。
                if not (passAllies and other.team == u.team) then return false end
            end
        end
    end
    return true
end

function Sim:GateStep()
    local used = {}
    self.gateUsed = 0
    for _, u in ipairs(self.units) do
        if self:Active(u) and u.team == "ally" and not u.passedGate then
            if u.gateSlots > 0 and u.x > C.wallCol + u.size * 0.5 then
                u.passedGate, u.gateSlots, u.ticket = true, 0, 0
                u.path = {}
            elseif u.gateSlots > 0 then
                for j = u.gateLane, u.gateLane + u.gateSlots - 1 do used[j] = true end
                self.gateUsed = self.gateUsed + u.gateSlots
            elseif u.ticket == 0 and u.x >= C.wallCol - 2.8 then
                u.ticket = self.nextTicket
                self.nextTicket = self.nextTicket + 1
            end
        end
    end
    local queue = {}
    for _, u in ipairs(self.units) do
        if self:Active(u) and u.ticket > 0 and u.gateSlots == 0 then table.insert(queue, u) end
    end
    table.sort(queue, function(a, b) return a.ticket < b.ticket end)
    for _, u in ipairs(queue) do
        local found = 0
        for lane = 1, C.gateWidth - u.size + 1 do
            local free = true
            for j = lane, lane + u.size - 1 do if used[j] then free = false end end
            if free then
                local offset = (u.size - 1) * 0.5
                local sx, sy = math.floor(u.x - offset + 0.5), math.floor(u.y - offset + 0.5)
                local row = C.gateTop + lane - 1
                local strict = u.size == 2
                -- 票据绑定可达门行，阻碍墙或岩石不得让空闲上行吞掉整个队列。
                free = self.grid:Path(sx, sy, C.wallCol - 1, row, u.size, strict) ~= nil
                    and self.grid:Footprint(C.wallCol, row, u.size)
                if strict then free = free and self.grid:LargeRoad(C.wallCol - 1, row) end
            end
            if free then found = lane; break end
        end
        if found == 0 then break end
        u.gateLane, u.gateSlots = found, u.size
        u.path = {}
        for j = found, found + u.size - 1 do used[j] = true end
        self.gateUsed = self.gateUsed + u.size
    end
end

-- 周围单位密度：越小越空旷。用于让拥堵单位朝人少的方向流动。
function Sim:CrowdDensity(x, y, u, radius)
    local count, r2 = 0, radius * radius
    for _, v in ipairs(self.units) do
        if v ~= u and v.active and v.hp > 0 then
            if (v.x - x)^2 + (v.y - y)^2 < r2 then count = count + 1 end
        end
    end
    return count
end

function Sim:Move(u, tx, ty, dt)
    local t = C.units[u.kind]
    local offset = (u.size - 1) * 0.5
    tx = math.max(1 + offset, math.min(C.cols - offset, tx))
    if u.team == "ally" and u.passedGate then tx = math.max(C.wallCol + 0.55 + offset, tx) end
    ty = math.max(1 + offset, math.min(C.rows - offset, ty))
    local sx, sy = math.floor(u.x - offset + 0.5), math.floor(u.y - offset + 0.5)
    local gx, gy = math.floor(tx - offset + 0.5), math.floor(ty - offset + 0.5)
    if u.ticket > 0 and u.gateSlots == 0 and u.x > C.wallCol - 2.3 then
        u.state, u.blocked = "城门排队", u.blocked + dt
        return
    end
    if u.team == "ally" and u.size == 2 and u.x <= C.wallCol then
        if not self.grid:LargeRoad(sx, sy) then
            u.state, u.blocked = "窄路卡滞", u.blocked + dt
            return
        end
    end
    if u.repath <= 0 or u.pathVersion ~= self.grid.version or gx ~= u.goalX or gy ~= u.goalY then
        local path = nil ---@type table[]?
        -- 营地内普通单位按"直线 + 横线"的最短 L 形折线行军，方向确定。
        if u.x < C.wallCol - 0.5 and u.size == 1 then
            path = self.grid:LRoute(sx, sy, gx, gy)
        end
        if not path and u.team == "ally" and u.size == 2 then
            path = self.grid:Path(sx, sy, gx, gy, u.size, true)
        end
        u.path = path or self.grid:Path(sx, sy, gx, gy, u.size) or {}
        u.pathVersion, u.goalX, u.goalY, u.repath = self.grid.version, gx, gy, 1.2
    end
    local nx, ny = tx, ty
    if #u.path > 0 then nx, ny = u.path[1].x + offset, u.path[1].y + offset end
    local dx, dy = nx - u.x, ny - u.y
    local dist = math.sqrt(dx * dx + dy * dy)
    if dist < 0.06 then
        if #u.path > 0 then table.remove(u.path, 1) end
        return
    end
    if #u.path == 0 and (sx ~= gx or sy ~= gy) then u.state = "路径阻断"; u.blocked = u.blocked + dt; return end
    if u.team == "ally" and u.size == 2 and nx <= C.wallCol
        and not self.grid:LargeRoad(math.floor(nx - offset + 0.5), math.floor(ny - offset + 0.5)) then
        u.state, u.blocked = "窄路卡滞", u.blocked + dt
        return
    end
    local speed = t.speed * C.trailSpeed[self.grid:TrailLevel(u.x, u.y) + 1]
    local step = math.min(dist, speed * dt)
    local px, py = u.x + dx / dist * step, u.y + dy / dist * step
    -- 僵持过久就允许穿过同阵营单位，避免密集队形锁死在碰撞晶格上。
    local stuck = u.blocked > 2.5
    if self:PositionClear(u, px, py) or (stuck and self:PositionClear(u, px, py, true)) then
        u.x, u.y, u.blocked, u.moving = px, py, 0, true
        if math.abs(dx) > 0.1 then u.facing = dx > 0 and 1 or -1 end
        -- 己方部队的踩踏把荒野逐渐压成道路；敌军不留下痕迹。
        -- step 近似等于本帧走过的格数，累加即为"经过此格的次数"。
        if u.team == "ally" and u.x < C.wallCol + 1 then self.grid:Trample(u.x, u.y, step) end
    else
        u.blocked = u.blocked + dt
        u.state = "拥堵排队"
        -- 密度梯度绕行：在几个候选方向里挑一个既能走、又最空旷的，
        -- 单位会自然朝人少的地方流动，而不是原地抖动或继续往人堆里挤。
        if u.blocked > 0.35 and u.gateSlots == 0 then
            local fx, fy = dx / dist, dy / dist
            local lx, ly = -fy, fx
            local candidates = {
                { fx, fy, 0 }, { fx * 0.7 + lx, fy * 0.7 + ly, 1 }, { fx * 0.7 - lx, fy * 0.7 - ly, 1 },
                { lx, ly, 1 }, { -lx, -ly, 1 }, { fx * 0.4 + lx * 1.2, fy * 0.4 + ly * 1.2, 1 },
                { fx * 0.4 - lx * 1.2, fy * 0.4 - ly * 1.2, 1 },
            }
            local bestX, bestY, bestScore = nil, nil, math.huge
            for _, c in ipairs(candidates) do
                local len = math.sqrt(c[1] * c[1] + c[2] * c[2])
                local ax, ay = u.x + c[1] / len * step, u.y + c[2] / len * step
                if self:PositionClear(u, ax, ay) then
                    -- 主要看密度，其次轻微偏好继续前进的方向。
                    local score = self:CrowdDensity(ax, ay, u, 1.3) * 2 + c[3] * 0.35
                    if score < bestScore then bestX, bestY, bestScore = ax, ay, score end
                end
            end
            if bestX then
                u.x, u.y, u.moving = bestX, bestY, true
            end
        end
    end
end

function Sim:UpgradeUnit(u)
    if u.upgraded or u.team ~= "ally" then return end
    -- 转职是原地换兵种，不增加单位数量，因此不受兵力上限约束。
    for _, b in ipairs(self.grid.buildings) do
        local def = C.buildings[b.kind]
        if def.upgrade and b.stock > 0 then
            local dx = math.max(b.x - 0.5 - u.x, 0, u.x - (b.x + def.w - 0.5))
            local dy = math.max(b.y - 0.5 - u.y, 0, u.y - (b.y + def.h - 0.5))
            if dx * dx + dy * dy < 0.72^2 then
                b.stock = b.stock - 1
                local t = C.units[def.upgrade]
                u.kind, u.hp, u.maxHp, u.armor, u.upgraded = def.upgrade, t.hp, t.hp, t.armor, true
                self.converted = self.converted + 1
                self:Effect(u.x, u.y, "upgrade", t.color, 0.65)
                print("[转职] 单位" .. u.id .. "拾取" .. def.name .. "库存，转为" .. t.name .. "，剩余" .. b.stock)
                break
            end
        end
    end
end

-- 敌军从右侧入场。出生点必须避开现有单位：两个单位叠在同一格会互相判定碰撞，
-- 之后谁也无法移动，整波敌军就此僵在边缘（兵力上限调低后尤其致命）。
function Sim:SpawnEnemy(kind)
    local t = C.units[kind]
    local size = t.size
    local offset = (size - 1) * 0.5
    local baseY = kind == "boss" and 6 or math.random(2, C.rows - 1)
    local baseX = C.cols - size + 1
    local probe = { size = size } --[[@as FrontierUnit]]
    -- 以理想行号为中心向两侧扩散，找到第一个不重叠的落点。
    local order = {}
    for d = 0, C.rows do
        if baseY - d >= 1 then table.insert(order, baseY - d) end
        if d > 0 and baseY + d <= C.rows - size + 1 then table.insert(order, baseY + d) end
    end
    for _, cy in ipairs(order) do
        local cx = math.max(1, math.min(C.cols - size + 1, baseX))
        if self:PositionClear(probe, cx + offset, cy + offset) then
            return self:AddUnit(kind, "enemy", cx + offset, cy + offset)
        end
    end
    return nil
end

-- 出兵点分散：优先选离已有同伴最远的候选格，避免新兵和旧部队叠在出口。
function Sim:PickSpawn(candidates, size)
    local best, bestClear = nil, -1
    for _, spot in ipairs(candidates) do
        local x, y = spot.x + (size-1)*0.5, spot.y + (size-1)*0.5
        local probe = { size = size } --[[@as FrontierUnit]]
        if self:PositionClear(probe, x, y) then
            local clearance = math.huge
            for _, v in ipairs(self.units) do
                if self:Active(v) and v.team == "ally" then
                    local d = (v.x-x)^2 + (v.y-y)^2
                    if d < clearance then clearance = d end
                end
            end
            if clearance > bestClear then best, bestClear = spot, clearance end
        end
    end
    return best
end

function Sim:ApplyCommand(u)
    if u.commandVersion == self.commandVersion then return end
    u.commandVersion = self.commandVersion
    u.path, u.repath = {}, 0
end

function Sim:AllyGoal(u, dt)
    if not u.passedGate then
        local offset = (u.size - 1) * 0.5
        local row = math.max(C.gateTop, math.min(C.gateTop + C.gateWidth - u.size, math.floor(u.y - offset + 0.5)))
        if u.gateSlots > 0 then row = C.gateTop + u.gateLane - 1 end
        u.state = "向城门行军"
        local goalX = C.wallCol + 1.6
        -- 通行票据必须对应实际通行行：先在墙内对准行，再穿过唯一出口。
        if u.gateSlots > 0 and u.x < C.wallCol - 0.5 and math.abs(u.y - row - offset) > 0.12 then
            goalX = C.wallCol - 1
        end
        self:Move(u, goalX, row + offset, dt)
        return
    end
    self:ApplyCommand(u)
    if self.command == "attack" then
        u.state = "向右推进"
        self:Move(u, C.cols - 1, u.y, dt)
    else
        -- 不分配预制阵形：近战、射程与避让产生自然前后排。
        local x = C.wallCol + 2.8
        local y = math.max(2 + u.size * 0.5, math.min(C.rows - 1 - u.size * 0.5, u.y))
        if u.kind == "cavalry" and self.command == "defend" then y = 6 + math.sin(self.time * 0.65 + u.id) * 2 end
        u.state = self.command == "defend" and "固守防线" or "城外待命"
        if math.abs(u.x - x) > 0.4 or math.abs(u.y-y) > 0.5 then self:Move(u, x, y, dt) end
    end
end

function Sim:Combat(u, target, dt)
    local t = C.units[u.kind]
    local dx, dy = target.x-u.x, target.y-u.y
    local dist = math.sqrt(dx*dx+dy*dy)
    local reach = t.range + (u.size + target.size - 2) * 0.35
    u.state = "自主交战"
    if dist <= reach then self:Attack(u, target) end
    if t.ranged then
        local desired = reach * (u.kind == "cavalry" and 0.85 or 0.9)
        if dist < desired * 0.65 then
            self:Move(u, u.x - dx / math.max(dist, 0.1) * 1.6, u.y - dy / math.max(dist, 0.1) * 1.6, dt)
        elseif dist > reach then
            self:Move(u, target.x - dx / math.max(dist, 0.1) * desired, target.y - dy / math.max(dist, 0.1) * desired, dt)
        elseif u.kind == "cavalry" then
            local flank = math.sin(self.time * 0.8 + u.id) > 0 and 1 or -1
            self:Move(u, u.x, u.y + flank * 0.8, dt)
        end
    elseif dist > reach then
        -- 待命与驻守不向远处追敌；重甲无论指令都不追击撤远目标。
        if u.team == "ally" and (self.command == "defend" or self.command == "wait") then
            if target.x > C.wallCol + 4.2 then return end
        end
        if u.kind == "heavy" and dist > 2.6 then
            if self.command == "attack" then self:Move(u, u.x + 0.8, u.y, dt) end
            return
        end
        self:Move(u, target.x, target.y, dt)
    end
end

function Sim:EnemyGoal(u, dt)
    if self.phase == "victory" or self.phase == "defeat" then return end
    local t = C.units[u.kind]
    local desiredX = C.wallCol + 0.8 + (u.size - 1) * 0.5
    if u.x <= desiredX + t.range * 0.2 then
        u.state = "攻击城墙"
        if u.cooldown <= 0 then
            self.wallHp = math.max(0, self.wallHp - t.damage)
            u.cooldown = t.interval
            self:Effect(C.wallCol, u.y, "aoe", t.color, t.aoe or 0.5)
            if self.wallHp <= 0 then self.phase = "defeat"; self:Notify("城墙被攻破。重新规划生产线，再战一次。"); end
        end
    else
        local y = math.max(2, math.min(C.rows - 1, u.y))
        if u.kind == "boss" then y = 6 end
        u.state = "进攻城墙"
        self:Move(u, desiredX, y, dt)
    end
end

function Sim:Production(dt)
    for _, b in ipairs(self.grid.buildings) do
        local def = C.buildings[b.kind]
        b.shot = math.max(0, b.shot - dt)
        if def.interval > 0 and b.kind ~= "tower" then
            b.timer = math.min(def.interval, b.timer + dt)
            if b.timer >= def.interval then
                if def.upgrade then
                    -- 库存只是"待转职名额"，同样受兵力上限约束，避免攒出用不掉的库存。
                    if b.stock < 5 and self:ArmyCount() + b.stock < C.armyLimit then
                        b.stock, b.timer = b.stock + 1, 0
                    end
                elseif def.unit and self:ArmyCount() < C.armyLimit then
                    local size = C.units[def.unit].size
                    local spot = self:PickSpawn(self.grid:SpawnSpot(b, size), size)
                    if spot then
                        self:AddUnit(def.unit, "ally", spot.x + (size-1)*0.5, spot.y + (size-1)*0.5)
                        self.produced = self.produced + 1
                        b.timer = 0
                        if self.produced <= 5 or self.produced % 10 == 0 then print("[生产] " .. def.name .. "产出，累计" .. self.produced) end
                    end
                end
            end
        elseif b.kind == "tower" and b.shot <= 0 then
            local target = nil ---@type FrontierUnit?
            local dist = 8^2
            for _, v in ipairs(self.units) do
                if self:Active(v) and v.team == "enemy" then
                    local d = (v.x-b.x)^2 + (v.y-b.y)^2
                    if d < dist then target, dist = v, d end
                end
            end
            if target then
                b.shot = def.interval
                table.insert(self.shots, { x = b.x, y = b.y, target = target.id, team = "ally", damage = 15, speed = 16, life = 2 })
            end
        end
    end
end

function Sim:RoadLevel()
    return self.roadLevelValue
end

-- 主路成型情况：逐列取城门附近踩得最实的一格（建筑格跳过），
-- 主路等级取这些列里最普遍的水平，另统计有多少列已经踩到土路以上。
function Sim:SurveyRoad()
    local columns, qualified, tally = 0, 0, { 0, 0, 0, 0, 0 }
    for x = 2, C.wallCol - 1 do
        local best = -1
        for y = C.gateTop - 1, C.gateTop + C.gateWidth do
            local cell = self.grid:Get(x, y)
            if cell and cell.building == 0 then
                local level = self.grid:TrailLevel(x, y)
                if level > best then best = level end
            end
        end
        if best >= 0 then
            columns = columns + 1
            tally[best + 1] = tally[best + 1] + 1
            if best >= 2 then qualified = qualified + 1 end
        end
    end
    local mode, modeCount = 0, -1
    for level = 0, 4 do
        if tally[level + 1] > modeCount then mode, modeCount = level, tally[level + 1] end
    end
    self.roadLevelValue = mode
    self.roadProgress = columns > 0 and qualified / columns or 0
end

function Sim:Step(dt)
    if self.paused or self.phase == "victory" or self.phase == "defeat" then return end
    self.time = self.time + dt
    self.commandTimer = math.max(0, self.commandTimer - dt)
    self.noticeTime = math.max(0, self.noticeTime - dt)
    self.gold = self.gold + C.passiveIncome * dt
    -- 兵力计数每帧统一刷新一次，之后生产/转职/胜负判定直接读缓存字段。
    self:RefreshCounts()
    if self.phase == "develop" then
        self.phaseTime = math.max(0, self.phaseTime - dt)
        if self.phaseTime == 0 then self:StartWave(false) end
    elseif self.phase == "battle" or self.phase == "boss" then
        self.spawnTimer = self.spawnTimer - dt
        if self.spawnTimer <= 0 and #self.waveQueue > 0 then
            local kind = self.waveQueue[1]
            if self:SpawnEnemy(kind) then
                table.remove(self.waveQueue, 1)
                self.spawnTimer = self.phase == "boss" and 1.3 or math.max(0.6, 1.5 - self.wave * 0.15)
            else
                -- 右侧暂时没有空位：稍后再试，不要把敌人丢在重叠坐标上。
                self.spawnTimer = 0.4
            end
        end
        if #self.waveQueue == 0 and self:EnemyCount() == 0 and self.phase == "battle" then self:WaveComplete() end
    end
    self:Production(dt)
    self:GateStep()
    self.blockedCount = 0
    for _, u in ipairs(self.units) do
        if self:Active(u) then
            u.cooldown, u.repath = math.max(0, u.cooldown-dt), math.max(0, u.repath-dt)
            u.flash, u.moving = math.max(0, u.flash-dt), false
            if u.team == "ally" then self:ApplyCommand(u); self:UpgradeUnit(u) end
            local target = self:Target(u)
            if target and (u.passedGate or u.team == "enemy") then self:Combat(u, target, dt)
            elseif u.team == "ally" then self:AllyGoal(u, dt)
            else self:EnemyGoal(u, dt) end
            if self.phase == "victory" or self.phase == "defeat" then return end
            if u.blocked > 0.7 then self.blockedCount = self.blockedCount + 1 end
        end
    end
    for i = #self.shots, 1, -1 do
        local p = self.shots[i]
        p.life = p.life - dt
        local target = self:FindUnit(p.target)
        if not target or not self:Active(target) or p.life <= 0 then table.remove(self.shots, i)
        else
            local dx, dy = target.x-p.x, target.y-p.y
            local dist = math.sqrt(dx*dx+dy*dy)
            local step = p.speed*dt
            if dist <= step then self:Damage(target, p.damage); table.remove(self.shots, i)
            else p.x, p.y = p.x+dx/dist*step, p.y+dy/dist*step end
        end
        if self.phase == "victory" or self.phase == "defeat" then return end
    end
    for i = #self.effects, 1, -1 do
        self.effects[i].life = self.effects[i].life-dt
        if self.effects[i].life <= 0 then table.remove(self.effects, i) end
    end
    for i = #self.units, 1, -1 do
        if self.units[i].hp <= 0 then
            local last = self.units[#self.units]
            self.units[i], self.units[#self.units] = last, self.units[i]
            self.units[#self.units] = nil
        end
    end
    self:RefreshCounts()
    self.diagnosticTimer = self.diagnosticTimer + dt
    if self.diagnosticTimer >= 15 then
        self.diagnosticTimer = 0
        print(string.format("[状态] %s 第%d波 部队%d 敌人%d 拥堵%d 城墙%.0f", self.phase, self.wave, self:ArmyCount(), self:EnemyCount(), self.blockedCount, self.wallHp))
    end
    self.roadTimer = self.roadTimer + dt
    if self.roadTimer >= 1 then
        self.roadTimer = 0
        self:SurveyRoad()
    end
end
return Sim
