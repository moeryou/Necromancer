-- 验证入口：复用真实main/UI，按规则搭建测试布局，提前推进模拟后截图。
-- 不被正式入口引用。所有单位仍由生产、库存和AI产生。
require "main"
local originalStart=Start
local UI=require "urhox-libs/UI"
local C=require "Frontier.Config"

function Start()
    originalStart()
    local root=UI.GetRoot()
    if not root then error("没有UI根节点") end
    local field=root:FindById("battlefield") --[[@as FrontierBattlefield?]]
    if not field then error("没有战场控件") end
    local sim=field.sim
    -- 玩家等价操作：只摆建筑。道路由部队自己踩出来，无需也无法铺设。
    sim.gold=4000
    -- 玩家等价操作：只摆建筑。道路由部队自己踩出来，无需也无法铺设。
    -- 工序建筑刻意贴在士兵走廊(第 8 行)的相邻格，士兵经过即逐件加工，
    -- 用于观察"盾+锻""弓+瞄"等装备叠加后的外观差异。
    local builds={ {"shield",6,7},{"forge",9,7},{"horn",12,7},{"bow",16,7},
        {"aim",14,8},{"stable",19,8},{"barracks",2,8},
        {"tower",C.wallCol,4},{"tower",C.wallCol,8} }
    for _,b in ipairs(builds) do
        sim:Perform(b[1],b[2],b[3])
    end
    -- 在第一处资源点旁找空位建仓库，让农民有卸货点、能真正跑起采集循环。
    local target=sim.grid.resources[1]
    if target then
        local base=target.cells[1]
        for radius=1,5 do
            local done=false
            for dy=-radius,radius do
                for dx=-radius,radius do
                    if not done and sim.grid:CanPlace("warehouse",base.x+dx,base.y+dy) then
                        done=sim:Perform("warehouse",base.x+dx,base.y+dy)
                    end
                end
            end
            if done then break end
        end
    end
    for _=1,75*30 do sim:Step(C.fixedStep) end
    sim:SetCommand("defend")
    sim:StartWave(true)
    for _=1,24*30 do sim:Step(C.fixedStep) end
    sim.paused=true
    print("[场景验证] 实际生产="..sim.produced.." 实际加工="..sim.converted.." 军队="..sim:ArmyCount().." 敌军="..sim:EnemyCount().." 主路="..sim:RoadLevel().." 阻断="..sim.pathBlocked)
end
