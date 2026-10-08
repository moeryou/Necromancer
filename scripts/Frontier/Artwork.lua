-- 战场矢量美术仅绘制地图与实体，文字、按钮和HUD由UI组件负责。
local C = require "Frontier.Config"
local Art = {}
Art.colors = {
    ink = { 38, 45, 40, 255 }, paper = { 232, 228, 208, 255 },
    gold = { 209, 180, 117, 255 }, olive = { 110, 128, 95, 255 },
    ground = { 96, 111, 79, 255 }, groundAlt = { 101, 115, 83, 255 },
    dark = { 48, 59, 46, 255 }, road = { 170, 156, 117, 255 },
}

function Art.Color(c, alpha)
    return nvgRGBA(c[1], c[2], c[3], alpha or c[4] or 255)
end

function Art.Rect(vg, x, y, w, h, color, radius)
    if w <= 0 or h <= 0 then return end
    nvgBeginPath(vg)
    if radius and radius > 0 then nvgRoundedRect(vg, x, y, w, h, radius)
    else nvgRect(vg, x, y, w, h) end
    nvgFillColor(vg, Art.Color(color))
    nvgFill(vg)
end

function Art.Line(vg, x1, y1, x2, y2, color, width)
    nvgBeginPath(vg)
    nvgMoveTo(vg, x1, y1)
    nvgLineTo(vg, x2, y2)
    nvgStrokeColor(vg, Art.Color(color))
    nvgStrokeWidth(vg, width or 1)
    nvgStroke(vg)
end

function Art.Circle(vg, x, y, r, color)
    nvgBeginPath(vg)
    nvgCircle(vg, x, y, r)
    nvgFillColor(vg, Art.Color(color))
    nvgFill(vg)
end

function Art.Ellipse(vg, x, y, rx, ry, color)
    nvgBeginPath(vg)
    nvgEllipse(vg, x, y, rx, ry)
    nvgFillColor(vg, Art.Color(color))
    nvgFill(vg)
end

function Art.Polygon(vg, points, color)
    nvgBeginPath(vg)
    nvgMoveTo(vg, points[1], points[2])
    for i = 3, #points, 2 do nvgLineTo(vg, points[i], points[i+1]) end
    nvgClosePath(vg)
    nvgFillColor(vg, Art.Color(color))
    nvgFill(vg)
end

-- 踩踏痕迹：等级越高，土色越实、车辙越深。
function Art.Trail(vg, x, y, s, level, seed)
    local k = ((seed * 37) % 17) / 17
    if level == 1 then
        Art.Rect(vg,x+s*.12,y+s*.14,s*.76,s*.72,{ 156, 142, 100, 74 },2)
        Art.Circle(vg,x+s*.33,y+s*.4,1,{ 146, 133, 94, 120 })
        Art.Circle(vg,x+s*.7,y+s*.66,1,{ 146, 133, 94, 120 })
    elseif level == 2 then
        Art.Rect(vg,x+s*.05,y+s*.06,s*.9,s*.88,{ 172, 152, 108, 255 },2)
        Art.Rect(vg,x+s*.1,y+s*.1,s*.8,s*.8,{ 183, 162, 116, 255 },1)
        Art.Line(vg,x+s*.2,y+s*.34+k*.1,x+s*.82,y+s*.34+k*.1,{ 143, 126, 90, 140 },1)
        Art.Line(vg,x+s*.2,y+s*.68-k*.1,x+s*.82,y+s*.68-k*.1,{ 143, 126, 90, 140 },1)
    elseif level == 3 then
        Art.Rect(vg,x,y,s,s,{ 166, 170, 148, 255 },2)
        Art.Rect(vg,x+1,y+1,s-2,s-2,{ 176, 179, 157, 255 },1)
        Art.Line(vg,x+s*.5,y+3,x+s*.5,y+s-3,{ 134, 148, 136, 120 },1)
        Art.Line(vg,x+3,y+s*.5,x+s-3,y+s*.5,{ 134, 148, 136, 120 },1)
        Art.Circle(vg,x+s*.28,y+s*.3,1.2,{ 148, 152, 132, 200 })
        Art.Circle(vg,x+s*.74,y+s*.72,1.2,{ 148, 152, 132, 200 })
    else
        Art.Rect(vg,x,y,s,s,{ 178, 184, 164, 255 },2)
        Art.Rect(vg,x+1,y+1,s-2,s-2,{ 190, 196, 176, 255 },1)
        Art.Line(vg,x+s*.5,y+2,x+s*.5,y+s-2,{ 150, 176, 168, 130 },1)
        Art.Line(vg,x+2,y+s*.5,x+s-2,y+s*.5,{ 150, 176, 168, 130 },1)
        Art.Polygon(vg,{ x+s*.32,y+s*.32,x+s*.7,y+s*.5,x+s*.32,y+s*.68 },{ 232, 216, 148, 235 })
    end
end

function Art.Tree(vg, x, y, s)
    Art.Ellipse(vg, x, y+s*.12, s*.6, s*.22, { 31, 43, 33, 60 })
    Art.Rect(vg,x-s*.09,y-s*.15,s*.18,s*.4,{ 83, 79, 52, 255 })
    Art.Polygon(vg,{ x,y-s*1.1,x-s*.55,y-s*.05,x+s*.55,y-s*.05 },{ 47, 72, 52, 255 })
    Art.Polygon(vg,{ x,y-s*1.3,x-s*.43,y-s*.4,x+s*.43,y-s*.4 },{ 57, 87, 62, 255 })
    Art.Polygon(vg,{ x,y-s*1.3,x-s*.43,y-s*.4,x,y-s*.6 },{ 72, 101, 68, 255 })
end

function Art.Wall(vg, x, y, s)
    Art.Rect(vg,x+s*.17,y+s*.10,s*.72,s*.92,{ 37, 46, 39, 75 },2)
    Art.Rect(vg,x+s*.08,y,s*.68,s,{ 179, 175, 145, 255 })
    Art.Rect(vg,x+s*.58,y,s*.18,s,{ 142, 148, 123, 255 })
    Art.Rect(vg,x+s*.03,y+s*.07,s*.77,s*.14,{ 207, 199, 164, 255 })
    Art.Rect(vg,x+s*.03,y+s*.57,s*.77,s*.12,{ 193, 185, 155, 255 })
    Art.Line(vg,x+s*.34,y+s*.23,x+s*.34,y+s*.54,{ 144, 148, 122, 180 },1)
    Art.Line(vg,x+s*.48,y+s*.71,x+s*.48,y+s*.99,{ 144, 148, 122, 180 },1)
    Art.Rect(vg,x+s*.03,y,s*.16,s*.24,{ 211, 200, 166, 255 })
    Art.Rect(vg,x+s*.39,y,s*.16,s*.24,{ 211, 200, 166, 255 })
end

function Art.Flag(vg, x, y, s, color, time)
    Art.Line(vg,x,y,x,y-s,{ 218, 208, 162, 255 },1.5)
    local flutter = math.sin(time * 3) * s*.07
    Art.Polygon(vg,{ x,y-s,x+s*.55,y-s+flutter,x+s*.45,y-s*.58+flutter,x,y-s*.60 },color)
end

function Art.Building(vg, kind, x, y, s, stock, progress, time)
    local def = C.buildings[kind]
    local w,h = def.w*s,def.h*s
    Art.Ellipse(vg,x+w*.55,y+h*.80,w*.46,h*.15,{ 34, 42, 32, 85 })
    if kind == "block" then Art.Wall(vg,x,y,s); return end
    if kind == "tower" then
        Art.Rect(vg,x+s*.13,y+s*.03,s*.7,s*.84,{ 189, 181, 148, 255 },2)
        Art.Rect(vg,x+s*.17,y+s*.3,s*.6,s*.3,{ 121, 132, 116, 255 })
        Art.Polygon(vg,{ x-s*.04,y+s*.23,x+s*.47,y-s*.15,x+s*.96,y+s*.23 },{ 96, 116, 107, 255 })
        Art.Line(vg,x+s*.3,y+s*.53,x+s*.77,y+s*.53,{ 55, 67, 60, 255 },3)
        Art.Line(vg,x+s*.52,y+s*.34,x+s*.52,y+s*.70,{ 57, 70, 60, 255 },2)
        return
    end
    if kind == "barracks" then
        Art.Rect(vg,x+w*.15,y+h*.4,w*.70,h*.4,{ 167, 135, 91, 255 },2)
        Art.Polygon(vg,{ x+w*.04,y+h*.48,x+w*.45,y+h*.12,x+w*.94,y+h*.48 },{ 217, 184, 123, 255 })
        Art.Polygon(vg,{ x+w*.45,y+h*.12,x+w*.94,y+h*.48,x+w*.50,y+h*.48 },{ 173, 131, 82, 255 })
        Art.Polygon(vg,{ x+w*.15,y+h*.8,x+w*.48,y+h*.42,x+w*.76,y+h*.8 },{ 221, 195, 145, 255 })
        Art.Polygon(vg,{ x+w*.37,y+h*.8,x+w*.48,y+h*.48,x+w*.58,y+h*.8 },{ 58, 66, 47, 255 })
        Art.Flag(vg,x+w*.45,y+h*.13,s*.55,{ 208, 138, 93, 255 },time)
    elseif kind == "elephant" or kind == "stable" then
        Art.Rect(vg,x+w*.11,y+h*.28,w*.78,h*.47,{ 143, 115, 82, 255 },2)
        Art.Polygon(vg,{ x+w*.02,y+h*.31,x+w*.23,y+h*.12,x+w*.79,y+h*.12,x+w*.97,y+h*.31 },def.color)
        Art.Rect(vg,x+w*.21,y+h*.4,w*.27,h*.34,{ 64, 67, 47, 255 },2)
        Art.Rect(vg,x+w*.57,y+h*.4,w*.23,h*.34,{ 64, 67, 47, 255 },2)
        Art.Line(vg,x+w*.03,y+h*.82,x+w*.95,y+h*.82,{ 200, 169, 114, 255 },3)
        for i=1,4 do Art.Line(vg,x+w*(i*.2),y+h*.65,x+w*(i*.2),y+h*.92,{ 184, 154, 101, 255 },2) end
    else
        Art.Rect(vg,x+w*.14,y+h*.29,w*.72,h*.47,{ 176, 161, 113, 255 },2)
        Art.Rect(vg,x+w*.2,y+h*.49,w*.6,h*.18,{ 74, 85, 58, 255 },2)
        Art.Polygon(vg,{ x+w*.03,y+h*.31,x+w*.22,y+h*.17,x+w*.76,y+h*.17,x+w*.97,y+h*.31 },def.color)
        if kind == "shield" then
            Art.Polygon(vg,{ x+w*.35,y+h*.42,x+w*.69,y+h*.42,x+w*.69,y+h*.56,x+w*.52,y+h*.64,x+w*.35,y+h*.56 },{ 158, 195, 191, 255 })
        else
            nvgBeginPath(vg)
            nvgMoveTo(vg,x+w*.4,y+h*.39)
            nvgBezierTo(vg,x+w*.84,y+h*.43,x+w*.84,y+h*.59,x+w*.4,y+h*.65)
            nvgStrokeColor(vg,nvgRGBA(213,200,141,255)); nvgStrokeWidth(vg,2); nvgStroke(vg)
            Art.Line(vg,x+w*.4,y+h*.39,x+w*.4,y+h*.65,{ 224, 207, 150, 255 },1)
        end
    end
    Art.Rect(vg,x+w*.15,y+h*.92,w*.7,3,{ 45, 56, 39, 220 },1)
    Art.Rect(vg,x+w*.15,y+h*.92,w*.7*progress,3,def.color,1)
    if stock and stock > 0 then
        for i=1,stock do Art.Circle(vg,x+w*.17+(i-1)*5,y+h*.86,1.7,{ 237, 205, 132, 255 }) end
    end
end

function Art.Unit(vg, u, x, y, s, time)
    local t = C.units[u.kind]
    local color = u.flash > 0 and { 255, 243, 211, 255 } or t.color
    local z = s * (u.size == 2 and 0.7 or 0.32)
    Art.Ellipse(vg,x,y+z*.58,z*.9,z*.35,{ 26, 38, 28, 90 })
    nvgSave(vg)
    nvgTranslate(vg,x,y)
    local bob = u.moving and math.sin(time*12+u.id)*z*.09 or 0
    nvgTranslate(vg,0,bob)
    if u.size == 2 then
        Art.Ellipse(vg,0,-z*.1,z*.78,z*.50,color)
        Art.Ellipse(vg,z*.59*u.facing,-z*.1,z*.45,z*.47,color)
        Art.Ellipse(vg,z*.36*u.facing,-z*.16,z*.33,z*.41,{ 137, 131, 139, 255 })
        Art.Rect(vg,-z*.56,z*.2,z*.20,z*.43,color,2)
        Art.Rect(vg,z*.24,z*.2,z*.22,z*.43,color,2)
        Art.Line(vg,z*.91*u.facing,-z*.03,z*1.03*u.facing,z*.58,color,z*.19)
        Art.Line(vg,z*.79*u.facing,z*.14,z*1.08*u.facing,z*.01,{ 229, 217, 182, 255 },z*.10)
        Art.Rect(vg,-z*.32,-z*.58,z*.6,z*.3,{ 105, 81, 78, 255 },2)
        if u.kind == "boss" then
            Art.Polygon(vg,{ -z*.5,-z*.47,-z*.38,-z*.95,-z*.23,-z*.54 },{ 213, 172, 137, 255 })
            Art.Polygon(vg,{ z*.1,-z*.47,z*.28,-z*.93,z*.36,-z*.46 },{ 213, 172, 137, 255 })
        end
    elseif u.kind == "cavalry" then
        Art.Ellipse(vg,0,z*.18,z,z*.43,{ 144, 115, 80, 255 })
        Art.Line(vg,-z*.5,z*.3,-z*.65,z*.86,{ 127, 103, 72, 255 },z*.24)
        Art.Line(vg,z*.55,z*.3,z*.66,z*.83,{ 127, 103, 72, 255 },z*.24)
        Art.Circle(vg,z*.86*u.facing,-z*.02,z*.34,{ 164, 129, 86, 255 })
        Art.Rect(vg,-z*.29,-z*.56,z*.57,z*.56,color,2)
        Art.Circle(vg,0,-z*.73,z*.28,{ 226, 202, 159, 255 })
    else
        Art.Line(vg,-z*.22,z*.26,-z*.38,z*.69,{ 63, 74, 54, 255 },z*.23)
        Art.Line(vg,z*.17,z*.26,z*.31,z*.69,{ 63, 74, 54, 255 },z*.23)
        Art.Rect(vg,-z*.48,-z*.42,z*.92,z*.80,color,z*.18)
        Art.Circle(vg,0,-z*.61,z*.39,{ 226, 203, 159, 255 })
        Art.Ellipse(vg,-z*.02,-z*.77,z*.44,z*.25,color)
        if u.kind == "heavy" or u.kind == "brute" then
            Art.Rect(vg,z*.1*u.facing,-z*.1,z*.63,z*.7,color,2)
            Art.Line(vg,z*.47*u.facing,-z*.06,z*.47*u.facing,z*.48,{ 208, 225, 204, 255 },1)
        elseif t.ranged then
            Art.Line(vg,z*.65*u.facing,-z*.49,z*.65*u.facing,z*.52,{ 208, 193, 126, 255 },1.5)
            Art.Line(vg,z*.4*u.facing,-z*.17,z*1.1*u.facing,-z*.17,{ 226, 214, 158, 255 },1)
        else
            Art.Line(vg,z*.5*u.facing,z*.26,z*1.04*u.facing,-z*.52,{ 214, 220, 188, 255 },2)
        end
    end
    nvgRestore(vg)
    if u.hp < u.maxHp then
        Art.Rect(vg,x-z,y-z*1.15,z*2,2,{ 40, 47, 35, 230 },1)
        Art.Rect(vg,x-z,y-z*1.15,z*2*math.max(0,u.hp/u.maxHp),2,color,1)
    end
    if u.blocked > 1 then
        Art.Circle(vg,x+z*.6,y-z*1.2,2,{ 238, 178, 86, 255 })
    end
end

function Art.Resource(vg,r,x,y,s,time)
    if r.remaining <= 0 then return end
    Art.Ellipse(vg,x,y+s*.19,s*.45,s*.18,{ 34, 45, 31, 70 })
    Art.Rect(vg,x-s*.32,y-s*.20,s*.64,s*.40,{ 148, 115, 67, 255 },3)
    Art.Rect(vg,x-s*.36,y-s*.25,s*.72,s*.15,{ 205, 169, 99, 255 },2)
    Art.Line(vg,x-s*.17,y-s*.22,x-s*.17,y+s*.20,{ 230, 203, 139, 255 },2)
    Art.Line(vg,x+s*.17,y-s*.22,x+s*.17,y+s*.20,{ 230, 203, 139, 255 },2)
    Art.Circle(vg,x,y-s*.37,2+math.sin(time*2+r.id)*.5,{ 243, 211, 138, 240 })
    if r.tech > 0 then Art.Circle(vg,x+s*.25,y-s*.38,2,{ 155, 196, 205, 255 }) end
    for i=1,r.remaining do Art.Circle(vg,x-s*.20+(i-1)*5,y+s*.31,1.5,{ 224, 202, 147, 255 }) end
end
return Art
