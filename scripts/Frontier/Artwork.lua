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
local retryTimes = {} ---@type table<string, number>
---@type NVGContextWrapper?
local context = nil
local sizes = {
    ground={1568,882}, hq={293,253}, barracks={157,139},
    coffin={150,151}, cauldron={212,165}, lumber={135,160},
    pumpkin_farm={153,137}, armory={253,163}, hut={211,138},
    ally={49,47},worker={62,54},guard={72,65},archer={84,67},hostile_guard={84,67},
    enemy_raider={84,67},enemy_brute={85,78},enemy_shooter={84,70},
    zombie={85,78}, ghost={68,58}, flame={74,63}, tree={109,149},
    ranger={128,120},armored={124,116},heavy={124,116},mounted={200,180},elephant={264,220},boss={172,170},
    building_aim={173,145},building_horn={161,141},building_tower={146,213},
    building_block={79,102},building_elephant={212,175},building_warehouse={165,157},
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
    if context ~= vg then context = vg; images = {}; retryTimes={} end
    local cached = images[name]
    if cached and cached>0 then return cached end
    -- DWP占位未就绪时不能永久缓存失败句柄；等待资源可用后重新加载。
    if cached and (time:GetElapsedTime()-(retryTimes[name] or 0))<1 then return 0 end
    local image = nvgCreateImage(vg, "Reference/"..name..".png", 0)
    images[name] = image
    retryTimes[name]=time:GetElapsedTime()
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
    bow="armory",forge="cauldron",aim="building_aim",stable="hut",
    horn="building_horn",warehouse="building_warehouse",elephant="building_elephant",
    tower="building_tower",block="building_block",
}

function Art.BuildingName(kind)
    return buildingImages[kind] or "barracks"
end

function Art.BuildingAspect(kind)
    local size=sizes[Art.BuildingName(kind)]
    return size[1]/size[2]
end

-- 从本地 PNG 的 alpha 轮廓提取12个水平带，透明屋顶角不能抢走邻格点击。
local buildingContours = {
    barracks={{.197,.841},{.019,.955},{.019,.975},{.025,.975},{.038,.981},{.038,.975},{.057,.981},{.051,.975},{.045,.981},{.045,.981},{.045,.962},{.057,.962}},
    pumpkin_farm={{.065,.941},{.059,.954},{.033,.974},{.026,.974},{.02,.98},{.026,.98},{.033,.961},{.026,.974},{.026,.967},{.026,.974},{.033,.974},{.059,.941}},
    coffin={{.26,.753},{.02,.953},{.02,.96},{.04,.98},{.033,.96},{.04,.98},{.04,.96},{.047,.953},{.033,.98},{.033,.973},{.027,.967},{.107,.967}},
    armory={{.016,.178},{.016,.292},{.024,.988},{.043,.984},{.036,.96},{.036,.953},{.032,.937},{.02,.957},{.012,.968},{.012,.964},{.016,.953},{.032,.949}},
    cauldron={{.363,.892},{.061,.915},{.024,.91},{.014,.906},{.014,.986},{.024,.986},{.075,.981},{.193,.976},{.184,.976},{.189,.967},{.212,.948},{.538,.849}},
    hut={{.156,.564},{.057,.796},{.033,.801},{.024,.953},{.014,.976},{.028,.986},{.028,.962},{.028,.905},{.019,.806},{.014,.782},{.014,.768},{.043,.754}},
    building_aim={{.1329,.4162},{.0867,.4913},{.0578,.7746},{.0578,.7977},{.0636,.8555},{.0636,.8439},{.0751,.9306},{.2197,.9306},{.0058,.9769},{0,.9942},{.0058,1},{.1156,.9133}},
    building_horn={{.2795,.7205},{.2671,.7267},{.2671,.9814},{.1739,.9876},{.1615,.9565},{.1553,.9565},{.1366,.9503},{.0311,.9255},{0,.9938},{0,1},{.0062,.9814},{.0062,.8758}},
    building_tower={{.0959,.7123},{.0548,.8082},{.0274,.8836},{.0205,.9452},{0,.9589},{.0205,1},{.1986,.9726},{.2055,.9589},{.2055,.8425},{.2055,.8356},{.1233,.9315},{.1027,.9384}},
    building_block={{.4051,.7975},{.3165,.8987},{.2025,.9241},{.1519,.9241},{.1519,.9241},{.1899,.9367},{.2025,.9367},{.2152,.9241},{.3291,.7722},{.038,.6962},{0,1},{.0127,1}},
    building_elephant={{.1132,.3868},{.0566,.4764},{.0283,.4481},{.0236,.4623},{.0283,.4623},{.0283,.9906},{.033,1},{.0425,.9953},{.0519,.9575},{.0142,.9292},{0,.934},{0,.9292}},
    building_warehouse={{.4303,.8182},{.4061,1},{.4061,.9939},{.3818,.9758},{.103,.9758},{0,.9576},{0,.9515},{0,.9515},{.0364,.903},{.0727,.897},{.2,.8848},{.4,.8848}},
}

function Art.BuildingContains(kind,x,y,w,h,px,py)
    if w<=0 or h<=0 or px<x or px>=x+w or py<y or py>=y+h then return false end
    local band=buildingContours[Art.BuildingName(kind)][math.min(12,math.floor((py-y)/h*12)+1)]
    local fraction=(px-x)/w
    return fraction>=band[1] and fraction<band[2]
end

function Art.Building(vg,kind,x,y,w,h,time)
    local name = Art.BuildingName(kind)
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

local enemyImages={raider="enemy_raider",brute="enemy_brute",shooter="enemy_shooter",boss="boss"}

function Art.UnitName(u)
    if u.worker then
        if u.carry>0 then return u.carryKind=="forest" and "worker" or "pumpkin_worker" end
        return "ally"
    end
    if u.team=="ally" then
        if u.kind=="elephant" then return "elephant" end
        if u.gear.stable then return "mounted" end
        if u.gear.bow then return "ranger" end
        if u.gear.shield then return "armored" end
        if u.gear.forge then return "heavy" end
        return "ally"
    end
    -- 同一种敌人始终使用同一贴图；编号/波次/集结状态不能改变兵种外观。
    return enemyImages[u.kind] or "enemy_raider"
end

local anchors={ally={13,42},worker={19,48},guard={32,61},archer={42,61},hostile_guard={42,61},
    enemy_raider={42,61},enemy_brute={34,72},enemy_shooter={48,64},
    zombie={34,72},ghost={40,47},flame={37,54},pumpkin_worker={20,45},
    ranger={59,98},armored={58,98},heavy={58,98},mounted={109,157},elephant={125,184},boss={86,143}}

local unitScales={ranger=.7,armored=.75,heavy=.75,mounted=.65,elephant=.5,boss=.75}

function Art.UnitGeometry(u)
    local name=Art.UnitName(u)
    local size=sizes[name]
    local anchor=anchors[name]
    local scale=unitScales[name] or 1
    return size[1]*scale,size[2]*scale,anchor[1]*scale,anchor[2]*scale
end

function Art.Unit(vg,u,x,y,time)
    local name=Art.UnitName(u)
    local size=sizes[name]
    local anchor=anchors[name]
    local scale=unitScales[name] or 1
    local w,h=size[1]*scale,size[2]*scale
    local ax,ay=anchor[1]*scale,anchor[2]*scale
    local nativeFacing=(name=="ally" or name=="worker" or name=="pumpkin_worker" or name=="ranger" or name=="mounted" or name=="elephant") and 1 or -1
    local flip=(u.facing>=0 and 1 or -1)~=nativeFacing
    if flip then ax=w-ax end
    Art.Ellipse(vg,x,y-2,w*.25,h*.07,Art.palette.shadow)
    local bob=u.moving and math.sin(time*9+u.id)*1.5 or math.sin(time*2+u.id)*.35
    local attack=u.cooldown>u.stats.interval*.8 and math.sin(time*25+u.id)*1.2 or 0
    Art.Image(vg,name,x-ax+attack,y-ay+bob,w,h,1,flip)
    -- 所有叠加装备统一在角色局部坐标中，转身不能把弓盾留在原侧。
    nvgSave(vg)
    nvgTranslate(vg,x,y)
    nvgScale(vg,u.facing>=0 and 1 or -1,1)
    x,y=0,0
    -- 骑射追加弓；普通弓兵使用完整独立精灵，不在剑盾图上硬叠弓。
    if u.gear.bow and name=="mounted" then
        Art.Line(vg,x+16,y-79,x+25,y-68,Art.palette.outline,5)
        Art.Line(vg,x+25,y-68,x+17,y-56,Art.palette.outline,5)
        Art.Line(vg,x+16,y-79,x+25,y-68,{192,133,67,255},2.5)
        Art.Line(vg,x+25,y-68,x+17,y-56,{192,133,67,255},2.5)
        Art.Line(vg,x+16,y-79,x+17,y-56,Art.palette.bone,1)
    end
    local chestY=name=="mounted" and -51 or -27
    if u.gear.forge and name~="heavy" then Art.Rect(vg,x-10,y+chestY,13,11,{128,119,157,255},3,Art.palette.outline,2) end
    if u.gear.shield and name=="mounted" then
        Art.Ellipse(vg,x+5,y-48,10,12,Art.palette.outline)
        Art.Ellipse(vg,x+5,y-48,8,10,{122,80,154,255})
        Art.Ellipse(vg,x+5,y-48,3,4,Art.palette.gold)
    end
    if u.gear.aim then Art.Ellipse(vg,x+w*.24,y-h*.65,2,2,{158,247,92,255}) end
    if u.gear.horn then Art.Ellipse(vg,x-w*.22,y-h*.26,2.5,2.5,Art.palette.gold) end
    nvgRestore(vg)
    return w,h
end

return Art
