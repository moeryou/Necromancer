-- 所有玩法参数集中配置；一格对应一米，绘制坐标为 X 向右、Y 向下。
local Config = {
    title = "边境工事 · FRONTIER",
    -- 营地占 cols 1..wallCol-1，城墙在 wallCol 列；荒野为 wallCol+1..cols。
    -- 营地宽度收窄了 4 列，总列数同步收窄，整张地图刚好铺满一屏。
    cols = 40, rows = 12, wallCol = 14, gateTop = 5, gateWidth = 3,
    developTime = 90, startGold = 420, wallHealth = 800,
    passiveIncome = 2.5, commandCost = 15, commandCooldown = 8,
    -- 我方同时存在的士兵上限。生产与转职都不突破这个数字。
    armyLimit = 5, fixedStep = 1 / 30,
    -- 道路既不能铺设也不能拆除，完全由部队反复踩踏累积而成：
    -- 阈值近似"经过此格的单位次数"，踩的人多，荒野就逐渐变成加速通道。
    trailThresholds = { 3, 8, 16, 28 },
    trailSpeed = { 1.0, 1.12, 1.30, 1.55, 1.85 },
    trailCost = { 1.0, 0.85, 0.72, 0.60, 0.50 },
    trailNames = { "荒野", "踩踏痕迹", "土路", "硬化路面", "加速通道" },
}

---@class FrontierBuildDef
---@field name string
---@field w number
---@field h number
---@field cost number
---@field interval number
---@field unit? string
---@field upgrade? string
---@field color number[]
---@field description string
---@field short string

---@type table<string, FrontierBuildDef>
Config.buildings = {
    barracks = { name = "民兵营", short = "兵", w = 2, h = 2, cost = 90, interval = 12,
        unit = "militia", color = { 205, 133, 78 }, description = "每 12 秒生产民兵 · 2×2" },
    shield = { name = "盾牌工坊", short = "盾", w = 1, h = 2, cost = 70, interval = 20,
        upgrade = "heavy", color = { 116, 158, 168 }, description = "途经拾取盾牌 → 重甲步兵 · 1×2" },
    bow = { name = "弓箭作坊", short = "弓", w = 1, h = 2, cost = 80, interval = 18,
        upgrade = "archer", color = { 123, 157, 94 }, description = "途经拾取弓箭 → 弓箭手 · 1×2" },
    stable = { name = "马厩", short = "骑", w = 2, h = 2, cost = 110, interval = 26,
        upgrade = "cavalry", color = { 174, 133, 95 }, description = "途经拾取马匹 → 轻骑兵 · 2×2" },
    elephant = { name = "大象驯养栏", short = "象", w = 2, h = 2, cost = 180, interval = 48,
        unit = "elephant", color = { 153, 135, 184 }, description = "每 48 秒生产大象 · 需双格硬化路" },
    tower = { name = "城墙箭塔", short = "塔", w = 1, h = 1, cost = 95, interval = 1.4,
        color = { 196, 167, 106 }, description = "仅建于城墙 · 射程 8 格 · 1×1" },
    block = { name = "阻碍墙", short = "墙", w = 1, h = 1, cost = 12, interval = 0,
        color = { 128, 139, 130 }, description = "阻断格子，引导分流 · 1×1" },
}
Config.buildOrder = { "barracks", "shield", "bow", "stable", "elephant", "tower", "block" }

---@class FrontierTemplate
---@field name string
---@field hp number
---@field armor number
---@field damage number
---@field range number
---@field speed number
---@field interval number
---@field size number
---@field color number[]
---@field sight number
---@field aoe? number
---@field ranged? boolean

---@type table<string, FrontierTemplate>
Config.units = {
    militia = { name = "民兵", hp = 45, armor = 0, damage = 7, range = 0.95,
        speed = 1.45, interval = 1.1, size = 1, color = { 238, 172, 88 }, sight = 6 },
    heavy = { name = "重甲步兵", hp = 115, armor = 4, damage = 12, range = 1.1,
        speed = 0.85, interval = 1.2, size = 1, color = { 126, 190, 205 }, sight = 5 },
    archer = { name = "弓箭手", hp = 34, armor = 0, damage = 9, range = 5.2, ranged = true,
        speed = 1.25, interval = 1.35, size = 1, color = { 153, 194, 116 }, sight = 7 },
    cavalry = { name = "轻骑兵", hp = 70, armor = 1, damage = 8, range = 4.0, ranged = true,
        speed = 2.4, interval = 1.05, size = 1, color = { 226, 170, 104 }, sight = 8 },
    elephant = { name = "大象兵", hp = 340, armor = 3, damage = 30, range = 1.8, aoe = 1.65,
        speed = 0.65, interval = 1.7, size = 2, color = { 183, 161, 214 }, sight = 7 },
    raider = { name = "掠夺者", hp = 42, armor = 0, damage = 8, range = 0.95,
        speed = 1.2, interval = 1.3, size = 1, color = { 205, 101, 87 }, sight = 6 },
    brute = { name = "重装掠夺者", hp = 110, armor = 2, damage = 15, range = 1.1,
        speed = 0.8, interval = 1.6, size = 1, color = { 171, 88, 79 }, sight = 6 },
    shooter = { name = "敌方射手", hp = 35, armor = 0, damage = 8, range = 4.5, ranged = true,
        speed = 0.9, interval = 1.6, size = 1, color = { 213, 129, 107 }, sight = 7 },
    boss = { name = "破城巨兽", hp = 1500, armor = 3, damage = 30, range = 2.0, aoe = 2.1,
        speed = 0.55, interval = 2, size = 2, color = { 215, 93, 82 }, sight = 8 },
}
Config.commandNames = { defend = "驻守城门", attack = "全力进攻", wait = "城外待命" }
Config.commandNotes = { defend = "依墙固守 · 密集站位易受范围伤害", attack = "前压追击 · 远离城墙，后方空虚" }
return Config
