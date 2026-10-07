local UI = require "urhox-libs/UI"
local C = require "Frontier.Config"
local Battlefield = require "Frontier.Battlefield"
local P = {
    bg = { 32, 40, 35, 255 }, panel = { 43, 53, 45, 255 }, card = { 52, 63, 52, 255 },
    line = { 77, 89, 70, 255 }, text = { 230, 226, 202, 255 }, muted = { 148, 163, 136, 255 },
    gold = { 218, 187, 124, 255 }, cyan = { 148, 190, 188, 255 }, red = { 208, 125, 107, 255 },
}
local function Label(text, size, color, props)
    props = props or {}
    props.text, props.fontSize, props.fontColor = text,size or 12,color or P.text
    return UI.Label(props)
end
local function Button(text, action, props)
    props=props or {}
    props.text,props.onClick=text,action
    props.height=props.height or 38
    props.fontSize=props.fontSize or 11
    props.borderRadius=props.borderRadius or 4
    props.borderWidth=1
    props.backgroundColor=props.backgroundColor or P.card
    props.borderColor=props.borderColor or P.line
    props.textColor=props.textColor or P.text
    props.boxShadow=false
    props.transition="backgroundColor 0.12s easeOut"
    props.paddingHorizontal=10
    return UI.Button(props)
end

---@class FrontierInterface
---@field sim FrontierSim
---@field root Panel
---@field battlefield FrontierBattlefield
---@field tool string
---@field tab string
---@field timer number
---@field narrow boolean
---@field helpOpen boolean
local Interface = {}
Interface.__index = Interface

---@param sim FrontierSim
---@return FrontierInterface
function Interface.New(sim)
    local self=setmetatable({},Interface) --[[@as FrontierInterface]]
    self:Init(sim)
    return self
end

function Interface:Init(sim)
    self.sim=sim
    self.tool,self.tab,self.timer="inspect","build",0
    self.narrow=graphics:GetWidth()/UI.GetScale()<1000
    self.helpOpen=false
    self.battlefield=Battlefield { id="battlefield",sim=sim } --[[@as FrontierBattlefield]]
    self:Create()
end

function Interface:Select(tool)
    self.tool=tool
    self.battlefield:SetTool(tool)
    self:Update(1)
end

function Interface:Text(id,text)
    local label=self.root:FindById(id) --[[@as Label?]]
    if label then label:SetText(text) end
end

function Interface:Create()
    local sim=self.sim
    local resourceCard=function(title,id,color)
        return UI.Panel {
            width=self.narrow and 105 or 140,height=52,paddingHorizontal=14,
            borderLeftWidth=1,borderLeftColor=P.line,justifyContent="center",gap=1,
            children={ Label(title,9,P.muted),Label("0",18,color,{ id=id,fontWeight="bold" }) },
        }
    end
    local header=UI.Panel {
        height=82,flexDirection="row",alignItems="center",paddingHorizontal=24,
        backgroundColor=P.bg,borderBottomWidth=1,borderBottomColor=P.line,
        children={
            UI.Panel { flexGrow=1,flexShrink=1,gap=3,children={
                Label("边 境 工 事",23,P.text,{ fontWeight="bold" }),
                Label("FRONTIER  /  间接指挥 · 波次塔防",9,P.muted,{ letterSpacing=1.5 }),
            } },
            resourceCard("基础资源  /  +2.5每秒","gold",P.gold),
            resourceCard("科技资源","tech",P.cyan),
            UI.Panel { width=self.narrow and 120 or 174,height=52,paddingHorizontal=14,justifyContent="center",gap=5,
                borderLeftWidth=1,borderLeftColor=P.line,children={
                    Label("城墙完整度",9,P.muted),
                    UI.ProgressBar { id="wallbar",value=1,height=6,width="100%",showLabel=false,
                        backgroundColor=P.card,fillColor=P.gold,borderRadius=2 },
                    Label("800 / 800",9,P.text,{ id="wall" }),
                } },
            Button("?",function() self:Help(true) end,{ width=34,height=34,marginLeft=12 }),
        },
    }
    local tools={
        { "inspect","浏览","拖动横向移动" }, { "clear","清岩","8资源 / 格" },
        { "road","铺路","3资源 / 格" }, { "erase","拆除","返还55%" },
    }
    local toolButtons={}
    for _,t in ipairs(tools) do
        local tool=t[1]
        table.insert(toolButtons,Button(t[2],function() self:Select(tool) end,{
            id="tool_"..tool,width="48%",height=34,fontSize=10,
        }))
    end
    local buildingButtons={}
    for _,kind in ipairs(C.buildOrder) do
        local def=C.buildings[kind]
        local k=kind
        table.insert(buildingButtons,Button(nil,function() self:Select(k) end,{
            id="tool_"..kind,height=58,width="100%",padding=8,
            children={
                UI.Panel { flexDirection="row",alignItems="center",height="100%",gap=10,pointerEvents="none",children={
                    UI.Panel { width=32,height=32,backgroundColor={ def.color[1],def.color[2],def.color[3],50 },borderRadius=4,
                        justifyContent="center",alignItems="center",children={ Label(def.short,16,def.color,{ fontWeight="bold" }) } },
                    UI.Panel { flexGrow=1,flexShrink=1,gap=3,children={
                        Label(def.name,12,P.text),
                        Label(def.w.."×"..def.h.."  ·  "..(def.unit and "兵力生产" or def.upgrade and "库存转职" or "战线规划"),8,P.muted),
                    } },
                    Label(tostring(def.cost),12,P.gold,{ textAlign="right" }),
                } },
            },
        }))
    end
    local buildPage=UI.Panel { id="buildPage",gap=8,children=buildingButtons }
    local techButtons={}
    for level=1,3 do
        local n=level
        table.insert(techButtons,UI.Panel { padding=12,gap=8,backgroundColor=P.card,borderWidth=1,borderColor=P.line,borderRadius=5,
            children={
                Label("0"..level.." / "..C.techNames[level],12,P.gold),
                Label(C.techDescriptions[level],10,P.muted,{ whiteSpace="normal",maxLines=3,width="100%" }),
                Button("研发 · "..C.techCosts[level].."科技",function()
                    if n==sim.techLevel+1 then sim:Upgrade()
                    elseif n>sim.techLevel then sim:Notify("请依次研发道路科技") end
                end,{ id="tech_"..level,width="100%",fontSize=10 }),
            } })
    end
    table.insert(techButtons,Button("铺设加速带 · 6资源/格",function() self:Select("boost") end,{ id="tool_boost",width="100%",fontSize=10 }))
    local techPage=UI.Panel { id="techPage",visible=false,gap=12,children=techButtons }
    local side=UI.Panel {
        width=self.narrow and 206 or 244,backgroundColor=P.panel,borderRightWidth=1,borderRightColor=P.line,
        padding=14,gap=12,children={
            UI.Panel { flexDirection="row",alignItems="center",justifyContent="space-between",children={
                Label("营地规划",15,P.text,{ fontWeight="bold" }),Label("左侧可建",9,P.muted),
            } },
            UI.Panel { flexDirection="row",flexWrap="wrap",gap=6,allowOverflow=true,children=toolButtons },
            UI.Panel { flexDirection="row",gap=6,children={
                Button("建筑",function() self:Tab("build") end,{ id="tab_build",width="48%",height=32 }),
                Button("道路科技",function() self:Tab("tech") end,{ id="tab_tech",width="48%",height=32 }),
            } },
            UI.ScrollView { flexGrow=1,flexBasis=0,scrollY=true,showScrollbar=true,children={ buildPage,techPage } },
            UI.Panel { paddingTop=10,borderTopWidth=1,borderTopColor=P.line,gap=4,children={
                Label("生产线提示",9,P.gold),
                Label("工坊需紧邻实际行军路径；同一民兵只能转职一次。",9,P.muted,{ whiteSpace="normal",maxLines=3,width="100%" }),
            } },
        },
    }
    local phaseBar=UI.Panel {
        height=72,flexDirection="row",alignItems="center",paddingHorizontal=20,gap=14,
        backgroundColor={ 49,61,49,255 },borderBottomWidth=1,borderBottomColor=P.line,
        children={
            UI.Panel { flexGrow=1,gap=4,children={
                Label("01  /  发育阶段",15,P.gold,{ id="phase",fontWeight="bold" }),
                Label("规划生产线，派遣部队采集城外资源",10,P.muted,{ id="phaseHint" }),
            } },
            Label("01:30",21,P.text,{ id="clock",fontWeight="bold",width=74,textAlign="right" }),
            Button("提前迎敌  →",function() sim:StartWave(true) end,{ id="waveButton",width=130,height=38,backgroundColor=P.gold,textColor=P.bg }),
        },
    }
    local mapLabels=UI.Panel { height=36,flexDirection="row",alignItems="center",paddingHorizontal=20,backgroundColor={ 60,76,55,255 },
        children={
            Label("营地  /  网格规划",10,{ 220,218,175,255 }),
            UI.Spacer(),Label("城门 3 格  ·  唯一出口",9,{ 205,207,162,255 }),
            UI.Spacer(),Label("荒野  /  自主交战",10,{ 207,210,170,255 }),
        } }
    local mapFooter=UI.Panel { height=42,flexDirection="row",alignItems="center",paddingHorizontal=16,gap=6,backgroundColor=P.panel,
        borderTopWidth=1,borderTopColor=P.line,children={
            Label("待命",10,P.text,{ id="mapStatus",flexGrow=1,flexShrink=1,maxLines=1 }),
            Button("←",function() self.battlefield:Pan(-5) end,{ width=32,height=26 }),
            Button("营地",function() self.battlefield.cameraX=0 end,{ width=48,height=26,fontSize=9 }),
            Button("城门",function() self.battlefield.cameraX=10 end,{ width=48,height=26,fontSize=9 }),
            Button("荒野",function() self.battlefield.cameraX=23 end,{ width=48,height=26,fontSize=9 }),
            Button("→",function() self.battlefield:Pan(5) end,{ width=32,height=26 }),
        } }
    local content=UI.Panel { flexGrow=1,flexBasis=0,flexShrink=1,flexDirection="row",children={
        side,UI.Panel { flexGrow=1,flexBasis=0,flexShrink=1,children={ phaseBar,mapLabels,self.battlefield,mapFooter } },
    } }
    local commands={}
    local commandIcons={ collect="采",defend="守",attack="攻" }
    for _,kind in ipairs({"collect","defend","attack"}) do
        local k=kind
        table.insert(commands,Button(nil,function() sim:SetCommand(k) end,{
            id="command_"..kind,height=58,flexGrow=1,flexBasis=0,flexShrink=1,padding=10,children={
                UI.Panel { flexDirection="row",alignItems="center",gap=10,pointerEvents="none",children={
                    Label(commandIcons[kind],18,P.gold,{ width=26,textAlign="center",fontWeight="bold" }),
                    UI.Panel { gap=4,flexGrow=1,flexShrink=1,children={
                        Label(C.commandNames[kind],12,P.text),
                        Label(kind=="collect" and "分散采集，守备空虚" or kind=="defend" and "固守城门，警惕范围伤害" or "前压追击，警惕绕后",8,P.muted),
                    } },
                } },
            },
        }))
    end
    table.insert(commands,UI.Panel { width=116,justifyContent="center",gap=4,children={
        Button("Ⅱ 暂停",function() sim.paused=not sim.paused; self:Update(1) end,{ id="pause",height=26,width="100%",fontSize=9 }),
        Button("1× 速度",function() sim.speed=sim.speed==1 and 2 or sim.speed==2 and 3 or 1; self:Update(1) end,{ id="speed",height=26,width="100%",fontSize=9 }),
    } })
    local bottom=UI.Panel { height=126,paddingHorizontal=20,paddingVertical=10,gap=8,backgroundColor=P.bg,
        borderTopWidth=1,borderTopColor=P.line,children={
            UI.Panel { flexDirection="row",alignItems="center",height=20,children={
                Label("全局指令",10,P.gold,{ fontWeight="bold" }),
                Label("   /   每次消耗15资源 · 冷却8秒",9,P.muted,{ id="commandHint" }),
                UI.Spacer(),Label("部队 0 · 击败 0",9,P.muted,{ id="counts" }),
            } },
            UI.Panel { flexDirection="row",gap=8,children=commands },
            Label("只能规划营地与发布全局指令，不能直接操控单位。",9,P.muted,{ id="notice",maxLines=1 }),
        } }
    self.root=UI.Panel { width="100%",height="100%",backgroundColor=P.bg,children={
        UI.SafeAreaView { width="100%",height="100%",nativeMenuInset=true,children={header,content,bottom} },
        self:CreateHelp(),self:CreateEnd(),
    } }
    UI.SetRoot(self.root,true)
    self:Update(1)
end

function Interface:CreateHelp()
    local lines={
        { "01 / 规划营地", "清除岩石、铺设道路，再把工坊紧邻行军路线。建筑占地会改变寻路，堵死出口会停止生产。" },
        { "02 / 发育与采集", "每轮发育90秒。民兵自动产出，在城外待命。发布收集资源后，部队自主寻找并清理资源点。" },
        { "03 / 攻守取舍", "驻守城门不追击，但怕范围伤害；全力进攻主动前压，但后方空虚。每条指令消耗15资源，冷却8秒。" },
        { "04 / 道路与巨兽", "击退波次或采集深处资源获得科技。大象必须有2格宽硬化道路；遇到窄路将卡滞并堵塞后队。" },
        { "05 / 最终决战", "击退3轮普通波次后直接迎战Boss。击败破城巨兽即可通关；城墙生命为0则失败。" },
    }
    local items={ Label("指挥的是规则，不是士兵。",20,P.gold,{ fontWeight="bold" }),
        Label("横向卷轴 · 间接指挥型塔防",11,P.muted) }
    for _,item in ipairs(lines) do
        table.insert(items,UI.Panel { gap=4,children={ Label(item[1],12,P.text,{fontWeight="bold"}),
            Label(item[2],10,P.muted,{whiteSpace="normal",maxLines=4,width="100%"}) } })
    end
    table.insert(items,Label("浏览模式拖动地图 / 滚轮或A、D横移 / 空格暂停 / 1、2、3发布指令",9,P.muted,{whiteSpace="normal",maxLines=3,width="100%"}))
    table.insert(items,Button("明白了，返回营地  →",function() self:Help(false) end,{width="100%",backgroundColor=P.gold,textColor=P.bg}))
    return UI.Panel { id="help",visible=false,position="absolute",left=0,top=0,right=0,bottom=0,
        backgroundColor={20,28,24,225},justifyContent="center",alignItems="center",children={
            UI.Panel { width="85%",maxWidth=610,height="88%",padding=24,backgroundColor=P.panel,borderWidth=1,borderColor=P.line,borderRadius=8,
                children={ UI.ScrollView { height="100%",scrollY=true,children={UI.Panel {gap=14,children=items}} } } },
        } }
end

function Interface:CreateEnd()
    return UI.Panel { id="end",visible=false,position="absolute",left=0,right=0,top=0,bottom=0,
        backgroundColor={24,32,27,228},alignItems="center",justifyContent="center",children={
            UI.Panel { width="85%",maxWidth=460,padding=34,gap=16,backgroundColor=P.panel,borderRadius=8,borderWidth=1,borderColor=P.gold,children={
                Label("边境守住了",27,P.gold,{id="endTitle",fontWeight="bold",textAlign="center"}),
                Label("",12,P.muted,{id="endStats",textAlign="center"}),
                Label("布局决定生产线，生产线决定战线。",11,P.text,{textAlign="center"}),
                Button("重新规划 · 再战一次",function()
                    self.sim:Init(); self.battlefield.sim=self.sim; self.battlefield.cameraX=0
                    self:Select("inspect"); self:Update(1)
                end,{width="100%",backgroundColor=P.gold,textColor=P.bg}),
            } },
        } }
end

function Interface:Help(open)
    self.helpOpen=open
    self.sim.paused=open
    local panel=self.root:FindById("help")
    if panel then panel:SetVisible(open) end
    self:Update(1)
end

function Interface:Tab(tab)
    self.tab=tab
    local build=self.root:FindById("buildPage")
    local tech=self.root:FindById("techPage")
    if build then build:SetVisible(tab=="build") end
    if tech then tech:SetVisible(tab=="tech") end
    self:Update(1)
end

function Interface:Update(dt)
    self.timer=self.timer+dt
    if self.timer<0.15 then return end
    self.timer=0
    local sim=self.sim
    self:Text("gold",tostring(math.floor(sim.gold)))
    self:Text("tech",tostring(sim.tech))
    self:Text("wall",math.ceil(sim.wallHp).." / "..C.wallHealth)
    local hp=self.root:FindById("wallbar") --[[@as ProgressBar?]]
    if hp then hp:SetValue(sim.wallHp/C.wallHealth) end
    local minutes=math.floor(sim.phaseTime/60)
    local seconds=math.floor(sim.phaseTime%60)
    self:Text("clock",sim.phase=="develop" and string.format("%02d:%02d",minutes,seconds) or "交战中")
    self:Text("phase",string.format("%02d",sim.wave).."  /  "..(sim.phase=="develop" and "发育阶段" or sim.phase=="boss" and "最终决战" or "波次进攻"))
    self:Text("phaseHint",sim.phase=="develop" and "规划生产线，派遣部队采集城外资源" or sim.phase=="boss" and "破城巨兽优先攻击密集部队 · 保持分散" or ("消灭全部敌军 · 待刷新 "..#sim.waveQueue.." · 战场 "..sim:EnemyCount()))
    local wb=self.root:FindById("waveButton") --[[@as Button?]]
    if wb then wb:SetDisabled(sim.phase~="develop"); wb:SetText(sim.phase=="develop" and ("迎敌 +"..math.floor(sim.phaseTime*.65).."  →") or "敌军来袭") end
    self:Text("counts","部队 "..sim:ArmyCount().." · 转职 "..sim.converted.." · 击败 "..sim.kills)
    local info=C.buildings[self.tool]
    self:Text("mapStatus",info and (info.name.." · "..info.description) or self.tool=="inspect" and ("浏览模式 · 拖动地图 / 滚轮横移 · 城门占用 "..sim.gateUsed.."/3") or self.tool=="road" and "铺路模式 · 按住刷格 · 土路+30%移速" or self.tool=="clear" and "清岩模式 · 按住刷格 · 8资源/格" or self.tool=="erase" and "拆除模式 · 55%返还 · 先拆道路再建工坊" or "加速带模式 · 硬化道路上的短时双倍移速")
    self:Text("commandHint",sim.commandTimer>0 and ("   /   冷却 "..math.ceil(sim.commandTimer).." 秒 · "..C.commandNames[sim.command]) or ("   /   15资源 · 当前："..C.commandNames[sim.command]))
    self:Text("notice",sim.noticeTime>0 and sim.notice or (sim.blockedCount>0 and ("拥堵预警："..sim.blockedCount.."个单位受阻。拓宽路径、清理出口或调整工坊布局。") or "格子是边界，道路是选择。只有全局指令，没有单兵微操。"))
    for _,kind in ipairs({"collect","defend","attack"}) do
        local btn=self.root:FindById("command_"..kind) --[[@as Button?]]
        if btn then
            btn:SetDisabled(sim.commandTimer>0 or sim.gold<C.commandCost or sim.phase=="victory" or sim.phase=="defeat")
            btn:SetStyle({borderColor=sim.command==kind and P.gold or P.line,backgroundColor=sim.command==kind and {73,78,56,255} or P.card})
        end
    end
    for _,kind in ipairs({"inspect","clear","road","erase","barracks","shield","bow","stable","elephant","tower","block","boost"}) do
        local btn=self.root:FindById("tool_"..kind) --[[@as Button?]]
        if btn then btn:SetStyle({borderColor=self.tool==kind and P.gold or P.line,backgroundColor=self.tool==kind and {75,81,58,255} or P.card}) end
    end
    for i=1,3 do
        local btn=self.root:FindById("tech_"..i) --[[@as Button?]]
        if btn then
            btn:SetText(sim.techLevel>=i and "已研发  ✓" or ("研发 · "..C.techCosts[i].."科技"))
            btn:SetDisabled(sim.techLevel>=i or sim.techLevel+1~=i or sim.tech<C.techCosts[i])
        end
    end
    for _,tab in ipairs({"build","tech"}) do
        local b=self.root:FindById("tab_"..tab)
        if b then b:SetStyle({backgroundColor=self.tab==tab and {75,81,58,255} or P.card,borderColor=self.tab==tab and P.gold or P.line}) end
    end
    local pause=self.root:FindById("pause") --[[@as Button?]]
    if pause then pause:SetText(sim.paused and "▶ 继续" or "Ⅱ 暂停") end
    local speed=self.root:FindById("speed") --[[@as Button?]]
    if speed then speed:SetText(sim.speed.."× 速度") end
    local ending=self.root:FindById("end")
    if ending then ending:SetVisible(sim.phase=="victory" or sim.phase=="defeat") end
    self:Text("endTitle",sim.phase=="victory" and "边境守住了" or "城墙已失守")
    self:Text("endStats","击败 "..sim.kills.." · 转职 "..sim.converted.." · 采集 "..sim.collected)
end
return Interface
