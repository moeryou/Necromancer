-- 万圣节喜剧主题（Spooky）：深紫夜色 + 南瓜橙主色 + 幽灵青强调。
-- 欧美卡通赛璐璐路线：大圆角、粗描边、高饱和、扁平色块，不用渐变和细线。
-- 基于 default-dark 扩展，只覆盖配色与关键组件尺寸，其余结构继承。
local Theme = require("urhox-libs/UI/Core/Theme")
local DefaultDark = require("urhox-libs/UI/Theme/DefaultDark")

local Spooky = Theme.ExtendTheme(DefaultDark, {
    fonts = {
        { family = "sans", weights = {
            normal = "Fonts/MiSans-Regular.ttf",
            bold = "Fonts/MiSans-Bold.ttf",
        } },
    },
    colors = {
        primary = { 246, 140, 54, 255 },          -- 南瓜橙
        primaryHover = { 255, 168, 88, 255 },
        primaryPressed = { 206, 110, 34, 255 },
        primaryDeep = { 156, 78, 22, 255 },
        primarySoft = { 198, 122, 62, 255 },
        primaryShadow = { 156, 78, 22, 255 },
        secondary = { 122, 96, 168, 255 },         -- 巫术紫
        secondaryHover = { 146, 120, 196, 255 },
        secondaryPressed = { 90, 68, 130, 255 },
        secondaryDeep = { 62, 46, 92, 255 },
        secondaryShadow = { 62, 46, 92, 255 },
        background = { 40, 32, 62, 255 },          -- 深紫夜色
        surface = { 71,85,101,255 },
        surfaceAlt = { 68, 55, 100, 255 },
        surfaceRaised = { 82, 67, 118, 255 },
        text = { 246, 240, 228, 255 },             -- 骨白
        textSecondary = { 188, 176, 210, 255 },
        textMuted = { 150, 138, 178, 255 },
        textPlaceholder = { 162, 152, 190, 255 },
        textInverse = { 44, 34, 62, 255 },
        border = { 98, 82, 136, 255 },
        borderStrong = { 130, 110, 174, 255 },
        borderFocus = { 246, 140, 54, 255 },
        divider = { 98, 82, 136, 255 },
        disabled = { 84, 74, 108, 255 },
        disabledBorder = { 100, 90, 126, 255 },
        disabledText = { 134, 124, 158, 255 },
        success = { 150, 224, 118, 255 },          -- 鬼火绿
        successHover = { 172, 240, 142, 255 },
        successPressed = { 116, 186, 90, 255 },
        successShadow = { 116, 186, 90, 255 },
        warning = { 248, 200, 84, 255 },
        warningPressed = { 186, 142, 30, 255 },
        error = { 232, 96, 100, 255 },             -- 血红
        errorHover = { 250, 126, 130, 255 },
        errorPressed = { 184, 68, 74, 255 },
        errorShadow = { 184, 68, 74, 255 },
        danger = { 232, 96, 100, 255 },
        dangerHover = { 250, 126, 130, 255 },
        dangerPressed = { 184, 68, 74, 255 },
        overlay = { 22, 16, 38, 215 },
        infoSoft = { 44, 76, 96, 255 },
        successSoft = { 40, 74, 52, 255 },
        warningSoft = { 80, 64, 28, 255 },
        dangerSoft = { 78, 38, 48, 255 },
        surfaceTooltip = { 64, 52, 94, 255 },
        borderTooltip = { 112, 94, 152, 255 },
    },
    radius = { none = 0, xs = 4, sm = 8, md = 12, lg = 18, xl = 22, full = 999 },
    componentDefaults = { borderRadius = 14 },
    components = {
        Button = {
            borderRadius = 14,
            height = 44,
            fontSize = 12,
            fontWeight = "bold",
            borderWidth = 2,
            pressedBorderWidth = 2,
            -- 赛璐璐平涂不要微立体底阴影：关掉它并去掉为阴影预留的底部内边距。
            glowShadow = false,
            padding = { 0, 0, 0, 0 },
            pressedPadding = 0,
        },
        TextField = { borderWidth = 2, borderRadius = 12, height = 40, fontSize = 10 },
        ProgressBar = { height = 10, borderWidth = 2, borderRadius = 999 },
        Card = { borderRadius = 18, borderWidth = 2 },
        Modal = { borderWidth = 2, borderRadius = 18 },
        Tooltip = { borderWidth = 2, borderRadius = 12 },
        Popover = { borderWidth = 2, borderRadius = 14 },
        Badge = { borderRadius = 999, borderWidth = 0, fontWeight = "bold" },
        Chip = { borderRadius = 999, borderWidth = 0, fontWeight = "bold" },
    },
})

return Spooky
