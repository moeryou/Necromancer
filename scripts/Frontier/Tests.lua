-- 独立、确定性玩法回归测试入口；不被 main.lua 调用，不影响正式游戏。
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
    -- 战场已无岩石，测试无需再清理地形；保留空实现以免误删初始民兵营。
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

function Start()
    local ok,err=pcall(function()
        for seed=1,30 do
            math.randomseed(seed)
            local grid=Grid.New()
            local worn=0
            for y=1,C.rows do for x=1,C.cols do
                local cell=grid.cells[y][x]
                if cell.trail~=0 or cell.wear~=0 then worn=worn+1 end
            end end
            Check(worn==0,"种子"..seed.."地图没有岩石且初始无踩踏")
            Check(grid:Path(4,6,C.wallCol+1,6,1)~=nil,"种子"..seed.."初始营房连通城门")
        end
        math.randomseed(31)
        local sim=Simulation.New()
        OpenCamp(sim)
        Check(not sim.grid:CanPlace("barracks",C.wallCol+1,3),"禁止城外建造")
        Check(not sim.grid:CanPlace("tower",C.wallCol,6),"禁止箭塔堵住城门")
        Check(sim.grid:CanPlace("tower",C.wallCol,3),"允许城墙箭塔")
        local gold=sim.gold
        Check(not sim:Perform("clear",5,6) and not sim:Perform("road",5,6)
            and not sim:Perform("boost",5,6) and sim.gold==gold,"清岩、铺路、加速带操作已取消且不消耗资源")
        sim.grid:Trample(6.2,6.2,C.trailThresholds[1]-1)
        Check(sim.grid.cells[6][6].trail==0,"踩踏不足阈值时仍是荒野")
        sim.grid:Trample(6.2,6.2,1)
        Check(sim.grid.cells[6][6].trail==1,"累计踩踏达到阈值生成踩踏痕迹")
        sim.grid:Trample(6.2,6.2,C.trailThresholds[2]*2)
        Check(sim.grid.cells[6][6].trail>=2 and sim.grid:TrailLevel(6,6)==2,"继续踩踏升级为土路")
        sim.techLevel=1; sim.grid.techLevel=1
        for _,p in ipairs({{6,6},{7,6},{6,7},{7,7}}) do Wear(sim,p[1],p[2],3) end
        Check(sim.grid:LargeRoad(6,6,1) and sim.grid:TrailLevel(6,6)==3,"科技1允许踩踏到硬化路面并供大象通行")
        for _,p in ipairs({{6,6},{7,6},{6,7},{7,7}}) do Wear(sim,p[1],p[2],2) end
        Check(not sim.grid:LargeRoad(6,6,1),"土路不满足大象道路要求")
        sim.techLevel=0; sim.grid.techLevel=0
        Check(C.TrailCap(0)==2 and sim.grid:TrailLevel(6,6)==2,"无科技时踩踏封顶在土路")
        Check(not sim.grid:LargeRoad(6,6,0),"无科技时大象无法通行")
        sim=Simulation.New(); OpenCamp(sim)
        local b=sim.grid:AddBuilding("shield",7,5)
        b.stock=1
        local a=sim:AddUnit("militia","ally",6,5)
        local z=sim:AddUnit("militia","ally",6,6)
        sim:UpgradeUnit(a); sim:UpgradeUnit(z)
        Check(a.kind=="heavy" and z.kind=="militia" and b.stock==0,"一份库存仅转职先到单位")
        local bow=sim.grid:AddBuilding("bow",5,4)
        bow.stock=2
        a.x,a.y=4,4
        sim:UpgradeUnit(a)
        Check(a.kind=="heavy" and bow.stock==2,"单位只允许一次不可逆转职")
        sim.units={}
        local elephant=sim:AddUnit("elephant","ally",10.5,6.5)
        sim:Move(elephant,14.5,6.5,C.fixedStep)
        Check(elephant.state=="窄路卡滞" and elephant.x==10.5,"大象在荒野停滞")
        sim.techLevel=1; sim.grid.techLevel=1
        for y=6,7 do for x=10,16 do Wear(sim,x,y,3) end end
        sim.grid.version=sim.grid.version+1
        for _=1,60 do sim:Move(elephant,14.5,6.5,C.fixedStep) end
        Check(elephant.x>11,"大象在两格硬化路面正常行军")
        for y=6,7 do for x=16,C.wallCol do Wear(sim,x,y,3) end end
        Check(sim.grid:LargeRoad(C.wallCol,6,1),"大象半跨城门时不要求城外踩踏")
        sim.units={}
        for y=1,C.rows do for x=4,17 do Wear(sim,x,y,0) end end
        for x=6,17 do for y=5,6 do Wear(sim,x,y,3) end end
        for y=5,6 do Wear(sim,10,y,0) end
        for y=5,11 do
            for _,x in ipairs({8,9,11,12}) do Wear(sim,x,y,3) end
        end
        for y=10,11 do for x=8,12 do Wear(sim,x,y,3) end end
        sim.grid.version=sim.grid.version+1
        local detour=sim.grid:Path(8,5,14,5,2,true)
        Check(detour~=nil,"大象能找到更长的双宽硬化绕路")
        if detour then
            for _,point in ipairs(detour) do Check(sim.grid:LargeRoad(point.x,point.y,1),"硬化绕路不经过荒野捷径") end
        end
        local walker=sim:AddUnit("elephant","ally",8.5,5.5)
        for _=1,45*30 do sim:Move(walker,14.5,5.5,C.fixedStep) end
        Check(walker.x>13,"有完整硬化绕路时大象不永久卡滞在荒野捷径")
        sim.units={}
        for y=5,7 do for x=14,C.wallCol do Wear(sim,x,y,3) end end
        local first=sim:AddUnit("militia","ally",16,5)
        local second=sim:AddUnit("elephant","ally",15.5,6.5)
        local third=sim:AddUnit("militia","ally",16,7)
        first.ticket,second.ticket,third.ticket=1,2,3
        sim:GateStep()
        Check(first.gateSlots==1 and second.gateSlots==2 and third.gateSlots==0 and sim.gateUsed==3,"城门先到先得，普通1位大象2位")
        sim.units={}
        local obstruction=sim.grid:AddBuilding("block",17,5)
        local validLane=sim:AddUnit("elephant","ally",15.5,6.5)
        validLane.ticket=4
        sim:GateStep()
        Check(validLane.gateLane==2 and validLane.gateSlots==2,"上门行被建筑阻断时大象使用可达下两行")
        for _=1,15*30 do sim:GateStep(); sim:AllyGoal(validLane,C.fixedStep) end
        Check(validLane.passedGate,"合法下两行硬化路面可以让大象真正出门")
        sim.grid:RemoveBuilding(obstruction.id)
        sim.units={}
        for i=1,6 do
            local unit=sim:AddUnit("militia","ally",20+(i%2)*.9,3+i)
            unit.passedGate=true
        end
        sim:SetCommand("collect")
        for _,unit in ipairs(sim.units) do sim:AllyGoal(unit,C.fixedStep) end
        local targets={}
        for _,unit in ipairs(sim.units) do targets[unit.resourceId]=true end
        local n=0
        for id in pairs(targets) do if id>0 then n=n+1 end end
        Check(n>=2,"距离与局部竞争使部队选择不同资源点")
        sim.units={}
        local resource=sim.resources[1]
        resource.remaining=1
        local gatherer=sim:AddUnit("militia","ally",resource.x,resource.y)
        gatherer.passedGate=true
        gatherer.commandVersion=sim.commandVersion
        gatherer.resourceId=resource.id
        for _=1,60 do sim:AllyGoal(gatherer,C.fixedStep) end
        Check(resource.remaining==0 and gatherer.returning,"采集消耗实体库存并自动返回")
        sim=Simulation.New()
        sim.units={}
        local heavyCollector=sim:AddUnit("heavy","ally",20,3)
        heavyCollector.passedGate=true
        heavyCollector.returning=true
        local distantGuard=sim:AddUnit("guardian","enemy",24,3)
        distantGuard.neutral=true
        sim:SetCommand("collect")
        sim:Step(C.fixedStep)
        Check(not heavyCollector.returning and heavyCollector.resourceId>0,"交战中的新采集指令立即清除旧返程状态")
        for _=1,30 do sim:Combat(heavyCollector,distantGuard,C.fixedStep) end
        Check(heavyCollector.x>20 and heavyCollector.state=="自主采集","重甲看到远处守卫时仍继续采集，不永久原地停留")
        sim=Simulation.New(); OpenCamp(sim)
        Advance(sim,70)
        local outside=0
        for _,u in ipairs(sim.units) do if u.team=="ally" and u.passedGate then outside=outside+1 end end
        print("[行军观测] 已出门="..outside.." 部队="..sim:ArmyCount().." 拥堵="..sim.blockedCount)
        for _,u in ipairs(sim.units) do if u.team=="ally" then print(string.format("[行军] %d %.2f %.2f %s 门位%d",u.id,u.x,u.y,u.state,u.gateSlots)) end end
        Check(outside>=5,"默认生产单位能自然穿过城门，不发生永久死锁")
        Check(sim.phase=="develop","90秒之前仍处于发育阶段")
        Advance(sim,21)
        Check(sim.phase=="battle" and sim.wave==1,"90秒自动进入第一波")
        sim:SetCommand("defend")
        Advance(sim,160)
        print("[战斗观测] 阶段="..sim.phase.." 波次="..sim.wave.." 敌军="..sim:EnemyCount().." 城墙="..sim.wallHp)
        Check(sim.wave>=2 or sim.phase=="defeat","真实自主接战可结束波次或失败，不会无限僵持")
        sim=Simulation.New()
        sim.phaseTime=60
        gold=sim.gold
        sim:StartWave(true)
        Check(sim.gold==gold+39 and sim.phase=="battle","提前迎敌奖励与剩余时间相关")
        sim.wave=1; sim:WaveComplete()
        Check(sim.phase=="develop" and sim.wave==2 and sim.tech==2,"首波胜利奖励并进入第二轮")
        sim.wave=2; sim:WaveComplete()
        Check(sim.phase=="develop" and sim.wave==3,"第二波胜利进入第三轮")
        sim.wave=3; sim:WaveComplete()
        Check(sim.phase=="boss" and sim.wave==4 and sim.waveQueue[1]=="boss","第三波后立即开始Boss，没有额外发育")
        local boss=sim:AddUnit("boss","enemy",25,6)
        sim:Damage(boss,10000)
        Check(sim.phase=="victory","击败Boss即通关")
        sim=Simulation.New(); sim.wallHp=1
        local enemy=sim:AddUnit("raider","enemy",18.9,6)
        sim:EnemyGoal(enemy,C.fixedStep)
        Check(sim.phase=="defeat" and sim.wallHp==0,"城墙归零即失败")
        boss=sim:AddUnit("boss","enemy",25,6)
        sim:Damage(boss,10000)
        Check(sim.phase=="defeat","同帧后续Boss伤害不能覆写城墙归零败局")
        sim=Simulation.New(); sim.phase="boss"
        boss=sim:AddUnit("boss","enemy",25,6)
        sim:Damage(boss,10000)
        sim.wallHp=1
        enemy=sim:AddUnit("raider","enemy",18.9,6)
        sim:EnemyGoal(enemy,C.fixedStep)
        Check(sim.phase=="victory" and sim.wallHp==1,"先触发的Boss胜利不能被后续砸墙覆写")
        -- 从干净空地开始，以正常资源与生产推进整局，不直接修改兵种或战斗属性。
        -- 道路不再是买来的，只能靠部队自己踩出来。
        sim=Simulation.New(); OpenCamp(sim)
        sim:Perform("shield",6,3); sim:Perform("bow",9,3); sim:Perform("barracks",2,8)
        Advance(sim,85)
        sim:Perform("tower",18,4); sim:Perform("tower",18,8)
        sim:SetCommand("defend")
        Advance(sim,700)
        print("[整局观测] 阶段="..sim.phase.." 波次="..sim.wave.." 城墙="..sim.wallHp.." 击败="..sim.kills)
        print(string.format("[道路观测] 主路等级=%d 达标比例=%.0f%%", sim:RoadLevel(), sim.roadProgress*100))
        Check(sim:RoadLevel()>=2 and sim.roadProgress>=0.5,"部队的反复行军能把营地至城门踩成土路")
        Check(sim.wave>=3,"正常生产与资源规划能连续击退前两波")
        Check(sim.phase=="victory" or sim.phase=="defeat","完整多波次加Boss流程能够收束")
        print("[测试汇总] "..checks.."项全部通过")
    end)
    if not ok then print(tostring(err)); log:Write(LOG_ERROR,tostring(err)) end
    engine:Exit()
end
