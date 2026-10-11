-- 参考图美术资源：本地原图拆分的透明精灵与清理后的地面。
-- UI.Widget 已统一处理帧、DPR与指针坐标，这里只在传入的上下文中绘制。
local C = require "Frontier.Config"
local Art = {}
Art.palette = {
    outline = { 29, 22, 34, 255 }, shadow = { 27, 22, 34, 65 },
    grassIn = { 194, 156, 105, 255 }, grassOut = { 89, 80, 112, 255 },
    bone = { 242, 221, 193, 255 }, green = { 137, 233, 68, 255 },
    red = { 233, 67, 91, 255 }, gold = { 248, 179, 37, 255 },
}

-- 图像句柄仅初始化一次；切换上下文时清除缓存，避免失效句柄复用。
local images = {} ---@type table<string, number>
---@type NVGContextWrapper?
local context = nil
local sizes = {
    ground={1568,882}, hq={293,253}, barracks={157,139},
    coffin={150,151}, cauldron={212,165}, lumber={135,160},
    pumpkin_farm={153,137}, armory={253,163}, hut={211,138},
    ally={49,47}, worker={62,54}, guard={72,65}, archer={84,67},
    zombie={85,78}, ghost={68,58}, flame={74,63}, tree={109,149},
    gold={43,42}, slime={37,44}, skull={40,39}, stone={54,50},pumpkin_worker={70,49},
}

function Art.Color(c, alpha)
    return nvgRGBA(c[1], c[2], c[3], alpha or c[4] or 255)
end

function Art.Rect(vg, x, y, w, h, color, radius, outline, ow)
    if w <= 0 or h <= 0 then return end
    nvgBeginPath(vg)
    nvgRoundedRect(vg, x, y, w, h, radius or 0)
    nvgFillColor(vg, Art.Color(color)); nvgFill(vg)
    if outline then
        nvgStrokeColor(vg, Art.Color(outline)); nvgStrokeWidth(vg, ow or 1.5); nvgStroke(vg)
    end
end

function Art.Line(vg, x1, y1, x2, y2, color, width)
    nvgBeginPath(vg); nvgMoveTo(vg,x1,y1); nvgLineTo(vg,x2,y2)
    nvgStrokeColor(vg,Art.Color(color)); nvgStrokeWidth(vg,width or 1.5)
    nvgLineCap(vg,NVG_ROUND); nvgStroke(vg)
end

function Art.Ellipse(vg,x,y,rx,ry,color)
    nvgBeginPath(vg); nvgEllipse(vg,x,y,rx,ry)
    nvgFillColor(vg,Art.Color(color)); nvgFill(vg)
end

function Art.Load(vg, name)
    if context ~= vg then context = vg; images = {} end
    local cached = images[name]
    if cached then return cached end
    local image = nvgCreateImage(vg, "Reference/"..name..".png", 0)
    images[name] = image
    if image > 0 then
        local w,h = nvgImageSize(vg,image)
        sizes[name] = {w,h}
        print("[参考美术] 已加载 "..name.." "..w.."×"..h)
    else
        print("[参考美术] 图片加载失败：Reference/"..name..".png")
    end
    return image
end

function Art.Image(vg,name,x,y,w,h,alpha,flip)
    local image = Art.Load(vg,name)
    if image <= 0 or w <= 0 or h <= 0 then return end
    nvgSave(vg)
    if flip then nvgTranslate(vg,x+w,y); nvgScale(vg,-1,1); x,y=0,0 end
    nvgBeginPath(vg); nvgRect(vg,x,y,w,h)
    nvgFillPaint(vg,nvgImagePattern(vg,x,y,w,h,0,image,alpha or 1))
    nvgFill(vg); nvgRestore(vg)
end

-- 按最大盒子等比放入，不拉伸原图的角色与建筑。
function Art.Fit(vg,name,x,y,w,h,alpha)
    Art.Load(vg,name)
    local size = sizes[name] or {w,h}
    local scale = math.min(w/size[1],h/size[2])
    local dw,dh = size[1]*scale,size[2]*scale
    Art.Image(vg,name,x+(w-dw)*.5,y+(h-dh)*.5,dw,dh,alpha)
end

local buildingImages = {
    barracks="barracks", farmerBarracks="pumpkin_farm", shield="coffin",
    bow="armory", forge="cauldron", aim="coffin", stable="hut",
    horn="coffin", warehouse="lumber", elephant="armory", tower="coffin",block="coffin",
}

function Art.Building(vg,kind,x,y,w,h,time)
    local name = buildingImages[kind] or "barracks"
    Art.Fit(vg,name,x,y,w,h)
    -- 召唤池仅叠加少量漂浮光点，保留原图色块与轮廓。
    if kind == "forge" then
        for i=1,3 do
            local phase = (time*.5+i*.27)%1
            local px = x+w*(.30+i*.11)
            local py = y+h*(.48-phase*.16)
            Art.Ellipse(vg,px,py,w*.011,h*.013,{113,255,184,math.floor((1-phase)*110)})
        end
    end
end

function Art.UnitName(u)
    if u.worker then
        if u.carry>0 then return u.carryKind=="forest" and "worker" or "pumpkin_worker" end
        return "ally"
    end
    if u.team == "ally" then
        if u.gear.shield or u.gear.forge then return "archer" end
        if u.gear.bow then return "archer" end
        if u.size == 2 then return "zombie" end
        return "ally"
    end
    if u.kind == "brute" or u.kind == "boss" then return "zombie" end
    if u.kind == "shooter" then return u.id%3==0 and "ghost" or "flame" end
    return u.id%2==0 and "guard" or "archer"
end

local anchors={ally={13,42},worker={19,48},guard={32,61},archer={42,61},
    zombie={34,72},ghost={40,47},flame={37,54},pumpkin_worker={20,45}}

function Art.Unit(vg,u,x,y,time)
    local name=Art.UnitName(u)
    local size=sizes[name]
    local anchor=anchors[name]
    local scale=u.kind=="boss" and 1.6 or 1
    local w,h=size[1]*scale,size[2]*scale
    local ax,ay=anchor[1]*scale,anchor[2]*scale
    local flip=u.team=="ally" and u.facing<0
    if flip then ax=w-ax end
    Art.Ellipse(vg,x,y-2,w*.25,h*.07,Art.palette.shadow)
    local bob=u.moving and math.sin(time*9+u.id)*1.5 or math.sin(time*2+u.id)*.35
    local attack=u.cooldown>u.stats.interval*.8 and math.sin(time*25+u.id)*1.2 or 0
    Art.Image(vg,name,x-ax+attack,y-ay+bob,w,h,1,flip)
    -- 升级之后有可辨认的装备变化，不在角色上增加文字标签。
    if u.gear.bow then
        Art.Line(vg,x+16,y-33,x+25,y-22,Art.palette.outline,5)
        Art.Line(vg,x+25,y-22,x+17,y-10,Art.palette.outline,5)
        Art.Line(vg,x+16,y-33,x+25,y-22,{192,133,67,255},2.5)
        Art.Line(vg,x+25,y-22,x+17,y-10,{192,133,67,255},2.5)
        Art.Line(vg,x+16,y-33,x+17,y-10,Art.palette.bone,1)
    end
    if u.gear.forge then Art.Rect(vg,x-10,y-27,13,11,{128,119,157,255},3,Art.palette.outline,2) end
    if u.gear.stable then
        Art.Ellipse(vg,x,y-6,15,6,{109,83,133,255})
        Art.Line(vg,x-10,y-5,x-12,y+3,Art.palette.bone,3)
        Art.Line(vg,x+10,y-5,x+12,y+3,Art.palette.bone,3)
    end
    if u.gear.aim then Art.Ellipse(vg,x+w*.24,y-h*.65,2,2,{158,247,92,255}) end
    if u.gear.horn then Art.Ellipse(vg,x-w*.22,y-h*.26,2.5,2.5,Art.palette.gold) end
    return w,h
end

return Art
