-- 专项逻辑修复验收入口：独立运行，不被正式 main.lua 引用。
-- assert 直接抛出失败，不使用 pcall；-validate 必须观察到最终 PASS 汇总。
local C = require "Frontier.Config"
local Simulation = require "Frontier.Simulation"
local checks = 0

local function Check(condition, message)
    assert(condition, "[LogicRepair FAIL] " .. message)
    checks = checks + 1
    print("[LogicRepair PASS] " .. message)
end

local function Lab()
    math.randomseed(41011)
    local sim = Simulation.New()
    for i = #sim.grid.resources, 1, -1 do sim.grid:RemoveResource(sim.grid.resources[i]) end
    sim.units = {}
    sim:RefreshCounts()
    return sim
end

local function Quad(x, y)
    return { { x = x, y = y }, { x = x + 1, y = y },
        { x = x, y = y + 1 }, { x = x + 1, y = y + 1 } }
end

local function Reserve(sim, u, res, x, y, task)
    u.targetResource, u.targetCell, u.task = res.id, { x = x, y = y }, task or "toResource"
    res.reserved = res.reserved + 1
    sim:ReserveCell(x, y, u.id)
    u.gatherVersion = sim.grid.version
end

local function Wear(sim, x, y, level)
    local cell = sim.grid.cells[y][x]
    cell.trail, cell.wear = level, level > 0 and C.trailThresholds[level] or 0
end

local function Farm(sim)
    for _, b in ipairs(sim.grid.buildings) do
        if b.kind == "farmerBarracks" then return b end
    end
    error("[LogicRepair FAIL] missing farmer barracks")
end

local function TickFarmer(sim, u, seconds)
    for _ = 1, math.floor(seconds / C.fixedStep + 0.5) do
        sim.time = sim.time + C.fixedStep
        u.repath = math.max(0, u.repath - C.fixedStep)
        sim:FarmerGoal(u, C.fixedStep)
    end
end

local function GatherRepair()
    for _, task in ipairs({ "toResource", "gathering" }) do
        local sim = Lab()
        local res = sim.grid:AddResource("mineral", Quad(9, 3))
        local u = sim:AddUnit("farmer", "ally", 6, 3)
        Reserve(sim, u, res, 8, 3, task)
        u.gatherTimer = 0
        local stock = res.stock
        Check(sim:Perform("block", 8, 3), task .. ": 玩家可在已预约但未占据格建阻挡物")
        sim:FarmerGoal(u, C.fixedStep)
        Check(sim:CellFree(8, 3), task .. ": 失效交互格释放预约，不永久卡位")
        Check(u.targetCell ~= nil and (u.targetCell.x ~= 8 or u.targetCell.y ~= 3)
            and sim.grid:IsWalkable(u.targetCell.x, u.targetCell.y), task .. ": 改选可通行作业位")
        Check(res.stock == stock and u.carry == 0, task .. ": 目标失效不凭空采集或扣储量")
        Check(res.reserved == 1 and sim:ReservedForResource(res) == 1,
            task .. ": 释放后重选只保留一个资源预约")
    end

    local sim = Lab()
    local res = sim.grid:AddResource("mineral", Quad(10, 8))
    local u = sim:AddUnit("farmer", "ally", 6, 6)
    Reserve(sim, u, res, 9, 8)
    Check(sim.grid:Path(6, 6, 9, 8, 1) ~= nil, "切断走廊前目标可达")
    for y = 1, C.rows do Check(sim:Perform("block", 8, y), "走廊阻挡建造 row " .. y) end
    Check(sim.grid:IsWalkable(9, 8) and sim.grid:Path(6, 6, 9, 8, 1) == nil,
        "交互格仍 walkable 但整条走廊已不可达")
    sim:FarmerGoal(u, C.fixedStep)
    Check(u.targetResource == nil and u.targetCell == nil and sim:CellFree(9, 8)
        and res.reserved == 0, "不可达目标释放资源和格子预约")
    Check(u.task == "wait" and u.waitTimer > 0, "完全不可达时限频等待，不每帧重选")
    sim:Demolish(8, 6)
    sim:FarmerGoal(u, C.fixedStep)
    Check(u.targetResource == res.id, "地图通路恢复后立即重选，不等待旧倒计时")
end

local function GateRepair()
    local sim = Lab()
    local elephant = sim:AddUnit("elephant", "ally", C.wallCol - 2.5, C.gateTop + 0.5)
    elephant.ticket = 1
    local troops = {}
    for i = 1, 4 do
        local u = sim:AddUnit("militia", "ally", C.wallCol - 2, C.gateTop + i % C.gateWidth)
        u.ticket = i + 1
        troops[i] = u
    end
    sim:GateStep()
    Check(elephant.gateSlots == 0 and elephant.ticket == 1,
        "无三级路 elephant ticket1 保留票号但不占门位")
    for i = 1, 3 do
        Check(troops[i].gateSlots == 1 and troops[i].gateLane == i,
            "可通行 militia ticket" .. (i + 1) .. " 按 FIFO 获得门位")
    end
    Check(troops[4].gateSlots == 0 and sim.gateUsed == C.gateWidth,
        "门位全部利用，后续可通行者仍按票号等待")
    for _, u in ipairs(troops) do u.active = false end
    for y = C.gateTop, C.gateTop + 1 do
        for x = C.wallCol - 3, C.wallCol do Wear(sim, x, y, 3) end
    end
    sim.grid.version = sim.grid.version + 1
    sim:GateStep()
    Check(elephant.gateSlots == 2 and elephant.ticket == 1,
        "道路硬化后先前不可通行者凭原票号恢复通行")
end

local function ProductionRepair()
    local sim = Lab()
    local res = sim.grid:AddResource("mineral", Quad(9, 3))
    local u = sim:AddUnit("farmer", "ally", 8, 3)
    Reserve(sim, u, res, 8, 3)
    local b = Farm(sim)
    b.timer = C.buildings.farmerBarracks.interval
    Check(sim:FreeGatherSlots() == 1 and sim:FarmerCount() == 1, "一矿2slots、已有1已预约农夫复现成立")
    sim:Production(0)
    Check(sim:FarmerCount() == 2 and sim.produced == 1, "已预约人口不双扣，确实产出第二名农夫")
    b.timer = C.buildings.farmerBarracks.interval
    sim:Production(0)
    Check(sim:FarmerCount() == 2, "达到有效总slots后不产第三人")
    local capacity = sim:GatherCapacity(b)
    res.stock = 0
    sim.grid:RemoveResource(res)
    Check(capacity == 2 and sim:GatherCapacity(b) == 0, "资源枯竭使缓存的作业容量立即失效")

    sim = Lab()
    sim.grid:AddResource("mineral", Quad(10, 8))
    for y = 1, C.rows do sim.grid:AddBuilding("block", 8, y) end
    b = Farm(sim)
    b.timer = C.buildings.farmerBarracks.interval
    Check(sim:GatherCapacity(b) == 0, "资源虽有slots，农民营出口不可达则有效容量为0")
    sim:Production(0)
    Check(sim:FarmerCount() == 0, "不可达矿不制造无事可做的农民")
    local barrier = sim.grid:Get(8, 6)
    assert(barrier)
    sim.grid:RemoveBuilding(barrier.building)
    b.timer = C.buildings.farmerBarracks.interval
    sim:Production(0)
    Check(sim:FarmerCount() == 1, "打通地图后容量缓存刷新，立即恢复生产")

    sim = Lab()
    sim.grid:AddResource("mineral", Quad(9, 3))
    for _, p in ipairs({ {8,3}, {8,4}, {11,3}, {11,4}, {9,2}, {10,2}, {9,5} }) do
        sim.grid:AddBuilding("block", p[1], p[2])
    end
    b = Farm(sim)
    Check(sim:GatherCapacity(b) == 1, "仅一个可达独占交互格时，2slots矿的有效容量降为1")

    sim = Lab()
    sim.grid:AddResource("forest", { { x = 9, y = 8 } })
    sim.grid:AddResource("forest", { { x = 9, y = 10 } })
    for _, p in ipairs({ {8,8}, {10,8}, {9,7}, {8,10}, {10,10}, {9,11} }) do
        sim.grid:AddBuilding("block", p[1], p[2])
    end
    Check(sim:GatherCapacity(Farm(sim)) == 1, "两个资源仅共享一个作业格时总容量不重复计算")
end

local function ReservationRepair()
    local sim = Lab()
    local mineral = sim.grid:AddResource("mineral", Quad(9, 8))
    local forest = sim.grid:AddResource("forest", { { x = 9, y = 11 }, { x = 10, y = 11 } })
    local f1 = sim:AddUnit("farmer", "ally", 9, 10)
    local f2 = sim:AddUnit("farmer", "ally", 10, 10)
    Reserve(sim, f1, mineral, 9, 10)
    Reserve(sim, f2, mineral, 10, 10)
    Check(sim:ReservedForResource(mineral) == 2 and sim:ReservedForResource(forest) == 0,
        "9,10/10,10两矿预约不把9,11森林串成满员")
    local f3 = sim:AddUnit("farmer", "ally", 8, 11)
    local target, adj = sim:FindGatherTarget(f3)
    Check(target == forest and adj ~= nil, "共享一格走廊下森林仍能被第三名农夫选择")
    f1.active = false
    Check(sim:ReservedForResource(mineral) == 1, "非active农夫不计作资源预约")

    sim = Lab()
    local concave = sim.grid:AddResource("forest", { { x = 9, y = 8 }, { x = 10, y = 9 },
        { x = 11, y = 9 }, { x = 11, y = 10 } })
    local f = sim:AddUnit("farmer", "ally", 9, 9)
    Reserve(sim, f, concave, 9, 9)
    Check(sim:ReservedForResource(concave) == 1, "一个交互格邻接同资源两格时只计一个农夫")
    sim:ReleaseSlot(f)
    sim:ReleaseSlot(f)
    Check(concave.reserved == 0 and sim:ReservedForResource(concave) == 0 and sim:CellFree(9, 9),
        "重复释放幂等，无负数或残留预约")
end

local function WarehouseRepair()
    local sim = Lab()
    local u = sim:AddUnit("farmer", "ally", 6, 8)
    u.task, u.carry, u.carryKind = "toWarehouse", 2, "mineral"
    local calls, original = 0, sim.FindWarehouse
    sim.FindWarehouse = function(self, worker)
        calls = calls + 1
        return original(self, worker)
    end
    TickFarmer(sim, u, C.gatherRetry * 0.9)
    Check(calls == 1 and u.carry == 2 and sim.harvested == 0,
        "无仓库数十帧只查一次，并保留携带资源")
    TickFarmer(sim, u, C.gatherRetry * 0.2)
    Check(calls == 2, "gatherRetry到期才重新查仓库")
    Check(sim:Perform("warehouse", 7, 8), "玩家在等待期间新增可达仓库")
    sim:FarmerGoal(u, C.fixedStep)
    Check(calls == 3 and u.carry == 0 and sim.harvested == 2,
        "新增仓库使下一帧立即查找并卸货，无重复入账")

    sim = Lab()
    local warehouse = sim.grid:AddBuilding("warehouse", 10, 8)
    for y = 1, C.rows do sim.grid:AddBuilding("block", 8, y) end
    u = sim:AddUnit("farmer", "ally", 6, 8)
    u.task, u.carry = "toWarehouse", 2
    sim:FarmerGoal(u, C.fixedStep)
    Check(u.state == "等待仓库" and u.targetCell == nil and u.waitTimer > 0,
        "已有仓库不可达时也限频等待")
    local barrier = sim.grid:Get(8, 8)
    assert(barrier)
    sim.grid:RemoveBuilding(barrier.building)
    sim:FarmerGoal(u, C.fixedStep)
    Check(u.state == "运送资源" and u.targetCell ~= nil,
        "地图版本变化打通路径后下一帧立即恢复运输")
    sim.grid:RemoveBuilding(warehouse.id)
    sim:FarmerGoal(u, C.fixedStep)
    Check(u.state == "等待仓库" and u.targetCell == nil and u.carry == 2,
        "仓库拆除即丢弃缓存落点，资源不能卸在消失的仓库")
end

local function WallFacingRepair()
    local sim = Lab()
    local u = sim:AddUnit("raider", "enemy", C.wallCol + 0.9, 6)
    u.facing = 1
    local before = sim.wallHp
    sim:EnemyGoal(u, C.fixedStep)
    Check(u.facing == -1 and u.state == "攻击城墙" and sim.wallHp < before,
        "敌人从朝右改为朝左攻击城墙且正常造成伤害")
    u.facing = 1
    sim:EnemyGoal(u, C.fixedStep)
    Check(u.facing == -1, "城墙攻击冷却期间也保持朝左")
end

local function MoveRepair()
    local sim = Lab()
    for x = 4, 12 do Wear(sim, x, 6, 4) end
    sim.grid.version = sim.grid.version + 1
    local l = sim.grid:LRoute(4, 5, 12, 5)
    local a = sim.grid:Path(4, 5, 12, 5, 1)
    assert(l and a)
    Check(sim:PathCost(l) == 8 and sim:PathCost(a) == 5.5,
        "y6 x4..12 trail4：A*成本5.5 vs L8，快31.25%")
    local u = sim:AddUnit("militia", "ally", 4, 5)
    local calls, original = 0, sim.grid.Path
    sim.grid.Path = function(self, ...)
        calls = calls + 1
        return original(self, ...)
    end
    sim:Move(u, 12, 5, 0)
    Check(sim:PathCost(u.path) == 5.5 and u.path[1].y == 6,
        "Move确实选A*快路，而非仅Grid:Path单独正确")
    Check(calls == 1, "初次选路只调用一次A*，不重复计算")
    for _ = 1, 120 do u.repath = 0; sim:Move(u, 12, 5, 0) end
    Check(calls == 1, "地图未变化即使repath到期也不重跑A*")
    Wear(sim, 5, 6, 3)
    sim.grid.version = sim.grid.version + 1
    sim:Move(u, 12, 5, 0)
    Check(calls == 2, "地图变化一次只做一次耗时比较")
    for _ = 1, 60 do u.repath = 0; sim:Move(u, 12, 5, 0) end
    Check(calls == 2, "比较未达15%也更新节流版本，不每帧反复A*")

    sim = Lab()
    local slow = sim.grid:LRoute(4, 5, 12, 5)
    assert(slow)
    sim.grid.Path = function() return { { x = 4, y = 6 }, { x = 5, y = 6 },
        { x = 6, y = 6 }, { x = 7, y = 6 }, { x = 8, y = 6 },
        { x = 9, y = 6 }, { x = 10, y = 6 }, { x = 11, y = 6 },
        { x = 12, y = 6 }, { x = 12, y = 5 } } end
    for x = 4, 12 do Wear(sim, x, 6, 2) end
    sim.grid.version = sim.grid.version + 1
    u = sim:AddUnit("militia", "ally", 4, 5)
    sim:Move(u, 12, 5, 0)
    Check(#u.path == #slow and u.path[1].x == 5 and u.path[1].y == 5,
        "绕路只快6.5%时保留L，不因小幅收益改道")

    sim = Lab()
    for x = 4, 12 do Wear(sim, x, 6, 4) end
    sim.grid.version = sim.grid.version + 1
    u = sim:AddUnit("militia", "ally", 4, 5)
    u.path = sim.grid:LRoute(4, 5, 12, 5) or {}
    u.goalX, u.goalY, u.pathVersion, u.repath = 12, 5, sim.grid.version - 1, 0
    calls, original = 0, sim.grid.Path
    sim.grid.Path = function(self, ...)
        calls = calls + 1
        return original(self, ...)
    end
    sim:Move(u, 12, 5, 0)
    Check(calls == 1 and sim:PathCost(u.path) == 5.5,
        "已持有L路径后升级道路，复用NeedsRepath的A*结果改走快路")
end

local function StrictLargeRepair()
    local sim = Lab()
    for y = 8, 9 do for x = 4, 5 do Wear(sim, x, y, 3) end end
    sim.grid.version = sim.grid.version + 1
    local u = sim:AddUnit("elephant", "ally", 4.5, 8.5)
    Check(sim.grid:LargeRoad(4, 8) and sim.grid:Path(4, 8, 10, 8, 2) ~= nil
        and sim.grid:Path(4, 8, 10, 8, 2, true) == nil,
        "大象起点硬化但中段未硬化：普通Path存在、strictLarge失败")
    local calls, nonStrict, original = 0, 0, sim.grid.Path
    sim.grid.Path = function(self, sx, sy, gx, gy, size, strict)
        calls = calls + 1
        if not strict then nonStrict = nonStrict + 1 end
        return original(self, sx, sy, gx, gy, size, strict)
    end
    sim:Move(u, 10.5, 8.5, C.fixedStep)
    Check(#u.path == 0 and nonStrict == 0 and u.x == 4.5,
        "strictLarge失败不回退普通Path，大象原地停住")
    sim:Move(u, 10.5, 8.5, C.fixedStep)
    Check(calls == 1, "失败strictLarge寻路在同版本下也节流")
    u.path = { { x = 6, y = 8 }, { x = 10, y = 8 } }
    Check(sim:NeedsRepath(u, 10, 8, 2, false), "缓存路径的未硬化步也判作失效")
    Check(not sim:PositionClear(u, 6.5, 8.5, true), "绕行或穿友军也不能跨未硬化格")
    u.path = {}
    for y = 8, 9 do for x = 4, 11 do Wear(sim, x, y, 3) end end
    sim.grid.version = sim.grid.version + 1
    sim:Move(u, 10.5, 8.5, C.fixedStep)
    Check(#u.path > 0 and u.x > 4.5 and nonStrict == 0,
        "地图补全硬化路后立即恢复严格寻路和移动")
    local valid = true
    for _, p in ipairs(u.path) do if not sim.grid:LargeRoad(p.x, p.y) then valid = false end end
    Check(valid, "恢复后的每一个大象路径步均满足2x2硬化路")
end

function Start()
    GatherRepair()
    GateRepair()
    ProductionRepair()
    ReservationRepair()
    WarehouseRepair()
    WallFacingRepair()
    MoveRepair()
    StrictLargeRepair()
    print("[LogicRepair SUMMARY] " .. checks .. " PASS / 0 FAIL")
    engine:Exit()
end
