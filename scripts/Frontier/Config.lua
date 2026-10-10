-- 所有玩法参数集中配置；一格对应一米，绘制坐标为 X 向右、Y 向下。
local Config = {
    title = "边境工事 · FRONTIER",
    -- 营地占 cols 1..wallCol-1，城墙在 wallCol 列，荒野为 wallCol+1..cols。
    -- 画面按 2/3 营地 : 1/3 荒野切分：营地 22 列，荒野 10 列（含城墙 11 列）。
    cols = 33, rows = 12, wallCol = 23, gateTop = 5, gateWidth = 3,
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
    -- 硬化路面（3 级）及以上提供的战斗减伤，强化"养路 = 提升战力"的正向循环。
    trailDamageReduction = { 0, 0, 0, 0.10, 0.10 },
    -- 同一士兵 10 秒内重复经过同一格只计 1 次踩踏，避免原地抖动刷道路。
    trampleCooldown = 10,
    -- 寻路分流阈值：存在多条代价差 ≤ 该比例的路径时随机选择，支持并行线玩法。
    routeSplitRatio = 0.10,
    -- 拆除建筑仅返还该比例的资源，保证布局决策的重量感。
    refundRatio = 0.5,
}

---@class FrontierBuildDef
---@field name string
---@field short string
---@field w number
---@field h number
---@field cost number
---@field interval number
---@field unit? string       -- 产兵建筑：产出的基础单位
---@field proc? string       -- 工序建筑：触发的加工 id
---@field color number[]
---@field description string

---@type table<string, FrontierBuildDef>
Config.buildings = {
    -- 产兵建筑
    barracks = { name = "民兵营", short = "兵", w = 2, h = 2, cost = 90, interval = 12,
        unit = "militia", color = { 205, 133, 78 }, description = "每 12 秒产出民兵 · 2×2" },
    elephant = { name = "大象驯养栏", short = "象", w = 2, h = 2, cost = 180, interval = 48,
        unit = "elephant", color = { 153, 135, 184 }, description = "每 48 秒产出大象 · 需双格硬化路 · 2×2" },
    -- 工序建筑
    shield = { name = "盾牌工坊", short = "盾", w = 2, h = 2, cost = 90, interval = 0,
        proc = "shield", color = { 116, 158, 168 }, description = "途经 +30 护甲 / 移速 -10% · 与弓互斥 · 2×2" },
    bow = { name = "弓箭作坊", short = "弓", w = 2, h = 2, cost = 100, interval = 0,
        proc = "bow", color = { 123, 157, 94 }, description = "途经改为远程 / 射程 8.5 · 生命 -20 · 与盾互斥 · 2×2" },
    forge = { name = "锻炉", short = "锻", w = 2, h = 2, cost = 120, interval = 0,
        proc = "forge", color = { 190, 108, 84 }, description = "途经 +50 生命 / 生命上限 +15% / 移速 -5% · 2×2" },
    aim = { name = "瞄准台", short = "瞄", w = 1, h = 1, cost = 90, interval = 0,
        proc = "aim", color = { 150, 176, 120 }, description = "途经 远程伤害 +40% / 攻速 -10% · 需已持弓 · 1×1" },
    stable = { name = "马厩", short = "骑", w = 3, h = 3, cost = 220, interval = 0,
        proc = "stable", color = { 174, 133, 95 }, description = "途经 移速 +80% / 冲锋伤害 +50% · 3×3" },
    horn = { name = "号角站", short = "号", w = 1, h = 1, cost = 120, interval = 0,
        proc = "horn", color = { 214, 176, 96 }, description = "途经 首次攻击伤害翻倍 · 仅生效一次 · 1×1" },
    -- 特殊建筑
    tower = { name = "城墙箭塔", short = "塔", w = 1, h = 1, cost = 95, interval = 1.4,
        color = { 196, 167, 106 }, description = "仅建于城墙 · 射程 8 格 · 不计入兵力上限 · 1×1" },
    -- 阻挡物
    block = { name = "阻碍墙", short = "墙", w = 1, h = 1, cost = 12, interval = 0,
        color = { 128, 139, 130 }, description = "阻断格子，引导分流 · 1×1" },
}
Config.buildOrder = { "barracks", "shield", "bow", "forge", "aim", "stable", "horn", "elephant", "tower", "block" }
-- 建筑分类，供界面分组与产能统计使用。
Config.produceOrder = { "barracks", "elephant" }
Config.processOrder = { "shield", "bow", "forge", "aim", "stable", "horn" }

---@class FrontierProcDef
---@field building string    -- 对应的建筑 kind
---@field tag string         -- 获得的装备标记（用于互斥与防重复）
---@field label string       -- 提示用的短名
---@field flat? table        -- 固定值加成（在基础值之后、百分比之前）
---@field pct? table         -- 百分比加成（乘法叠加，与加工顺序无关）
---@field set? table         -- 直接设定的属性（如切远程、射程）
---@field conflict? string[] -- 与之互斥的装备标记
---@field requires? string   -- 前置装备标记
---@field charge? number     -- 冲锋伤害加成（首次接敌额外倍率）
---@field firstHit? number   -- 首次攻击伤害倍率
---@field once? boolean      -- 全局仅生效一次
---@field conflictNote? string -- 无法加工时的提示文案

---@type table<string, FrontierProcDef>
Config.processings = {
    -- 弓与盾互斥是双向的：谁先装备，另一个就会被跳过并给出对应提示。
    shield = { building = "shield", tag = "shield", label = "盾牌", conflict = { "bow" },
        conflictNote = "已持弓，无法装备盾牌", flat = { armor = 30 }, pct = { speed = -0.10 } },
    forge = { building = "forge", tag = "forge", label = "重甲",
        flat = { hp = 50 }, pct = { hp = 0.15, speed = -0.05 } },
    bow = { building = "bow", tag = "bow", label = "弓箭", conflict = { "shield" },
        conflictNote = "已装备盾牌，无法持弓",
        flat = { hp = -20 }, set = { ranged = true, range = 8.5 } },
    aim = { building = "aim", tag = "aim", label = "瞄准配件", requires = "bow",
        conflictNote = "尚未持弓，瞄准台无法生效", pct = { damage = 0.40, interval = 0.10 } },
    stable = { building = "stable", tag = "stable", label = "坐骑",
        pct = { speed = 0.80 }, charge = 0.50 },
    horn = { building = "horn", tag = "horn", label = "号角", once = true,
        firstHit = 2.0 },
}

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
    -- 我方基础单位：只有民兵与大象两种"原料"，装备差异全部由工序加工产生。
    militia = { name = "民兵", hp = 45, armor = 0, damage = 7, range = 0.95,
        speed = 1.45, interval = 1.1, size = 1, color = { 238, 172, 88 }, sight = 6 },
    elephant = { name = "大象兵", hp = 340, armor = 3, damage = 30, range = 1.8, aoe = 1.65,
        speed = 0.65, interval = 1.7, size = 2, color = { 183, 161, 214 }, sight = 7 },
    -- 敌军沿用原有模板。
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
