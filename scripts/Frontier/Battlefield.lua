-- 全屏战场：以参考图1568×882为设计画布；世界坐标与UI共享同一等比映射。
local UI = require "urhox-libs/UI"
local C = require "Frontier.Config"
local Art = require "Frontier.Artwork"

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

local function ByDepth(a,b) return a.depth<b.depth end

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

local rowEdges={85,159,233,307,380,409,438,467,525,583,641,699,757}

function Battlefield:DesignPoint(x,y)
    local px=x<=23.5 and 25+(x-.5)*40 or 945+(x-23.5)*62.3
    local t=math.max(0,math.min(12,y-.5))
    local i=math.min(12,math.floor(t)+1)
    return px,rowEdges[i]+(t-i+1)*(rowEdges[i+1]-rowEdges[i])
end

function Battlefield:Project(x,y)
    local px,py=self:DesignPoint(x,y)
    return self.viewX+px*self.scaleFactor,self.viewY+py*self.scaleFactor
end

function Battlefield:WorldPoint(x,y)
    self:UpdateGeometry()
    local px,py=(x-self.viewX)/self.scaleFactor,(y-self.viewY)/self.scaleFactor
    local col=px<945 and math.floor((px-25)/40)+1 or 24+math.floor((px-945)/62.3)
    local row=0
    for i=1,12 do if py>=rowEdges[i] and py<rowEdges[i+1] then row=i; break end end
    return col,row
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
            local px,py=(event.x-self.viewX)/self.scaleFactor,(event.y-self.viewY)/self.scaleFactor
            local pickedDepth=-math.huge
            for _,b in ipairs(self.sim.grid.buildings) do
                local bx,by,bw,bh=self:BuildingRect(b)
                if px>=bx and px<=bx+bw and py>=by and py<=by+bh and by+bh>pickedDepth then
                    x,y,pickedDepth=b.x,b.y,by+bh
                end
            end
        end
        if self.tool=="demolish" then self.sim:Demolish(x,y)
        elseif C.buildings[self.tool] then self.sim:Perform(self.tool,x,y)
        else
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
    if b.visualX and b.visualY and b.visualW and b.visualH then
        return b.visualX,b.visualY,b.visualW,b.visualH
    end
    local d=C.buildings[b.kind]
    local x,y=self:Project(b.x+d.w*.5-.5,b.y+d.h*.5-.5)
    -- 建筑高于地面占地，脚点贴合原图；上部轮廓不改变碰撞网格。
    local w=math.max(d.w*40+42,100)
    local h=math.max(d.h*54+35,110)
    if b.kind=="barracks" then w,h=166,166
    elseif b.kind=="farmerBarracks" then w,h=178,152
    elseif b.kind=="forge" then w,h=180,168
    elseif b.kind=="shield" then w,h=140,178
    elseif b.kind=="bow" then w,h=238,175
    elseif b.kind=="warehouse" then w,h=130,155
    elseif b.kind=="stable" then w,h=198,153 end
    return x/self.scaleFactor-self.viewX/self.scaleFactor-w*.5,
        y/self.scaleFactor-self.viewY/self.scaleFactor-h+55,w,h
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
            local big=u.size==2 or u.kind=="brute"
            bar:SetStyle { left=x-l.x-17*self.scaleFactor,top=y-l.y-(big and 76 or 57)*self.scaleFactor,
                width=34*self.scaleFactor,height=8*self.scaleFactor,borderWidth=2*self.scaleFactor }
            bar:SetValue(math.max(0,u.hp/u.maxHp))
            bar:SetVisible(x>=l.x and x<=l.x+l.w and y>=l.y+80*self.scaleFactor and y<=l.y+l.h)
        end
    end
    for id,bar in pairs(self.bars) do
        if not seen[id] then self:RemoveChild(bar); self.bars[id]=nil end
    end
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
    -- 只在选中建造时显露占地与预览，日常战场绝不铺棋盘格。
    if C.buildings[self.tool] and self.hoverX>=1 and self.hoverX<=C.wallCol and self.hoverY>=1 and self.hoverY<=C.rows then
        local d=C.buildings[self.tool]
        local valid=sim.grid:CanPlace(self.tool,self.hoverX,self.hoverY) and sim.gold>=d.cost
        local px,py=25+(self.hoverX-1)*40,rowEdges[self.hoverY]
        local height=rowEdges[math.min(13,self.hoverY+d.h)]-py
        Art.Rect(vg,px,py,d.w*40,height,valid and {126,231,86,48} or {231,71,80,55},5,
            valid and {170,240,116,200} or {242,85,99,220},2)
        nvgGlobalAlpha(vg,.5)
        Art.Building(vg,self.tool,px-20,py-60,d.w*40+42,d.h*54+35,sim.time)
        nvgGlobalAlpha(vg,1)
    end
    -- 资源点使用参考图的枯树和木材屋旁的木料，储量由原采集系统管理。
    for _,r in ipairs(sim.grid.resources) do
        local c=r.cells[1]
        if c then
            local px,py=self:DesignPoint(c.x,c.y)
            local name=r.kind=="forest" and "tree" or "stone"
            if r.kind=="forest" then Art.Fit(vg,name,px-35,py-80,70,100)
            else Art.Fit(vg,name,px-27,py-46,54,50) end
        end
    end
    local order=self.drawOrder
    local count=0
    for _,b in ipairs(sim.grid.buildings) do
        count=count+1
        local item=order[count] or {}; order[count]=item
        item.depth=b.y+C.buildings[b.kind].h*.5
        item.building,item.unit=b,nil
    end
    for _,u in ipairs(sim.units) do
        if sim:Active(u) or (u.assembling and u.active and u.hp>0) then
            count=count+1
            local item=order[count] or {}; order[count]=item
            item.depth=u.y
            item.building,item.unit=nil,u
        end
    end
    for i=count+1,#order do order[i]=nil end
    table.sort(order,ByDepth)
    for i=1,count do
        local item=order[i]
        if item.building then
            local b=item.building
            local x,y,w,h=self:BuildingRect(b)
            Art.Building(vg,b.kind,x,y,w,h,sim.time)
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
    nvgRestore(vg)
end
return Battlefield
