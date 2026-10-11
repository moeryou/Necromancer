-- 全屏战场：以参考图1568×882为设计画布；世界坐标与UI共享同一等比映射。
local UI = require "urhox-libs/UI"
local C = require "Frontier.Config"
local Art = require "Frontier.Artwork"
local View = require "Frontier.WorldView"

---@class FrontierBattlefield : Widget
---@field sim FrontierSim
---@field tool string
---@field hoverX number
---@field hoverY number
---@field scaleFactor number
---@field originX number
---@field originY number
---@field tile number
---@field rowStep number
---@field viewX number
---@field viewY number
---@field dragging boolean
---@field dragMoved boolean
---@field dragX number
---@field dragY number
---@field drawOrder table[]
---@field bars table<number, ProgressBar>
local Battlefield = UI.Widget:Extend("FrontierBattlefield")

local function ByDepth(a,b)
    if a.depth==b.depth then return a.key<b.key end
    return a.depth<b.depth
end

function Battlefield:Init(props)
    props = props or {}
    props.width,props.height="100%","100%"
    props.overflow,props.pointerEvents="hidden","auto"
    UI.Widget.Init(self,props)
    self.sim=props.sim
    self.tool,self.hoverX,self.hoverY="inspect",0,0
    self.tile,self.rowStep,self.scaleFactor=40,54,1
    self.originX,self.originY,self.viewX,self.viewY=25,85,0,0
    self.dragX,self.dragY=0,0
    self.dragging,self.dragMoved=false,false
    self.drawOrder={}
    self.bars={} ---@type table<number, ProgressBar>
end

function Battlefield:UpdateGeometry()
    local l=self:GetAbsoluteLayout()
    self.scaleFactor=math.min(l.w/1568,l.h/882)
    self.viewX=l.x+(l.w-1568*self.scaleFactor)*.5
    self.viewY=l.y+(l.h-882*self.scaleFactor)*.5
    self.originX,self.originY=self.viewX+25*self.scaleFactor,self.viewY+85*self.scaleFactor
    self.tile,self.rowStep=40*self.scaleFactor,54*self.scaleFactor
end

function Battlefield:DesignPoint(x,y)
    return View.Point(x,y)
end

function Battlefield:Project(x,y)
    local px,py=self:DesignPoint(x,y)
    return self.viewX+px*self.scaleFactor,self.viewY+py*self.scaleFactor
end

function Battlefield:WorldPoint(x,y)
    self:UpdateGeometry()
    local px,py=(x-self.viewX)/self.scaleFactor,(y-self.viewY)/self.scaleFactor
    return View.Cell(px,py)
end

function Battlefield:SetTool(tool) rawset(self,"tool",tool) end
function Battlefield:Pan(amount) end
function Battlefield:OnWheel(dx,dy) end

function Battlefield:OnPointerDown(event)
    if not event:IsPrimaryButton() and event.pointerType~="touch" then return end
    self.dragging,self.dragMoved=true,false
    self.dragX,self.dragY=event.x,event.y
    self.hoverX,self.hoverY=self:WorldPoint(event.x,event.y)
    event:StopPropagation()
end

function Battlefield:OnPointerMove(event)
    self.hoverX,self.hoverY=self:WorldPoint(event.x,event.y)
    if self.dragging and math.abs(event.x-self.dragX)+math.abs(event.y-self.dragY)>7 then self.dragMoved=true end
end

function Battlefield:OnPointerUp(event)
    if self.dragging and not self.dragMoved then
        local x,y=self:WorldPoint(event.x,event.y)
        if self.tool=="inspect" or self.tool=="demolish" then
            local cell=self.sim.grid:Get(x,y)
            local pickedDepth=cell and cell.building>0 and math.huge or -math.huge
            local px,py=(event.x-self.viewX)/self.scaleFactor,(event.y-self.viewY)/self.scaleFactor
            for _,b in ipairs(self.sim.grid.buildings) do
                local bx,by,bw,bh=self:BuildingRect(b)
                if Art.BuildingContains(b.kind,bx,by,bw,bh,px,py) and by+bh>pickedDepth then
                    x,y,pickedDepth=b.x,b.y,by+bh
                end
            end
        end
        if self.tool=="demolish" then self.sim:Demolish(x,y)
        elseif C.buildings[self.tool] then self.sim:Perform(self.tool,x,y)
        else
            local body=self.sim.grid:Get(x,y)
            if body and body.building==-2 then self.sim:Notify("骷髅总部 · 固定地标，不可拆除") end
            if body and body.resource>0 then
                local r=self.sim.grid:FindResource(body.resource)
                if r then self.sim:Notify(C.resources[r.kind].name.." · 剩余 "..r.stock.." / "..r.maxStock) end
            end
            local cell=self.sim.grid:Get(x,y)
            if cell and cell.building>0 then
                local b=self.sim.grid:FindBuilding(cell.building)
                if b then self.sim:Notify(C.buildings[b.kind].name.." · "..C.buildings[b.kind].description) end
            end
        end
    end
    self.dragging=false
    event:StopPropagation()
end
function Battlefield:OnPointerCancel(event) self.dragging=false end
function Battlefield:OnPointerLeave(event) self.hoverX,self.hoverY=0,0 end

function Battlefield:BuildingRect(b)
    return View.BuildingRect(b.kind,b.x,b.y,Art.BuildingAspect(b.kind))
end

-- 血条是真实UI.ProgressBar子控件，图形层只负责角色和背景。
function Battlefield:UpdateBars()
    self:UpdateGeometry()
    local l=self:GetAbsoluteLayout()
    local sim=self.sim
    local seen={}
    for _,u in ipairs(sim.units) do
        if sim:Active(u) or (u.assembling and u.active and u.hp>0) then
            seen[u.id]=true
            local bar=self.bars[u.id]
            if not bar then
                bar=UI.ProgressBar { position="absolute",width=34,height=8,showLabel=false,
                    borderWidth=2,borderColor={27,20,33,255},borderRadius=4,
                    backgroundColor={29,23,37,255},fillColor=u.team=="ally" and Art.palette.green or Art.palette.red,
                    pointerEvents="none" }
                self.bars[u.id]=bar
                self:AddChild(bar)
            end
            local x,y=self:Project(u.x,u.y)
            local _,_,_,top=Art.UnitGeometry(u)
            bar:SetStyle { left=x-l.x-17*self.scaleFactor,top=y-l.y-(top+12)*self.scaleFactor,
                width=34*self.scaleFactor,height=8*self.scaleFactor,borderWidth=2*self.scaleFactor,
                fillColor=u.team=="ally" and Art.palette.green or Art.palette.red }
            bar:SetValue(math.max(0,u.hp/u.maxHp))
            local visible=x>=l.x and x<=l.x+l.w and y>=l.y+(top+12)*self.scaleFactor and y<=l.y+l.h
            local dx,dy=self:DesignPoint(u.x,u.y)
            for _,b in ipairs(sim.grid.buildings) do
                local bx,by,bw,bh,bottom=self:BuildingRect(b)
                if bottom>dy and Art.BuildingContains(b.kind,bx,by,bw,bh,dx,dy-top) then
                    visible=false
                    break
                end
            end
            bar:SetVisible(visible)
        end
    end
    for id,bar in pairs(self.bars) do
        if not seen[id] then self:RemoveChild(bar); self.bars[id]=nil end
    end
end

function Battlefield:RenderPreview(vg)
    if not C.buildings[self.tool] or self.hoverX<1 or self.hoverX>C.wallCol or self.hoverY<1 or self.hoverY>C.rows then return end
    local valid=self.sim:CanBuild(self.tool,self.hoverX,self.hoverY)
    local px,py,pw,ph=View.Footprint(self.tool,self.hoverX,self.hoverY)
    Art.Rect(vg,px,py,pw,ph,valid and {126,231,86,48} or {231,71,80,55},5,
        valid and {170,240,116,200} or {242,85,99,220},2)
    local bx,by,bw,bh=self:BuildingRect({kind=self.tool,x=self.hoverX,y=self.hoverY})
    nvgSave(vg)
    nvgGlobalAlpha(vg,.5)
    Art.Building(vg,self.tool,bx,by,bw,bh,self.sim.time)
    nvgRestore(vg)
end

function Battlefield:Render(vg)
    self:UpdateGeometry()
    local l=self:GetAbsoluteLayout()
    local k=self.scaleFactor
    nvgSave(vg); nvgIntersectScissor(vg,l.x,l.y,l.w,l.h)
    Art.Rect(vg,l.x,l.y,l.w,l.h,{34,29,45,255})
    nvgTranslate(vg,self.viewX,self.viewY); nvgScale(vg,k,k)
    Art.Image(vg,"ground",0,0,1568,882)
    local sim=self.sim
    -- 道路仍由真实踩踏升级；仅高等级留下细小石块，避免恢复旧棋盘格。
    for y=1,C.rows do
        for x=1,C.wallCol-1 do
            local cell=sim.grid:Get(x,y)
            if cell and cell.trail>=2 and cell.building==0 and cell.resource==0 then
                local px,py=self:DesignPoint(x,y)
                local color=cell.trail>=3 and {164,145,129,95} or {145,111,76,55}
                Art.Ellipse(vg,px-7,py-3,5,2,color)
                Art.Ellipse(vg,px+5,py+3,4,2,color)
            end
        end
    end
    -- 参考图左上角的骷髅总部：营地的不可移动地标，不伪装成可操作建筑。
    Art.Image(vg,"hq",34,43,293,253)
    local order=self.drawOrder
    local count=0
    for _,r in ipairs(sim.grid.resources) do
        for _,c in ipairs(r.cells) do
            count=count+1
            local item=order[count] or {}; order[count]=item
            local _,foot=self:DesignPoint(c.x,c.y)
            item.depth,item.key=foot,50000+r.id*100+c.x
            item.building,item.unit,item.resource,item.cell=nil,nil,r,c
        end
    end
    for _,b in ipairs(sim.grid.buildings) do
        count=count+1
        local item=order[count] or {}; order[count]=item
        local _,_,_,_,bottom=self:BuildingRect(b)
        item.depth,item.key=bottom,b.id
        item.building,item.unit,item.resource=b,nil,nil
    end
    for _,u in ipairs(sim.units) do
        if sim:Active(u) or (u.assembling and u.active and u.hp>0) then
            count=count+1
            local item=order[count] or {}; order[count]=item
            local _,foot=self:DesignPoint(u.x,u.y)
            item.depth,item.key=foot,100000+u.id
            item.building,item.unit,item.resource=nil,u,nil
        end
    end
    for i=count+1,#order do order[i]=nil end
    table.sort(order,ByDepth)
    for i=1,count do
        local item=order[i]
        if item.building then
            local b=item.building
            local x,y,w,h=self:BuildingRect(b)
            local fx,fy,fw,fh=View.Footprint(b.kind,b.x,b.y)
            Art.Ellipse(vg,fx+fw*.5,fy+fh-10,fw*.48,8,Art.palette.shadow)
            Art.Building(vg,b.kind,x,y,w,h,sim.time)
        elseif item.resource then
            local px,py=self:DesignPoint(item.cell.x,item.cell.y)
            Art.Ellipse(vg,px,py+3,18,8,{89,75,95,90})
            if item.resource.kind=="forest" then Art.Fit(vg,"tree",px-25,py-67,50,72)
            else Art.Fit(vg,"stone",px-19,py-33,38,35) end
        else
            local u=item.unit
            local x,y=self:DesignPoint(u.x,u.y)
            Art.Unit(vg,u,x,y,sim.time)
        end
    end
    for _,shot in ipairs(sim.shots) do
        local target=sim:FindUnit(shot.target)
        if target then
            local x,y=self:DesignPoint(shot.x,shot.y)
            local tx,ty=self:DesignPoint(target.x,target.y)
            local dx,dy=tx-x,ty-y
            local len=math.max(1,math.sqrt(dx*dx+dy*dy))
            Art.Line(vg,x,y-14,x-dx/len*14,y-14-dy/len*14,
                shot.team=="ally" and {189,245,151,255} or {252,180,96,255},2.5)
        end
    end
    for _,e in ipairs(sim.effects) do
        local life=e.life/e.maxLife
        local x,y=self:DesignPoint(e.x,e.y)
        if e.kind=="hit" then
            local r=11*(1.3-life*.3)
            Art.Line(vg,x-r,y-22,x+r,y-8,{255,228,173,math.floor(life*230)},3)
            Art.Line(vg,x-r,y-8,x+r,y-22,{255,228,173,math.floor(life*230)},3)
        elseif e.kind=="upgrade" then
            for j=1,4 do
                local a=j*math.pi*.5+life
                Art.Ellipse(vg,x+math.cos(a)*18*(1-life),y-22+math.sin(a)*12*(1-life),2,2,{122,249,168,math.floor(life*220)})
            end
        else
            Art.Ellipse(vg,x,y-10,e.radius*25*(1.1-life*.3),e.radius*13,{e.color[1],e.color[2],e.color[3],math.floor(life*45)})
        end
    end
    self:RenderPreview(vg)
    nvgRestore(vg)
end
return Battlefield
