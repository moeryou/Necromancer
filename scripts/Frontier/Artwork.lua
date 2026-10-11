-- 万圣节喜剧美术：欧美卡通 + 赛璐璐平涂 + 现代。
-- 三条硬规则：圆润夸张的形体、清晰的深紫描边、每块颜色只叠一层块面阴影。
-- 全部由 NanoVG 矢量绘制；文字、按钮和 HUD 由 UI 组件负责，不在本模块内。
--
-- 配色策略：世界用"夜墓园"紫灰地 + 鬼火绿草；建筑保留可辨认的南瓜橙/巫术紫/骨白，
-- 升级与装备一律靠"外形变化"表达（帽子、翅膀、角、披风），不靠文字标签。
local C = require "Frontier.Config"
local Art = {}

-- 统一调色板。描边用深紫而非纯黑，平涂色块之间靠"一层暗面"分层。
Art.palette = {
    outline    = { 58, 40, 74, 255 },
    outlineSoft= { 74, 54, 92, 200 },
    shadow     = { 40, 30, 58, 105 },
    -- 地面：月光下的墓园草坪。营地内偏鬼火绿，荒野更冷更紫，整体压低饱和度。
    grassIn    = { 104, 146, 116, 255 },
    grassIn2   = { 98, 139, 110, 255 },
    grassOut   = { 86, 112, 116, 255 },
    grassOut2  = { 80, 106, 110, 255 },
    -- 土路（踩踏）
    road       = { 186, 160, 122, 255 },
    roadDark   = { 152, 126, 92, 255 },
    roadLight  = { 210, 186, 146, 255 },
    -- 石料：偏冷紫灰，像墓碑
    stone      = { 168, 166, 192, 255 },
    stoneDark  = { 132, 130, 158, 255 },
    stoneLite  = { 204, 202, 226, 255 },
    -- 木料：南瓜色系
    wood       = { 196, 138, 84, 255 },
    woodDark   = { 152, 100, 58, 255 },
    woodLite   = { 222, 172, 114, 255 },
    -- 屋顶（升级色阶）
    roofOrange = { 246, 140, 54, 255 },
    roofOrangeD= { 198, 102, 34, 255 },
    roofPurple = { 150, 116, 200, 255 },
    roofPurpleD= { 112, 82, 158, 255 },
    roofGreen  = { 138, 196, 108, 255 },
    roofGreenD = { 102, 158, 78, 255 },
    roofTeal   = { 104, 190, 190, 255 },
    roofTealD  = { 72, 148, 152, 255 },
    roofRed    = { 230, 96, 108, 255 },
    roofRedD   = { 184, 66, 80, 255 },
    -- 亡灵色
    bone       = { 242, 236, 216, 255 },
    boneDark   = { 200, 192, 172, 255 },
    ghost      = { 168, 226, 226, 255 },
    ghostDark  = { 122, 186, 194, 255 },
    goo        = { 150, 220, 118, 255 },
    gooDark    = { 108, 178, 84, 255 },
    -- 金属与杂项
    gold       = { 250, 202, 96, 255 },
    goldDark   = { 202, 154, 54, 255 },
    metal      = { 178, 182, 200, 255 },
    metalDark  = { 134, 138, 160, 255 },
    boot       = { 78, 62, 92, 255 },
    pumpkin    = { 246, 140, 54, 255 },
    pumpkinD   = { 198, 102, 34, 255 },
}

function Art.Color(c, alpha)
    return nvgRGBA(c[1], c[2], c[3], alpha or c[4] or 255)
end

-- 卡通轮廓统一出口：圆角连接 + 圆头线帽，避免尖角割裂平涂块面。
local function stroke(vg, color, width)
    nvgStrokeColor(vg, Art.Color(color))
    nvgStrokeWidth(vg, width or 1.5)
    nvgLineJoin(vg, NVG_ROUND)
    nvgLineCap(vg, NVG_ROUND)
    nvgStroke(vg)
end

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

-- 一对圆眼：亡灵角色的表情载体。pupil 决定视线方向，让单位"活"起来。
local function eyes(vg, x, y, spread, r, pupilDx)
    local p = Art.palette
    Art.Circle(vg, x - spread, y, r, { 255, 255, 255, 255 }, p.outline, r * .55)
    Art.Circle(vg, x + spread, y, r, { 255, 255, 255, 255 }, p.outline, r * .55)
    Art.Circle(vg, x - spread + (pupilDx or 0), y, r * .46, { 52, 36, 66, 255 })
    Art.Circle(vg, x + spread + (pupilDx or 0), y, r * .46, { 52, 36, 66, 255 })
end

-- 咧嘴笑：可爱亡灵的标志。齿缝用竖线切，不描外轮廓以免过重。
local function grin(vg, x, y, w, h, teeth)
    local p = Art.palette
    nvgBeginPath(vg)
    nvgMoveTo(vg, x - w * .5, y)
    nvgQuadTo(vg, x, y + h * 1.7, x + w * .5, y)
    nvgClosePath(vg)
    nvgFillColor(vg, Art.Color({ 52, 36, 66, 255 })); nvgFill(vg)
    if teeth then
        for i = -1, 1 do
            Art.Line(vg, x + i * w * .26, y + h * .10, x + i * w * .26, y + h * .55, { 255, 255, 255, 220 }, w * .07)
        end
    end
end

-- 草丛与小花：地图上的低成本点缀，让草地不那么平。
function Art.GrassTuft(vg, x, y, s)
    local g = { 88, 148, 90, 230 }
    Art.Line(vg, x, y, x - s * .30, y - s * .62, g, s * .16)
    Art.Line(vg, x, y, x + s * .06, y - s * .80, g, s * .16)
    Art.Line(vg, x, y, x + s * .38, y - s * .58, g, s * .16)
end

-- 万圣节小装饰：小南瓜与糖果，随机撒在草地上。
function Art.Flower(vg, x, y, s, color)
    local p = Art.palette
    Art.Ellipse(vg, x, y + s * .1, s * .34, s * .30, p.pumpkin, p.outline, s * .10)
    Art.Ellipse(vg, x - s * .22, y, s * .20, s * .26, p.pumpkinD)
    Art.Ellipse(vg, x + s * .22, y, s * .20, s * .26, p.pumpkinD)
    Art.Rect(vg, x - s * .06, y - s * .40, s * .12, s * .18, p.gooDark, s * .04, p.outline, s * .06)
end

-- 踩踏痕迹：等级越高，土色越实、车辙越深。
-- 2 级以上刻意不描边、不留圆角，让相邻格自然连成一条连续道路。
function Art.Trail(vg, x, y, s, level, seed)
    local p = Art.palette
    local k = ((seed * 37) % 17) / 17
    if level == 1 then
        -- 鬼脚印：两枚小椭圆脚印，而不是一大块土斑——"走出来的"比"泼出来的"可信。
        local lean = (k - .5) * s * .18
        Art.Ellipse(vg, x + s * .38 + lean, y + s * .38, s * .13, s * .09, { 156, 138, 102, 190 })
        Art.Ellipse(vg, x + s * .62 + lean, y + s * .64, s * .13, s * .09, { 156, 138, 102, 190 })
        Art.Circle(vg, x + s * .30 + lean, y + s * .30, s * .035, { 138, 120, 86, 150 })
        Art.Circle(vg, x + s * .54 + lean, y + s * .56, s * .035, { 138, 120, 86, 150 })
    elseif level == 2 then
        Art.Rect(vg, x, y, s, s, p.road)
        Art.Line(vg, x + s * .12, y + s * (.34 + k * .10), x + s * .88, y + s * (.34 + k * .10), p.roadDark, s * .06)
        Art.Line(vg, x + s * .12, y + s * (.68 - k * .10), x + s * .88, y + s * (.68 - k * .10), p.roadDark, s * .06)
    elseif level == 3 then
        Art.Rect(vg, x, y, s, s, p.road)
        Art.Rect(vg, x + s * .12, y + s * .12, s * .76, s * .76, p.roadLight)
        Art.Circle(vg, x + s * .28, y + s * .30, s * .07, { 142, 124, 88, 145 })
        Art.Circle(vg, x + s * .74, y + s * .72, s * .07, { 142, 124, 88, 145 })
    else
        -- 硬化路面：石砖铺装 + 中央鬼火加速箭头
        Art.Rect(vg, x, y, s, s, { 176, 172, 200, 255 })
        Art.Rect(vg, x + s * .09, y + s * .09, s * .82, s * .82, { 198, 194, 220, 255 })
        nvgBeginPath(vg)
        nvgMoveTo(vg, x + s * .5, y + s * .09); nvgLineTo(vg, x + s * .5, y + s * .91)
        nvgMoveTo(vg, x + s * .09, y + s * .5); nvgLineTo(vg, x + s * .91, y + s * .5)
        stroke(vg, { 156, 152, 186, 150 }, s * .05)
        Art.Polygon(vg, { x + s * .28, y + s * .30, x + s * .70, y + s * .50, x + s * .28, y + s * .70 },
            { 190, 246, 140, 245 }, p.outline, s * .05)
    end
end

-- 扭曲枯树：弯折的树干 + 幽紫树冠 + 一对发光眼睛。
-- 树是玩家第一眼看到的"这是个万圣节游戏"的信号，所以必须脱离清新绿。
function Art.Tree(vg, x, y, s)
    local p = Art.palette
    local seed = x * .07 + y * .11
    Art.Ellipse(vg, x, y + s * .20, s * .56, s * .19, p.shadow)
    -- 弯折树干：两条错位的梯形拼出"歪脖"感
    Art.Polygon(vg, { x - s * .13, y + s * .22, x + s * .13, y + s * .22,
        x + s * .09, y - s * .18, x - s * .06, y - s * .18 }, p.woodDark, p.outline, s * .07)
    Art.Polygon(vg, { x - s * .07, y - s * .12, x + s * .09, y - s * .12,
        x + s * .12, y - s * .44, x - s * .02, y - s * .42 }, p.woodDark, p.outline, s * .07)
    -- 树枝（细，向两侧张开）
    Art.Line(vg, x, y - s * .30, x - s * .34, y - s * .50, p.woodDark, s * .07)
    Art.Line(vg, x, y - s * .40, x + s * .32, y - s * .58, p.woodDark, s * .07)
    -- 幽紫树冠
    nvgBeginPath(vg)
    blobPath(vg, x, y - s * .74, s * .60, seed, .11)
    fillStroke(vg, { 108, 78, 140, 255 }, p.outline, s * .07)
    nvgBeginPath(vg)
    blobPath(vg, x - s * .06, y - s * .84, s * .40, seed + 1.3, .14)
    nvgFillColor(vg, Art.Color({ 138, 106, 176, 255 })); nvgFill(vg)
    nvgBeginPath(vg)
    blobPath(vg, x - s * .18, y - s * .96, s * .16, 1.7, .18)
    nvgFillColor(vg, Art.Color({ 172, 146, 208, 220 })); nvgFill(vg)
    -- 树冠里的一对眼睛：可爱恐怖的记忆点
    Art.Ellipse(vg, x - s * .14, y - s * .74, s * .075, s * .085, { 196, 250, 158, 255 })
    Art.Ellipse(vg, x + s * .14, y - s * .74, s * .075, s * .085, { 196, 250, 158, 255 })
end

-- 墓墙：一排圆顶墓碑，堆叠的石块 + 顶部拱形，万圣节墓园的骨架。
function Art.Wall(vg, x, y, s)
    local p = Art.palette
    -- 投影
    Art.Rect(vg, x + s * .05, y + s * .12, s * .92, s * .86, { 40, 30, 58, 80 }, s * .14)
    -- 碑身（拱顶矩形：上方用圆角做出圆头）
    nvgBeginPath(vg)
    nvgMoveTo(vg, x + s * .06, y + s * .96)
    nvgLineTo(vg, x + s * .06, y + s * .34)
    nvgQuadTo(vg, x + s * .06, y + s * .06, x + s * .5, y + s * .06)
    nvgQuadTo(vg, x + s * .94, y + s * .06, x + s * .94, y + s * .34)
    nvgLineTo(vg, x + s * .94, y + s * .96)
    nvgClosePath(vg)
    fillStroke(vg, p.stone, p.outline, s * .07)
    -- 左侧受光块面（赛璐璐一层亮面）
    nvgBeginPath(vg)
    nvgMoveTo(vg, x + s * .06, y + s * .96)
    nvgLineTo(vg, x + s * .06, y + s * .34)
    nvgQuadTo(vg, x + s * .06, y + s * .06, x + s * .5, y + s * .06)
    nvgLineTo(vg, x + s * .5, y + s * .96)
    nvgClosePath(vg)
    nvgFillColor(vg, Art.Color(p.stoneLite, 90)); nvgFill(vg)
    -- 碑面刻字（两道横杠）
    Art.Rect(vg, x + s * .26, y + s * .48, s * .48, s * .09, p.stoneDark, s * .03)
    Art.Rect(vg, x + s * .26, y + s * .70, s * .48, s * .09, p.stoneDark, s * .03)
end

-- 旗帜：木杆 + 飘动三角旗。
function Art.Flag(vg, x, y, s, color, time)
    local p = Art.palette
    Art.Rect(vg, x - s * .05, y - s, s * .10, s, p.woodDark, s * .04, p.outline, s * .05)
    local flutter = math.sin(time * 3) * s * .08
    Art.Polygon(vg, {
        x + s * .05, y - s,
        x + s * .70, y - s + flutter,
        x + s * .58, y - s * .60 + flutter,
        x + s * .05, y - s * .58,
    }, color, p.outline, s * .05)
end

-- 南瓜灯：屋顶/门口的万圣节符号，也用来标识"已升级"。
local function jackO(vg, cx, cy, r, lit)
    local p = Art.palette
    Art.Ellipse(vg, cx, cy, r * 1.05, r * .92, p.pumpkin, p.outline, r * .16)
    Art.Ellipse(vg, cx - r * .62, cy, r * .38, r * .74, p.pumpkinD)
    Art.Ellipse(vg, cx + r * .62, cy, r * .38, r * .74, p.pumpkinD)
    Art.Rect(vg, cx - r * .16, cy - r * 1.24, r * .32, r * .42, p.gooDark, r * .10, p.outline, r * .12)
    local glow = lit and { 255, 236, 150, 255 } or { 92, 62, 40, 255 }
    -- 三角眼 + 锯齿嘴
    Art.Polygon(vg, { cx - r * .52, cy - r * .34, cx - r * .14, cy - r * .30, cx - r * .33, cy + r * .02 }, glow)
    Art.Polygon(vg, { cx + r * .14, cy - r * .30, cx + r * .52, cy - r * .34, cx + r * .33, cy + r * .02 }, glow)
    nvgBeginPath(vg)
    nvgMoveTo(vg, cx - r * .50, cy + r * .28)
    nvgLineTo(vg, cx - r * .25, cy + r * .54); nvgLineTo(vg, cx, cy + r * .28)
    nvgLineTo(vg, cx + r * .25, cy + r * .54); nvgLineTo(vg, cx + r * .50, cy + r * .28)
    nvgClosePath(vg)
    nvgFillColor(vg, Art.Color(glow)); nvgFill(vg)
end

-- 鬼屋通用件：歪斜墙体 + 尖顶屋顶 + 门窗。歪斜是"喜剧感"的来源。
local function spookyHouse(vg, x, y, w, h, roof, roofDark, opts)
    local p = Art.palette
    opts = opts or {}
    local lean = opts.lean or 0
    Art.Ellipse(vg, x + w * .52, y + h * .88, w * .48, h * .14, p.shadow)
    -- 墙体（轻微倾斜）
    nvgSave(vg)
    nvgTranslate(vg, x + w * .5, y + h * .7)
    nvgRotate(vg, lean)
    nvgTranslate(vg, -(x + w * .5), -(y + h * .7))
    nvgBeginPath(vg)
    nvgRoundedRect(vg, x + w * .13, y + h * .42, w * .74, h * .48, w * .06)
    fillStroke(vg, p.wood, p.outline, w * .035)
    nvgBeginPath(vg)
    for i = 1, 3 do
        local xx = x + w * (.13 + i * .185)
        nvgMoveTo(vg, xx, y + h * .46); nvgLineTo(vg, xx, y + h * .86)
    end
    stroke(vg, p.woodDark, w * .022)
    nvgRestore(vg)
    -- 尖顶屋顶（比平屋顶更有万圣节感，出檐更大）
    nvgBeginPath(vg)
    nvgMoveTo(vg, x + w * .00, y + h * .50)
    nvgLineTo(vg, x + w * .30, y + h * .02)
    nvgLineTo(vg, x + w * .70, y + h * .02)
    nvgLineTo(vg, x + w * 1.00, y + h * .50)
    nvgClosePath(vg)
    fillStroke(vg, roof, p.outline, w * .04)
    -- 屋顶右半块面阴影（赛璐璐：只叠一层）
    nvgBeginPath(vg)
    nvgMoveTo(vg, x + w * .50, y + h * .02)
    nvgLineTo(vg, x + w * .70, y + h * .02)
    nvgLineTo(vg, x + w * 1.00, y + h * .50)
    nvgLineTo(vg, x + w * .50, y + h * .50)
    nvgClosePath(vg)
    nvgFillColor(vg, Art.Color(roofDark)); nvgFill(vg)
    -- 屋脊高光
    Art.Rect(vg, x + w * .30, y + h * .02, w * .40, h * .05, { 255, 255, 255, 70 }, h * .02)
    -- 门
    local doorW, doorH = w * .22, h * .32
    nvgBeginPath(vg)
    nvgMoveTo(vg, x + w * .40, y + h * .90)
    nvgLineTo(vg, x + w * .40, y + h * .68)
    nvgQuadTo(vg, x + w * .51, y + h * .58, x + w * .62, y + h * .68)
    nvgLineTo(vg, x + w * .62, y + h * .90)
    nvgClosePath(vg)
    fillStroke(vg, p.woodDark, p.outline, w * .028)
    Art.Circle(vg, x + w * .58, y + h * .80, w * .022, p.gold)
    -- 圆窗（拱形）
    local function archWin(wx, wy)
        nvgBeginPath(vg)
        nvgMoveTo(vg, wx - w * .07, wy + h * .07)
        nvgLineTo(vg, wx - w * .07, wy)
        nvgQuadTo(vg, wx, wy - h * .09, wx + w * .07, wy)
        nvgLineTo(vg, wx + w * .07, wy + h * .07)
        nvgClosePath(vg)
        fillStroke(vg, { 250, 214, 132, 255 }, p.outline, w * .026)
    end
    archWin(x + w * .26, y + h * .58)
    archWin(x + w * .74, y + h * .58)
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
        -- 城墙箭塔：墓碑塔身 + 南瓜垛口，顶上一盏鬼火灯。
        Art.Ellipse(vg, x + s * .55, y + s * .92, s * .40, s * .12, p.shadow)
        nvgBeginPath(vg)
        nvgRoundedRect(vg, x + s * .18, y + s * .24, s * .64, s * .72, s * .10)
        fillStroke(vg, p.stone, p.outline, s * .07)
        nvgBeginPath(vg)
        for i = 1, 2 do
            local yy = y + s * (.24 + i * .24)
            nvgMoveTo(vg, x + s * .18, yy); nvgLineTo(vg, x + s * .82, yy)
        end
        stroke(vg, p.stoneDark, s * .05)
        nvgBeginPath(vg)
        nvgRoundedRect(vg, x + s * .10, y + s * .10, s * .80, s * .20, s * .06)
        fillStroke(vg, p.stoneLite, p.outline, s * .06)
        for i = 0, 3 do
            Art.Rect(vg, x + s * (.11 + i * .205), y + s * .01, s * .13, s * .15, p.stoneLite, s * .04, p.outline, s * .05)
        end
        -- 箭孔
        Art.Rect(vg, x + s * .44, y + s * .46, s * .12, s * .28, { 52, 36, 66, 255 }, s * .05, p.outline, s * .045)
        -- 塔顶鬼火
        local flick = 1 + math.sin(time * 6 + x) * .12
        Art.Circle(vg, x + s * .5, y + s * .02, s * .10 * flick, { 176, 240, 170, 235 })
        return
    end

    local roof, roofDark = p.roofOrange, p.roofOrangeD
    local lean, emblem = 0, nil
    if kind == "barracks" then
        -- 民兵营：交叉双骨
        roof, roofDark, lean = p.roofOrange, p.roofOrangeD, -0.02
        emblem = function(g, cx, cy, r)
            -- 交叉双骨：骨棒够粗 + 端头圆节，小尺寸下才读得出是"骨头"
            Art.Line(g, cx - r, cy + r, cx + r, cy - r, p.bone, r * .38)
            Art.Line(g, cx + r, cy + r, cx - r, cy - r, p.bone, r * .38)
            Art.Circle(g, cx - r, cy + r, r * .26, p.bone, p.outline, r * .12)
            Art.Circle(g, cx + r, cy + r, r * .26, p.bone, p.outline, r * .12)
            Art.Circle(g, cx + r, cy - r, r * .26, p.bone, p.outline, r * .12)
            Art.Circle(g, cx - r, cy - r, r * .26, p.bone, p.outline, r * .12)
        end
    elseif kind == "farmerBarracks" then
        -- 农民营：南瓜 + 麦穗
        roof, roofDark, lean = p.roofGreen, p.roofGreenD, 0.025
        emblem = function(g, cx, cy, r) jackO(g, cx, cy, r * .82, true) end
    elseif kind == "shield" then
        roof, roofDark, lean = p.roofTeal, p.roofTealD, -0.015
        emblem = function(g, cx, cy, r) shieldEmblem(g, cx, cy, r, { 150, 220, 214, 255 }) end
    elseif kind == "bow" then
        roof, roofDark, lean = p.roofGreen, p.roofGreenD, 0.02
        emblem = function(g, cx, cy, r)
            nvgBeginPath(g)
            nvgMoveTo(g, cx - r * .6, cy - r)
            nvgQuadTo(g, cx + r * 1.5, cy, cx - r * .6, cy + r)
            stroke(g, { 236, 220, 170, 255 }, r * .26)
            Art.Line(g, cx - r * .6, cy - r, cx - r * .6, cy + r, { 244, 236, 200, 200 }, r * .16)
        end
    elseif kind == "stable" then
        roof, roofDark, lean = p.roofPurple, p.roofPurpleD, -0.02
        emblem = function(g, cx, cy, r)
            -- 骷髅马头剪影
            Art.Polygon(g, { cx - r * .8, cy + r * .9, cx - r * .3, cy - r * .1, cx + r * .1, cy - r * .5,
                cx + r * .8, cy - r * .9, cx + r * .7, cy - r * .2, cx + r * .9, cy + r * .5, cx - r * .1, cy + r * .7 },
                p.bone, p.outline, r * .14)
        end
    elseif kind == "elephant" then
        roof, roofDark, lean = p.roofPurple, p.roofPurpleD, 0.02
        emblem = function(g, cx, cy, r)
            Art.Circle(g, cx, cy, r * .8, { 226, 214, 246, 255 }, p.outline, r * .18)
            eyes(g, cx, cy - r * .05, r * .3, r * .16, 0)
        end
    elseif kind == "forge" then
        -- 锻炉：大锅 + 绿火
        roof, roofDark, lean = p.roofRed, p.roofRedD, -0.025
        emblem = function(g, cx, cy, r)
            Art.Polygon(g, { cx - r * .9, cy + r * .5, cx + r * .9, cy + r * .5,
                cx + r * .55, cy - r * .1, cx - r * .55, cy - r * .1 }, { 96, 92, 118, 255 }, p.outline, r * .16)
            Art.Polygon(g, { cx - r * .30, cy - r * .3, cx + r * .30, cy - r * .3, cx, cy - r * 1.0 },
                { 176, 240, 150, 255 }, p.outline, r * .14)
            Art.Polygon(g, { cx - r * .14, cy - r * .3, cx + r * .14, cy - r * .3, cx, cy - r * .72 },
                { 236, 255, 210, 255 })
        end
    elseif kind == "aim" then
        roof, roofDark, lean = p.roofGreen, p.roofGreenD, 0.015
        emblem = function(g, cx, cy, r)
            nvgBeginPath(g); nvgCircle(g, cx, cy, r * .7)
            stroke(g, { 240, 236, 200, 255 }, r * .16)
            Art.Line(g, cx - r, cy, cx - r * .35, cy, { 240, 236, 200, 255 }, r * .16)
            Art.Line(g, cx + r * .35, cy, cx + r, cy, { 240, 236, 200, 255 }, r * .16)
            Art.Line(g, cx, cy - r, cx, cy - r * .35, { 240, 236, 200, 255 }, r * .16)
            Art.Line(g, cx, cy + r * .35, cx, cy + r, { 240, 236, 200, 255 }, r * .16)
            Art.Circle(g, cx, cy, r * .16, { 190, 246, 140, 255 })
        end
    elseif kind == "horn" then
        -- 号角站：弯角号
        roof, roofDark, lean = p.roofOrange, p.roofOrangeD, -0.015
        emblem = function(g, cx, cy, r)
            nvgBeginPath(g)
            nvgMoveTo(g, cx - r * .8, cy + r * .5)
            nvgQuadTo(g, cx + r * .3, cy + r * .5, cx + r * .8, cy - r * .7)
            stroke(g, { 250, 228, 156, 255 }, r * .34)
            Art.Circle(g, cx - r * .8, cy + r * .5, r * .3, { 250, 228, 156, 255 }, p.outline, r * .14)
        end
    elseif kind == "warehouse" then
        -- 仓库是 1×1 非阻挡建筑：南瓜箱堆 + 顶棚。
        Art.Ellipse(vg, x + s * .55, y + s * .92, s * .40, s * .12, p.shadow)
        Art.Rect(vg, x + s * .14, y + s * .34, s * .72, s * .54, p.wood, s * .08, p.outline, s * .06)
        Art.Rect(vg, x + s * .10, y + s * .22, s * .80, s * .18, p.roofPurple, s * .06, p.outline, s * .05)
        Art.Line(vg, x + s * .14, y + s * .61, x + s * .86, y + s * .61, p.woodDark, s * .05)
        jackO(vg, x + s * .5, y + s * .48, s * .15, true)
        return
    end

    spookyHouse(vg, x, y, w, h, roof, roofDark, { emblem = emblem, lean = lean })
    -- 库存进度条
    local bx, by, bw = x + w * .15, y + h * .93, w * .70
    Art.Rect(vg, bx, by, bw, 4, { 45, 32, 62, 225 }, 2)
    Art.Rect(vg, bx, by, bw * progress, 4, def.color, 2)
    if stock and stock > 0 then
        for i = 1, math.min(stock, 8) do
            Art.Circle(vg, x + w * .18 + (i - 1) * 5, y + h * .86, 1.8, p.gold, p.outline, .8)
        end
    end
end

-- 圆头盔：只盖住颅顶的穹顶，必须给眼窝留出空间，否则小尺寸下糊成一团。
local function helm(vg, z, yTop, color, dark)
    local p = Art.palette
    Art.Ellipse(vg, 0, yTop - z * .22, z * .31, z * .17, color, p.outline, z * .08)
    Art.Rect(vg, -z * .33, yTop - z * .11, z * .66, z * .07, dark, z * .035, p.outline, z * .05)
end

-- 骷髅头：所有亡灵单位的共用头型。
-- 尺寸现实：单位头只有 ~8px 高，任何牙齿/鼻孔级细节都会糊成黑带。
-- 因此只保留两件事——大的骨白颅骨 + 两个大眼窝，表情全靠眼窝形状传达。
-- horns = true 时加一对小恶魔弯角：敌方从轮廓上就能与骷髅兵区分，不靠颜色。
local function skull(vg, z, yTop, mood, horns)
    local p = Art.palette
    local dark = { 48, 32, 62, 255 }
    if horns then
        -- 弯角（先画，压在颅骨下）：向外上方伸出，够粗才在 8px 头上读得出
        Art.Polygon(vg, { -z * .30, yTop - z * .18, -z * .54, yTop - z * .50, -z * .16, yTop - z * .30 }, p.bone, p.outline, z * .055)
        Art.Polygon(vg, { z * .30, yTop - z * .18, z * .54, yTop - z * .50, z * .16, yTop - z * .30 }, p.bone, p.outline, z * .055)
    end
    -- 颅骨：上圆下略方的蛋形，比方脸更可爱
    nvgBeginPath(vg)
    nvgMoveTo(vg, -z * .30, yTop + z * .10)
    nvgQuadTo(vg, -z * .32, yTop - z * .34, 0, yTop - z * .34)
    nvgQuadTo(vg, z * .32, yTop - z * .34, z * .30, yTop + z * .10)
    nvgQuadTo(vg, z * .26, yTop + z * .30, 0, yTop + z * .30)
    nvgQuadTo(vg, -z * .26, yTop + z * .30, -z * .30, yTop + z * .10)
    nvgClosePath(vg)
    fillStroke(vg, p.bone, p.outline, z * .085)
    if mood == "angry" then
        -- 愤怒：斜切眼窝（内低外高，凶相）
        Art.Polygon(vg, { -z * .24, yTop - z * .06, -z * .05, yTop + z * .02, -z * .05, yTop + z * .12, -z * .24, yTop + z * .05 }, dark)
        Art.Polygon(vg, { z * .24, yTop - z * .06, z * .05, yTop + z * .02, z * .05, yTop + z * .12, z * .24, yTop + z * .05 }, dark)
    else
        -- 大圆眼窝，间距拉满
        Art.Ellipse(vg, -z * .145, yTop, z * .105, z * .125, dark)
        Art.Ellipse(vg, z * .145, yTop, z * .105, z * .125, dark)
        -- 眼中鬼火：小尺寸下唯一的"活"感来源，必须够亮
        Art.Circle(vg, -z * .145, yTop, z * .052, { 196, 250, 158, 255 })
        Art.Circle(vg, z * .145, yTop, z * .052, { 196, 250, 158, 255 })
    end
end

-- Q版亡灵士兵：骷髅头 + 厚轮廓 + 武器。facing 决定朝向（-1 左 / 1 右）。
-- 外观直接由 u.gear 驱动：盾牌、重甲、弓箭、瞄准配件、号角都能一眼认出。
local function soldier(vg, u, z, t, p)
    local color = u.flash > 0 and { 255, 250, 236, 255 } or C.units[u.kind].color
    -- 重甲：身体颜色加深，体型略微放大，并加上护肩。
    local armored = u.gear.forge
    if armored then
        color = u.flash > 0 and color or { math.floor(color[1] * .70), math.floor(color[2] * .72), math.floor(color[3] * .80) }
        z = z * 1.06
    end
    local f = u.facing
    -- 腿
    Art.Rect(vg, -z * .28, z * .18, z * .21, z * .40, p.boot, z * .08, p.outline, z * .07)
    Art.Rect(vg, z * .07, z * .18, z * .21, z * .40, p.boot, z * .08, p.outline, z * .07)
    -- 躯干（圆润的桶形）+ 腰带
    nvgBeginPath(vg)
    nvgRoundedRect(vg, -z * .40, -z * .30, z * .80, z * .60, z * .26)
    fillStroke(vg, color, p.outline, z * .11)
    Art.Rect(vg, -z * .41, z * .04, z * .82, z * .13, p.woodDark, z * .03, p.outline, z * .06)
    -- 武器
    if t.ranged then
        nvgBeginPath(vg)
        nvgMoveTo(vg, z * .50 * f, -z * .40)
        nvgQuadTo(vg, z * 1.08 * f, -z * .02, z * .50 * f, z * .40)
        stroke(vg, { 222, 184, 116, 255 }, z * .11)
        Art.Line(vg, z * .50 * f, -z * .40, z * .50 * f, z * .40, { 244, 236, 200, 220 }, z * .06)
        if u.gear.aim then Art.Circle(vg, z * .78 * f, 0, z * .08, { 190, 246, 140, 255 }, p.outline, z * .035) end
    else
        -- 骨剑：剑刃 + 十字护手
        Art.Line(vg, z * .46 * f, z * .32, z * 1.02 * f, -z * .54, { 240, 244, 250, 255 }, z * .15)
        Art.Line(vg, z * .30 * f, -z * .10, z * .62 * f, z * .10, { 240, 244, 250, 255 }, z * .09)
        Art.Line(vg, z * .38 * f, z * .12, z * .70 * f, z * .28, p.gold, z * .13)
    end
    -- 头（骷髅）+ 头盔。敌方（捣蛋鬼）无头盔、长犄角，轮廓上即可区分。
    local foe = u.team ~= "ally"
    skull(vg, z, -z * .46, (armored or foe) and "angry" or "happy", foe)
    if not foe then
        helm(vg, z, -z * .46, armored and { 140, 138, 158, 255 } or p.metal, p.metalDark)
    end
    -- 盾牌：单手举盾
    if u.gear.shield then
        Art.Polygon(vg, {
            z * .28 * f, -z * .30, z * .88 * f, -z * .30,
            z * .88 * f, z * .26, z * .58 * f, z * .50, z * .28 * f, z * .26,
        }, { 176, 220, 216, 255 }, p.outline, z * .08)
        Art.Line(vg, z * .58 * f, -z * .26, z * .58 * f, z * .40, { 255, 255, 255, 130 }, z * .07)
    end
    -- 号角：背部小型黄色标识
    if u.gear.horn then
        Art.Circle(vg, -z * .34 * f, -z * .16, z * .11, p.gold, p.outline, z * .035)
    end
end

-- 骷髅坐骑：马 + 骑手。任何装备了坐骑（马厩加工）的单位都切换到该姿态。
local function cavalry(vg, u, z, t, p)
    local color = u.flash > 0 and { 255, 250, 236, 255 } or C.units[u.kind].color
    if u.gear.forge then
        color = u.flash > 0 and color or { math.floor(color[1] * .70), math.floor(color[2] * .72), math.floor(color[3] * .80) }
    end
    local f = u.facing
    -- 马身（骨骼感：浅骨白 + 暗色胸腔）
    Art.Ellipse(vg, 0, z * .18, z * .92, z * .44, p.bone, p.outline, z * .10)
    Art.Ellipse(vg, -z * .10, z * .22, z * .50, z * .26, p.boneDark)
    Art.Line(vg, -z * .52, z * .30, -z * .66, z * .86, p.boneDark, z * .24)
    Art.Line(vg, z * .56, z * .30, z * .68, z * .84, p.boneDark, z * .24)
    -- 马头
    Art.Circle(vg, z * .88 * f, -z * .06, z * .34, p.bone, p.outline, z * .09)
    Art.Circle(vg, z * .88 * f - z * .10, -z * .10, z * .07, { 52, 36, 66, 255 })
    Art.Circle(vg, z * .88 * f + z * .10, -z * .10, z * .07, { 52, 36, 66, 255 })
    -- 鬃毛（紫色）
    Art.Polygon(vg, { z * .70 * f, -z * .34, z * .95 * f, -z * .62, z * 1.05 * f, -z * .30 },
        p.roofPurple, p.outline, z * .06)
    -- 骑手躯干
    Art.Rect(vg, -z * .30, -z * .58, z * .58, z * .58, color, z * .18, p.outline, z * .10)
    skull(vg, z * .9, -z * .70, "happy")
    helm(vg, z * .9, -z * .70, p.metal, p.metalDark)
end

-- 大型单位（亡灵巨象 / 破城巨兽）。
local function beast(vg, u, z, t, p)
    local color = u.flash > 0 and { 255, 250, 236, 255 } or t.color
    local f = u.facing
    Art.Ellipse(vg, 0, -z * .08, z * .82, z * .54, color, p.outline, z * .10)
    Art.Ellipse(vg, -z * .12, -z * .02, z * .48, z * .30, { math.floor(color[1] * .82), math.floor(color[2] * .82), math.floor(color[3] * .86), 255 })
    Art.Circle(vg, z * .62 * f, -z * .16, z * .46, color, p.outline, z * .10)
    if u.kind == "elephant" then
        nvgBeginPath(vg)
        nvgMoveTo(vg, z * 1.0 * f, -z * .04)
        nvgQuadTo(vg, z * 1.26 * f, z * .34, z * .96 * f, z * .60)
        stroke(vg, color, z * .22)
        Art.Ellipse(vg, z * .74 * f, -z * .30, z * .17, z * .21, color, p.outline, z * .07)
    else
        -- 巨兽：双角
        Art.Polygon(vg, { z * .50 * f, -z * .40, z * .92 * f, -z * .92, z * 1.06 * f, -z * .34 },
            p.bone, p.outline, z * .08)
        Art.Polygon(vg, { z * .30 * f, -z * .44, z * .52 * f, -z * .98, z * .70 * f, -z * .40 },
            p.bone, p.outline, z * .08)
    end
    -- 眼睛（大而圆，喜剧感）
    Art.Circle(vg, z * (.62 + .12) * f, -z * .22, z * .10, { 255, 255, 255, 255 }, p.outline, z * .04)
    Art.Circle(vg, z * (.62 + .12) * f + z * .03 * f, -z * .22, z * .05, { 52, 36, 66, 255 })
    Art.Line(vg, -z * .50, z * .32, -z * .58, z * .86, color, z * .24)
    Art.Line(vg, z * .18, z * .32, z * .14, z * .86, color, z * .24)
end

-- 农民亡灵：破草帽 + 布衣，背负资源时显示袋子。
local function farmer(vg, u, z, t, p)
    local color = u.flash > 0 and { 255, 250, 236, 255 } or C.units[u.kind].color
    local f = u.facing
    Art.Rect(vg, -z * .26, z * .18, z * .20, z * .40, p.boot, z * .08, p.outline, z * .07)
    Art.Rect(vg, z * .06, z * .18, z * .20, z * .40, p.boot, z * .08, p.outline, z * .07)
    nvgBeginPath(vg)
    nvgRoundedRect(vg, -z * .38, -z * .30, z * .76, z * .60, z * .26)
    fillStroke(vg, color, p.outline, z * .11)
    Art.Rect(vg, -z * .39, z * .04, z * .78, z * .12, { 176, 130, 86, 255 }, z * .03, p.outline, z * .05)
    -- 背负资源袋：采集完成、运送途中才显示。
    if u.carry > 0 then
        Art.Circle(vg, -z * .40 * f, -z * .16, z * .21,
            u.carryKind == "mineral" and { 176, 172, 200, 255 } or p.goo,
            p.outline, z * .05)
    end
    skull(vg, z, -z * .46, "happy")
    -- 破草帽：宽檐 + 尖顶，压在颅顶上（不遮眼窝）
    Art.Ellipse(vg, 0, -z * .74, z * .48, z * .15, { 226, 196, 118, 255 }, p.outline, z * .06)
    Art.Polygon(vg, { -z * .26, -z * .78, 0, -z * 1.04, z * .26, -z * .78 },
        { 240, 214, 140, 255 }, p.outline, z * .06)
end

-- 资源点：枯树（圆冠暗绿）与幽灵水晶，逐格绘制。
function Art.Resource(vg, res, ox, oy, s)
    local def = C.resources[res.kind]
    for _, c in ipairs(res.cells) do
        local x, y = ox + (c.x - 1) * s, oy + (c.y - 1) * s
        if res.kind == "forest" then
            -- 枯木林：一丛扭曲枯树 + 幽紫树冠，与地图边缘的树同源。
            Art.Ellipse(vg, x + s * .5, y + s * .9, s * .42, s * .12, Art.palette.shadow)
            Art.Rect(vg, x + s * .44, y + s * .52, s * .12, s * .40, Art.palette.woodDark, s * .04, Art.palette.outline, s * .05)
            Art.Line(vg, x + s * .5, y + s * .40, x + s * .26, y + s * .20, Art.palette.woodDark, s * .07)
            Art.Line(vg, x + s * .5, y + s * .46, x + s * .74, y + s * .24, Art.palette.woodDark, s * .07)
            nvgBeginPath(vg)
            blobPath(vg, x + s * .5, y + s * .40, s * .34, x * .05 + y * .03, .13)
            fillStroke(vg, def.color, Art.palette.outline, s * .07)
            nvgBeginPath(vg)
            blobPath(vg, x + s * .44, y + s * .30, s * .20, 1.3, .16)
            nvgFillColor(vg, Art.Color({ 148, 116, 188, 230 })); nvgFill(vg)
        else
            Art.Ellipse(vg, x + s * .5, y + s * .9, s * .40, s * .12, Art.palette.shadow)
            Art.Polygon(vg, { x + s * .5, y + s * .12, x + s * .82, y + s * .52, x + s * .5, y + s * .88, x + s * .18, y + s * .52 },
                def.color, Art.palette.outline, s * .07)
            Art.Polygon(vg, { x + s * .5, y + s * .18, x + s * .68, y + s * .50, x + s * .5, y + s * .48 },
                { 208, 246, 240, 215 })
        end
    end
    -- 剩余储量条：让"还要不要继续采"一眼可判。
    if #res.cells > 0 then
        local c = res.cells[1]
        local ratio = res.maxStock > 0 and res.stock / res.maxStock or 0
        local bx, by = ox + (c.x - 1) * s + s * .12, oy + (c.y - 1) * s - s * .16
        Art.Rect(vg, bx, by, s * .76, 3, { 42, 30, 58, 225 }, 1.5)
        Art.Rect(vg, bx, by, s * .76 * ratio, 3, def.color, 1.5)
    end
end

function Art.Unit(vg, u, x, y, s, time)
    local p = Art.palette
    local t = C.units[u.kind]
    local z = s * (u.size == 2 and 0.74 or 0.38)
    Art.Ellipse(vg, x, y + z * .66, z * .94, z * .36, { 34, 24, 50, 100 })
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
        Art.Rect(vg, x - z, y - z * 1.30, z * 2, 3, { 42, 30, 58, 240 }, 1.5)
        Art.Rect(vg, x - z, y - z * 1.30, z * 2 * math.max(0, u.hp / u.maxHp), 3,
            u.team == "ally" and { 176, 240, 150, 255 } or { 240, 118, 128, 255 }, 1.5)
    end
    if u.blocked > 1 then
        Art.Circle(vg, x + z * .62, y - z * 1.33, 2.6, { 250, 202, 96, 255 }, p.outline, .8)
    end
end

return Art
