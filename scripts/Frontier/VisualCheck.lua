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
    -- 玩家等价操作：清出两格道路，建立沿路工坊与额外营房。
    sim.gold=2000
    for y=5,6 do
        for x=4,17 do
            local cell=sim.grid:Get(x,y)
            if cell and cell.terrain=="rock" then sim:Perform("clear",x,y) end
            if cell and cell.terrain=="empty" then sim:Perform("road",x,y) end
        end
    end
    local builds={ {"shield",6,3},{"bow",9,3},{"stable",12,3},{"barracks",2,8},
        {"tower",18,4},{"tower",18,8} }
    for _,b in ipairs(builds) do
        for dy=0,C.buildings[b[1]].h-1 do
            for dx=0,C.buildings[b[1]].w-1 do
                local cell=sim.grid:Get(b[2]+dx,b[3]+dy)
                if cell and cell.terrain=="rock" then sim:Perform("clear",b[2]+dx,b[3]+dy) end
            end
        end
        sim:Perform(b[1],b[2],b[3])
    end
    for _=1,75*30 do sim:Step(C.fixedStep) end
    sim:SetCommand("defend")
    sim:StartWave(true)
    for _=1,24*30 do sim:Step(C.fixedStep) end
    sim.paused=true
    field.cameraX=8
    print("[场景验证] 实际生产="..sim.produced.." 实际转职="..sim.converted.." 军队="..sim:ArmyCount().." 敌军="..sim:EnemyCount())
end
