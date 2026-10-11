-- 参考图开场：建筑是真实生产/加工设施，人物由原模拟系统驱动。
-- 总部占地不可建造；中部横向通道与墓门保持畅通，资源位不堵住产兵口。
local C = require "Frontier.Config"
local Layout = {}

---@param sim FrontierSim
function Layout.Apply(sim)
    local grid = sim.grid
    for i = #grid.buildings, 1, -1 do grid:RemoveBuilding(grid.buildings[i].id) end
    for i = #grid.resources, 1, -1 do grid:RemoveResource(grid.resources[i]) end
    -- 总部落在左上 7×3 格，建筑高部位只属于美术，不扩大地面碰撞。
    -- [总部][兵营]  [棺材] [木材]
    -- [农场][绿液池][工坊]   → 三格墓门 → 敌军集结
    -- [兵营][木屋]  [农场]
    for y = 1, 3 do
        for x = 1, 7 do
            local cell = grid:Get(x, y)
            if cell then cell.building, cell.solid = -2, true end
        end
    end
    local entries = {
        {"barracks",9,2},{"shield",15,2},{"warehouse",20,3},
        {"farmerBarracks",3,4},{"forge",10,4},{"bow",17,4},
        {"stable",10,8},{"barracks",4,9},{"forge",10,11},
        {"farmerBarracks",17,9},{"farmerBarracks",5,11},
    }
    for _,e in ipairs(entries) do
        local kind,x,y = e[1],e[2],e[3]
        assert(grid:CanPlace(kind,x,y), "参考布局占地冲突："..kind)
        grid:AddBuilding(kind,x,y)
    end
    local resourceEntries = {
        {"forest",20,1},{"forest",2,8},{"forest",19,11},
        {"mineral",7,8},{"mineral",14,10},
    }
    for _,e in ipairs(resourceEntries) do
        local cells = {{x=e[2],y=e[3]},{x=e[2]+1,y=e[3]}}
        grid:AddResource(e[1],cells)
    end
    local farmers = {{7,5},{6,8},{14,3},{14,5},{14,7},{20,4},{16,9},{16,11}}
    for _,p in ipairs(farmers) do sim:AddUnit("farmer","ally",p[1],p[2]) end
    local soldiers = {{13,2},{13,4},{8,6},{17,8},{20,8}}
    for _,p in ipairs(soldiers) do sim:AddUnit("militia","ally",p[1],p[2]) end
    sim.command="defend"
    -- 预先展示当前首波的11名真实敌人；发育阶段不攻击，开波后投入战斗，
    -- 同时从波次队列扣除，不能因为参考构图额外加倍敌人数。
    for i = 1, 7+sim.wave*4 do
        local kind = i%5==0 and "brute" or i%4==0 and "shooter" or "raider"
        local x = 25+((i-1)%4)*2
        local y=3+math.floor((i-1)/4)*3+(i%2)
        local u = sim:AddUnit(kind,"enemy",x,y)
        u.assembling = true
    end
    sim:RefreshCounts()
    sim.noticeTime=0
    grid.version = grid.version+1
    print("[参考布局] 真实设施 "..#grid.buildings.."，资源 "..#grid.resources.."，农夫 "..sim:FarmerCount().."，战斗人口 "..sim:ArmyCount().."/"..C.armyLimit)
end
return Layout
