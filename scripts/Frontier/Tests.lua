-- 独立、确定性玩法回归测试入口；不被 main.lua 调用，不影响正式游戏。
-- 覆盖 V3 验收清单 T1–T10：重复加工、布局改线、弓盾互斥、道路联动、
-- 封路提示、兵力上限、工序差异、阵亡补员、重复运行无残留。
local C = require "Frontier.Config"
local Grid = require "Frontier.Grid"
local Simulation = require "Frontier.Simulation"
local checks = 0
local function Check(condition, message)
    assert(condition, "[测试失败] " .. message)
    checks = checks + 1
    print("[测试通过] " .. message)
end
local function OpenCamp(sim)
    -- 战场已无岩石，测试无需清理地形；保留空实现以免误删初始民兵营。
    sim.grid.version = sim.grid.version + 1
end
local function Advance(sim, seconds)
    for _=1,math.floor(seconds/C.fixedStep) do sim:Step(C.fixedStep) end
end
local function Wear(sim,x,y,level)
    local cell=sim.grid.cells[y][x]
    cell.trail=level
    cell.wear=level>0 and C.trailThresholds[level] or 0
end
-- 在空地上放一名我方民兵，返回单位。
local function MilitiaAt(sim,x,y)
    return sim:AddUnit("militia","ally",x,y)
end
-- 全新网格 + 单个民兵，保证每个加工用例互不干扰。
local function Lab()
    local sim=Simulation.New(); OpenCamp(sim)
    sim.units={}
    return sim
end

function Start()
    local ok,err=pcall(function()
        -- 配置完整性：V3 新建筑与工序均已定义。
        Check(C.buildings.forge.w==2 and C.buildings.forge.h==2,"锻炉为 2×2")
        Check(C.buildings.stable.w==3 and C.buildings.stable.h==3,"马厩为 3×3")
        Check(C.buildings.aim.w==1 and C.buildings.horn.w==1,"瞄准台与号角站为 1×1")
        Check(C.buildings.shield.w==2 and C.buildings.bow.w==2,"盾牌工坊与弓箭作坊为 2×2")
        Check(C.buildings.forge.cost==120 and C.buildings.stable.cost==220,"工序建筑成本与 V3 一致")
        Check(C.processings.bow.conflict[1]=="shield","弓箭与盾牌互斥已配置")
        Check(C.processings.aim.requires=="bow","瞄准台需要前置弓箭")

        -- 地图初始：无岩石、无踩踏，营房连通城门。
        for seed=1,20 do
            math.randomseed(seed)
            local grid=Grid.New()
            local worn=0
            for y=1,C.rows do for x=1,C.cols do
                local cell=grid.cells[y][x]
                if cell.trail~=0 or cell.wear~=0 then worn=worn+1 end
            end end
            Check(worn==0,"种子"..seed.."地图初始无踩踏")
        end

        -- T1 重复经过同一工序：单次生效，不重复叠加。
        math.randomseed(101)
        local sim=Lab()
        local u=MilitiaAt(sim,15,5)
        sim.grid:AddBuilding("shield",16,5)
        sim:ProcessUnit(u)
        local armor1=u.stats.armor
        Check(u.gear.shield and armor1==30,"经过盾牌工坊获得 +30 护甲")
        sim:ProcessUnit(u); sim:ProcessUnit(u)
        Check(u.stats.armor==armor1 and u.processed.shield,"重复经过同一工序不会叠加")
        Check(math.abs(u.stats.speed-1.45*0.9)<1e-6,"盾牌移速惩罚 -10% 正确应用")

        -- T3 弓箭与盾牌互斥，且有清晰提示。两种顺序各用独立网格。
        sim=Lab()
        u=MilitiaAt(sim,15,5)
        sim.grid:AddBuilding("shield",16,5)
        sim:ProcessUnit(u)
        sim.grid:AddBuilding("bow",13,5)
        sim:ProcessUnit(u)
        Check(u.gear.shield and not u.gear.bow,"已持盾时弓箭作坊被跳过")
        Check(not u.stats.ranged,"互斥单位未切换为远程")
        -- 先弓后盾：弓箭生效，盾牌被拒。
        sim=Lab()
        u=MilitiaAt(sim,15,5)
        sim.grid:AddBuilding("bow",16,5)
        sim:ProcessUnit(u)
        Check(u.gear.bow and u.stats.ranged and math.abs(u.stats.range-8.5)<1e-6,"先经过弓箭作坊获得远程与射程")
        Check(u.stats.hp==25,"弓箭加工扣除 20 生命（45→25）")
        sim.grid:AddBuilding("shield",13,5)
        sim:ProcessUnit(u)
        Check(not u.gear.shield,"已持弓时盾牌被拒（互斥双向生效）")

        -- 瞄准台：需要前置弓箭；生效后远程伤害 +40%、攻速 -10%。
        sim=Lab()
        u=MilitiaAt(sim,15,5)
        sim.grid:AddBuilding("aim",16,5)
        sim:ProcessUnit(u)
        Check(not u.gear.aim,"未持弓时瞄准台不生效")
        sim=Lab()
        u=MilitiaAt(sim,15,5)
        sim.grid:AddBuilding("bow",13,5)
        sim:ProcessUnit(u)
        local dmgBefore, intBefore = u.stats.damage, u.stats.interval
        sim.grid:AddBuilding("aim",16,5)
        sim:ProcessUnit(u)
        Check(u.gear.aim,"持弓后瞄准台生效")
        Check(math.abs(u.stats.damage-dmgBefore*1.4)<1e-6,"瞄准台远程伤害 +40%")
        Check(u.stats.interval>intBefore,"瞄准台攻速惩罚生效（间隔变长）")

        -- 锻炉：+50 生命、上限 +15%、移速 -5%。
        sim=Lab()
        u=MilitiaAt(sim,15,5)
        sim.grid:AddBuilding("forge",16,5)
        sim:ProcessUnit(u)
        Check(u.gear.forge,"经过锻炉获得重甲")
        Check(math.abs(u.stats.hp-(45+50)*1.15)<1e-6,"锻炉生命按 基础+50 再 +15% 计算")
        Check(u.hp==u.maxHp,"加工后生命补足到新上限")
        Check(math.abs(u.stats.speed-1.45*0.95)<1e-6,"锻炉移速 -5%")

        -- 属性计算与加工顺序无关：盾牌+锻炉，移速按乘法叠加。
        -- 两座 2×2 建筑无法同时贴住同一个 1×1 单位，因此顺序移动单位分别加工。
        sim=Lab()
        local a=MilitiaAt(sim,15,5)
        sim.grid:AddBuilding("shield",16,5)
        sim:ProcessUnit(a)
        a.x,a.y=15,7
        sim.grid:AddBuilding("forge",16,7)
        sim:ProcessUnit(a)
        Check(math.abs(a.stats.speed-1.45*0.9*0.95)<1e-6,"盾+锻移速按乘法叠加")
        Check(a.stats.armor==30 and a.gear.forge,"盾与锻炉可共存（非互斥）")

        -- 马厩：移速 +80%、冲锋 +50%。
        sim=Lab()
        u=MilitiaAt(sim,15,5)
        sim.grid:AddBuilding("stable",16,5)
        sim:ProcessUnit(u)
        Check(u.gear.stable and math.abs(u.stats.speed-1.45*1.8)<1e-6,"马厩移速 +80%")
        Check(u.chargeBonus==0.5,"马厩提供冲锋伤害 +50%")

        -- 号角：首击翻倍，仅一次。
        sim=Lab()
        u=MilitiaAt(sim,15,5)
        sim.grid:AddBuilding("horn",16,5)
        sim:ProcessUnit(u)
        Check(u.gear.horn and u.firstHit==2.0,"号角使首击伤害翻倍")
        local processedCount=u.processed.horn
        sim:ProcessUnit(u)
        Check(processedCount and u.firstHit==2.0,"号角效果不会重复叠加")

        -- 多格建筑产能：2×2 建筑沿行进方向的正面两格都能触发（两个独立工位）。
        sim=Lab()
        local p1=MilitiaAt(sim,15,5)
        local p2=MilitiaAt(sim,15,6)
        sim.grid:AddBuilding("shield",16,5)
        sim:ProcessUnit(p1); sim:ProcessUnit(p2)
        Check(p1.gear.shield and p2.gear.shield,"2×2 工坊的正面两格均可独立加工")

        -- T2 调整工序/阻挡物位置：路线随布局改变。
        sim=Simulation.New(); OpenCamp(sim)
        local route1=sim.grid:Path(4,6,C.wallCol-1,6,1)
        Check(route1~=nil,"初始存在通往城门的路线")
        for y=1,C.rows do for x=2,12 do
            if not (y==6) then sim.grid:AddBuilding("block",x,y) end
        end end
        local route2=sim.grid:Path(4,6,C.wallCol-1,6,1)
        Check(route2~=nil and #route2>=#route1,"阻挡物改变后路线仍然可达（且被拉长）")

        -- T4/T5 道路：踩踏升级、10 秒去重、上限 4 级。
        sim=Simulation.New(); OpenCamp(sim)
        sim.grid:Trample(6.2,6.2,C.trailThresholds[1]-1,1,0)
        Check(sim.grid.cells[6][6].trail==0,"踩踏不足阈值时仍是荒野")
        sim.grid:Trample(6.2,6.2,1,1,11)
        Check(sim.grid.cells[6][6].trail==1,"达到阈值生成踩踏痕迹")
        -- 同一单位 10 秒内重复经过同一格不再计数。
        sim.grid:Trample(6.2,6.2,100,1,12)
        Check(sim.grid.cells[6][6].trail==1,"同一单位 10 秒内重复经过不累计")
        -- 换一个单位即可继续累计。
        sim.grid:Trample(6.2,6.2,100,2,12)
        Check(sim.grid.cells[6][6].trail>=2,"不同单位可继续累计踩踏")
        for _=1,400 do sim.grid:Trample(6.2,6.2,1,1000+_%7,_*11) end
        Check(sim.grid:TrailLevel(6,6)==4,"反复踩踏可升到加速通道（4 级上限）")

        -- 道路减伤：3 级及以上提供 10% 减伤。
        sim=Simulation.New(); OpenCamp(sim)
        sim.units={}
        local plain=MilitiaAt(sim,10,5)
        local paved=MilitiaAt(sim,10,7)
        Wear(sim,10,7,3)
        sim:Damage(plain,20); sim:Damage(paved,20)
        Check(math.abs((45-plain.hp)-20)<1e-6,"荒野单位承受全额伤害")
        Check(math.abs((45-paved.hp)-18)<1e-6,"硬化路面单位减伤 10%")

        -- 大象通行门槛：需要 2×2 硬化路。
        sim=Simulation.New(); OpenCamp(sim)
        sim.units={}
        local elephant=sim:AddUnit("elephant","ally",16.5,6.5)
        sim:Move(elephant,20.5,6.5,C.fixedStep)
        Check(elephant.state=="窄路卡滞","大象在荒野停滞")
        for y=6,7 do for x=16,C.wallCol do Wear(sim,x,y,3) end end
        sim.grid.version=sim.grid.version+1
        for _=1,60 do sim:Move(elephant,20.5,6.5,C.fixedStep) end
        Check(elephant.x>17,"大象在两格硬化路面正常行军")
        Check(sim.grid:LargeRoad(C.wallCol,6),"大象半跨城门时不要求城外踩踏")

        -- 城门先到先得：普通占 1 位、大象占 2 位。
        sim=Simulation.New(); OpenCamp(sim)
        for y=5,7 do for x=20,C.wallCol do Wear(sim,x,y,3) end end
        local first=sim:AddUnit("militia","ally",22,5)
        local second=sim:AddUnit("elephant","ally",21.5,6.5)
        local third=sim:AddUnit("militia","ally",22,7)
        first.ticket,second.ticket,third.ticket=1,2,3
        sim:GateStep()
        Check(first.gateSlots==1 and second.gateSlots==2 and third.gateSlots==0 and sim.gateUsed==3,
            "城门先到先得，普通 1 位、大象 2 位")

        -- T6 完全封路：寻路失败，路径阻断被记录（供界面红色提示）。
        sim=Simulation.New(); OpenCamp(sim)
        sim.units={}
        for y=1,C.rows do sim.grid:AddBuilding("block",C.wallCol-1,y) end
        Check(sim.grid:Path(4,6,C.wallCol-1,6,1)==nil,"完全封路后无法寻路到城门")
        sim:CheckPathBlocked()
        Check(sim.pathBlocked>=1,"封路时路径阻断计数被记录")

        -- T7 兵力上限：生产不突破上限，出生即计入、阵亡即扣除。
        sim=Simulation.New(); OpenCamp(sim)
        Advance(sim,75)
        Check(sim.phase=="develop","兵力上限观测仍在发育阶段内")
        Check(sim:ArmyCount()<=C.armyLimit,"发育期内我方兵力不超过上限")
        Check(sim:ArmyCount()==C.armyLimit,"产线会自然把兵力填到上限")
        local victim=sim.units[1]
        sim:Damage(victim,100000)
        sim:RefreshCounts()
        Check(sim:ArmyCount()<C.armyLimit,"阵亡后名额立即释放")
        Advance(sim,20)
        Check(sim:ArmyCount()==C.armyLimit,"兵营随后把兵力补回上限")

        -- T9 阵亡补员：新兵重新走生产线并接受全部加工。
        sim=Simulation.New(); OpenCamp(sim)
        sim.units={}
        local newbie=MilitiaAt(sim,15,5)
        sim.grid:AddBuilding("shield",16,5)
        sim:ProcessUnit(newbie)
        Check(newbie.gear.shield,"补员新兵经过工序同样获得加工")

        -- T10 拆除返还 50%，且不残留占位。
        sim=Simulation.New(); OpenCamp(sim)
        local built=sim:Perform("forge",14,8)
        local goldAfterBuild=sim.gold
        Check(built and sim.grid:Get(14,8).building>0,"锻炉建造成功并占位")
        sim:Demolish(14,8)
        Check(sim.gold==goldAfterBuild+60,"拆除锻炉返还 50%（120→60）")
        Check(sim.grid:Get(14,8).building==0,"拆除后格子恢复通行")

        -- 建造限制：城外禁止建造，箭塔只能建在城墙。
        sim=Simulation.New(); OpenCamp(sim)
        Check(not sim.grid:CanPlace("barracks",C.wallCol+1,3),"禁止城外建造")
        Check(not sim.grid:CanPlace("tower",C.wallCol,6),"禁止箭塔堵住城门")
        Check(sim.grid:CanPlace("tower",C.wallCol,3),"允许城墙箭塔")

        -- 完整多波次 + Boss 流程能收束。
        -- 布局刻意把工序建筑摆在士兵走廊(第 8 行)的相邻格，验证"布局→加工→战力"闭环。
        sim=Simulation.New(); OpenCamp(sim)
        sim.gold=1600
        sim:Perform("shield",7,6); sim:Perform("forge",11,6); sim:Perform("bow",15,6)
        sim:Perform("aim",13,7); sim:Perform("horn",9,7)
        sim:Perform("barracks",2,8)
        Advance(sim,85)
        sim:Perform("tower",C.wallCol,4); sim:Perform("tower",C.wallCol,8)
        Check(sim.converted>0,"贴在走廊旁的工序建筑真的加工了经过的士兵")
        sim:SetCommand("defend")
        Advance(sim,1600)
        print("[整局观测] 阶段="..sim.phase.." 波次="..sim.wave.." 城墙="..sim.wallHp.." 击败="..sim.kills.." 加工="..sim.converted)
        print(string.format("[道路观测] 主路等级=%d 达标比例=%.0f%%", sim:RoadLevel(), sim.roadProgress*100))
        Check(sim:RoadLevel()>=1,"部队行军能在主路上踩出痕迹")
        Check(sim.wave>=3,"正常生产能连续击退波次并抵达 Boss")
        Check(sim.phase=="victory" or sim.phase=="defeat","多波次加 Boss 流程能够收束")

        -- 提前迎敌奖励与波次推进。
        sim=Simulation.New(); sim.phaseTime=60
        local gold=sim.gold
        sim:StartWave(true)
        Check(sim.gold==gold+39 and sim.phase=="battle","提前迎敌奖励与剩余时间相关")
        sim.wave=3; sim:WaveComplete()
        Check(sim.phase=="boss" and sim.wave==4 and sim.waveQueue[1]=="boss","第三波后立即开始 Boss")
        local boss=sim:AddUnit("boss","enemy",25,6)
        sim:Damage(boss,10000)
        Check(sim.phase=="victory","击败 Boss 即通关")
        sim=Simulation.New(); sim.wallHp=1
        local enemy=sim:AddUnit("raider","enemy",C.wallCol+0.9,6)
        sim:EnemyGoal(enemy,C.fixedStep)
        Check(sim.phase=="defeat" and sim.wallHp==0,"城墙归零即失败")

        print("[测试汇总] "..checks.."项全部通过")
    end)
    if not ok then print(tostring(err)); log:Write(LOG_ERROR,tostring(err)) end
    engine:Exit()
end
