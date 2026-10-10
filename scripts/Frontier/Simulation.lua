local C = require "Frontier.Config"
local Grid = require "Frontier.Grid"

---@class FrontierStats
---@field hp number
---@field armor number
---@field damage number
---@field range number
---@field speed number
---@field interval number
---@field sight number
---@field ranged boolean
---@field aoe? number
---@field size number

---@class FrontierUnit
---@field id number
---@field kind string
---@field team string
---@field x number
---@field y number
---@field hp number
---@field maxHp number
---@field size number
---@field stats FrontierStats
---@field base FrontierStats
---@field flat table
---@field pct table
---@field override table
---@field gear table<string, boolean>
---@field processed table<string, boolean>
---@field chargeBonus number
---@field firstHit number
---@field firstHitUsed boolean
---@field lastTarget number
---@field cooldown number
---@field path table[]
---@field pathVersion number
---@field goalX number
---@field goalY number
---@field repath number
---@field blocked number
---@field state string
---@field commandVersion number
---@field passedGate boolean
---@field ticket number
---@field gateLane number
---@field gateSlots number
---@field cellX? number
---@field cellY? number
---@field facing number
---@field moving boolean
---@field flash number
---@field active boolean
-- 农民专用
---@field worker boolean
---@field task string
---@field targetResource? number
---@field targetCell? table
---@field carry number
---@field carryKind? string
---@field gatherTimer number
---@field waitTimer number
---@field homeX number
---@field homeY number
---@field wanderAngle number

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
---@field harvested number
---@field notice string
---@field noticeTime number
---@field gateUsed number
---@field blockedCount number
---@field pathBlocked number
---@field diagnosticTimer number
---@field roadTimer number
---@field roadProgress number
---@field roadLevelValue number
---@field allyCount number
---@field enemyCount number
---@field farmerCount number
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
    self.kills, self.converted, self.produced, self.harvested = 0, 0, 0, 0
    self.allyCount, self.enemyCount, self.farmerCount = 0, 0, 0
    self.notice = "民兵营与农民营已就绪。建仓库、让农民采集资源，再规划你的生产线。"
    self.noticeTime, self.gateUsed, self.blockedCount = 8, 0, 0
    self.pathBlocked = 0
    self.diagnosticTimer = 0
    self.roadTimer, self.roadProgress, self.roadLevelValue = 0, 0, 0
    print("[游戏] 单机初始化：双产线（民兵/农民）+ 资源采集；被动 0.5/秒，初始 " .. C.startGold)
end

function Sim:Notify(text)
    self.notice, self.noticeTime = text, 4
    print("[操作] " .. text)
end

function Sim:Active(u)
    return u.active and u.hp > 0
end

function Sim:ArmyCount()
    return self.allyCount
end

function Sim:EnemyCount()
    return self.enemyCount
end

-- 农民不占战斗人口：allyCount 只统计战斗单位。
function Sim:FarmerCount()
    return self.farmerCount
end

function Sim:RefreshCounts()
    local ally, enemy, farmer = 0, 0, 0
    for _, u in ipairs(self.units) do
        if u.active and u.hp > 0 then
            if u.team == "enemy" then enemy = enemy + 1
            elseif u.worker then farmer = farmer + 1
            else ally = ally + 1 end
        end
    end
    self.allyCount, self.enemyCount, self.farmerCount = ally, enemy, farmer
end

-- 从单位模板复制一份可变的"基础属性"。所有加工都以此为起点，绝不直接改写模板。
---@param kind string
---@return FrontierStats
local function BaseStats(kind)
    local t = C.units[kind]
    return { hp = t.hp, armor = t.armor, damage = t.damage, range = t.range,
        speed = t.speed, interval = t.interval, sight = t.sight,
        ranged = t.ranged or false, aoe = t.aoe, size = t.size }
end

-- 属性统一按「基础值 → 固定值加成 → 百分比加成」计算，与加工顺序无关。
-- 固定值先求和，百分比再以乘法叠加（例如两个 -10% 与 -5% 得 0.9×0.95）。
function Sim:Recompute(u)
    local b, f, p = u.base, u.flat, u.pct
    local s = u.stats
    local oldMax = u.maxHp
    s.hp = math.max(1, (b.hp + (f.hp or 0)) * (p.hp or 1))
    s.armor = b.armor + (f.armor or 0)
    s.damage = (b.damage + (f.damage or 0)) * (p.damage or 1)
    s.speed = (b.speed + (f.speed or 0)) * (p.speed or 1)
    s.interval = math.max(0.2, (b.interval + (f.interval or 0)) * (p.interval or 1))
    s.range = u.override.range or b.range
    s.ranged = u.override.ranged ~= nil and u.override.ranged or b.ranged
    s.sight = b.sight
    s.aoe = b.aoe
    s.size = b.size
    u.maxHp = s.hp
    if oldMax and s.hp > oldMax then u.hp = u.hp + (s.hp - oldMax) end
    if u.hp > u.maxHp then u.hp = u.maxHp end
end

function Sim:AddUnit(kind, team, x, y)
    local t = C.units[kind]
    local base = BaseStats(kind)
    local u = { id = self.nextUnit, kind = kind, team = team, x = x, y = y,
        hp = base.hp, maxHp = base.hp, size = base.size,
        stats = {}, base = base, flat = {}, pct = {}, override = {},
        gear = {}, processed = {},
        chargeBonus = 0, firstHit = 1, firstHitUsed = false, lastTarget = 0,
        cooldown = 0, path = {}, pathVersion = 0, goalX = -1, goalY = -1, repath = 0, blocked = 0,
        state = "行军", commandVersion = 0, passedGate = team ~= "ally", ticket = 0,
        gateLane = 0, gateSlots = 0, facing = team == "ally" and 1 or -1,
        moving = false, flash = 0, active = true,
        worker = t.worker or false, task = "idle", carry = 0, carryKind = nil,
        gatherTimer = 0, waitTimer = 0, homeX = x, homeY = y, wanderAngle = 0 } --[[@as FrontierUnit]]
    u.stats = BaseStats(kind)
    self.nextUnit = self.nextUnit + 1
    self.units[#self.units + 1] = u
    if u.active and u.hp > 0 then
        if team == "enemy" then self.enemyCount = self.enemyCount + 1
        elseif u.worker then self.farmerCount = self.farmerCount + 1
        else self.allyCount = self.allyCount + 1 end
    end
    return u
end

-- 单位占地左上角格号（与 Grid:ProcessorsFor 的约定一致）。
function Sim:FootCell(u)
    local offset = (u.size - 1) * 0.5
    return math.floor(u.x - offset + 0.5), math.floor(u.y - offset + 0.5)
end

------------------------------------------------------------------
-- 接触式加工
------------------------------------------------------------------

function Sim:ProcessUnit(u)
    if u.team ~= "ally" or u.worker then return end
    local ux, uy = self:FootCell(u)
    local procs = self.grid:ProcessorsFor(ux, uy, u.size)
    for _, b in ipairs(procs) do
        local def = C.buildings[b.kind]
        local pr = def.proc and C.processings[def.proc]
        if pr and not u.processed[pr.tag] then
            local blocked = nil ---@type string?
            if pr.requires and not u.gear[pr.requires] then blocked = pr.conflictNote
            elseif pr.conflict then
                for _, c in ipairs(pr.conflict) do
                    if u.gear[c] then blocked = pr.conflictNote; break end
                end
            end
            if blocked then
                if u.lastReject ~= pr.tag then
                    u.lastReject = pr.tag
                    self:Notify(blocked)
                end
            elseif C.heavyProcessings[pr.tag] and self.gold < C.heavyProcessCost then
                -- 重装工序额外消耗矿物资源值，资源不足则跳过加工（不扣、不标记）。
                if u.lastReject ~= pr.tag then
                    u.lastReject = pr.tag
                    self:Notify("矿物不足（需 " .. C.heavyProcessCost .. " 资源值），无法完成" .. pr.label)
                end
            else
                if C.heavyProcessings[pr.tag] then self.gold = self.gold - C.heavyProcessCost end
                self:GrantProcessing(u, pr, b)
            end
        end
    end
end

function Sim:GrantProcessing(u, pr, b)
    u.processed[pr.tag] = true
    u.gear[pr.tag] = true
    if pr.flat then
        for k, v in pairs(pr.flat) do u.flat[k] = (u.flat[k] or 0) + v end
    end
    if pr.pct then
        -- 百分比加成以乘法叠加：pct[k] 存累计乘数，默认 1。
        for k, v in pairs(pr.pct) do u.pct[k] = (u.pct[k] or 1) * (1 + v) end
    end
    if pr.set then
        for k, v in pairs(pr.set) do u.override[k] = v end
    end
    if pr.charge then u.chargeBonus = u.chargeBonus + pr.charge end
    if pr.firstHit then u.firstHit = u.firstHit * pr.firstHit end
    self:Recompute(u)
    b.processed = (b.processed or 0) + 1
    self.converted = self.converted + 1
    self:Effect(u.x, u.y, "upgrade", C.buildings[pr.building].color, 0.65)
    if self.converted <= 8 or self.converted % 10 == 0 then
        print("[加工] 单位" .. u.id .. " 获得" .. pr.label .. "（" .. C.buildings[pr.building].name .. "）")
    end
end

------------------------------------------------------------------
-- 建造 / 拆除 / 指令
------------------------------------------------------------------

function Sim:Perform(tool, x, y)
    if self.phase == "victory" or self.phase == "defeat" then return false end
    local def = C.buildings[tool]
    if def then
        local ok, reason = self.grid:CanPlace(tool, x, y)
        if not ok then self:Notify(reason); return false end
        if self.gold < def.cost then self:Notify("资源不足"); return false end
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

function Sim:Demolish(x, y)
    if self.phase == "victory" or self.phase == "defeat" then return false end
    local cell = self.grid:Get(x, y)
    if not cell or cell.building <= 0 then self:Notify("此处没有可拆除的建筑"); return false end
    local b = self.grid:FindBuilding(cell.building)
    if not b then return false end
    local def = C.buildings[b.kind]
    local refund = math.floor(def.cost * C.refundRatio)
    self.grid:RemoveBuilding(b.id)
    self.gold = self.gold + refund
    self:Notify("已拆除" .. def.name .. "，返还 " .. refund .. " 资源")
    return true
end

function Sim:SetCommand(command)
    if self.phase == "victory" or self.phase == "defeat" then return end
    if self.commandTimer > 0 then self:Notify("全局指令冷却中"); return end
    if self.gold < C.commandCost then self:Notify("发布指令需要15资源"); return end
    self.gold = self.gold - C.commandCost
    self.command, self.commandTimer = command, C.commandCooldown
    self.commandVersion = self.commandVersion + 1
    self:Notify(C.commandNames[command] .. "：" .. C.commandNotes[command])
end

------------------------------------------------------------------
-- 波次
------------------------------------------------------------------

function Sim:StartWave(early)
    if self.phase ~= "develop" then return end
    if early and self.phaseTime > 0 then
        local reward = math.floor(self.phaseTime * 0.65)
        self.gold = self.gold + reward
        self:Notify("提前迎敌！奖励 " .. reward .. " 资源；趁敌人还没到，先摆好产线")
    end
    self.phase, self.phaseTime, self.spawnTimer = "battle", 0, 0.2
    self.waveQueue = {}
    -- 波次规模：原 8+wave*5 到第 3 波就有 23 个敌人，与我方 5 人上限严重失衡。
    -- 收敛到 7+wave*4 后，城墙会真正承压，但不会出现"打不完也打不死"的僵持。
    for i = 1, 7 + self.wave * 4 do
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
    self:Notify("第 " .. self.wave .. " 波击退！获得资源补给")
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

------------------------------------------------------------------
-- 战斗
------------------------------------------------------------------

function Sim:Damage(target, amount)
    if self.phase == "victory" or self.phase == "defeat" then return end
    if not self:Active(target) then return end
    -- 站在 3 级及以上硬化路面上的单位额外减伤 10%（"养路 = 提升战力"）。
    local level = self.grid:TrailLevel(target.x, target.y)
    local reduction = C.trailDamageReduction[level + 1] or 0
    -- 护甲是减法，但设有减伤下限，避免高护甲把敌人伤害完全归零。
    local afterArmor = math.max(amount * C.armorFloor, amount - target.stats.armor)
    local dealt = math.max(1, afterArmor) * (1 - reduction)
    target.hp = target.hp - dealt
    target.flash = 0.12
    if target.hp <= 0 then
        self:Effect(target.x, target.y, "death", C.units[target.kind].color, target.size * 0.5)
        target.active = false
        -- 农民阵亡立即释放已占用的采集位（V3.2 §3.4）。
        if target.worker then self:ReleaseSlot(target) end
        if target.team == "enemy" then self.kills = self.kills + 1 end
        if target.kind == "boss" then
            self.phase = "victory"
            self:Notify("破城巨兽已倒下，边境守住了！")
        end
    end
end

function Sim:Attack(u, target)
    local t = u.stats
    if u.cooldown > 0 then return end
    u.cooldown = t.interval
    u.facing = target.x > u.x and 1 or -1
    local multiplier = 1
    if not u.firstHitUsed and u.firstHit ~= 1 then multiplier = multiplier * u.firstHit end
    if u.chargeBonus > 0 and u.lastTarget ~= target.id then multiplier = multiplier * (1 + u.chargeBonus) end
    if not u.firstHitUsed then u.firstHitUsed = true end
    u.lastTarget = target.id
    local damage = t.damage * multiplier
    if t.ranged then
        table.insert(self.shots, { x = u.x, y = u.y, target = target.id, team = u.team,
            damage = damage, speed = 13, life = 2 })
    elseif t.aoe then
        self:Effect(target.x, target.y, "aoe", C.units[u.kind].color, t.aoe)
        for _, v in ipairs(self.units) do
            if self:Active(v) and v.team ~= u.team and (v.x - target.x)^2 + (v.y - target.y)^2 <= t.aoe^2 then
                self:Damage(v, damage)
            end
        end
    else
        self:Effect((u.x + target.x) / 2, (u.y + target.y) / 2, "hit", C.units[u.kind].color, 0.4)
        self:Damage(target, damage)
    end
end

function Sim:Target(u)
    local t = u.stats
    local best = nil ---@type FrontierUnit?
    local bestScore = math.huge
    local sight2 = t.sight * t.sight
    for _, v in ipairs(self.units) do
        -- 农民不参战、也不被选为目标。
        if v.active and v.hp > 0 and v.team ~= u.team and not v.worker
            and (v.x - u.x)^2 + (v.y - u.y)^2 <= sight2 then
            local dx, dy = v.x - u.x, v.y - u.y
            local dist = math.sqrt(dx * dx + dy * dy)
            local visible = true
            if u.x < C.wallCol - 0.5 or v.x < C.wallCol - 0.5 then visible = false end
            if u.team == "ally" and (self.command == "defend" or self.command == "wait") then
                if v.x > C.wallCol + 4.2 and dist > t.range then visible = false end
            end
            if visible then
                local score = dist
                if u.gear.stable and C.units[v.kind].ranged then score = score - 2.5 end
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

------------------------------------------------------------------
-- 移动与碰撞
------------------------------------------------------------------

function Sim:CollisionRadius(u, x, y)
    if u.size == 2 then return 0.87 end
    return 0.36
end

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
                if not (passAllies and other.team == u.team) then return false end
            end
        end
    end
    return true
end

-- 避让优先级（V3.2 §1.5）：农民 < 民兵 < 转职兵种 < 大象。数值越大越"重"，
-- 相向而行时轻单位主动侧移，重单位保持原路径。
function Sim:AvoidRank(u)
    if u.worker then return 1 end
    if u.size == 2 then return 4 end
    if next(u.gear) ~= nil then return 3 end
    return 2
end

function Sim:GateStep()
    local used = {}
    self.gateUsed = 0
    for _, u in ipairs(self.units) do
        if self:Active(u) and u.team == "ally" and not u.worker and not u.passedGate then
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
    -- 出城优先于进城、战斗单位优先于生产单位：票据内先按这两项排序（V3.2 §1.5）。
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

function Sim:CrowdDensity(x, y, u, radius)
    local count, r2 = 0, radius * radius
    for _, v in ipairs(self.units) do
        if v ~= u and v.active and v.hp > 0 then
            if (v.x - x)^2 + (v.y - y)^2 < r2 then count = count + 1 end
        end
    end
    return count
end

-- 路径惰性（V3.2 §1.3）：只有"路径被阻断""目标失效"或"新路径快 15% 以上"才重算。
-- 路径为空（阻断/失效）必须立刻重算；是否愿意做一次昂贵的 A* 比较，由
-- allowExpensive 控制（Move 里按 repathInterval 节流），避免每帧重算。
---@param allowExpensive boolean
function Sim:NeedsRepath(u, gx, gy, size, allowExpensive)
    if #u.path == 0 then return true end
    if not allowExpensive then return false end
    local fresh = self.grid:Path(math.floor(u.x), math.floor(u.y), gx, gy, size)
    if not fresh then return true end
    local curRemain, newTotal = 0, 0
    for _, p in ipairs(u.path) do curRemain = curRemain + C.trailCost[self.grid:TrailLevel(p.x, p.y) + 1] end
    for _, p in ipairs(fresh) do newTotal = newTotal + C.trailCost[self.grid:TrailLevel(p.x, p.y) + 1] end
    return newTotal < curRemain * (1 - C.repathGain)
end

function Sim:Move(u, tx, ty, dt)
    local t = u.stats
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
    if gx ~= u.goalX or gy ~= u.goalY then
        u.goalX, u.goalY, u.path = gx, gy, {}
    end
    -- 地图版本变化时才允许做一次昂贵的重算比较，并按 repathInterval 节流。
    local allowExpensive = u.repath <= 0
    if self:NeedsRepath(u, gx, gy, u.size, allowExpensive) then
        local path = nil ---@type table[]?
        -- 营地内普通战斗单位按"直线 + 横线"的最短 L 形折线行军，方向确定。
        if u.x < C.wallCol - 0.5 and u.size == 1 and not u.worker then
            path = self.grid:LRoute(sx, sy, gx, gy)
        end
        if not path and u.team == "ally" and u.size == 2 then
            path = self.grid:Path(sx, sy, gx, gy, u.size, true)
        end
        u.path = path or self.grid:Path(sx, sy, gx, gy, u.size) or {}
        u.pathVersion, u.repath = self.grid.version, C.repathInterval
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
    local stuck = u.blocked > 2.5
    if self:PositionClear(u, px, py) or (stuck and self:PositionClear(u, px, py, true)) then
        u.x, u.y, u.blocked, u.moving = px, py, 0, true
        if math.abs(dx) > 0.1 then u.facing = dx > 0 and 1 or -1 end
        -- 踩踏只发生在营地内（V3.2 §1.4 区域隔离）：荒野/城外地形永久为荒野。
        -- 只在"进入新格子"时记 1 次经过，同一单位 10 秒内折返同一格不再计数。
        local cx, cy = math.floor(u.x + 0.5), math.floor(u.y + 0.5)
        if u.cellX ~= cx or u.cellY ~= cy then
            u.cellX, u.cellY = cx, cy
            if u.team == "ally" and cx <= C.campMaxX then
                self.grid:Trample(u.x, u.y, 1, u.id, self.time)
            end
        end
    else
        u.blocked = u.blocked + dt
        u.state = "拥堵排队"
        if u.blocked > 0.35 and u.gateSlots == 0 then
            local fx, fy = dx / dist, dy / dist
            local lx, ly = -fy, fx
            -- 侧移方向偏向让路：轻单位优先向"人少"的一侧闪避（V3.2 §1.5）。
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
                    local score = self:CrowdDensity(ax, ay, u, 1.3) * 2 + c[3] * 0.35
                    if score < bestScore then bestX, bestY, bestScore = ax, ay, score end
                end
            end
            if bestX then u.x, u.y, u.moving = bestX, bestY, true end
        end
    end
end

function Sim:SpawnEnemy(kind)
    local t = C.units[kind]
    local size = t.size
    local offset = (size - 1) * 0.5
    local baseY = kind == "boss" and 6 or math.random(2, C.rows - 1)
    local baseX = C.cols - size + 1
    local probe = { size = size, stats = { size = size } } --[[@as FrontierUnit]]
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

function Sim:PickSpawn(candidates, size)
    local best, bestClear = nil, -1
    for _, spot in ipairs(candidates) do
        local x, y = spot.x + (size-1)*0.5, spot.y + (size-1)*0.5
        local probe = { size = size, stats = { size = size } } --[[@as FrontierUnit]]
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

------------------------------------------------------------------
-- 农民采集 AI（V3.2 §3）
------------------------------------------------------------------

-- 释放农民占用的采集位与目标。
function Sim:ReleaseSlot(u)
    if u.targetResource then
        local res = self.grid:FindResource(u.targetResource)
        if res and res.reserved > 0 then res.reserved = res.reserved - 1 end
    end
    u.targetResource, u.targetCell = nil, nil
end

-- 找到可抵达、有空闲采集位、距离最近的资源点及其相邻采集格。
function Sim:FindGatherTarget(u)
    local best, bestDist, bestCell = nil, math.huge, nil
    for _, res in ipairs(self.grid.resources) do
        if res.stock > 0 and res.reserved < res.slots then
            for _, c in ipairs(res.cells) do
                for _, adj in ipairs(self.grid:AdjacentWalkable(c.x, c.y)) do
                    local d = (adj.x - u.x)^2 + (adj.y - u.y)^2
                    -- 已枯竭或路径不通的点直接跳过。
                    if d < bestDist then
                        local path = self.grid:Path(math.floor(u.x), math.floor(u.y), adj.x, adj.y, 1)
                        if path then best, bestDist, bestCell = res, d, adj end
                    end
                end
            end
        end
    end
    return best, bestCell
end

-- 通行时间最短的仓库相邻格（V3.2 §3.3 运输阶段）。
function Sim:FindWarehouse(u)
    local bestCell, bestCost = nil, math.huge
    for _, b in ipairs(self.grid.buildings) do
        if b.kind == "warehouse" then
            for _, adj in ipairs(self.grid:AdjacentWalkable(b.x, b.y)) do
                local path = self.grid:Path(math.floor(u.x), math.floor(u.y), adj.x, adj.y, 1)
                if path then
                    local cost = 0
                    for _, p in ipairs(path) do cost = cost + C.trailCost[self.grid:TrailLevel(p.x, p.y) + 1] end
                    if cost < bestCost then bestCell, bestCost = adj, cost end
                end
            end
        end
    end
    return bestCell
end

function Sim:FarmerIdle(u, dt)
    u.state = "待命"
    u.waitTimer = u.waitTimer - dt
    -- 在农民营附近缓慢游荡，不堵路（V3.2 §3.4）。
    u.wanderAngle = u.wanderAngle + dt * 0.7
    local wx = u.homeX + math.cos(u.wanderAngle) * 1.6
    local wy = u.homeY + math.sin(u.wanderAngle * 0.8) * 1.2
    self:Move(u, wx, wy, dt * 0.5)
end

function Sim:FarmerGoal(u, dt)
    local cell = u.cellX
    -- 无仓库且无目标时进入待命；每 gatherRetry 秒复查一次。
    if u.task == "idle" or u.task == "wait" then
        if u.waitTimer > 0 then self:FarmerIdle(u, dt); return end
        u.waitTimer = C.gatherRetry
        local res, adj = self:FindGatherTarget(u)
        if res and adj then
            res.reserved = res.reserved + 1
            u.targetResource, u.targetCell = res.id, adj
            u.task, u.path = "toResource", {}
        else
            u.task = "wait"
            self:FarmerIdle(u, dt)
            return
        end
    end

    if u.task == "toResource" then
        local res = u.targetResource and self.grid:FindResource(u.targetResource)
        if not res or res.stock <= 0 or not u.targetCell then
            self:ReleaseSlot(u); u.task, u.waitTimer = "wait", 0
            return
        end
        u.state = "前往资源点"
        local d = math.abs(u.x - u.targetCell.x) + math.abs(u.y - u.targetCell.y)
        if d < 0.4 then
            u.task, u.gatherTimer = "gathering", C.resources[res.kind].gather
        else
            self:Move(u, u.targetCell.x, u.targetCell.y, dt)
        end
        return
    end

    if u.task == "gathering" then
        local res = u.targetResource and self.grid:FindResource(u.targetResource)
        if not res or res.stock <= 0 then
            self:ReleaseSlot(u); u.task, u.waitTimer = "wait", 0
            return
        end
        u.state = "采集中"
        u.gatherTimer = u.gatherTimer - dt
        if u.gatherTimer <= 0 then
            -- 每次采集扣 1 次储量、记 1 次资源，不重复结算（V3.2 §4.2）。
            res.stock = res.stock - 1
            local def = C.resources[res.kind]
            u.carry, u.carryKind = def.value, res.kind
            self:ReleaseSlot(u)
            u.task, u.path = "toWarehouse", {}
            if res.stock <= 0 then
                self.grid:RemoveResource(res)
                self:Notify(def.name .. "资源点已枯竭，地块恢复为普通营地格")
            end
        end
        return
    end

    if u.task == "toWarehouse" then
        local adj = self:FindWarehouse(u)
        if not adj then
            -- 所有仓库均不可达：保留携带资源原地待命（V3.2 §5.3）。
            u.state = "等待仓库"
            u.waitTimer = u.waitTimer - dt
            if u.waitTimer <= 0 then u.waitTimer = C.gatherRetry end
            return
        end
        u.state = "运送资源"
        local d = math.abs(u.x - adj.x) + math.abs(u.y - adj.y)
        if d < 0.4 then
            self.gold = self.gold + u.carry
            self.harvested = self.harvested + u.carry
            self:Effect(u.x, u.y, "upgrade", { 240, 210, 130 }, 0.4)
            u.carry, u.carryKind = 0, nil
            u.task, u.waitTimer = "wait", 0
        else
            self:Move(u, adj.x, adj.y, dt)
        end
        return
    end
end

------------------------------------------------------------------
-- 战斗单位 AI
------------------------------------------------------------------

function Sim:AllyGoal(u, dt)
    if not u.passedGate then
        local offset = (u.size - 1) * 0.5
        local row = math.max(C.gateTop, math.min(C.gateTop + C.gateWidth - u.size, math.floor(u.y - offset + 0.5)))
        if u.gateSlots > 0 then row = C.gateTop + u.gateLane - 1 end
        u.state = "向城门行军"
        local goalX = C.wallCol + 1.6
        if u.gateSlots > 0 and u.x < C.wallCol - 0.5 and math.abs(u.y - row - offset) > 0.12 then
            goalX = C.wallCol - 1
        end
        self:Move(u, goalX, row + offset, dt)
        return
    end
    self:ApplyCommand(u)
    if self.command == "attack" then
        -- 进攻推进到城墙外一小段即停，把敌人放进视野后由 Combat 接管。
        -- 若一路冲到敌人出生点，近战单位会撞上城墙、与远程敌人贴脸互啃，
        -- 既打不到也走不掉，形成长时间僵持。
        u.state = "向右推进"
        self:Move(u, C.wallCol + 4.5, u.y, dt)
    else
        -- 驻守位置必须贴住城门：敌人停在墙外约 wallCol+0.8 处磨墙，
        -- 若我军站在 wallCol+2.8，间距 2.0 远超近战射程 0.95，会站着看敌人拆墙。
        local x = C.wallCol + 1.8
        local y = math.max(2 + u.size * 0.5, math.min(C.rows - 1 - u.size * 0.5, u.y))
        if u.gear.stable and self.command == "defend" then y = 6 + math.sin(self.time * 0.65 + u.id) * 2 end
        u.state = self.command == "defend" and "固守防线" or "城外待命"
        if math.abs(u.x - x) > 0.4 or math.abs(u.y-y) > 0.5 then self:Move(u, x, y, dt) end
    end
end

function Sim:Combat(u, target, dt)
    local t = u.stats
    local dx, dy = target.x-u.x, target.y-u.y
    local dist = math.sqrt(dx*dx+dy*dy)
    local reach = t.range + (u.size + target.size - 2) * 0.35
    u.state = "自主交战"
    if dist <= reach then self:Attack(u, target) end
    if t.ranged then
        if u.team == "enemy" then
            -- 敌方远程不风筝：它的目标是城墙，边打边压上。
            -- 若停在射程边缘，遇上高护甲的我军会变成"双方都够不到对方"的永久僵持。
            if dist > reach * 0.55 then self:Move(u, target.x, target.y, dt) end
        else
            local desired = reach * (u.gear.stable and 0.85 or 0.9)
            if dist < desired * 0.65 then
                self:Move(u, u.x - dx / math.max(dist, 0.1) * 1.6, u.y - dy / math.max(dist, 0.1) * 1.6, dt)
            elseif dist > reach then
                self:Move(u, target.x - dx / math.max(dist, 0.1) * desired, target.y - dy / math.max(dist, 0.1) * desired, dt)
            elseif u.gear.stable then
                local flank = math.sin(self.time * 0.8 + u.id) > 0 and 1 or -1
                self:Move(u, u.x, u.y + flank * 0.8, dt)
            end
        end
    elseif dist > reach then
        if u.team == "ally" and (self.command == "defend" or self.command == "wait") then
            if target.x > C.wallCol + 4.2 then return end
        end
        if u.gear.forge and not u.gear.stable and dist > 2.6 then
            if self.command == "attack" then self:Move(u, u.x + 0.8, u.y, dt) end
            return
        end
        self:Move(u, target.x, target.y, dt)
    end
end

function Sim:EnemyGoal(u, dt)
    if self.phase == "victory" or self.phase == "defeat" then return end
    local t = u.stats
    local desiredX = C.wallCol + 0.8 + (u.size - 1) * 0.5
    if u.x <= desiredX + t.range * 0.2 then
        u.state = "攻击城墙"
        if u.cooldown <= 0 then
            -- 城墙吃伤害系数：否则 13 个掠夺者约 80dps，10 秒拆掉整面墙。
            self.wallHp = math.max(0, self.wallHp - t.damage * C.wallDamageScale)
            u.cooldown = t.interval
            self:Effect(C.wallCol, u.y, "aoe", C.units[u.kind].color, t.aoe or 0.5)
            if self.wallHp <= 0 then self.phase = "defeat"; self:Notify("城墙被攻破。重新规划生产线，再战一次。"); end
        end
    else
        local y = math.max(2, math.min(C.rows - 1, u.y))
        if u.kind == "boss" then y = 6 end
        u.state = "进攻城墙"
        self:Move(u, desiredX, y, dt)
    end
end

------------------------------------------------------------------
-- 生产
------------------------------------------------------------------

-- 采集位总余量：决定农民营是否继续产兵（按需产兵，V3.2 §3.1）。
function Sim:FreeGatherSlots()
    local free = 0
    for _, res in ipairs(self.grid.resources) do
        if res.stock > 0 then free = free + math.max(0, res.slots - res.reserved) end
    end
    return free
end

function Sim:Production(dt)
    for _, b in ipairs(self.grid.buildings) do
        local def = C.buildings[b.kind]
        b.shot = math.max(0, b.shot - dt)
        if def.unit then
            b.timer = math.min(def.interval, b.timer + dt)
            if b.timer >= def.interval then
                local canSpawn = false
                if def.unit == "farmer" then
                    -- 按需产兵：可用采集位 > 存活农民数时才继续生产。
                    canSpawn = self:FreeGatherSlots() > self:FarmerCount()
                        and self:FarmerCount() < C.farmerLimit
                else
                    canSpawn = self:ArmyCount() < C.armyLimit
                end
                if canSpawn then
                    local size = C.units[def.unit].size
                    local spot = self:PickSpawn(self.grid:SpawnSpot(b, size), size)
                    if spot then
                        local u = self:AddUnit(def.unit, "ally", spot.x + (size-1)*0.5, spot.y + (size-1)*0.5)
                        u.homeX, u.homeY = u.x, u.y
                        self.produced = self.produced + 1
                        b.timer = 0
                        if self.produced <= 5 or self.produced % 10 == 0 then
                            print("[生产] " .. def.name .. "产出，累计" .. self.produced)
                        end
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

-- 路径阻断检测：产兵建筑若找不到能通往城门的落点，就记为阻断（界面红色提示）。
function Sim:CheckPathBlocked()
    local blocked = 0
    for _, b in ipairs(self.grid.buildings) do
        local def = C.buildings[b.kind]
        if def.unit then
            local size = C.units[def.unit].size
            local reachable = false
            for _, spot in ipairs(self.grid:SpawnSpot(b, size)) do
                local offset = (size - 1) * 0.5
                local sx, sy = spot.x + offset, spot.y + offset
                -- 农民只需在营地内可达资源点，不要求通到城门。
                local goalX = def.unit == "farmer" and C.campMaxX or (C.wallCol - 1)
                local goalY = def.unit == "farmer" and math.max(2, math.min(C.rows - 1, math.floor(sy))) or C.gateTop
                local path = self.grid:Path(math.floor(sx), math.floor(sy), goalX, goalY, size, size == 2)
                if path then reachable = true; break end
            end
            if not reachable then blocked = blocked + 1 end
        end
    end
    self.pathBlocked = blocked
end

------------------------------------------------------------------
-- 路线反馈与道路统计
------------------------------------------------------------------

function Sim:RoadLevel()
    return self.roadLevelValue
end

function Sim:SurveyRoad()
    local columns, qualified, tally = 0, 0, { 0, 0, 0, 0, 0 }
    for x = 2, C.campMaxX do
        local best = -1
        for y = C.gateTop - 1, C.gateTop + C.gateWidth do
            local cell = self.grid:Get(x, y)
            if cell and not cell.solid and cell.resource == 0 then
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

------------------------------------------------------------------
-- 主循环
------------------------------------------------------------------

function Sim:Step(dt)
    if self.paused or self.phase == "victory" or self.phase == "defeat" then return end
    self.time = self.time + dt
    self.commandTimer = math.max(0, self.commandTimer - dt)
    self.noticeTime = math.max(0, self.noticeTime - dt)
    self.gold = self.gold + C.passiveIncome * dt
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
            if u.worker then
                self:FarmerGoal(u, dt)
            else
                if u.team == "ally" then self:ApplyCommand(u); self:ProcessUnit(u) end
                local target = self:Target(u)
                if target and (u.passedGate or u.team == "enemy") then self:Combat(u, target, dt)
                elseif u.team == "ally" then self:AllyGoal(u, dt)
                else self:EnemyGoal(u, dt) end
            end
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
        self:CheckPathBlocked()
        print(string.format("[状态] %s 第%d波 部队%d 农民%d 敌人%d 拥堵%d 阻断%d 城墙%.0f 资源%.0f",
            self.phase, self.wave, self:ArmyCount(), self:FarmerCount(), self:EnemyCount(),
            self.blockedCount, self.pathBlocked, self.wallHp, self.gold))
    end
    self.roadTimer = self.roadTimer + dt
    if self.roadTimer >= 1 then
        self.roadTimer = 0
        self:SurveyRoad()
    end
end
return Sim
