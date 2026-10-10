-- 独立、确定性玩法回归测试入口；不被 main.lua 调用，不影响正式游戏。
-- 覆盖 V3.2 验收清单 T1–T10（寻路/采集/资源/库存/地图生成/异常），
-- 以及 V3.0 的加工与互斥规则回归。
local C = require "Frontier.Config"
local Grid = require "Frontier.Grid"
local Simulation = require "Frontier.Simulation"
local checks = 0
local function Check(condition, message)
    assert(condition, "[测试失败] " .. message)
    checks = checks + 1
    print("[测试通过] " .. message)
end
local function Advance(sim, seconds)
    for _=1,math.floor(seconds/C.fixedStep) do sim:Step(C.fixedStep) end
end
local function Wear(sim,x,y,level)
    local cell=sim.grid.cells[y][x]
    cell.trail=level
    cell.wear=level>0 and C.trailThresholds[level] or 0
end
local function MilitiaAt(sim,x,y)
    return sim:AddUnit("militia","ally",x,y)
end
-- 全新网格 + 清空单位，保证每个用例互不干扰。
local function Lab()
    local sim=Simulation.New()
    sim.units={}
    sim:RefreshCounts()
    return sim
end
-- 清空随机生成的资源点，便于放置受控资源点。
local function ClearResources(sim)
    for i=#sim.grid.resources,1,-1 do
        local r=sim.grid.resources[i]
        for _,c in ipairs(r.cells) do sim.grid.cells[c.y][c.x].resource=0 end
        table.remove(sim.grid.resources,i)
    end
    sim.grid.version=sim.grid.version+1
end

function Start()
    local ok,err=pcall(function()
        ------------------------------------------------------------------
        -- 配置完整性
        ------------------------------------------------------------------
        Check(C.buildings.farmerBarracks.w==2 and C.buildings.farmerBarracks.cost==60,"农民营 2×2 / 60 资源")
        Check(C.buildings.warehouse.w==1 and C.buildings.warehouse.blocking==false,"仓库 1×1 且不阻挡通行")
        Check(C.passiveIncome==0.5 and C.startGold==420,"被动 0.5/秒、初始 420 资源")
        Check(C.units.farmer.worker==true,"农民标记为采集单位")
        Check(C.resources.forest.value==1 and C.resources.mineral.value==2,"森林1值 / 矿物2值")
        Check(C.heavyProcessings.shield and C.heavyProcessings.forge and C.heavyProcessings.stable,
            "盾/锻/马厩为重装工序（耗矿）")

        ------------------------------------------------------------------
        -- T9 地图生成校验：每局都保证通路正常、无重叠
        ------------------------------------------------------------------
        for seed=1,20 do
            math.randomseed(seed)
            local grid=Grid.New()
            Check(grid:ValidateMap(),"种子"..seed.."地图通过生成校验")
            Check(#grid.resources>=3,"种子"..seed.."至少生成 3 处资源点")
            -- 资源点互不重叠
            local seen={}
            local overlap=false
            for _,r in ipairs(grid.resources) do
                for _,c in ipairs(r.cells) do
                    local k=c.y*100+c.x
                    if seen[k] then overlap=true end
                    seen[k]=true
                end
            end
            Check(not overlap,"种子"..seed.."资源点无占地重叠")
            -- 民兵营到城门可达（从建筑出口出发，不能拿建筑内部格子当起点）
            local bar
            for _,b in ipairs(grid.buildings) do if b.kind=="barracks" then bar=b end end
            local exit=bar and grid:BuildingExit(bar)
            Check(exit~=nil and grid:Path(exit.x,exit.y,C.wallCol-1,C.gateTop,1)~=nil,
                "种子"..seed.."民兵营可达城门")
        end
        -- 保底地图：资源点位置固定且校验通过
        math.randomseed(999)
        local g2=Grid.New()
        g2:FallbackMap()
        Check(g2:ValidateMap(),"保底地图通过校验")
        Check(#g2.resources==5,"保底地图含 5 处资源点")

        ------------------------------------------------------------------
        -- T1 正交移动：路径相邻步只允许横竖
        ------------------------------------------------------------------
        local sim=Lab()
        local path=sim.grid:Path(4,5,C.wallCol-1,5,1)
        Check(path~=nil,"存在通往城门的路径")
        ---@cast path table[]
        local orthogonal=true
        local px,py=4,5
        for _,p in ipairs(path) do
            if math.abs(p.x-px)+math.abs(p.y-py)~=1 then orthogonal=false end
            px,py=p.x,p.y
        end
        Check(orthogonal,"路径每一步都是正交移动，无斜向穿行")

        ------------------------------------------------------------------
        -- T2 寻路时间优先：等距下优先高等级道路
        ------------------------------------------------------------------
        sim=Lab(); ClearResources(sim)
        -- 直路 y=5 全荒野(代价1.0×8)；绕路 y=7 全 4 级路(代价0.5×8)
        for x=4,12 do Wear(sim,x,7,4) end
        sim.grid.version=sim.grid.version+1
        local fast=sim.grid:Path(4,5,12,5,1)
        Check(fast~=nil,"时间最优路径存在")
        ---@cast fast table[]
        local usesRoad=false
        for _,p in ipairs(fast) do if p.y==7 then usesRoad=true end end
        Check(usesRoad,"等距下单位改走更快的硬化路面，而非直线最短")

        ------------------------------------------------------------------
        -- T3 路径惰性：小幅升级不改道，快 15% 以上才重算
        ------------------------------------------------------------------
        sim=Lab(); ClearResources(sim)
        local u=MilitiaAt(sim,4,5)
        -- 当前路径刻意走远路：y=7 全荒野，8 格代价 8.0。
        u.path={}
        for x=4,12 do u.path[#u.path+1]={x=x,y=7} end
        u.pathVersion=sim.grid.version
        u.repath=5
        -- 小幅升级：直路 y=5 只把两格提到 1 级（代价 7.7），仍不划算
        Wear(sim,6,5,1); Wear(sim,7,5,1)
        sim.grid.version=sim.grid.version+1
        Check(not sim:NeedsRepath(u,12,5,1,true),"道路小幅升级不触发改道")
        -- 大幅升级：直路 y=5 全提到 4 级（代价 4.0），显著快于远路 8.0
        for x=4,12 do Wear(sim,x,5,4) end
        sim.grid.version=sim.grid.version+1
        Check(sim:NeedsRepath(u,12,5,1,true),"新路径快 15% 以上时触发改道")

        ------------------------------------------------------------------
        -- T4 营地内外道路隔离：城外踩踏不升级
        ------------------------------------------------------------------
        sim=Lab(); ClearResources(sim)
        sim.units={}
        local out=MilitiaAt(sim,26,5)
        out.passedGate=true
        for _=1,120 do sim:Move(out,30,5,C.fixedStep) end
        local wildWear=0
        for x=C.wildMinX,C.wildMaxX do
            if sim.grid.cells[5][x].wear>0 then wildWear=wildWear+1 end
        end
        Check(wildWear==0 and out.x>26,"荒野行军不产生任何踩踏，地形永久为荒野")
        -- 营地内则正常累积
        sim=Lab(); ClearResources(sim)
        sim.units={}
        local inn=MilitiaAt(sim,4,8)
        for _=1,120 do sim:Move(inn,12,8,C.fixedStep) end
        local campWear=0
        for x=4,12 do if sim.grid.cells[8][x].wear>0 then campWear=campWear+1 end end
        Check(campWear>0,"营地内行军正常累积踩踏")

        ------------------------------------------------------------------
        -- T5 农民按需产兵：采集位满员后暂停生产
        ------------------------------------------------------------------
        sim=Lab(); ClearResources(sim)
        sim.units={}; sim:RefreshCounts()
        -- 无资源点：可用采集位为 0，不产农民
        Advance(sim,25)
        Check(sim:FarmerCount()==0,"无可用资源点时农民营不产兵")
        -- 放一处矿物（2 采集位）：应产出农民，且不超过 2 名
        sim.grid:AddResource("mineral",{{x=9,y=3},{x=10,y=3},{x=9,y=4},{x=10,y=4}})
        sim:Perform("warehouse",12,3)
        Advance(sim,40)
        Check(sim:FarmerCount()>0 and sim:FarmerCount()<=2,"采集位决定农民数量上限（2 位→最多 2 名）")

        ------------------------------------------------------------------
        -- T6 采集位机制：不超采集位上限
        ------------------------------------------------------------------
        sim=Lab(); ClearResources(sim)
        sim.units={}; sim:RefreshCounts()
        local res=sim.grid:AddResource("mineral",{{x=9,y=3},{x=10,y=3},{x=9,y=4},{x=10,y=4}})
        Check(res.slots==2,"标准 2×2 资源点有 2 个采集位")
        local f1=sim:AddUnit("farmer","ally",8,3)
        local f2=sim:AddUnit("farmer","ally",8,4)
        local f3=sim:AddUnit("farmer","ally",8,5)
        local r1,a1=sim:FindGatherTarget(f1); Check(r1~=nil,"第 1 名农民找到采集点")
        if r1 then r1.reserved=r1.reserved+1 end
        local r2,a2=sim:FindGatherTarget(f2); Check(r2~=nil,"第 2 名农民找到采集点")
        if r2 then r2.reserved=r2.reserved+1 end
        local r3,a3=sim:FindGatherTarget(f3)
        Check(r3==nil,"采集位满员后第 3 名农民找不到采集点（不扎堆）")
        -- 森林采集位按剩余格数：3 格 → 1 位
        local fr=sim.grid:AddResource("forest",{{x=16,y=9},{x=17,y=9},{x=17,y=10}})
        Check(fr.slots==1,"3 格森林按每 2 格 1 位得 1 个采集位")

        ------------------------------------------------------------------
        -- T7 资源枯竭：储量归零后资源点消失，地块恢复为普通空地
        ------------------------------------------------------------------
        sim=Lab(); ClearResources(sim)
        sim.units={}; sim:RefreshCounts()
        local res2=sim.grid:AddResource("mineral",{{x=9,y=3},{x=10,y=3},{x=9,y=4},{x=10,y=4}})
        Check(not sim.grid:IsWalkable(9,3),"资源点占格不可通行")
        local f=sim:AddUnit("farmer","ally",8,3)
        f.task,f.targetResource,f.targetCell="toResource",res2.id,{x=8,y=3}
        f.x,f.y=8,3
        res2.stock=1
        Advance(sim,6)
        Check(sim.grid:FindResource(res2.id)==nil,"储量归零后资源点实体移除")
        Check(sim.grid:IsWalkable(9,3) and sim.grid:IsWalkable(10,4),"枯竭后原占地恢复为普通空地（可通行）")
        Check(sim.grid:CanPlace("block",9,3),"枯竭后的格子可正常摆放建筑")
        -- 可正常累积踩踏
        sim.grid:Trample(9.2,3.2,3,77,0)
        Check(sim.grid:TrailLevel(9,3)>0,"枯竭后的格子可正常累积踩踏")

        ------------------------------------------------------------------
        -- T8 全局库存结算：仅卸货时入账；重装工序额外耗矿
        ------------------------------------------------------------------
        sim=Lab(); ClearResources(sim)
        sim.units={}; sim:RefreshCounts()
        local res3=sim.grid:AddResource("mineral",{{x=9,y=3},{x=10,y=3},{x=9,y=4},{x=10,y=4}})
        sim:Perform("warehouse",12,3)
        local farmer=sim:AddUnit("farmer","ally",8,3)
        local gold0=sim.gold
        -- 手动推进采集→运输→卸货
        farmer.task,f.targetResource,f.targetCell="toResource",res3.id,{x=8,y=3}
        farmer.x,farmer.y=8,3
        local delivered=false
        for _=1,60*30 do
            sim:Step(C.fixedStep)
            if sim.harvested>0 then delivered=true; break end
        end
        Check(delivered,"农民完成采集并卸货入库")
        Check(sim.harvested==2,"矿物 1 单位按 2 资源值结算")
        -- 重装工序耗矿：锻炉加工扣 2
        sim=Lab(); ClearResources(sim)
        sim.units={}; sim.gold=100
        local sm=MilitiaAt(sim,15,5)
        sim.grid:AddBuilding("forge",16,5)
        local before=sim.gold
        sim:ProcessUnit(sm)
        Check(sm.gear.forge and math.abs((before-sim.gold)-2)<1e-6,"锻炉加工额外消耗 2 资源值")
        -- 资源不足时跳过加工
        sim.gold=1
        sim.units={}
        local sm2=MilitiaAt(sim,15,5)
        sim:ProcessUnit(sm2)
        Check(not sm2.gear.forge,"资源不足时重装工序跳过，不消耗、不标记")

        ------------------------------------------------------------------
        -- T10 异常状态：无资源/无仓库时进入待命，不死循环
        ------------------------------------------------------------------
        sim=Lab(); ClearResources(sim)
        sim.units={}; sim:RefreshCounts()
        local idle=sim:AddUnit("farmer","ally",4,4)
        idle.homeX,idle.homeY=4,4
        Advance(sim,20)
        Check(idle.task=="wait" or idle.task=="idle","无资源点时农民进入待命状态")
        Check(idle.waitTimer>0,"待命农民设有复查计时，不会每帧无效寻路")
        -- 有资源但无仓库：采完原地待命、保留携带资源
        sim=Lab(); ClearResources(sim)
        sim.units={}; sim:RefreshCounts()
        local res4=sim.grid:AddResource("mineral",{{x=9,y=3},{x=10,y=3},{x=9,y=4},{x=10,y=4}})
        local f2=sim:AddUnit("farmer","ally",8,3)
        f2.task,f2.targetResource,f2.targetCell="toResource",res4.id,{x=8,y=3}
        f2.x,f2.y=8,3
        for _=1,20*30 do sim:Step(C.fixedStep) end
        Check(f2.task=="toWarehouse" and f2.carry>0,"无仓库时农民保留携带资源并等待")
        Check(f2.waitTimer>0,"等待仓库时设有复查计时")

        ------------------------------------------------------------------
        -- 回归：V3.0 加工规则
        ------------------------------------------------------------------
        math.randomseed(101)
        sim=Lab(); ClearResources(sim)
        local pu=MilitiaAt(sim,15,5)
        sim.grid:AddBuilding("shield",16,5)
        sim:ProcessUnit(pu)
        Check(pu.gear.shield and pu.stats.armor==30,"经过盾牌工坊获得 +30 护甲")
        sim:ProcessUnit(pu)
        Check(pu.stats.armor==30,"重复经过同一工序不会叠加")
        Check(math.abs(pu.stats.speed-1.45*0.9)<1e-6,"盾牌移速惩罚 -10% 正确应用")

        -- 弓盾双向互斥
        sim=Lab(); ClearResources(sim)
        local bu=MilitiaAt(sim,15,5)
        sim.grid:AddBuilding("bow",16,5)
        sim:ProcessUnit(bu)
        Check(bu.gear.bow and bu.stats.ranged and math.abs(bu.stats.range-8.5)<1e-6,"经过弓箭作坊获得远程与射程")
        Check(bu.stats.hp==25,"弓箭加工扣除 20 生命（45→25）")
        sim.grid:AddBuilding("shield",13,5)
        sim:ProcessUnit(bu)
        Check(not bu.gear.shield,"已持弓时盾牌被拒（双向互斥）")

        -- 瞄准台前置 + 效果
        sim=Lab(); ClearResources(sim)
        local au=MilitiaAt(sim,15,5)
        sim.grid:AddBuilding("aim",16,5)
        sim:ProcessUnit(au)
        Check(not au.gear.aim,"未持弓时瞄准台不生效")
        sim=Lab(); ClearResources(sim)
        au=MilitiaAt(sim,15,5)
        sim.grid:AddBuilding("bow",13,5)
        sim:ProcessUnit(au)
        local dmgBefore=au.stats.damage
        sim.grid:AddBuilding("aim",16,5)
        sim:ProcessUnit(au)
        Check(au.gear.aim and math.abs(au.stats.damage-dmgBefore*1.4)<1e-6,"持弓后瞄准台生效，远程伤害 +40%")

        -- 锻炉属性 + 盾锻叠加
        sim=Lab(); ClearResources(sim)
        local fu=MilitiaAt(sim,15,5)
        sim.grid:AddBuilding("shield",16,5)
        sim:ProcessUnit(fu)
        fu.x,fu.y=15,7
        sim.grid:AddBuilding("forge",16,7)
        sim:ProcessUnit(fu)
        Check(math.abs(fu.stats.speed-1.45*0.9*0.95)<1e-6,"盾+锻移速按乘法叠加")
        Check(math.abs(fu.stats.hp-(45+50)*1.15)<1e-6,"锻炉生命按 基础+50 再 +15% 计算")

        -- 马厩 / 号角
        sim=Lab(); ClearResources(sim)
        local su=MilitiaAt(sim,15,5)
        sim.grid:AddBuilding("stable",16,5)
        sim:ProcessUnit(su)
        Check(su.gear.stable and math.abs(su.stats.speed-1.45*1.8)<1e-6,"马厩移速 +80%")
        sim=Lab(); ClearResources(sim)
        local hu=MilitiaAt(sim,15,5)
        sim.grid:AddBuilding("horn",16,5)
        sim:ProcessUnit(hu)
        Check(hu.gear.horn and hu.firstHit==2.0,"号角使首击伤害翻倍")
        sim:ProcessUnit(hu)
        Check(hu.firstHit==2.0,"号角效果不会重复叠加")

        -- 2×2 工坊双工位
        sim=Lab(); ClearResources(sim)
        local p1=MilitiaAt(sim,15,5)
        local p2=MilitiaAt(sim,15,6)
        sim.grid:AddBuilding("shield",16,5)
        sim:ProcessUnit(p1); sim:ProcessUnit(p2)
        Check(p1.gear.shield and p2.gear.shield,"2×2 工坊的正面两格均可独立加工")

        -- 道路减伤
        sim=Lab(); ClearResources(sim)
        sim.units={}
        local plain=MilitiaAt(sim,10,5)
        local paved=MilitiaAt(sim,10,7)
        Wear(sim,10,7,3)
        sim:Damage(plain,20); sim:Damage(paved,20)
        Check(math.abs((45-plain.hp)-20)<1e-6,"荒野单位承受全额伤害")
        Check(math.abs((45-paved.hp)-18)<1e-6,"硬化路面单位减伤 10%")

        -- 兵力上限：只统计战斗单位，农民不占名额
        sim=Lab(); ClearResources(sim)
        sim.units={}; sim:RefreshCounts()
        for _=1,C.armyLimit+2 do MilitiaAt(sim,10,5) end
        sim:RefreshCounts()
        Check(sim:ArmyCount()==C.armyLimit+2,"手动添加的战斗单位如实计入（上限由生产端约束）")
        sim=Lab(); ClearResources(sim)
        sim.units={}; sim:RefreshCounts()
        sim.grid:AddResource("mineral",{{x=9,y=3},{x=10,y=3},{x=9,y=4},{x=10,y=4}})
        sim:Perform("warehouse",12,3)
        Advance(sim,90)
        Check(sim:ArmyCount()<=C.armyLimit,"产线自然把战斗兵力填到上限且不超")
        Check(sim:FarmerCount()>0,"农民同时存在且不占用战斗人口")

        -- 拆除返还 50%
        sim=Lab(); ClearResources(sim)
        local built=sim:Perform("forge",14,8)
        local goldAfterBuild=sim.gold
        Check(built and sim.grid:Get(14,8).building>0,"锻炉建造成功并占位")
        sim:Demolish(14,8)
        Check(sim.gold==goldAfterBuild+60,"拆除锻炉返还 50%（120→60）")

        -- 建造限制
        sim=Lab(); ClearResources(sim)
        Check(not sim.grid:CanPlace("barracks",C.wallCol+1,3),"禁止城外建造")
        Check(not sim.grid:CanPlace("tower",C.wallCol,6),"禁止箭塔堵住城门")
        Check(sim.grid:CanPlace("tower",C.wallCol,3),"允许城墙箭塔")

        -- 仓库不阻挡通行
        sim=Lab(); ClearResources(sim)
        sim:Perform("warehouse",10,10)
        Check(sim.grid:IsWalkable(10,10),"仓库格子仍可通行")
        Check(sim.grid:CanPlace("block",10,10)==false,"仓库仍占用格子，不可叠放")

        ------------------------------------------------------------------
        -- 整局：完整多波次 + Boss 能收束
        ------------------------------------------------------------------
        sim=Simulation.New()
        sim.gold=1600
        -- 在离某处资源点最近的空闲格建仓库：保证农民有卸货点，且往返距离短。
        local target=sim.grid.resources[1]
        local placedWarehouse=false
        if target then
            local base=target.cells[1]
            for radius=1,4 do
                for dy=-radius,radius do
                    for dx=-radius,radius do
                        local wx,wy=base.x+dx,base.y+dy
                        if not placedWarehouse and sim.grid:CanPlace("warehouse",wx,wy) then
                            placedWarehouse=sim:Perform("warehouse",wx,wy)
                        end
                    end
                end
                if placedWarehouse then break end
            end
        end
        Check(placedWarehouse,"整局用例成功建立仓库")
        sim:Perform("shield",7,6); sim:Perform("forge",11,6); sim:Perform("bow",15,6)
        sim:Perform("aim",13,7); sim:Perform("horn",9,7)
        Advance(sim,85)
        sim:Perform("tower",C.wallCol,4); sim:Perform("tower",C.wallCol,8)
        Check(sim.converted>0,"工序建筑真的加工了经过的士兵")
        Check(sim.harvested>0,"农民真的完成了采集并入库")
        sim:SetCommand("defend")
        Advance(sim,1600)
        print("[整局观测] 阶段="..sim.phase.." 波次="..sim.wave.." 城墙="..sim.wallHp
            .." 击败="..sim.kills.." 加工="..sim.converted.." 采集="..math.floor(sim.harvested)
            .." 农民="..sim:FarmerCount())
        print(string.format("[道路观测] 主路等级=%d 达标比例=%.0f%%", sim:RoadLevel(), sim.roadProgress*100))
        Check(sim.wave>=3,"正常生产能连续击退波次并抵达 Boss")
        Check(sim.phase=="victory" or sim.phase=="defeat","多波次加 Boss 流程能够收束")

        -- 提前迎敌奖励
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
