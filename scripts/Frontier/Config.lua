-- 所有玩法参数集中配置；一格对应一米，绘制坐标为 X 向右、Y 向下。
local Config = {
    title = "边境工事 · FRONTIER",
    cols = 44, rows = 12, wallCol = 18, gateTop = 5, gateWidth = 3,
    developTime = 90, startGold = 420, wallHealth = 800,
    passiveIncome = 2.5, commandCost = 15, commandCooldown = 8,
    armyLimit = 100, fixedStep = 1 / 30,
    roadCost = 3, clearCost = 8, boostCost = 6, refundRate = 0.55,
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
---@field tech? number

---@type table<string, FrontierBuildDef>
Config.buildings = {
    barracks = { name = "民兵营", short = "兵", w = 2, h = 2, cost = 90, interval = 6,
        unit = "militia", color = { 205, 133, 78 }, description = "每 6 秒生产民兵 · 2×2" },
    shield = { name = "盾牌工坊", short = "盾", w = 1, h = 2, cost = 70, interval = 10,
        upgrade = "heavy", color = { 116, 158, 168 }, description = "途经拾取盾牌 → 重甲步兵 · 1×2" },
    bow = { name = "弓箭作坊", short = "弓", w = 1, h = 2, cost = 80, interval = 9,
        upgrade = "archer", color = { 123, 157, 94 }, description = "途经拾取弓箭 → 弓箭手 · 1×2" },
    stable = { name = "马厩", short = "骑", w = 2, h = 2, cost = 110, interval = 13,
        upgrade = "cavalry", color = { 174, 133, 95 }, description = "途经拾取马匹 → 轻骑兵 · 2×2" },
    elephant = { name = "大象驯养栏", short = "象", w = 2, h = 2, cost = 180, interval = 24,
        unit = "elephant", tech = 1, color = { 153, 135, 184 }, description = "每 24 秒生产大象 · 需双格硬化路" },
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
        speed = 1.45, interval = 1.1, size = 1, color = { 223, 198, 137 }, sight = 6 },
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
    flanker = { name = "游袭者", hp = 50, armor = 0, damage = 10, range = 1,
        speed = 2, interval = 1.2, size = 1, color = { 233, 139, 81 }, sight = 4 },
    guardian = { name = "荒野守卫", hp = 28, armor = 0, damage = 5, range = 1,
        speed = 0.9, interval = 1.5, size = 1, color = { 175, 126, 113 }, sight = 3.8 },
    boss = { name = "破城巨兽", hp = 1500, armor = 3, damage = 30, range = 2.0, aoe = 2.1,
        speed = 0.55, interval = 2, size = 2, color = { 215, 93, 82 }, sight = 8 },
}
Config.techNames = { "硬化路面", "拓宽车道", "加速通道" }
Config.techDescriptions = { "道路 +50% 移速 · 解锁大象通行", "道路最大并行数 +1 · 缓解拥堵", "解锁加速带 · 经过后短时双倍移速" }
Config.techCosts = { 1, 2, 3 }
Config.commandNames = { collect = "收集资源", defend = "驻守城门", attack = "全力进攻", wait = "城外待命" }
Config.commandNotes = { collect = "自主采集 · 部队分散，城门空虚", defend = "依墙固守 · 密集站位易受范围伤害", attack = "前压追击 · 远离城墙，后方空虚" }
return Config
