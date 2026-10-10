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
    sim.gold=2000
    local builds={ {"shield",4,3},{"bow",7,3},{"stable",9,3},{"barracks",2,8},
        {"tower",C.wallCol,4},{"tower",C.wallCol,8} }
    for _,b in ipairs(builds) do
        sim:Perform(b[1],b[2],b[3])
    end
    for _=1,75*30 do sim:Step(C.fixedStep) end
    sim:SetCommand("defend")
    sim:StartWave(true)
    for _=1,24*30 do sim:Step(C.fixedStep) end
    sim.paused=true
    print("[场景验证] 实际生产="..sim.produced.." 实际转职="..sim.converted.." 军队="..sim:ArmyCount().." 敌军="..sim:EnemyCount().." 主路="..sim:RoadLevel())
end
