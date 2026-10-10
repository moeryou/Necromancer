local UI = require "urhox-libs/UI"
local C = require "Frontier.Config"
local Art = require "Frontier.Artwork"

---@class FrontierBattlefield : Widget
---@field sim FrontierSim
---@field cameraX number
---@field zoom number
---@field tile number
---@field originX number
---@field originY number
---@field viewWidth number
---@field viewHeight number
---@field tool string
---@field hoverX number
---@field hoverY number
---@field dragX number
---@field dragY number
---@field dragCamera number
---@field dragging boolean
---@field dragMoved boolean
---@field lastCell string
local Battlefield = UI.Widget:Extend("FrontierBattlefield")

function Battlefield:Init(props)
    props = props or {}
    props.flexGrow, props.flexBasis, props.flexShrink = 1, 0, 1
    props.overflow, props.pointerEvents = "hidden", "auto"
    UI.Widget.Init(self, props)
    self.sim = props.sim
    self.cameraX, self.zoom, self.tile = 0, 1, 36
    self.originX, self.originY, self.viewWidth, self.viewHeight = 0, 0, 1, 1
    self.tool, self.hoverX, self.hoverY = "inspect", 0, 0
    self.dragX, self.dragY, self.dragCamera = 0, 0, 0
    self.dragging, self.dragMoved, self.lastCell = false, false, ""
end

function Battlefield:UpdateGeometry()
    local l = self:GetAbsoluteLayout()
    self.viewWidth, self.viewHeight = l.w, l.h
    self.tile = math.max(18, math.min(44, (l.h - 70) / C.rows)) * self.zoom
    self.originX = l.x + 24 - self.cameraX * self.tile
    self.originY = l.y + math.max(34, (l.h - C.rows*self.tile)*0.5)
    local maxCamera = math.max(0, C.cols - (l.w - 48) / self.tile)
    self.cameraX = math.max(0, math.min(maxCamera, self.cameraX))
    self.originX = l.x + 24 - self.cameraX * self.tile
end

function Battlefield:WorldPoint(x, y)
    self:UpdateGeometry()
    return math.floor((x-self.originX)/self.tile)+1, math.floor((y-self.originY)/self.tile)+1
end

function Battlefield:SetTool(tool)
    -- Widget 的透明属性路由会调用同名 setter，内部字段必须 rawset。
    rawset(self, "tool", tool)
end

function Battlefield:Pan(amount)
    self.cameraX = self.cameraX + amount
    self:UpdateGeometry()
end

function Battlefield:OnWheel(dx, dy)
    self:Pan(-dy * 2 + dx * 2)
end

function Battlefield:OnPointerDown(event)
    if not event:IsPrimaryButton() and event.pointerType ~= "touch" then return end
    self.dragging, self.dragMoved = true, false
    self.dragX, self.dragY, self.dragCamera = event.x, event.y, self.cameraX
    self.lastCell = ""
    self.hoverX, self.hoverY = self:WorldPoint(event.x,event.y)
    -- 地形不可编辑：点击只用于浏览和放置建筑。
    event:StopPropagation()
end

function Battlefield:OnPointerMove(event)
    self.hoverX, self.hoverY = self:WorldPoint(event.x,event.y)
    if self.dragging and self.tool == "inspect" then
        local delta = event.x-self.dragX
        if math.abs(delta)+math.abs(event.y-self.dragY)>6 then self.dragMoved = true end
        self.cameraX = self.dragCamera - delta/self.tile
        self:UpdateGeometry()
    end
end

function Battlefield:OnPointerUp(event)
    if self.dragging and not self.dragMoved then
        local x,y = self:WorldPoint(event.x,event.y)
        if C.buildings[self.tool] or self.tool == "erase" then
            self.sim:Perform(self.tool,x,y)
        else
            local cell = self.sim.grid:Get(x,y)
            if cell and cell.building>0 then
                local b = self.sim.grid:FindBuilding(cell.building)
                if b then
                    local def = C.buildings[b.kind]
                    self.sim:Notify(def.name .. " · " .. def.description .. (def.upgrade and (" · 库存 " .. b.stock .. "/5") or ""))
                end
            end
        end
    end
    self.dragging = false
end

function Battlefield:OnPointerCancel(event)
    self.dragging = false
end

function Battlefield:OnPointerLeave(event)
    self.hoverX,self.hoverY = 0,0
end

function Battlefield:Render(vg)
    self:UpdateGeometry()
    local l = self:GetAbsoluteLayout()
    local s,ox,oy = self.tile,self.originX,self.originY
    nvgSave(vg)
    nvgIntersectScissor(vg,l.x,l.y,l.w,l.h)
    local pal = Art.palette
    Art.Rect(vg,l.x,l.y,l.w,l.h,pal.grassOut)
    local gradient = nvgLinearGradient(vg,0,l.y,0,l.y+l.h,nvgRGBA(128,180,90,255),nvgRGBA(96,146,68,255))
    nvgBeginPath(vg); nvgRect(vg,l.x,l.y,l.w,l.h); nvgFillPaint(vg,gradient); nvgFill(vg)
    local startCol = math.max(1,math.floor(self.cameraX))
    local endCol = math.min(C.cols,math.ceil(self.cameraX+l.w/s)+1)
    -- 地图边缘森林与散落植被，细节由坐标哈希决定而非每帧随机。
    for x=startCol,endCol do
        if x%3 == 0 then
            Art.Tree(vg,ox+(x-.5)*s,oy+s*.15,s*.78)
            Art.Tree(vg,ox+(x-.1)*s,oy+C.rows*s+s*.95,s*.82)
        end
        for y=1,C.rows do
            local px,py = ox+(x-1)*s,oy+(y-1)*s
            local cell = self.sim.grid.cells[y][x]
            local base = x<C.wallCol and ((x+y)%2==0 and pal.grassIn or pal.grassIn2)
                or ((x+y)%2==0 and pal.grassOut or pal.grassOut2)
            Art.Rect(vg,px,py,s,s,base)
            local hash = (x*71+y*37)%23
            if hash<7 and cell.building==0 and cell.trail==0 then
                local cx,cy=px+s*(.18+hash*.10),py+s*.72
                Art.GrassTuft(vg,cx,cy,s*.34)
                if hash<2 then Art.Flower(vg,cx+s*.30,cy-s*.06,s*.30,{ 246,244,236,255 }) end
            end
            if cell.trail > 0 then Art.Trail(vg,px,py,s,cell.trail,x*13+y*7)
            elseif x==C.wallCol and not self.sim.grid:IsGateRow(y) then Art.Wall(vg,px,py,s) end
        end
    end
    -- 营地边界、城门条纹与行军方向刻线。
    local wx = ox+(C.wallCol-1)*s
    Art.Line(vg,ox-2,oy,ox-2,oy+C.rows*s,{ 150,196,124,150 },2)
    for y=C.gateTop,C.gateTop+C.gateWidth-1 do
        -- 门道：木板铺面 + 向右的通行箭头
        local gy = oy+(y-1)*s
        Art.Rect(vg,wx+s*.06,gy+s*.05,s*.88,s*.9,pal.woodLite,s*.08,pal.outline,s*.05)
        nvgBeginPath(vg)
        for i=1,2 do
            local yy=gy+s*(.05+i*.30)
            nvgMoveTo(vg,wx+s*.06,yy); nvgLineTo(vg,wx+s*.94,yy)
        end
        Art.Stroke(vg,pal.woodDark,s*.05)
        Art.Polygon(vg,{ wx+s*.30,oy+(y-.68)*s,wx+s*.78,oy+(y-.5)*s,wx+s*.30,oy+(y-.32)*s },
            { 250,226,158,235 },pal.outline,s*.05)
    end
    Art.Flag(vg,wx+s*.17,oy+(C.gateTop-1.1)*s,s*.8,{ 226,177,99,255 },self.sim.time)
    Art.Flag(vg,wx+s*.17,oy+(C.gateTop+C.gateWidth)*s,s*.8,{ 226,177,99,255 },self.sim.time+2)
    if self.sim.phase == "develop" then
        for _,r in ipairs(self.sim.resources) do
            Art.Resource(vg,r,ox+(r.x-.5)*s,oy+(r.y-.5)*s,s*.9,self.sim.time)
        end
    end
    for _,b in ipairs(self.sim.grid.buildings) do
        local def=C.buildings[b.kind]
        if b.x+def.w>=startCol and b.x<=endCol then
            Art.Building(vg,b.kind,ox+(b.x-1)*s,oy+(b.y-1)*s,s,b.stock,
                def.interval>0 and b.timer/def.interval or 0,self.sim.time)
        end
    end
    local order = {}
    for _,u in ipairs(self.sim.units) do if self.sim:Active(u) then table.insert(order,u) end end
    table.sort(order,function(a,b) return a.y<b.y end)
    for _,u in ipairs(order) do
        if u.x>=startCol-1 and u.x<=endCol+1 then
            Art.Unit(vg,u,ox+(u.x-.5)*s,oy+(u.y-.5)*s,s,self.sim.time)
        end
    end
    for _,p in ipairs(self.sim.shots) do
        local target=self.sim:FindUnit(p.target)
        local dx,dy=target and target.x-p.x or 1,target and target.y-p.y or 0
        local d=math.max(.1,math.sqrt(dx*dx+dy*dy))
        local x,y=ox+(p.x-.5)*s,oy+(p.y-.5)*s
        Art.Line(vg,x,y,x-dx/d*s*.28,y-dy/d*s*.28,p.team=="ally" and { 248,222,157,255 } or { 227,137,100,255 },1.5)
    end
    for _,e in ipairs(self.sim.effects) do
        local alpha=math.floor(210*e.life/e.maxLife)
        local x,y=ox+(e.x-.5)*s,oy+(e.y-.5)*s
        local radius=e.radius*s*(1-e.life/e.maxLife*.5)
        nvgBeginPath(vg); nvgCircle(vg,x,y,radius)
        nvgStrokeColor(vg,Art.Color(e.color,alpha)); nvgStrokeWidth(vg,1.5); nvgStroke(vg)
        if e.kind=="aoe" then Art.Circle(vg,x,y,radius,{ e.color[1],e.color[2],e.color[3],math.floor(alpha*.2) }) end
    end
    if self.tool == "erase" and self.hoverX>0 and self.hoverY>0 then
        local cell = self.sim.grid:Get(self.hoverX,self.hoverY)
        local x,y=ox+(self.hoverX-1)*s,oy+(self.hoverY-1)*s
        if cell and cell.building>0 then
            Art.Rect(vg,x,y,s,s,{ 225,117,95,110 },2)
            nvgBeginPath(vg); nvgRect(vg,x+1,y+1,s-2,s-2)
            nvgStrokeColor(vg,nvgRGBA(244,138,112,255)); nvgStrokeWidth(vg,2); nvgStroke(vg)
        end
    elseif C.buildings[self.tool] and self.hoverX>0 and self.hoverY>0 then
        local def=C.buildings[self.tool]
        local w,h=def.w,def.h
        local valid=self.sim.grid:CanPlace(self.tool,self.hoverX,self.hoverY)
        local col=valid and { 229,218,163,90 } or { 225,117,95,120 }
        local x,y=ox+(self.hoverX-1)*s,oy+(self.hoverY-1)*s
        Art.Rect(vg,x,y,w*s,h*s,col,2)
        nvgBeginPath(vg); nvgRect(vg,x+1,y+1,w*s-2,h*s-2)
        nvgStrokeColor(vg,valid and nvgRGBA(243,223,160,255) or nvgRGBA(244,138,112,255))
        nvgStrokeWidth(vg,2); nvgStroke(vg)
    end
    -- 底部缩略全图。点击导航由独立UI按钮负责，这里仅提供视觉信息。
    local mw=math.min(280,l.w*.35)
    local mx,my=l.x+l.w-mw-20,l.y+l.h-26
    Art.Rect(vg,mx-6,my-6,mw+12,18,{ 44,56,42,215 },3,pal.outline,1.2)
    Art.Rect(vg,mx,my,mw*C.wallCol/C.cols,6,pal.grassIn,1)
    Art.Rect(vg,mx+mw*C.wallCol/C.cols,my,mw*(C.cols-C.wallCol)/C.cols,6,pal.grassOut,1)
    for _,u in ipairs(self.sim.units) do
        if self.sim:Active(u) then Art.Circle(vg,mx+mw*u.x/C.cols,my+3,1.3,u.team=="ally" and { 216,210,145,255 } or { 221,113,90,255 }) end
    end
    local visible=(l.w-48)/s
    nvgBeginPath(vg); nvgRect(vg,mx+mw*self.cameraX/C.cols,my-2,math.min(mw,mw*visible/C.cols),10)
    nvgStrokeColor(vg,nvgRGBA(228,214,164,230)); nvgStrokeWidth(vg,1); nvgStroke(vg)
    nvgRestore(vg)
end
return Battlefield
