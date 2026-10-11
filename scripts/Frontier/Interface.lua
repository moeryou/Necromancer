local UI = require "urhox-libs/UI"
local C = require "Frontier.Config"
local Battlefield = require "Frontier.Battlefield"
-- 万圣节喜剧配色：深紫夜色底 + 南瓜橙主色 + 骨白文字 + 鬼火绿点缀。
local P = {
    bg = { 40, 32, 62, 255 }, panel = { 54, 44, 80, 255 }, card = { 68, 55, 100, 255 },
    line = { 98, 82, 136, 255 }, text = { 246, 240, 228, 255 }, muted = { 160, 148, 188, 255 },
    gold = { 250, 202, 96, 255 }, red = { 232, 96, 128, 255 },
    orange = { 246, 140, 54, 255 }, goo = { 176, 240, 150, 255 },
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
    self.tool,self.timer="inspect",0
    self.narrow=graphics:GetWidth()/UI.GetScale()<1000
    self.helpOpen=false
    self.widgets = {} ---@type table<string, any>
    self.battlefield=Battlefield { id="battlefield",sim=sim } --[[@as FrontierBattlefield]]
    self:Create()
end

function Interface:Select(tool)
    self.tool=tool
    self.battlefield:SetTool(tool)
    self:Update(1)
end

-- 控件引用在首次取用时缓存：每 0.15 秒更新一次界面，没必要每次都遍历控件树。
function Interface:Find(id)
    local w = self.widgets[id]
    if w == nil then
        w = self.root:FindById(id) or false
        self.widgets[id] = w
    end
    return w or nil
end

function Interface:Text(id,text)
    local label=self:Find(id) --[[@as Label?]]
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
                Label("亡 灵 工 坊",23,P.orange,{ fontWeight="bold" }),
                Label("NECRO WORKS  /  间接指挥 · 万圣夜塔防",9,P.muted,{ letterSpacing=1.5 }),
            } },
            resourceCard("灵魂  /  被动+"..C.passiveIncome.."每秒 · 采集为主","gold",P.gold),
            UI.Panel { width=self.narrow and 120 or 174,height=52,paddingHorizontal=14,justifyContent="center",gap=5,
                borderLeftWidth=1,borderLeftColor=P.line,children={
                    Label("墓墙完整度",9,P.muted),
                    UI.ProgressBar { id="wallbar",value=1,height=6,width="100%",showLabel=false,
                        backgroundColor=P.card,fillColor=P.orange,borderRadius=2 },
                    Label("800 / 800",9,P.text,{ id="wall" }),
                } },
            Button("?",function() self:Help(true) end,{ width=34,height=34,marginLeft=12 }),
        },
    }
    local toolButtons={
        Button("浏览",function() self:Select("inspect") end,{ id="tool_inspect",flexGrow=1,flexBasis=0,height=34,fontSize=10 }),
        Button("拆除",function() self:Select("demolish") end,{ id="tool_demolish",flexGrow=1,flexBasis=0,height=34,fontSize=10 }),
    }
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
                        Label(def.w.."×"..def.h.."  ·  "..(def.unit and "兵力生产" or def.proc and "接触加工" or "战线规划"),8,P.muted),
                    } },
                    Label(tostring(def.cost),12,P.gold,{ textAlign="right" }),
                } },
            },
        }))
    end
    local buildPage=UI.Panel { id="buildPage",gap=8,children=buildingButtons }
    local side=UI.Panel {
        width=self.narrow and 206 or 244,backgroundColor=P.panel,borderRightWidth=1,borderRightColor=P.line,
        padding=14,gap=12,children={
            UI.Panel { flexDirection="row",alignItems="center",justifyContent="space-between",children={
                Label("墓园规划",15,P.text,{ fontWeight="bold" }),
                Label("兵力 "..C.armyLimit.." 上限",9,P.muted),
            } },
            UI.Panel { flexDirection="row",gap=6,children=toolButtons },
            UI.ScrollView { flexGrow=1,flexBasis=0,scrollY=true,showScrollbar=true,children={ buildPage } },
            UI.Panel { paddingTop=10,borderTopWidth=1,borderTopColor=P.line,gap=4,children={
                Label("行军与鬼脚印",9,P.gold),
                Label("亡灵自动行军；营地内按直线加横线的最短折线走向墓门。路面不能铺设也不能拆除，全靠亡灵反复踩踏自然形成。",9,P.muted,{ whiteSpace="normal",maxLines=4,width="100%" }),
                Label("当前主路",9,P.gold,{ marginTop=4 }),
                Label("荒坟地",9,P.text,{ id="roadLevel" }),
            } },
        },
    }
    local phaseBar=UI.Panel {
        height=72,flexDirection="row",alignItems="center",paddingHorizontal=20,gap=14,
        backgroundColor={ 62,50,90,255 },borderBottomWidth=1,borderBottomColor=P.line,
        children={
            UI.Panel { flexGrow=1,gap=4,children={
                Label("01  /  发育阶段",15,P.gold,{ id="phase",fontWeight="bold" }),
                Label("规划生产线，用建筑占地引导部队走向",10,P.muted,{ id="phaseHint" }),
            } },
            Label("01:30",21,P.text,{ id="clock",fontWeight="bold",width=74,textAlign="right" }),
            Button("提前开门  →",function() sim:StartWave(true) end,{ id="waveButton",width=130,height=38,backgroundColor=P.orange,textColor={44,34,62,255} }),
        },
    }
    local mapLabels=UI.Panel { height=36,flexDirection="row",alignItems="center",paddingHorizontal=20,backgroundColor={ 84,66,120,255 },
        children={
            Label("墓园  /  网格规划",10,{ 232,222,248,255 }),
            UI.Spacer(),Label("墓门 3 格  ·  唯一出口",9,{ 214,202,238,255 }),
            UI.Spacer(),Label("荒坟地  /  自主交战",10,{ 218,206,240,255 }),
        } }
    local mapFooter=UI.Panel { height=36,flexDirection="row",alignItems="center",paddingHorizontal=16,gap=6,backgroundColor=P.panel,
        borderTopWidth=1,borderTopColor=P.line,children={
            Label("待命",10,P.text,{ id="mapStatus",flexGrow=1,flexShrink=1,maxLines=1 }),
        } }
    local content=UI.Panel { flexGrow=1,flexBasis=0,flexShrink=1,flexDirection="row",children={
        side,UI.Panel { flexGrow=1,flexBasis=0,flexShrink=1,children={ phaseBar,mapLabels,self.battlefield,mapFooter } },
    } }
    local commands={}
    local commandIcons={ defend="守",attack="攻" }
    for _,kind in ipairs({"defend","attack"}) do
        local k=kind
        table.insert(commands,Button(nil,function() sim:SetCommand(k) end,{
            id="command_"..kind,height=58,flexGrow=1,flexBasis=0,flexShrink=1,padding=10,children={
                UI.Panel { flexDirection="row",alignItems="center",gap=10,pointerEvents="none",children={
                    Label(commandIcons[kind],18,P.orange,{ width=26,textAlign="center",fontWeight="bold" }),
                    UI.Panel { gap=4,flexGrow=1,flexShrink=1,children={
                        Label(C.commandNames[kind],12,P.text),
                        Label(kind=="defend" and "固守墓门，警惕范围伤害" or "前压追击，警惕绕后",8,P.muted),
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
                Label("全局指令",10,P.orange,{ fontWeight="bold" }),
                Label("   /   每次消耗15灵魂 · 冷却8秒",9,P.muted,{ id="commandHint" }),
                UI.Spacer(),Label("部队 0 · 击败 0",9,P.muted,{ id="counts" }),
            } },
            UI.Panel { flexDirection="row",gap=8,children=commands },
            Label("只能规划墓园与发布全局指令，不能直接操控亡灵。",9,P.muted,{ id="notice",maxLines=1 }),
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
        { "01 / 双产线墓园", "墓园有两条独立产线：骷髅兵营拼战斗单位（上限" .. C.armyLimit .. "），南瓜农场召唤采集单位（不占战斗人口）。亡灵农夫永久限制在墓园内，只负责采集与运输，绝不出城。" },
        { "02 / 农夫与资源", "在资源点旁建南瓜仓库，农夫会自动前往最近的空闲资源点采集，再把资源背回仓库入库。枯木林单次3秒、幽灵石单次5秒；幽灵石更值钱（1单位=2灵魂值）。资源点采空后地块恢复为普通空地，可通行、可建造。" },
        { "03 / 灵魂怎么花", "被动产出仅 0.5/秒，经济主力是农夫采集。骨盾工坊、鬼火锻炉、骷髅马厩属重装工序，每加工1名骷髅兵额外消耗2灵魂值（等价1单位幽灵石）；其余建筑只消耗灵魂值。" },
        { "04 / 兵力与加工", "骷髅兵路过工序建筑相邻格即自动加工：骨盾、鬼火锻炉提升生存，骨弓、幽灵瞄准台切换远程，骷髅马厩提升机动，哀嚎号角强化首击。装备可叠加，但弓与盾互斥。多格建筑的正面多格可并行加工。" },
        { "05 / 路面与寻路", "所有亡灵只走横竖向、按通行时间最短寻路：走得多的格子路更好、更快，亡灵自然改走快路。路面完全由亡灵在墓园内踩踏形成，城外不产生任何路面变化。" },
        { "06 / 最终决战", "击退3轮普通波次后直接迎战Boss。击败南瓜王即可通关；墓墙生命为0则失败。亡灵巨象需2格宽石棺道才能通行。" },
    }
    local items={ Label("指挥的是规则，不是亡灵。",20,P.orange,{ fontWeight="bold" }),
        Label("横向卷轴 · 间接指挥型万圣夜塔防",11,P.muted) }
    for _,item in ipairs(lines) do
        table.insert(items,UI.Panel { gap=4,children={ Label(item[1],12,P.text,{fontWeight="bold"}),
            Label(item[2],10,P.muted,{whiteSpace="normal",maxLines=4,width="100%"}) } })
    end
    table.insert(items,Label("整张地图铺满屏幕 / 空格暂停 / 1、2发布指令",9,P.muted,{whiteSpace="normal",maxLines=3,width="100%"}))
    table.insert(items,Button("明白了，返回墓园  →",function() self:Help(false) end,{width="100%",backgroundColor=P.orange,textColor={44,34,62,255}}))
    return UI.Panel { id="help",visible=false,position="absolute",left=0,top=0,right=0,bottom=0,
        backgroundColor={24,16,40,228},justifyContent="center",alignItems="center",children={
            UI.Panel { width="85%",maxWidth=610,height="88%",padding=24,backgroundColor=P.panel,borderWidth=2,borderColor=P.line,borderRadius=18,
                children={ UI.ScrollView { height="100%",scrollY=true,children={UI.Panel {gap=14,children=items}} } } },
        } }
end

function Interface:CreateEnd()
    return UI.Panel { id="end",visible=false,position="absolute",left=0,right=0,top=0,bottom=0,
        backgroundColor={24,16,40,230},alignItems="center",justifyContent="center",children={
            UI.Panel { width="85%",maxWidth=460,padding=34,gap=16,backgroundColor=P.panel,borderRadius=18,borderWidth=2,borderColor=P.orange,children={
                Label("亡灵之夜守住了",27,P.orange,{id="endTitle",fontWeight="bold",textAlign="center"}),
                Label("",12,P.muted,{id="endStats",textAlign="center"}),
                Label("布局决定生产线，生产线决定战线。",11,P.text,{textAlign="center"}),
                Button("重新规划 · 再战一夜",function()
                    self.sim:Init(); self.battlefield.sim=self.sim
                    self:Select("inspect"); self:Update(1)
                end,{width="100%",backgroundColor=P.orange,textColor={44,34,62,255}}),
            } },
        } }
end

function Interface:Help(open)
    self.helpOpen=open
    self.sim.paused=open
    local panel=self:Find("help")
    if panel then panel:SetVisible(open) end
    self:Update(1)
end

function Interface:Update(dt)
    self.timer=self.timer+dt
    if self.timer<0.15 then return end
    self.timer=0
    local sim=self.sim
    self:Text("gold",tostring(math.floor(sim.gold)))
    self:Text("wall",math.ceil(sim.wallHp).." / "..C.wallHealth)
    local hp=self:Find("wallbar") --[[@as ProgressBar?]]
    if hp then hp:SetValue(sim.wallHp/C.wallHealth) end
    local minutes=math.floor(sim.phaseTime/60)
    local seconds=math.floor(sim.phaseTime%60)
    self:Text("clock",sim.phase=="develop" and string.format("%02d:%02d",minutes,seconds) or "交战中")
    self:Text("phase",string.format("%02d",sim.wave).."  /  "..(sim.phase=="develop" and "发育阶段" or sim.phase=="boss" and "最终决战" or "波次进攻"))
    self:Text("phaseHint",sim.phase=="develop" and "规划生产线，用建筑占地引导亡灵走向" or sim.phase=="boss" and "南瓜王优先攻击密集亡灵 · 保持分散" or ("消灭全部捣蛋鬼 · 待刷新 "..#sim.waveQueue.." · 战场 "..sim:EnemyCount()))
    local wb=self:Find("waveButton") --[[@as Button?]]
    if wb then wb:SetDisabled(sim.phase~="develop"); wb:SetText(sim.phase=="develop" and ("开门 +"..math.floor(sim.phaseTime*.65).."  →") or "捣蛋鬼来袭") end
    self:Text("counts","部队 "..sim:ArmyCount().." · 农夫 "..sim:FarmerCount().." · 采集 "..math.floor(sim.harvested).." · 击败 "..sim.kills)
    local info=C.buildings[self.tool]
    if self.tool=="demolish" then
        self:Text("mapStatus","拆除模式 · 点击建筑返还 50% 灵魂")
    else
        self:Text("mapStatus",info and (info.name.." · "..info.description) or ("一屏看完全场 · 墓门占用 "..sim.gateUsed.."/3"))
    end
    local level=sim:RoadLevel()
    self:Text("roadLevel",C.trailNames[level+1].."  ·  "..math.floor(sim.roadProgress*100).."% 通行段达标")
    self:Text("commandHint",sim.commandTimer>0 and ("   /   冷却 "..math.ceil(sim.commandTimer).." 秒 · "..C.commandNames[sim.command]) or ("   /   15灵魂 · 当前："..C.commandNames[sim.command]))
    self:Text("notice",sim.noticeTime>0 and sim.notice or (sim.blockedCount>0 and ("拥堵预警："..sim.blockedCount.."个亡灵受阻。分散出口或调整工坊布局。") or "没有单兵微操：你能改的是墓园布局、路面走向与全局指令。"))
    for _,kind in ipairs({"defend","attack"}) do
        local btn=self:Find("command_"..kind) --[[@as Button?]]
        if btn then
            btn:SetDisabled(sim.commandTimer>0 or sim.gold<C.commandCost or sim.phase=="victory" or sim.phase=="defeat")
            btn:SetStyle({borderColor=sim.command==kind and P.orange or P.line,backgroundColor=sim.command==kind and {92,68,120,255} or P.card})
        end
    end
    for _,kind in ipairs({"inspect","demolish","barracks","farmerBarracks","elephant","shield","bow","forge","aim","stable","horn","warehouse","tower","block"}) do
        local btn=self:Find("tool_"..kind) --[[@as Button?]]
        if btn then btn:SetStyle({borderColor=self.tool==kind and P.orange or P.line,backgroundColor=self.tool==kind and {92,68,120,255} or P.card}) end
    end
    local pause=self:Find("pause") --[[@as Button?]]
    if pause then pause:SetText(sim.paused and "▶ 继续" or "Ⅱ 暂停") end
    local speed=self:Find("speed") --[[@as Button?]]
    if speed then speed:SetText(sim.speed.."× 速度") end
    local ending=self:Find("end")
    if ending then ending:SetVisible(sim.phase=="victory" or sim.phase=="defeat") end
    self:Text("endTitle",sim.phase=="victory" and "亡灵之夜守住了" or "墓墙已失守")
    self:Text("endStats","击败 "..sim.kills.." · 加工 "..sim.converted.." · 召唤 "..sim.produced)
end
return Interface
