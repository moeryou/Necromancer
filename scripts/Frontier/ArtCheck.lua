-- 美术验收专用入口：实际 PNG、真实装备表现和双朝向；正式 main 不引用。
require "main"
local originalStart=Start
local UI=require "urhox-libs/UI"
local Art=require "Frontier.Artwork"
local Sim=require "Frontier.Simulation"
local View=require "Frontier.WorldView"
local C=require "Frontier.Config"
local Gallery=UI.Widget:Extend("FrontierArtGallery")

function Gallery:Init(props)
    UI.Widget.Init(self,props)
    self.units=props.units
end

function Gallery:Render(vg)
    local layout=self:GetAbsoluteLayout()
    local scale=math.min(layout.w/1568,layout.h/882)
    nvgSave(vg)
    nvgTranslate(vg,layout.x,layout.y)
    nvgScale(vg,scale,scale)
    Art.Rect(vg,0,0,1568,882,{194,156,105,255})
    for i,kind in ipairs(C.buildOrder) do
        local x=25+((i-1)%6)*260
        local y=40+math.floor((i-1)/6)*220
        local w=160
        local h=w/Art.BuildingAspect(kind)
        if h>165 then w=w*165/h; h=165 end
        Art.Building(vg,kind,x+(220-w)*.5,y+165-h,w,h,0)
        Art.Line(vg,x+25,y+166,x+195,y+166,{109,72,55,255},2)
    end
    for i,u in ipairs(self.units) do
        local x=110+((i-1)%6)*260
        local y=600+math.floor((i-1)/6)*190
        u.facing=-1
        Art.Unit(vg,u,x-36,y,0)
        u.facing=1
        Art.Unit(vg,u,x+52,y,0)
        local _,_,_,top=Art.UnitGeometry(u)
        Art.Line(vg,x-65,y-top-12,x+84,y-top-12,{67,82,92,255},2)
    end
    nvgRestore(vg)
end

function Start()
    originalStart()
    UnsubscribeFromEvent("Update")
    local sim=Sim.New()
    local cases={
        {"militia","ally",{}}, {"militia","ally",{bow=true}},
        {"militia","ally",{shield=true}}, {"militia","ally",{forge=true}},
        {"militia","ally",{stable=true}}, {"militia","ally",{stable=true,bow=true}},
        {"militia","ally",{stable=true,shield=true,forge=true}},
        {"elephant","ally",{}}, {"boss","enemy",{}},
        {"brute","enemy",{}}, {"raider","enemy",{}}, {"shooter","enemy",{}},
    }
    local units,children={},{}
    for _,case in ipairs(cases) do
        local u=sim:AddUnit(case[1],case[2],28,9)
        u.gear=case[3]
        units[#units+1]=u
    end
    local vg=UI.GetNVGContext()
    for _,kind in ipairs(C.buildOrder) do
        assert(Art.Load(vg,Art.BuildingName(kind))>0,"[美术验收失败] 建筑素材缺失："..kind)
    end
    for _,u in ipairs(units) do
        assert(Art.Load(vg,Art.UnitName(u))>0,"[美术验收失败] 角色素材缺失："..u.kind)
    end
    local props={width="100%",height="100%",units=units}
    children[1]=Gallery:new(props --[[@as WidgetProps]])
    local k=math.min(UI.GetWidth()/View.width,UI.GetHeight()/View.height)
    for i,kind in ipairs(C.buildOrder) do
        children[#children+1]=UI.Label {text=C.buildings[kind].name,position="absolute",
            left=(25+((i-1)%6)*260)*k,top=(210+math.floor((i-1)/6)*220)*k,
            width=220*k,textAlign="center",fontSize=16*k,fontColor={36,29,43,255},pointerEvents="none"}
    end
    for i,u in ipairs(units) do
        local label=Art.UnitName(u)
        if u.gear.bow and u.gear.stable then label=label.." 骑射" end
        if u.gear.shield then label=label.." 盾" end
        children[#children+1]=UI.Label {text=label,position="absolute",
            left=(25+((i-1)%6)*260)*k,top=(620+math.floor((i-1)/6)*190)*k,
            width=220*k,textAlign="center",fontSize=16*k,fontColor={36,29,43,255},pointerEvents="none"}
    end
    UI.SetRoot(UI.Panel {width="100%",height="100%",children=children},true)
    print("[美术验收] 12建筑、12角色装备组和双朝向已创建")
end
