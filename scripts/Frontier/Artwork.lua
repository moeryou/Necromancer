-- 战场卡通美术：厚轮廓 + 暖色高饱和 + Q版造型，全部由 NanoVG 矢量绘制。
-- 本模块只画地图与实体；文字、按钮和 HUD 由 UI 组件负责。
local C = require "Frontier.Config"
local Art = {}

-- 统一调色板。参考图是暖色卡通，轮廓用深棕而非纯黑，避免生硬。
Art.palette = {
    outline   = { 58, 44, 36, 255 },
    shadow    = { 40, 52, 36, 90 },
    -- 草地：内侧营地更亮，外侧荒野偏深；棋盘格对比压得很低，避免"方格布"感
    grassIn   = { 128, 180, 86, 255 },
    grassIn2  = { 125, 176, 83, 255 },
    grassOut  = { 112, 163, 76, 255 },
    grassOut2 = { 108, 158, 72, 255 },
    -- 土路
    road      = { 204, 174, 120, 255 },
    roadDark  = { 176, 146, 96, 255 },
    roadLight = { 222, 196, 148, 255 },
    -- 石材
    stone     = { 178, 184, 194, 255 },
    stoneDark = { 140, 148, 162, 255 },
    stoneLite = { 216, 222, 230, 255 },
    -- 木料
    wood      = { 178, 134, 86, 255 },
    woodDark  = { 138, 100, 62, 255 },
    woodLite  = { 208, 168, 116, 255 },
    -- 屋顶
    roofRed    = { 198, 76, 60, 255 },
    roofRedD   = { 158, 56, 46, 255 },
    roofBlue   = { 76, 126, 180, 255 },
    roofBlueD  = { 56, 98, 148, 255 },
    roofGreen  = { 108, 156, 88, 255 },
    roofGreenD = { 82, 126, 68, 255 },
    roofOrange = { 218, 134, 70, 255 },
    roofOrangeD= { 178, 102, 52, 255 },
    roofPurple = { 150, 128, 190, 255 },
    roofPurpleD= { 116, 96, 156, 255 },
    -- 其他
    gold      = { 238, 194, 100, 255 },
    skin      = { 238, 206, 162, 255 },
    metal     = { 176, 184, 196, 255 },
    metalDark = { 138, 148, 162, 255 },
    boot      = { 74, 84, 62, 255 },
}

function Art.Color(c, alpha)
    return nvgRGBA(c[1], c[2], c[3], alpha or c[4] or 255)
end

-- 卡通轮廓统一出口：圆角连接 + 圆头线帽。
local function stroke(vg, color, width)
    nvgStrokeColor(vg, Art.Color(color))
    nvgStrokeWidth(vg, width or 1.5)
    nvgLineJoin(vg, NVG_ROUND)
    nvgLineCap(vg, NVG_ROUND)
    nvgStroke(vg)
end

-- 对调用方已构建好的路径描边（保持统一的圆角连接与线帽）。
function Art.Stroke(vg, color, width)
    stroke(vg, color, width)
end

local function fillStroke(vg, fill, outline, width)
    nvgFillColor(vg, Art.Color(fill))
    nvgFill(vg)
    if outline then stroke(vg, outline, width) end
end

-- 有机斑块路径：卡通树冠/土路都靠它避免死板的正圆。
local function blobPath(vg, x, y, r, seed, wobble)
    local n = 12
    for i = 0, n - 1 do
        local a = i / n * math.pi * 2
        local rr = r * (1 + math.sin(a * 3 + seed) * wobble + math.cos(a * 5 + seed) * wobble * .6)
        local px, py = x + math.cos(a) * rr, y + math.sin(a) * rr
        if i == 0 then nvgMoveTo(vg, px, py) else nvgLineTo(vg, px, py) end
    end
    nvgClosePath(vg)
end

function Art.Rect(vg, x, y, w, h, color, radius, outline, ow)
    if w <= 0 or h <= 0 then return end
    nvgBeginPath(vg)
    if radius and radius > 0 then nvgRoundedRect(vg, x, y, w, h, radius)
    else nvgRect(vg, x, y, w, h) end
    fillStroke(vg, color, outline, ow or 1.2)
end

function Art.Line(vg, x1, y1, x2, y2, color, width)
    nvgBeginPath(vg)
    nvgMoveTo(vg, x1, y1)
    nvgLineTo(vg, x2, y2)
    stroke(vg, color, width or 1)
end

function Art.Circle(vg, x, y, r, color, outline, ow)
    nvgBeginPath(vg)
    nvgCircle(vg, x, y, r)
    fillStroke(vg, color, outline, ow or 1.2)
end

function Art.Ellipse(vg, x, y, rx, ry, color, outline, ow)
    nvgBeginPath(vg)
    nvgEllipse(vg, x, y, rx, ry)
    fillStroke(vg, color, outline, ow or 1.2)
end

function Art.Polygon(vg, points, color, outline, ow)
    nvgBeginPath(vg)
    nvgMoveTo(vg, points[1], points[2])
    for i = 3, #points, 2 do nvgLineTo(vg, points[i], points[i + 1]) end
    nvgClosePath(vg)
    fillStroke(vg, color, outline, ow or 1.2)
end

-- 草丛与小花：地图上的低成本点缀，让草地不那么平。
function Art.GrassTuft(vg, x, y, s)
    local g = { 96, 148, 66, 220 }
    Art.Line(vg, x, y, x - s * .30, y - s * .62, g, s * .16)
    Art.Line(vg, x, y, x + s * .06, y - s * .80, g, s * .16)
    Art.Line(vg, x, y, x + s * .38, y - s * .58, g, s * .16)
end

function Art.Flower(vg, x, y, s, color)
    Art.Circle(vg, x - s * .22, y, s * .20, color)
    Art.Circle(vg, x + s * .22, y, s * .20, color)
    Art.Circle(vg, x, y - s * .24, s * .20, color)
    Art.Circle(vg, x, y + s * .20, s * .20, color)
    Art.Circle(vg, x, y, s * .16, { 246, 214, 120, 255 })
end

-- 踩踏痕迹：等级越高，土色越实、车辙越深。
-- 2 级以上刻意不描边、不留圆角，让相邻格自然连成一条连续道路。
function Art.Trail(vg, x, y, s, level, seed)
    local p = Art.palette
    local k = ((seed * 37) % 17) / 17
    if level == 1 then
        nvgBeginPath(vg)
        blobPath(vg, x + s * .5, y + s * .5, s * .44, seed, .16)
        nvgFillColor(vg, Art.Color({ 178, 160, 110, 170 })); nvgFill(vg)
        Art.Circle(vg, x + s * .33, y + s * .40, s * .07, { 150, 132, 88, 170 })
        Art.Circle(vg, x + s * .70, y + s * .66, s * .07, { 150, 132, 88, 170 })
    elseif level == 2 then
        Art.Rect(vg, x, y, s, s, p.road)
        Art.Line(vg, x + s * .12, y + s * (.34 + k * .10), x + s * .88, y + s * (.34 + k * .10), p.roadDark, s * .06)
        Art.Line(vg, x + s * .12, y + s * (.68 - k * .10), x + s * .88, y + s * (.68 - k * .10), p.roadDark, s * .06)
    elseif level == 3 then
        Art.Rect(vg, x, y, s, s, p.road)
        Art.Rect(vg, x + s * .12, y + s * .12, s * .76, s * .76, p.roadLight)
        Art.Circle(vg, x + s * .28, y + s * .30, s * .07, { 150, 132, 88, 140 })
        Art.Circle(vg, x + s * .74, y + s * .72, s * .07, { 150, 132, 88, 140 })
    else
        -- 硬化路面：石砖铺装 + 中央金色加速箭头
        Art.Rect(vg, x, y, s, s, { 190, 196, 204, 255 })
        Art.Rect(vg, x + s * .09, y + s * .09, s * .82, s * .82, { 208, 214, 222, 255 })
        nvgBeginPath(vg)
        nvgMoveTo(vg, x + s * .5, y + s * .09); nvgLineTo(vg, x + s * .5, y + s * .91)
        nvgMoveTo(vg, x + s * .09, y + s * .5); nvgLineTo(vg, x + s * .91, y + s * .5)
        stroke(vg, { 168, 190, 198, 150 }, s * .05)
        Art.Polygon(vg, { x + s * .28, y + s * .30, x + s * .70, y + s * .50, x + s * .28, y + s * .70 },
            { 242, 210, 124, 245 }, p.outline, s * .05)
    end
end

-- 卡通圆冠树：木干 + 有机树冠 + 高光。
function Art.Tree(vg, x, y, s)
    local p = Art.palette
    Art.Ellipse(vg, x, y + s * .18, s * .58, s * .20, p.shadow)
    Art.Rect(vg, x - s * .09, y - s * .26, s * .18, s * .46, p.wood, s * .05, p.outline, s * .07)
    nvgBeginPath(vg)
    blobPath(vg, x, y - s * .70, s * .62, x * .03 + y * .07, .10)
    fillStroke(vg, { 70, 128, 72, 255 }, p.outline, s * .07)
    nvgBeginPath(vg)
    blobPath(vg, x - s * .05, y - s * .80, s * .44, x * .05 + y * .03, .13)
    nvgFillColor(vg, Art.Color({ 106, 174, 94, 255 })); nvgFill(vg)
    nvgBeginPath(vg)
    blobPath(vg, x - s * .16, y - s * .92, s * .19, 1.7, .18)
    nvgFillColor(vg, Art.Color({ 142, 204, 114, 210 })); nvgFill(vg)
end

-- 石墙：圆角石块 + 砖缝 + 顶面高光。
function Art.Wall(vg, x, y, s)
    local p = Art.palette
    Art.Rect(vg, x + s * .06, y + s * .10, s * .94, s * .90, { 30, 40, 30, 70 }, s * .12)
    nvgBeginPath(vg)
    nvgRoundedRect(vg, x + s * .03, y + s * .03, s * .94, s * .94, s * .12)
    fillStroke(vg, p.stone, p.outline, s * .07)
    nvgBeginPath(vg)
    nvgMoveTo(vg, x + s * .03, y + s * .38); nvgLineTo(vg, x + s * .97, y + s * .38)
    nvgMoveTo(vg, x + s * .03, y + s * .70); nvgLineTo(vg, x + s * .97, y + s * .70)
    nvgMoveTo(vg, x + s * .36, y + s * .03); nvgLineTo(vg, x + s * .36, y + s * .38)
    nvgMoveTo(vg, x + s * .68, y + s * .38); nvgLineTo(vg, x + s * .68, y + s * .70)
    nvgMoveTo(vg, x + s * .36, y + s * .70); nvgLineTo(vg, x + s * .36, y + s * .97)
    stroke(vg, p.stoneDark, s * .05)
    Art.Rect(vg, x + s * .12, y + s * .07, s * .76, s * .11, p.stoneLite, s * .05)
end

-- 旗帜：木杆 + 飘动三角旗。
function Art.Flag(vg, x, y, s, color, time)
    local p = Art.palette
    Art.Rect(vg, x - s * .05, y - s, s * .10, s, p.wood, s * .04, p.outline, s * .05)
    local flutter = math.sin(time * 3) * s * .08
    Art.Polygon(vg, {
        x + s * .05, y - s,
        x + s * .70, y - s + flutter,
        x + s * .58, y - s * .60 + flutter,
        x + s * .05, y - s * .58,
    }, color, p.outline, s * .05)
end

-- 木屋通用件：墙体 + 梯形屋顶 + 门窗。
local function house(vg, x, y, w, h, roof, roofDark, opts)
    local p = Art.palette
    opts = opts or {}
    Art.Ellipse(vg, x + w * .52, y + h * .88, w * .48, h * .14, p.shadow)
    -- 墙体
    nvgBeginPath(vg)
    nvgRoundedRect(vg, x + w * .13, y + h * .42, w * .74, h * .48, w * .05)
    fillStroke(vg, p.wood, p.outline, w * .035)
    -- 墙板竖纹
    nvgBeginPath(vg)
    for i = 1, 3 do
        local xx = x + w * (.13 + i * .185)
        nvgMoveTo(vg, xx, y + h * .46); nvgLineTo(vg, xx, y + h * .86)
    end
    stroke(vg, p.woodDark, w * .022)
    -- 屋顶梯形（带出檐）
    nvgBeginPath(vg)
    nvgMoveTo(vg, x + w * .00, y + h * .50)
    nvgLineTo(vg, x + w * .28, y + h * .07)
    nvgLineTo(vg, x + w * .72, y + h * .07)
    nvgLineTo(vg, x + w * 1.00, y + h * .50)
    nvgClosePath(vg)
    fillStroke(vg, roof, p.outline, w * .04)
    -- 屋顶右半阴影
    nvgBeginPath(vg)
    nvgMoveTo(vg, x + w * .50, y + h * .07)
    nvgLineTo(vg, x + w * .72, y + h * .07)
    nvgLineTo(vg, x + w * 1.00, y + h * .50)
    nvgLineTo(vg, x + w * .50, y + h * .50)
    nvgClosePath(vg)
    nvgFillColor(vg, Art.Color(roofDark)); nvgFill(vg)
    -- 屋脊高光
    Art.Rect(vg, x + w * .28, y + h * .07, w * .44, h * .05, { 255, 255, 255, 70 }, h * .02)
    -- 门
    local doorW, doorH = w * .20, h * .30
    Art.Rect(vg, x + w * .40, y + h * .60, doorW, doorH, p.woodDark, doorW * .28, p.outline, w * .028)
    -- 窗
    Art.Rect(vg, x + w * .20, y + h * .56, w * .13, h * .13, { 250, 214, 132, 255 }, w * .02, p.outline, w * .026)
    Art.Rect(vg, x + w * .67, y + h * .56, w * .13, h * .13, { 250, 214, 132, 255 }, w * .02, p.outline, w * .026)
    if opts.emblem then opts.emblem(vg, x + w * .5, y + h * .30, w * .17) end
end

-- 圆形盾徽，工坊类建筑共用。
local function shieldEmblem(vg, cx, cy, r, fill)
    local p = Art.palette
    Art.Polygon(vg, {
        cx - r, cy - r * .95, cx + r, cy - r * .95,
        cx + r, cy + r * .25, cx, cy + r * 1.05, cx - r, cy + r * .25,
    }, fill, p.outline, r * .16)
    Art.Line(vg, cx, cy - r * .7, cx, cy + r * .7, { 255, 255, 255, 120 }, r * .14)
end

function Art.Building(vg, kind, x, y, s, stock, progress, time)
    local p = Art.palette
    local def = C.buildings[kind]
    local w, h = def.w * s, def.h * s
    if kind == "block" then Art.Wall(vg, x, y, s); return end

    if kind == "tower" then
        Art.Ellipse(vg, x + s * .55, y + s * .92, s * .40, s * .12, p.shadow)
        nvgBeginPath(vg)
        nvgRoundedRect(vg, x + s * .18, y + s * .24, s * .64, s * .72, s * .05)
        fillStroke(vg, p.stone, p.outline, s * .07)
        nvgBeginPath(vg)
        for i = 1, 2 do
            local yy = y + s * (.24 + i * .24)
            nvgMoveTo(vg, x + s * .18, yy); nvgLineTo(vg, x + s * .82, yy)
        end
        stroke(vg, p.stoneDark, s * .05)
        -- 顶部垛口
        nvgBeginPath(vg)
        nvgRoundedRect(vg, x + s * .10, y + s * .10, s * .80, s * .20, s * .04)
        fillStroke(vg, p.stoneLite, p.outline, s * .06)
        for i = 0, 3 do
            Art.Rect(vg, x + s * (.11 + i * .205), y + s * .01, s * .13, s * .15, p.stoneLite, s * .03, p.outline, s * .05)
        end
        -- 箭孔
        Art.Rect(vg, x + s * .44, y + s * .46, s * .12, s * .28, { 62, 52, 44, 255 }, s * .05, p.outline, s * .045)
        return
    end

    local roof, roofDark = p.roofRed, p.roofRedD
    local emblem
    if kind == "barracks" then
        roof, roofDark = p.roofRed, p.roofRedD
        emblem = function(g, cx, cy, r)
            -- 交叉双剑
            Art.Line(g, cx - r, cy + r, cx + r, cy - r, p.metalLite or p.stoneLite, r * .22)
            Art.Line(g, cx + r, cy + r, cx - r, cy - r, p.metalLite or p.stoneLite, r * .22)
        end
    elseif kind == "shield" then
        roof, roofDark = p.roofBlue, p.roofBlueD
        emblem = function(g, cx, cy, r) shieldEmblem(g, cx, cy, r, { 150, 198, 206, 255 }) end
    elseif kind == "bow" then
        roof, roofDark = p.roofGreen, p.roofGreenD
        emblem = function(g, cx, cy, r)
            nvgBeginPath(g)
            nvgMoveTo(g, cx - r * .6, cy - r)
            nvgQuadTo(g, cx + r * 1.5, cy, cx - r * .6, cy + r)
            stroke(g, { 226, 214, 158, 255 }, r * .26)
            Art.Line(g, cx - r * .6, cy - r, cx - r * .6, cy + r, { 240, 232, 190, 200 }, r * .16)
        end
    elseif kind == "stable" then
        roof, roofDark = p.roofOrange, p.roofOrangeD
        emblem = function(g, cx, cy, r)
            -- 马蹄铁
            nvgBeginPath(g)
            nvgMoveTo(g, cx - r, cy + r * .6)
            nvgLineTo(g, cx - r, cy)
            nvgLineTo(g, cx + r, cy)
            nvgLineTo(g, cx + r, cy + r * .6)
            stroke(g, { 246, 226, 170, 255 }, r * .34)
        end
    elseif kind == "elephant" then
        roof, roofDark = p.roofPurple, p.roofPurpleD
        emblem = function(g, cx, cy, r)
            Art.Circle(g, cx, cy, r * .8, { 224, 208, 244, 255 }, p.outline, r * .18)
        end
    elseif kind == "forge" then
        roof, roofDark = p.roofRed, p.roofRedD
        -- 铁砧 + 炉火
        emblem = function(g, cx, cy, r)
            Art.Polygon(g, { cx - r * .9, cy + r * .5, cx + r * .9, cy + r * .5,
                cx + r * .55, cy - r * .1, cx - r * .55, cy - r * .1 }, { 96, 104, 116, 255 }, p.outline, r * .16)
            Art.Polygon(g, { cx - r * .18, cy - r * .35, cx + r * .18, cy - r * .35, cx, cy - r * .95 },
                { 246, 196, 96, 255 }, p.outline, r * .14)
        end
    elseif kind == "aim" then
        roof, roofDark = p.roofGreen, p.roofGreenD
        -- 准星
        emblem = function(g, cx, cy, r)
            nvgBeginPath(g); nvgCircle(g, cx, cy, r * .7)
            stroke(g, { 240, 236, 200, 255 }, r * .16)
            Art.Line(g, cx - r, cy, cx - r * .35, cy, { 240, 236, 200, 255 }, r * .16)
            Art.Line(g, cx + r * .35, cy, cx + r, cy, { 240, 236, 200, 255 }, r * .16)
            Art.Line(g, cx, cy - r, cx, cy - r * .35, { 240, 236, 200, 255 }, r * .16)
            Art.Line(g, cx, cy + r * .35, cx, cy + r, { 240, 236, 200, 255 }, r * .16)
        end
    elseif kind == "horn" then
        roof, roofDark = p.roofOrange, p.roofOrangeD
        -- 号角
        emblem = function(g, cx, cy, r)
            nvgBeginPath(g)
            nvgMoveTo(g, cx - r * .8, cy + r * .5)
            nvgQuadTo(g, cx + r * .3, cy + r * .5, cx + r * .8, cy - r * .7)
            stroke(g, { 248, 226, 156, 255 }, r * .34)
            Art.Circle(g, cx - r * .8, cy + r * .5, r * .3, { 248, 226, 156, 255 }, p.outline, r * .14)
        end
    elseif kind == "farmerBarracks" then
        roof, roofDark = p.roofGreen, p.roofGreenD
        -- 麦穗
        emblem = function(g, cx, cy, r)
            Art.Line(g, cx, cy + r * .9, cx, cy - r * .8, { 232, 206, 120, 255 }, r * .16)
            for i = 0, 2 do
                local yy = cy - r * (.5 - i * .55)
                Art.Line(g, cx, yy, cx - r * .5, yy - r * .35, { 244, 224, 150, 255 }, r * .14)
                Art.Line(g, cx, yy, cx + r * .5, yy - r * .35, { 244, 224, 150, 255 }, r * .14)
            end
        end
    elseif kind == "warehouse" then
        -- 仓库是 1×1 非阻挡建筑：木箱 + 顶棚，不能画成普通房屋。
        Art.Ellipse(vg, x + s * .55, y + s * .92, s * .40, s * .12, p.shadow)
        Art.Rect(vg, x + s * .14, y + s * .34, s * .72, s * .54, p.wood, s * .06, p.outline, s * .06)
        Art.Rect(vg, x + s * .10, y + s * .22, s * .80, s * .18, p.roofOrange, s * .05, p.outline, s * .05)
        Art.Line(vg, x + s * .14, y + s * .61, x + s * .86, y + s * .61, p.woodDark, s * .05)
        Art.Circle(vg, x + s * .5, y + s * .48, s * .10, { 240, 210, 138, 255 }, p.outline, s * .04)
        return
    end

    house(vg, x, y, w, h, roof, roofDark, { emblem = emblem })
    -- 库存进度条
    local bx, by, bw = x + w * .15, y + h * .93, w * .70
    Art.Rect(vg, bx, by, bw, 3, { 45, 56, 39, 220 }, 1.5)
    Art.Rect(vg, bx, by, bw * progress, 3, def.color, 1.5)
    if stock and stock > 0 then
        for i = 1, stock do
            Art.Circle(vg, x + w * .18 + (i - 1) * 5, y + h * .86, 1.8, { 240, 210, 138, 255 }, p.outline, .8)
        end
    end
end

-- 圆头盔：只盖头顶的穹顶 + 帽檐，脸部必须露出来，否则会糊成一团。
local function helm(vg, z, yTop, color, dark)
    Art.Ellipse(vg, 0, yTop - z * .13, z * .29, z * .20, color, Art.palette.outline, z * .08)
    Art.Rect(vg, -z * .33, yTop + z * .01, z * .66, z * .10, dark, z * .05, Art.palette.outline, z * .065)
end

-- Q版士兵：圆头盔 + 厚轮廓 + 武器。facing 决定朝向（-1 左 / 1 右）。
-- 外观直接由 u.gear 驱动：盾牌、重甲、弓箭、瞄准配件、号角都能一眼认出。
local function soldier(vg, u, z, t, p)
    local color = u.flash > 0 and { 255, 246, 224, 255 } or C.units[u.kind].color
    -- 重甲：身体颜色加深，体型略微放大。
    if u.gear.forge then
        color = u.flash > 0 and color or { math.floor(color[1] * .68), math.floor(color[2] * .70), math.floor(color[3] * .74) }
        z = z * 1.06
    end
    local f = u.facing
    -- 腿
    Art.Rect(vg, -z * .28, z * .18, z * .21, z * .40, p.boot, z * .08, p.outline, z * .07)
    Art.Rect(vg, z * .07, z * .18, z * .21, z * .40, p.boot, z * .08, p.outline, z * .07)
    -- 躯干 + 腰带（腰带把上衣和裤子色块切开，避免整体糊成一块）
    nvgBeginPath(vg)
    nvgRoundedRect(vg, -z * .40, -z * .30, z * .80, z * .60, z * .22)
    fillStroke(vg, color, p.outline, z * .11)
    Art.Rect(vg, -z * .41, z * .04, z * .82, z * .13, p.woodDark, z * .03, p.outline, z * .06)
    -- 武器
    if t.ranged then
        nvgBeginPath(vg)
        nvgMoveTo(vg, z * .50 * f, -z * .40)
        nvgQuadTo(vg, z * 1.08 * f, -z * .02, z * .50 * f, z * .40)
        stroke(vg, { 214, 176, 108, 255 }, z * .11)
        Art.Line(vg, z * .50 * f, -z * .40, z * .50 * f, z * .40, { 240, 232, 190, 220 }, z * .06)
        -- 瞄准配件：弓身加装金色瞄具
        if u.gear.aim then Art.Circle(vg, z * .78 * f, 0, z * .07, { 246, 214, 120, 255 }, p.outline, z * .03) end
    else
        Art.Line(vg, z * .46 * f, z * .32, z * 1.02 * f, -z * .54, { 226, 232, 240, 255 }, z * .15)
        Art.Line(vg, z * .38 * f, z * .12, z * .70 * f, z * .28, { 240, 214, 130, 255 }, z * .13)
    end
    -- 头（含眼睛），头盔只扣在头顶
    Art.Circle(vg, 0, -z * .48, z * .30, p.skin, p.outline, z * .085)
    Art.Circle(vg, -z * .12, -z * .30, z * .05, { 62, 48, 42, 255 })
    Art.Circle(vg, z * .12, -z * .30, z * .05, { 62, 48, 42, 255 })
    helm(vg, z, -z * .62, u.gear.forge and { 132, 138, 150, 255 } or p.metal, p.metalDark)
    -- 盾牌：单手举盾
    if u.gear.shield then
        Art.Polygon(vg, {
            z * .28 * f, -z * .30, z * .88 * f, -z * .30,
            z * .88 * f, z * .26, z * .58 * f, z * .50, z * .28 * f, z * .26,
        }, { 196, 212, 220, 255 }, p.outline, z * .08)
    end
    -- 号角：背部小型黄色标识
    if u.gear.horn then
        Art.Circle(vg, -z * .34 * f, -z * .16, z * .10, { 246, 208, 96, 255 }, p.outline, z * .035)
    end
end

-- 骑兵：马 + 骑手。任何装备了坐骑（马厩加工）的单位都切换到该姿态。
local function cavalry(vg, u, z, t, p)
    local color = u.flash > 0 and { 255, 246, 224, 255 } or C.units[u.kind].color
    if u.gear.forge then
        color = u.flash > 0 and color or { math.floor(color[1] * .68), math.floor(color[2] * .70), math.floor(color[3] * .74) }
    end
    local f = u.facing
    -- 马身
    Art.Ellipse(vg, 0, z * .18, z * .92, z * .44, { 150, 118, 80, 255 }, p.outline, z * .10)
    -- 马腿
    Art.Line(vg, -z * .52, z * .30, -z * .66, z * .86, { 132, 104, 70, 255 }, z * .24)
    Art.Line(vg, z * .56, z * .30, z * .68, z * .84, { 132, 104, 70, 255 }, z * .24)
    -- 马头
    Art.Circle(vg, z * .88 * f, -z * .06, z * .34, { 168, 132, 90, 255 }, p.outline, z * .09)
    -- 骑手躯干
    Art.Rect(vg, -z * .30, -z * .58, z * .58, z * .58, color, z * .16, p.outline, z * .10)
    -- 骑手头 + 头盔
    Art.Circle(vg, 0, -z * .72, z * .26, p.skin, p.outline, z * .08)
    Art.Circle(vg, -z * .10, -z * .58, z * .045, { 62, 48, 42, 255 })
    Art.Circle(vg, z * .10, -z * .58, z * .045, { 62, 48, 42, 255 })
    helm(vg, z * .92, -z * .86, p.metal, p.metalDark)
end

-- 大型单位（大象 / 破城巨兽）。
local function beast(vg, u, z, t, p)
    local color = u.flash > 0 and { 255, 246, 224, 255 } or t.color
    local f = u.facing
    -- 躯干
    Art.Ellipse(vg, 0, -z * .08, z * .82, z * .54, color, p.outline, z * .10)
    -- 头
    Art.Circle(vg, z * .62 * f, -z * .16, z * .46, color, p.outline, z * .10)
    -- 长鼻 / 犄角
    if u.kind == "elephant" then
        nvgBeginPath(vg)
        nvgMoveTo(vg, z * 1.0 * f, -z * .04)
        nvgQuadTo(vg, z * 1.26 * f, z * .34, z * .96 * f, z * .60)
        stroke(vg, color, z * .22)
        Art.Ellipse(vg, z * .74 * f, -z * .30, z * .16, z * .20, color, p.outline, z * .07)
    else
        Art.Polygon(vg, { z * .50 * f, -z * .40, z * .92 * f, -z * .92, z * 1.06 * f, -z * .34 },
            { 240, 224, 190, 255 }, p.outline, z * .08)
        Art.Polygon(vg, { z * .30 * f, -z * .44, z * .52 * f, -z * .98, z * .70 * f, -z * .40 },
            { 240, 224, 190, 255 }, p.outline, z * .08)
    end
    -- 四条腿
    Art.Line(vg, -z * .50, z * .32, -z * .58, z * .86, color, z * .24)
    Art.Line(vg, z * .18, z * .32, z * .14, z * .86, color, z * .24)
end

-- 农民：草帽 + 布衣，背负资源时显示袋子。
local function farmer(vg, u, z, t, p)
    local color = u.flash > 0 and { 255, 246, 224, 255 } or C.units[u.kind].color
    local f = u.facing
    Art.Rect(vg, -z * .26, z * .18, z * .20, z * .40, p.boot, z * .08, p.outline, z * .07)
    Art.Rect(vg, z * .06, z * .18, z * .20, z * .40, p.boot, z * .08, p.outline, z * .07)
    nvgBeginPath(vg)
    nvgRoundedRect(vg, -z * .38, -z * .30, z * .76, z * .60, z * .22)
    fillStroke(vg, color, p.outline, z * .11)
    Art.Rect(vg, -z * .39, z * .04, z * .78, z * .12, { 168, 128, 84, 255 }, z * .03, p.outline, z * .05)
    -- 背负资源袋：采集完成、运送途中才显示。
    if u.carry > 0 then
        Art.Circle(vg, -z * .40 * f, -z * .16, z * .20,
            u.carryKind == "mineral" and { 176, 184, 198, 255 } or { 150, 190, 110, 255 },
            p.outline, z * .05)
    end
    Art.Circle(vg, 0, -z * .48, z * .29, p.skin, p.outline, z * .085)
    Art.Circle(vg, -z * .11, -z * .30, z * .05, { 62, 48, 42, 255 })
    Art.Circle(vg, z * .11, -z * .30, z * .05, { 62, 48, 42, 255 })
    -- 草帽：宽檐 + 尖顶
    Art.Ellipse(vg, 0, -z * .66, z * .46, z * .14, { 226, 196, 118, 255 }, p.outline, z * .06)
    Art.Ellipse(vg, 0, -z * .76, z * .26, z * .18, { 240, 214, 140, 255 }, p.outline, z * .06)
end

-- 资源点：森林（圆冠树丛）与矿物（晶体块），逐格绘制。
function Art.Resource(vg, res, ox, oy, s)
    local def = C.resources[res.kind]
    for _, c in ipairs(res.cells) do
        local x, y = ox + (c.x - 1) * s, oy + (c.y - 1) * s
        if res.kind == "forest" then
            Art.Ellipse(vg, x + s * .5, y + s * .9, s * .42, s * .12, Art.palette.shadow)
            Art.Rect(vg, x + s * .42, y + s * .55, s * .16, s * .36, Art.palette.wood, s * .04, Art.palette.outline, s * .05)
            nvgBeginPath(vg)
            nvgCircle(vg, x + s * .5, y + s * .42, s * .36)
            fillStroke(vg, def.color, Art.palette.outline, s * .07)
            nvgBeginPath(vg)
            nvgCircle(vg, x + s * .42, y + s * .32, s * .18)
            nvgFillColor(vg, Art.Color({ 124, 186, 110, 220 })); nvgFill(vg)
        else
            Art.Ellipse(vg, x + s * .5, y + s * .9, s * .40, s * .12, Art.palette.shadow)
            Art.Polygon(vg, { x + s * .5, y + s * .12, x + s * .82, y + s * .52, x + s * .5, y + s * .88, x + s * .18, y + s * .52 },
                def.color, Art.palette.outline, s * .07)
            Art.Polygon(vg, { x + s * .5, y + s * .18, x + s * .68, y + s * .50, x + s * .5, y + s * .48 },
                { 214, 222, 234, 210 })
        end
    end
    -- 剩余储量条：让"还要不要继续采"一眼可判。
    if #res.cells > 0 then
        local c = res.cells[1]
        local ratio = res.maxStock > 0 and res.stock / res.maxStock or 0
        local bx, by = ox + (c.x - 1) * s + s * .12, oy + (c.y - 1) * s - s * .16
        Art.Rect(vg, bx, by, s * .76, 3, { 42, 50, 38, 220 }, 1.5)
        Art.Rect(vg, bx, by, s * .76 * ratio, 3, def.color, 1.5)
    end
end

function Art.Unit(vg, u, x, y, s, time)
    local p = Art.palette
    local t = C.units[u.kind]
    local z = s * (u.size == 2 and 0.74 or 0.38)
    Art.Ellipse(vg, x, y + z * .66, z * .94, z * .36, { 34, 46, 30, 95 })
    nvgSave(vg)
    nvgTranslate(vg, x, y)
    local bob = u.moving and math.sin(time * 12 + u.id) * z * .08 or 0
    nvgTranslate(vg, 0, bob)
    if u.worker then farmer(vg, u, z, t, p)
    elseif u.size == 2 then beast(vg, u, z, t, p)
    elseif u.gear.stable then cavalry(vg, u, z, t, p)
    else soldier(vg, u, z, t, p) end
    nvgRestore(vg)
    if u.hp < u.maxHp then
        Art.Rect(vg, x - z, y - z * 1.25, z * 2, 2.5, { 42, 50, 38, 235 }, 1.2)
        Art.Rect(vg, x - z, y - z * 1.25, z * 2 * math.max(0, u.hp / u.maxHp), 2.5,
            u.team == "ally" and { 128, 208, 112, 255 } or { 226, 118, 96, 255 }, 1.2)
    end
    if u.blocked > 1 then
        Art.Circle(vg, x + z * .62, y - z * 1.28, 2.2, { 244, 188, 92, 255 }, p.outline, .8)
    end
end

return Art
