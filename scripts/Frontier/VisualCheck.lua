-- 第二轮参考布局验收入口：复用 main 的实际模拟、UI 树和回调，不被正式入口引用。
-- 只注入本入口的临时建造资金；不改配置、不伪造单位/加工/采集/波次/胜负。
-- 主线程统一构建后使用此入口验收；通过后保留真实交战的暂停画面供截图。
require "main"
local originalStart = Start
local UI = require "urhox-libs/UI"
local C = require "Frontier.Config"
local checks = 0

local function Check(ok, message)
    assert(ok, "[第二轮验收失败] " .. message)
    checks = checks + 1
    print("[第二轮验收通过] " .. message)
end
local function Near(a, b) return math.abs(a-b) < 1e-6 end

---@param root Widget
---@param id string
---@return Widget
local function Find(root, id)
    local widget = root:FindById(id)
    assert(widget, "[第二轮验收失败] 缺少实际控件 " .. id)
    return widget
end

-- 菜单/帮助/重开按钮没有 id：从当前可见的真实子树按文案寻找回调。
---@param widget Widget
---@param text string
---@return Button?
local function FindText(widget, text)
    if not widget:IsVisible() then return nil end
    if widget.props.text == text and type(widget.props.onClick) == "function" then
        return widget --[[@as Button]]
    end
    for _, child in ipairs(widget:GetChildren()) do
        local found = FindText(child, text)
        if found then return found end
    end
    return nil
end

---@param button Widget
local function Click(button)
    assert(button:IsVisible(), "[第二轮验收失败] 按钮不可见")
    local callback = button.props.onClick
    assert(type(callback) == "function", "[第二轮验收失败] 按钮没有实际 onClick 回调")
    callback(button) -- Interface 创建的原回调；不能使用自制 hud 或替代回调。
    UI.Layout()
end

---@param root Widget
---@param scope string
---@param text string
local function ClickText(root, scope, text)
    local button = FindText(Find(root, scope), text)
    assert(button, "[第二轮验收失败] 可见按钮不存在：" .. text)
    Click(button)
end

---@param root Widget
---@param kind string
local function SelectMenu(root, kind)
    Click(Find(root, "slot_7"))
    ClickText(root, "buildMenu", C.buildings[kind].name .. "  ·  " .. C.buildings[kind].cost)
end

-- 使用真实 PointerEvent 与 Battlefield 的 down/move/up；不是直接调用 Perform。
---@param field FrontierBattlefield
---@param x number
---@param y number
---@param drag boolean?
local function Point(field, x, y, drag)
    field:UpdateGeometry()
    local px, py = field:Project(x, y)
    local down = UI.PointerEvent.new(UI.PointerEvent.Types.PointerDown, {
        x=px, y=py, button=MOUSEB_LEFT, buttons=UI.PointerEvent.Buttons.Primary,
        pointerType=UI.PointerEvent.PointerTypes.Mouse, target=field,
    })
    field:OnPointerDown(down)
    assert(field.dragging and field.hoverX==x and field.hoverY==y,
        "[第二轮验收失败] 指针按下未命中目标格")
    if drag then
        field:OnPointerMove(UI.PointerEvent.new(UI.PointerEvent.Types.PointerMove, {
            x=px+12, y=py, button=MOUSEB_LEFT, buttons=UI.PointerEvent.Buttons.Primary,
            pointerType=UI.PointerEvent.PointerTypes.Mouse, target=field,
        }))
    end
    local up = UI.PointerEvent.new(UI.PointerEvent.Types.PointerUp, {
        x=px, y=py, button=MOUSEB_LEFT, buttons=UI.PointerEvent.Buttons.None,
        pointerType=UI.PointerEvent.PointerTypes.Mouse, target=field,
    })
    field:OnPointerUp(up)
    assert(not field.dragging and down:IsPropagationStopped() and up:IsPropagationStopped(),
        "[第二轮验收失败] 战场指针生命周期未结束/未阻止冒泡")
end

---@param sim FrontierSim
---@param kind string
---@param x number
---@param y number
local function UnitOverlaps(sim, kind, x, y)
    local d = C.buildings[kind]
    for _, u in ipairs(sim.units) do
        if sim:Active(u) and u.x+u.size*.42>x-.5 and u.x-u.size*.42<x+d.w-.5
            and u.y+u.size*.42>y-.5 and u.y-u.size*.42<y+d.h-.5 then return true end
    end
    return false
end

-- 从本局真实状态搜索空地，避开总部、资源、已有建筑、单位与三格墓门。
---@param sim FrontierSim
---@param kind string
---@return number, number
local function EmptySpot(sim, kind)
    for y=C.rows,1,-1 do
        for x=C.campMaxX,1,-1 do
            if sim.grid:CanPlace(kind,x,y) and not UnitOverlaps(sim,kind,x,y) then return x,y end
        end
    end
    error("[第二轮验收失败] 当前布局没有可建造的 " .. kind .. " 空地")
end

---@param sim FrontierSim
local function Population(sim)
    local farmers, army, enemies, assembling = 0,0,0,0
    for _, u in ipairs(sim.units) do
        if u.active and u.hp>0 then
            if u.team=="enemy" then
                enemies=enemies+1
                if u.assembling then assembling=assembling+1 end
            elseif u.worker then farmers=farmers+1
            else army=army+1 end
        end
    end
    return farmers,army,enemies,assembling
end

---@param sim FrontierSim
local function Footprints(sim)
    local seen = {}
    for _, b in ipairs(sim.grid.buildings) do
        local d = C.buildings[b.kind]
        for dy=0,d.h-1 do
            for dx=0,d.w-1 do
                local x,y=b.x+dx,b.y+dy
                local cell=sim.grid:Get(x,y)
                local key=(y-1)*C.cols+x
                assert(cell and cell.building==b.id and not seen[key],
                    "[第二轮验收失败] 建筑真实占地重叠/缺失：" .. b.kind)
                assert(cell.solid==(d.blocking~=false), "[第二轮验收失败] 建筑通行属性不符")
                seen[key]=true
            end
        end
    end
    for _, r in ipairs(sim.grid.resources) do
        for _, p in ipairs(r.cells) do
            local cell=sim.grid:Get(p.x,p.y)
            assert(cell and cell.building==0 and cell.resource==r.id and not sim.grid:IsWalkable(p.x,p.y),
                "[第二轮验收失败] 资源真实占地冲突")
        end
    end
end

---@param sim FrontierSim
---@param label string
local function ReferenceState(sim, label)
    local farmers,army,enemies,assembling=Population(sim)
    Check(#sim.grid.buildings==11 and #sim.grid.resources==5,
        label .. "：ReferenceLayout 为11座真实建筑、5处资源（不是旧布局13座）")
    Check(farmers==8 and army==5 and enemies==11 and assembling==11
        and sim:FarmerCount()==farmers and sim:ArmyCount()==army and sim:EnemyCount()==enemies,
        label .. "：8农夫、5战斗兵、11集结敌军，与存活实体及计数一致")
    Check(sim.phase=="develop" and sim.wave==1 and sim.time==0 and not sim.paused
        and sim.gold==C.startGold and sim.wallHp==C.wallHealth and #sim.waveQueue==0,
        label .. "：正式初始资金/生命/阶段未被验收改写")
    Footprints(sim)
    for y=1,3 do
        for x=1,7 do
            local cell=sim.grid:Get(x,y)
            assert(cell and cell.building==-2 and cell.solid and not sim.grid:CanPlace("warehouse",x,y),
                "[第二轮验收失败] 总部 -2 占地允许放置")
        end
    end
    Check(sim.grid:ValidateMap(), label .. "：建筑/资源占地正确，总部7×3不可放置，真实通路可达")
end

---@param field FrontierBattlefield
local function Geometry(field)
    UI.Layout()
    field:UpdateGeometry()
    assert(field.scaleFactor>0, "[第二轮验收失败] 战场布局未形成有效尺寸")
    for y=1,C.rows do
        for x=1,C.cols do
            local px,py=field:Project(x,y)
            local col,row=field:WorldPoint(px,py)
            assert(col==x and row==y,
                string.format("[第二轮验收失败] 格中心逆变换 (%d,%d) -> (%d,%d)",x,y,col,row))
        end
    end
    Check(true, "Project/WorldPoint 全部" .. C.cols*C.rows .. "格中心双向一致（含城外变宽列）")
    Check(C.gateTop==5 and C.gateWidth==3, "墓门配置为第5行起、宽3格")
    local _,top=field:Project(C.wallCol,C.gateTop-.5)
    local _,bottom=field:Project(C.wallCol,C.gateTop+C.gateWidth-.5)
    Check(Near((top-field.viewY)/field.scaleFactor,380)
        and Near((bottom-field.viewY)/field.scaleFactor,467), "三格墓门边缘与参考图开口 y=380..467 对齐")
    for y=1,C.rows do
        local cell=field.sim.grid:Get(C.wallCol,y)
        assert(cell, "[第二轮验收失败] 墓墙格缺失")
        if y>=5 and y<=7 then
            assert(cell.building==0 and field.sim.grid:IsWalkable(C.wallCol,y)
                and not field.sim.grid:CanPlace("tower",C.wallCol,y), "[第二轮验收失败] 墓门被墙/箭塔占用")
        else
            assert(cell.building==-1 and not field.sim.grid:IsWalkable(C.wallCol,y),
                "[第二轮验收失败] 墓墙非开口格可通行")
        end
    end
    Check(true, "视觉开口与真实墓墙/墓门/箭塔限制一致")
end

---@param sim FrontierSim
local function Snapshot(sim)
    local values={sim.time,sim.phase,sim.phaseTime,sim.gold,sim.wallHp,sim.commandTimer,
        sim.produced,sim.converted,sim.harvested,sim.kills,#sim.waveQueue,#sim.shots,#sim.effects}
    for _,u in ipairs(sim.units) do
        values[#values+1]=table.concat({u.id,u.x,u.y,u.hp,u.carry,u.gatherTimer,u.cooldown,u.task},",")
    end
    for _,b in ipairs(sim.grid.buildings) do values[#values+1]=b.timer end
    for _,r in ipairs(sim.grid.resources) do values[#values+1]=r.stock end
    return table.concat(values,"|")
end

-- 暂停键经过 main 的真实事件处理器；VariantMap 是引擎事件数据，不是 mock。
local function PauseKey()
    local data=VariantMap() --[[@as KeyDownEventData]]
    data["Key"]=Variant(KEY_SPACE) --[[@as VariantWithInt]]
    HandleFrontierKey("KeyDown",data)
end

---@param sim FrontierSim
---@param seconds number
---@param predicate fun():boolean
local function Until(sim, seconds, predicate)
    for _=1,math.ceil(seconds/C.fixedStep) do
        if predicate() then return true end
        sim:Step(C.fixedStep)
        assert(sim:ArmyCount()<=C.armyLimit, "[第二轮验收失败] 真实生产超出5兵上限")
    end
    return predicate()
end

---@param root Widget
---@param sim FrontierSim
local function HelpPause(root, sim)
    Click(Find(root,"skull_3"))
    Check(Find(root,"help"):IsVisible() and sim.paused, "第三骷髅实际回调打开帮助并暂停")
    local frozen=Snapshot(sim)
    sim:Step(C.fixedStep)
    Check(Snapshot(sim)==frozen, "帮助暂停时真实模拟时间、单位、库存和生产不前进")
    ClickText(root,"help","继续游戏")
    Check(not Find(root,"help"):IsVisible() and not sim.paused, "继续游戏实际回调恢复未暂停状态")
    PauseKey()
    Check(sim.paused, "main 的空格事件切换为暂停")
    Click(Find(root,"skull_3"))
    ClickText(root,"help","继续游戏")
    Check(sim.paused and not Find(root,"help"):IsVisible(), "原本暂停时打开/关闭帮助仍保持暂停")
    frozen=Snapshot(sim)
    sim:Step(C.fixedStep)
    Check(Snapshot(sim)==frozen, "手动暂停不会悄悄推进采集、加工或战斗")
    PauseKey()
    Check(not sim.paused, "main 的空格事件恢复游戏")
end

---@param root Widget
---@param sim FrontierSim
local function OpenWave(root, sim)
    local gold,timeLeft,nextId=sim.gold,sim.phaseTime,sim.nextUnit
    local enemies={}
    for _,u in ipairs(sim.units) do if u.team=="enemy" and u.assembling then enemies[#enemies+1]=u end end
    Click(Find(root,"skull_3"))
    ClickText(root,"help","提前迎敌")
    local _,_,count,assembling=Population(sim)
    Check(sim.phase=="battle" and sim.wave==1 and not sim.paused and not Find(root,"help"):IsVisible(),
        "帮助中的提前迎敌真实回调开波、关闭帮助并恢复模拟")
    Check(Near(sim.gold,gold+math.floor(timeLeft*.65)), "提前开波奖励按实际剩余发育时间结算")
    Check(#enemies==11 and count==11 and assembling==0 and #sim.waveQueue==0 and sim.nextUnit==nextId,
        "11名预集结敌军投入首波并抵扣完整队列，没有生成第二批敌军")
    for _,u in ipairs(enemies) do
        assert(sim:FindUnit(u.id)==u and sim:Active(u), "[第二轮验收失败] 集结敌军未按原实体投入")
    end
end

---@param root Widget
---@param field FrontierBattlefield
local function BuildChecks(root, field)
    local sim=field.sim
    sim.gold=4000 -- 仅本验收实例；重开须恢复 C.startGold。
    local toolbarKinds={"inspect","barracks","shield","forge","warehouse","farmerBarracks"}
    for i,kind in ipairs(toolbarKinds) do
        Click(Find(root,"slot_"..i))
        assert(field.tool==kind and not Find(root,"buildMenu"):IsVisible(),
            "[第二轮验收失败] 工具栏回调选错工具")
    end
    Check(true, "六个实际工具栏按钮分别选择检查/兵营/盾/锻/仓库/农场")
    for i=7,9 do
        Click(Find(root,"slot_"..i))
        assert(Find(root,"buildMenu"):IsVisible(), "[第二轮验收失败] 加号未打开建筑清单")
        ClickText(root,"buildMenu","收起")
        assert(not Find(root,"buildMenu"):IsVisible(), "[第二轮验收失败] 收起回调失效")
    end
    for _,kind in ipairs(C.buildOrder) do
        SelectMenu(root,kind)
        assert(field.tool==kind and not Find(root,"buildMenu"):IsVisible(),
            "[第二轮验收失败] 完整建筑清单回调失效："..kind)
    end
    Check(true, "三个加号、完整建筑清单与收起均执行原 UI 回调")
    for _,kind in ipairs({"barracks","warehouse"}) do
        local x,y=EmptySpot(sim,kind)
        SelectMenu(root,kind)
        local before,gold=#sim.grid.buildings,sim.gold
        Point(field,x,y,true)
        assert(#sim.grid.buildings==before and sim.gold==gold, "[第二轮验收失败] 拖动误触建造")
        Point(field,x,y)
        local cell=sim.grid:Get(x,y)
        local b=cell and sim.grid:FindBuilding(cell.building)
        Check(b~=nil and b.kind==kind and b.x==x and b.y==y and #sim.grid.buildings==before+1
            and Near(sim.gold,gold-C.buildings[kind].cost), kind .. "：真实指针点击建造并按正式费用扣款，拖动不建造")
        Footprints(sim)
        if kind=="warehouse" then
            Check(sim.grid:IsWalkable(x,y) and not sim.grid:CanPlace("warehouse",x,y),
                "新仓库真实占地但不阻挡通行、不能叠放")
        end
        local count,balance=#sim.grid.buildings,sim.gold
        Point(field,x,y)
        Check(#sim.grid.buildings==count and sim.gold==balance, kind .. "：重复点击占地不会叠建/扣款")
    end
    SelectMenu(root,"warehouse")
    local blocked={{x=1,y=1},{x=C.wildMinX,y=C.gateTop}}
    for _,r in ipairs(sim.grid.resources) do blocked[#blocked+1]=r.cells[1] end
    for _,u in ipairs(sim.units) do
        if sim:Active(u) and sim.grid:CanPlace("warehouse",u.x,u.y) then
            blocked[#blocked+1]={x=u.x,y=u.y}; break
        end
    end
    for _,p in ipairs(blocked) do
        local before,gold=#sim.grid.buildings,sim.gold
        Point(field,p.x,p.y)
        assert(#sim.grid.buildings==before and sim.gold==gold,
            "[第二轮验收失败] 总部/资源/城外/单位占格误建造")
    end
    Check(#blocked==8, "总部 -2、5处资源、城外和实际单位占格点击均被拒绝且不扣款")
    SelectMenu(root,"tower")
    for y=C.gateTop,C.gateTop+C.gateWidth-1 do
        local count,gold=#sim.grid.buildings,sim.gold
        Point(field,C.wallCol,y)
        assert(#sim.grid.buildings==count and sim.gold==gold, "[第二轮验收失败] 箭塔占用了墓门")
    end
    local towerRow=1
    local gold,count=sim.gold,#sim.grid.buildings
    Point(field,C.wallCol,towerRow)
    local cell=sim.grid:Get(C.wallCol,towerRow)
    local b=cell and sim.grid:FindBuilding(cell.building)
    Check(b~=nil and b.kind=="tower" and #sim.grid.buildings==count+1
        and Near(sim.gold,gold-C.buildings.tower.cost), "箭塔实际点击只能建在非墓门墓墙格")
    Footprints(sim)
    Click(Find(root,"slot_1"))
end

function Start()
    checks=0
    originalStart()
    local root=UI.GetRoot()
    assert(root, "[第二轮验收失败] main 没有真实 UI 根节点")
    local field=Find(root,"battlefield") --[[@as FrontierBattlefield]]
    local sim=field.sim
    ReferenceState(sim,"开场")
    Geometry(field)
    BuildChecks(root,field)
    HelpPause(root,sim)

    local gold=sim.gold
    Click(Find(root,"skull_1"))
    Check(sim.command=="defend" and sim.commandTimer==C.commandCooldown
        and Near(sim.gold,gold-C.commandCost), "第一骷髅原回调驻守、扣费并进入冷却")
    gold=sim.gold
    Click(Find(root,"skull_2"))
    Check(sim.command=="defend" and sim.gold==gold, "第二骷髅在真实指令冷却期间被拒绝")
    Check(Until(sim,C.commandCooldown+1,function() return sim.commandTimer==0 end), "指令冷却由真实 Step 自然到期")
    gold=sim.gold
    Click(Find(root,"skull_2"))
    Check(sim.command=="attack" and Near(sim.gold,gold-C.commandCost), "第二骷髅原回调切换进攻并按正式费用扣款")

    -- 保留资源实体引用，即使随后枯竭移除仍能核对库存守恒，不凭金币增长冒充采集。
    local resources={}
    local initialBudget=0
    for _,r in ipairs(sim.grid.resources) do
        resources[#resources+1]=r
        initialBudget=initialBudget+r.maxStock*C.resources[r.kind].value
    end
    Check(Until(sim,55,function() return sim.harvested>0 and sim.converted>0 and sim.commandTimer==0 end),
        "真实农夫完成采集运输卸货，士兵自然经过工序获得加工，未直接调用加工/发奖")
    local remaining,carried,processed=0,0,0
    for _,r in ipairs(resources) do remaining=remaining+r.stock*C.resources[r.kind].value end
    for _,u in ipairs(sim.units) do if u.worker then carried=carried+u.carry end end
    for _,b in ipairs(sim.grid.buildings) do processed=processed+b.processed end
    Check(Near(initialBudget,remaining+carried+sim.harvested), "真实资源储量 + 农夫携带 + 已卸货收入守恒")
    Check(processed==sim.converted and processed>0, "加工累计与真实工序建筑加工次数一致")
    local geared=false
    for _,u in ipairs(sim.units) do
        if u.team=="ally" and not u.worker and next(u.gear) then geared=true end
    end
    Check(geared and sim:ArmyCount()<=5, "存活士兵持有真实加工装备，农夫不占5兵上限")
    Click(Find(root,"skull_1"))
    OpenWave(root,sim)

    -- 到达真实胜负后才从可见结算面板点击重开；不改 phase/血量制造结算。
    Check(Until(sim,900,function() return sim.phase=="victory" or sim.phase=="defeat" end),
        "真实波次战斗最终进入胜利或失败结算")
    local update=VariantMap() --[[@as UpdateEventData]]
    update["TimeStep"]=Variant(.15) --[[@as VariantWithFloat]]
    HandleFrontierUpdate("Update",update)
    Check(Find(root,"end"):IsVisible(), "main 更新使真实胜负结算面板可见")
    print(string.format("[第二轮真实结算] 阶段=%s 波次=%d 时间=%.2f 生产=%d 加工=%d 采集=%.0f 击败=%d",
        sim.phase,sim.wave,sim.time,sim.produced,sim.converted,sim.harvested,sim.kills))
    local oldGrid=sim.grid
    ClickText(root,"end","重新开始")
    Check(field.sim==sim and sim.grid~=oldGrid and UI.GetRoot()==root and field.tool=="inspect"
        and not Find(root,"end"):IsVisible() and #sim.shots==0 and #sim.effects==0
        and sim.produced==0 and sim.converted==0 and sim.harvested==0 and sim.kills==0,
        "重开原回调重置实际模拟且复用原 UI/战场，清空结算、加工与战斗残留")
    ReferenceState(sim,"重开")
    Geometry(field)

    -- 截图阶段恢复原参考布局与正式初始资金，全部角色仍靠真实 AI 行军/采集/战斗。
    Click(Find(root,"skull_1"))
    Check(Until(sim,45,function() return sim.harvested>0 and sim.converted>0 end),
        "重开后的原参考布局也能自然采集/加工，无须额外测试建筑")
    OpenWave(root,sim)
    local function Fighting()
        if sim.phase~="battle" or sim:ArmyCount()==0 or sim:EnemyCount()==0 then return false end
        local combat,damage=false,sim.kills>0
        for _,u in ipairs(sim.units) do
            if sim:Active(u) and not u.worker then
                if u.team=="ally" and u.state=="自主交战" then combat=true end
                if u.hp<u.maxHp then damage=true end
            end
        end
        return combat and damage
    end
    Check(Until(sim,45,Fighting), "截图停在双方存活、士兵自主交战且真实造成伤害的时刻")
    sim.paused=true -- 只在最终截图保留真实战斗现场；暂停功能此前已经由真实回调验证。
    HandleFrontierUpdate("Update",update)
    UI.Layout()
    local frozen=Snapshot(sim)
    sim:Step(C.fixedStep)
    Check(sim.paused and Snapshot(sim)==frozen and not Find(root,"help"):IsVisible()
        and not Find(root,"end"):IsVisible(), "最终真实战斗画面已暂停，无遮挡帮助/结算面板")
    print(string.format("[第二轮验收汇总] %d项全部通过；真实建筑=%d 资源=%d 农夫=%d 军队=%d 敌军=%d 加工=%d 采集=%.0f 墓门=5/3 时间=%.2f paused=%s",
        checks,#sim.grid.buildings,#sim.grid.resources,sim:FarmerCount(),sim:ArmyCount(),sim:EnemyCount(),
        sim.converted,sim.harvested,sim.time,tostring(sim.paused)))
end
