-- 参考图HUD：右上资源条与三个骷髅状态，左下六个建筑图标与三个空槽。
-- 所有可点击区域由UI.Button负责，不把参考图当作一张不可交互的界面截图。
local UI=require "urhox-libs/UI"
local C=require "Frontier.Config"
local Battlefield=require "Frontier.Battlefield"
local Art=require "Frontier.Artwork"
local P={ bg={20,29,43,255},panel={27,37,53,248},line={63,73,91,255},text={242,223,194,255},
    muted={176,168,172,255},gold={250,183,53,255},purple={113, 70,161,255} }

local Icon=UI.Widget:Extend("ReferenceIcon")
function Icon:Init(props)
    UI.Widget.Init(self,props)
    self.imageName=props.imageName
end
function Icon:Render(vg)
    local l=self:GetAbsoluteLayout()
    Art.Fit(vg,self.imageName,l.x,l.y,l.w,l.h)
end

local function Label(text,size,color,props)
    props=props or {}; props.text,props.fontSize,props.fontColor=text,size or 12,color or P.text
    return UI.Label(props)
end
local function Button(text,action,props)
    props=props or {}; props.text,props.onClick=text,action
    if text==nil then
        props.paddingHorizontal,props.paddingVertical=0,0
        props.hoverBorderWidth,props.pressedBorderWidth=2,2
    end
    props.height=props.height or 40
    props.fontSize=props.fontSize or 11
    props.backgroundColor=props.backgroundColor or P.panel
    props.borderColor=props.borderColor or P.line
    props.borderWidth=props.borderWidth or 2
    props.borderRadius=props.borderRadius or 7
    props.textColor=P.text
    props.glowShadow,props.boxShadow=false,false
    props.hoverBackgroundColor=props.hoverBackgroundColor or {54,50,78,255}
    props.pressedBackgroundColor=props.pressedBackgroundColor or {78,58,104,255}
    return UI.Button(props)
end

---@class FrontierInterface
---@field sim FrontierSim
---@field root Panel
---@field battlefield FrontierBattlefield
---@field tool string
---@field timer number
---@field helpOpen boolean
---@field wasPaused boolean
---@field scaleFactor number
---@field lastW number
---@field lastH number
---@field widgets table<string, any>
---@field buildButtons table<string, Button>
local Interface={}
Interface.__index=Interface

function Interface.New(sim)
    local self=setmetatable({},Interface) --[[@as FrontierInterface]]
    self.sim=sim
    self.tool,self.timer="inspect",0
    self.helpOpen,self.wasPaused=false,false
    self.scaleFactor,self.lastW,self.lastH=1,0,0
    self.widgets={}
    self.battlefield=Battlefield {id="battlefield",sim=sim,position="absolute",left=0,top=0} --[[@as FrontierBattlefield]]
    self:Create()
    return self
end

function Interface:Find(id)
    local w=self.widgets[id]
    if not w then w=self.root:FindById(id); self.widgets[id]=w end
    return w
end
function Interface:Text(id,text)
    local w=self:Find(id) --[[@as Label?]]
    if w then w:SetText(text) end
end
function Interface:Select(tool)
    self.tool=tool; self.battlefield:SetTool(tool)
    if C.buildings[tool] then self.sim:Notify(C.buildings[tool].name.." · "..C.buildings[tool].cost.."灵魂 · 点击绿色占地放置")
    elseif tool=="inspect" then self.sim:Notify("检查模式：点击建筑查看说明；总部为固定地标") end
    local panel=self:Find("buildMenu")
    if panel then panel:SetVisible(false) end
    self:Update(1)
end

function Interface:Menu(open)
    local panel=self:Find("buildMenu")
    if panel then panel:SetVisible(open) end
end

function Interface:Create()
    local sim=self.sim
    local slots={}
    local kinds={"inspect","barracks","shield","forge","stable","farmerBarracks"}
    local icons={"hq","barracks","coffin","cauldron","hut","pumpkin_farm"}
    for i=1,9 do
        local index=i
        local kind=kinds[i]
        slots[i]=Button(nil,function()
            if index<=6 then self:Select(kind) else self:Menu(true) end
        end,{
            id="slot_"..i,position="absolute",padding=0,width=79,height=82,borderWidth=0,
            backgroundColor={0,0,0,0},hoverBackgroundColor={147,108,191,55},pressedBackgroundColor={160,112,212,85},
            backgroundImage="Reference/"..(i<=6 and "ui_icon_"..icons[i] or "ui_empty")..".png",
            backgroundFit="contain",glowShadow=false,boxShadow=false,
        })
    end
    local toolbar=UI.Panel {id="toolbar",position="absolute",width=810,height=113,
        backgroundImage="Reference/ui_toolbar.png",backgroundFit="stretch",pointerEvents="box-none",children=slots}
    local resources=UI.Panel {id="resources",position="absolute",width=245,height=49,
        backgroundImage="Reference/ui_hud.png",backgroundFit="stretch",pointerEvents="box-none",children={
            Icon {id="goldIcon",imageName="gold",position="absolute",left=8,top=8,width=37,height=33,pointerEvents="none"},
            UI.ProgressBar {id="goldbar",position="absolute",left=51,top=21,width= 60,height=10,
                value=.24,showLabel=false,backgroundColor={71,85,101,255},fillColor={244,177,44,255},borderWidth=0,borderRadius=3,pointerEvents="none"},
            Icon {id="slimeIcon",imageName="slime",position="absolute",left=133,top=6,width=34,height=36,pointerEvents="none"},
            UI.ProgressBar {id="wallbar",position="absolute",left=173,top=21,width= 60,height=10,
                value=1,showLabel=false,backgroundColor={71,85,101,255},fillColor={128,222,57,255},borderWidth=0,borderRadius=3,pointerEvents="none"},
        }}
    local skulls={}
    for i=1,3 do
        local index=i
        skulls[i]=Button(nil,function()
            if index==1 then sim:SetCommand("defend")
            elseif index==2 then sim:SetCommand("attack")
            else self:Help(true) end
        end,{id="skull_"..i,position="absolute",width=37,height=35,padding=0,borderWidth=0,
            backgroundColor={0,0,0,0},children={Icon {imageName="skull",width="100%",height="100%",pointerEvents="none"}}})
    end
    local skullPanel=UI.Panel {id="skullPanel",position="absolute",width=124,height=50,
        backgroundImage="Reference/ui_skull_panel.png",backgroundFit="stretch",pointerEvents="box-none",children=skulls}
    local menuItems={Label("亡灵建筑",18,P.text,{fontWeight="bold"}),Label("选择建筑后点击营地空地放置",10,P.muted)}
    local itemButtons={}
    for _,kind in ipairs(C.buildOrder) do
        local k=kind
        local btn=Button(C.buildings[kind].name.."  ·  "..C.buildings[kind].cost,function() self:Select(k) end,{id="build_"..kind,width="100%",height=34})
        itemButtons[kind]=btn
        table.insert(menuItems,btn)
    end
    self.buildButtons=itemButtons
    table.insert(menuItems,Button("拆除建筑",function() self:Select("demolish") end,{width="100%"}))
    table.insert(menuItems,Button("收起",function() self:Menu(false) end,{width="100%"}))
    local menu=UI.Panel {id="buildMenu",visible=false,position="absolute",left=18,bottom=138,width=265,height="70%",
        padding=14,gap=8,backgroundColor=P.panel,borderWidth=2,borderColor=P.line,borderRadius=12,
        children={UI.ScrollView {scrollY=true,width="100%",height="100%",flexShrink=1,children={UI.Panel {gap=7,children=menuItems}}}}}
    self.root=UI.Panel {width="100%",height="100%",pointerEvents="box-none",children={
        self.battlefield,toolbar,resources,skullPanel,menu,
        UI.Panel {id="notice",visible=false,position="absolute",left="25%",top="9%",width="50%",
            padding=10,backgroundColor=P.panel,borderWidth=1,borderColor=P.line,borderRadius=8,pointerEvents="none",
            children={Label("",11,P.text,{id="noticeText",textAlign="center",width="100%",whiteSpace="normal"})}},
        self:CreateHelp(),self:CreateEnd(),
    }}
    UI.SetRoot(self.root,true)
    self:Layout()
    print("[参考UI] 全屏战场、右上双资源条/骷髅指令、左下九槽已建立")
end

-- 缩放与战场使用同一个参考画布映射。屏幕比例改变时重排而非拉伸素材。
function Interface:Layout()
    local w,h=UI.GetWidth(),UI.GetHeight()
    local k=math.min(w/1568,h/882)
    local ox,oy=(w-1568*k)*.5,(h-882*k)*.5
    self.scaleFactor,self.lastW,self.lastH=k,w,h
    self:Find("toolbar"):SetStyle {left=ox+7*k,top=oy+755*k,width=810*k,height=113*k}
    local slotLeft={21,108,195,282,369,456,532,622,713}
    for i=1,9 do self:Find("slot_"..i):SetStyle {left=slotLeft[i]*k,top=15*k,width=79*k,height=82*k} end
    self:Find("resources"):SetStyle {left=ox+1187*k,top=oy+9*k,width=245*k,height=49*k}
    self:Find("goldIcon"):SetStyle {left=8*k,top=8*k,width=37*k,height=33*k}
    self:Find("slimeIcon"):SetStyle {left=133*k,top=6*k,width=34*k,height=36*k}
    self:Find("goldbar"):SetStyle {left=51*k,top=21*k,width=60*k,height=10*k}
    self:Find("wallbar"):SetStyle {left=173*k,top=21*k,width=60*k,height=10*k}
    self:Find("skullPanel"):SetStyle {left=ox+1438*k,top=oy+10*k,width=124*k,height=50*k}
    for i=1,3 do self:Find("skull_"..i):SetStyle {left=(10+(i-1)*35)*k,top=7*k,width=37*k,height=35*k} end
    self:Find("buildMenu"):SetStyle {left=ox+18*k,bottom=math.max(0,h-(oy+745*k)),width=265*math.max(.7,k),height=math.min(h*.7,580*math.max(.7,k))}
end

function Interface:CreateHelp()
    local items={Label("亡灵墓园",24,P.text,{fontWeight="bold"}),
        Label("界面位置与素材以参考图为准。建造、采集、自动加工和波次战斗仍由真实模拟驱动。",12,P.muted,{whiteSpace="normal",width="100%"}),
        Label("左下建筑栏",16,P.gold,{fontWeight="bold"}),
        Label("点建筑图标，再点营地空地建造。三个加号打开完整建筑清单；Esc退出建造。",12,P.text,{whiteSpace="normal",width="100%"}),
        Label("木屋图标对应马厩；仓库在加号清单中。红色预览表示占地、资金或单位经过不允许建造，绿色表示可放置。",12,P.text,{whiteSpace="normal",width="100%"}),
        Label("右上骷髅指令",16,P.gold,{fontWeight="bold"}),
        Label("第一个骷髅：驻守墓门；第二个：全力进攻；第三个：打开说明。金币条显示建造资金，绿液条显示墓墙生命。",12,P.text,{whiteSpace="normal",width="100%"}),
        Label("战斗单位上限5；亡灵农夫不占人口。先发育90秒，或按N提前开波。道路由反复踩踏形成，工坊对邻格经过的士兵自动加工。",12,P.text,{whiteSpace="normal",width="100%"}),
        Label("快捷键",16,P.gold,{fontWeight="bold"}),
        Label("空格暂停 / 1驻守 / 2进攻 / N提前迎敌 / B建筑清单 / X拆除 / H帮助 / Tab切换速度。",12,P.text,{whiteSpace="normal",width="100%"}),
        Button("提前迎敌",function() self.sim:StartWave(true); self:Help(false) end,{width="100%"}),
        Button("继续游戏",function() self:Help(false) end,{width="100%"}),
    }
    return UI.Panel {id="help",visible=false,position="absolute",left=0,top=0,right=0,bottom=0,
        backgroundColor={15,17,28,190},alignItems="center",justifyContent="center",children={
            UI.Panel {width="85%",maxWidth=540,height="80%",padding=24,backgroundColor=P.panel,
                borderWidth=3,borderColor=P.line,borderRadius=14,children={
                    UI.ScrollView {scrollY=true,width="100%",height="100%",flexShrink=1,children={UI.Panel {gap=13,children=items}}},
                }},
        }}
end

function Interface:CreateEnd()
    return UI.Panel {id="end",visible=false,position="absolute",left=0,top=0,right=0,bottom=0,
        backgroundColor={15,17,28,190},alignItems="center",justifyContent="center",children={
            UI.Panel {width="85%",maxWidth=420,padding=28,gap=18,backgroundColor=P.panel,borderWidth=3,borderColor=P.line,borderRadius=14,
                children={Label("亡灵之夜守住了",24,P.text,{id="endTitle",fontWeight="bold",textAlign="center"}),
                    Label("",12,P.muted,{id="endStats",textAlign="center"}),
                    Button("重新开始",function()
                        self.helpOpen,self.wasPaused=false,false
                        self:Find("help"):SetVisible(false)
                        self.sim:Init()
                        require("Frontier.ReferenceLayout").Apply(self.sim)
                        self:Select("inspect")
                    end,{width="100%"})}},
        }}
end

function Interface:Help(open)
    if open and not self.helpOpen then self.wasPaused=self.sim.paused end
    self.helpOpen=open
    self.sim.paused=open or self.wasPaused
    if not open then self.wasPaused=false end
    self:Find("help"):SetVisible(open)
end

function Interface:Update(dt)
    self.battlefield:UpdateBars()
    self.timer=self.timer+dt
    if self.timer<.1 then return end
    self.timer=0
    if UI.GetWidth()~=self.lastW or UI.GetHeight()~=self.lastH then self:Layout() end
    local sim=self.sim
    for kind,btn in pairs(self.buildButtons) do btn:SetDisabled(sim.gold<C.buildings[kind].cost) end
    self:Find("notice"):SetVisible(sim.noticeTime>0 and not self.helpOpen and (self.tool~="inspect" or sim.phase~="develop" or sim.notice:find("检查模式",1,true) or sim.notice:find(" · ",1,true)))
    self:Text("noticeText",sim.notice)
    local goldbar=self:Find("goldbar") --[[@as ProgressBar?]]
    local wallbar=self:Find("wallbar") --[[@as ProgressBar?]]
    if goldbar then goldbar:SetValue(math.min(1,sim.gold/2000)) end
    if wallbar then wallbar:SetValue(math.max(0,sim.wallHp/C.wallHealth)) end
    for i=1,6 do
        local btn=self:Find("slot_"..i) --[[@as Button?]]
        local kinds={"inspect","barracks","shield","forge","stable","farmerBarracks"}
        local selected=self.tool~="inspect" and self.tool==kinds[i]
        local ending=sim.phase=="victory" or sim.phase=="defeat"
        if btn then btn:SetStyle {borderWidth=selected and 2 or 0,borderColor={186,150,225,255}}
            btn:SetDisabled(ending or (C.buildings[kinds[i]] and sim.gold<C.buildings[kinds[i]].cost) or false)
        end
    end
    local ending=self:Find("end")
    if ending then ending:SetVisible(sim.phase=="victory" or sim.phase=="defeat") end
    self:Text("endTitle",sim.phase=="victory" and "亡灵之夜守住了" or "墓墙已失守")
    self:Text("endStats","击败 "..sim.kills.." · 加工 "..sim.converted.." · 采集 "..math.floor(sim.harvested))
end
return Interface
