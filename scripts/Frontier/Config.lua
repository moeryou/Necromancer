-- 所有玩法参数集中配置；一格对应一米，绘制坐标为 X 向右、Y 向下。
local Config = {
    title = "亡灵工坊 · NECRO WORKS",
    cols = 33, rows = 12, wallCol = 23, gateTop = 5, gateWidth = 3,
    -- 刚性区域定义（V3.2 §1.4）：营地 1..22 列，城墙 23 列，荒野 24..33 列。
    campMinX = 1, campMaxX = 22, wildMinX = 24, wildMaxX = 33,
    developTime = 90, startGold = 480, wallHealth = 800,
    -- 敌人对城墙的伤害倍率：单位间战斗保持原数值，但城墙是工事而非纸片。
    -- 不加这个系数时，13 个掠夺者约 80dps，10 秒就能拆掉 800 血城墙，
    -- 导致"第一波必须建箭塔"成为唯一解。
    wallDamageScale = 0.45,
    -- 护甲减伤下限：护甲是减法，但最多只能把伤害压到原始的 20%。
    -- 否则"盾牌 +30 护甲"会把掠夺者(8 伤害)直接归零，1-3 波失去全部威胁。
    armorFloor = 0.20,
    -- 被动产出只作兜底启动资金，经济主力来自农民采集（V3.2 §7.1）。
    passiveIncome = 1.2, commandCost = 15, commandCooldown = 8,
    -- 5 人上限只针对战斗单位；农民不占战斗人口（V3.2 §二）。
    armyLimit = 5, fixedStep = 1 / 30,
    -- 道路既不能铺设也不能拆除，完全由部队在营地内反复踩踏累积而成。
    -- 阈值按"经过次数"计；单局里士兵只出城一次，农民往返才持续踩踏，
    -- 所以门槛定得比"纯士兵通行"低，保证一局内真能看到道路升级。
    trailThresholds = { 2, 6, 12, 22 },
    trailSpeed = { 1.0, 1.12, 1.30, 1.55, 1.85 },
    -- 寻路代价即"每格通行时间"，与 trailSpeed 互为倒数（V3.2 §1.2）。
    trailCost = { 1.0, 0.85, 0.72, 0.60, 0.50 },
    trailNames = { "荒坟地", "鬼脚印", "骨径", "石棺道", "幽魂大道" },
    trailDamageReduction = { 0, 0, 0, 0.10, 0.10 },
    -- 同一单位 10 秒内重复经过同一格只计 1 次踩踏，避免原地抖动刷道路。
    trampleCooldown = 10,
    -- 路径惰性（V3.2 §1.3）：新路径须比当前剩余耗时快 15% 以上才改道。
    repathGain = 0.15, repathInterval = 3.0,
    -- 拆除建筑仅返还该比例的资源。
    refundRatio = 0.5,
    -- 农民无强制硬上限，此值仅作安全阀，防止异常情况下无限膨胀。
    farmerLimit = 12,
    -- 重装工序（盾牌工坊/锻炉/马厩）每加工 1 名士兵额外消耗的矿物资源值。
    heavyProcessCost = 2,
    -- 农民目标失效后的复查间隔（V3.2 §3.4）。
    gatherRetry = 5.0,
}

---@class FrontierBuildDef
---@field name string
---@field short string
---@field w number
---@field h number
---@field cost number
---@field interval number
---@field unit? string       -- 产兵建筑：产出的单位
---@field proc? string       -- 工序建筑：触发的加工 id
---@field blocking? boolean  -- false = 不阻挡通行（默认阻挡）
---@field color number[]
---@field description string

---@type table<string, FrontierBuildDef>
Config.buildings = {
    -- 产兵建筑
    barracks = { name = "骷髅兵营", short = "兵", w = 2, h = 2, cost = 90, interval = 12,
        unit = "militia", color = { 246, 140, 54 }, description = "每 12 秒拼出一具骷髅兵 · 可出城作战 · 2×2" },
    farmerBarracks = { name = "南瓜农场", short = "农", w = 2, h = 2, cost = 60, interval = 10,
        unit = "farmer", color = { 150, 220, 118 }, description = "每 10 秒召唤一名亡灵农夫 · 营地内采集 · 按需产兵 · 2×2" },
    elephant = { name = "亡象墓栏", short = "象", w = 2, h = 2, cost = 180, interval = 48,
        unit = "elephant", color = { 150, 116, 200 }, description = "每 48 秒唤醒一具亡灵巨象 · 需双格石棺道 · 2×2" },
    -- 工序建筑
    shield = { name = "骨盾工坊", short = "盾", w = 2, h = 2, cost = 90, interval = 0,
        proc = "shield", color = { 104, 190, 190 }, description = "途经 +30 护甲 / 移速 -10% · 与弓互斥 · 耗矿 2 · 2×2" },
    bow = { name = "骨弓作坊", short = "弓", w = 2, h = 2, cost = 100, interval = 0,
        proc = "bow", color = { 138, 196, 108 }, description = "途经改为远程 / 射程 8.5 · 生命 -20 · 与盾互斥 · 2×2" },
    forge = { name = "鬼火锻炉", short = "锻", w = 2, h = 2, cost = 120, interval = 0,
        proc = "forge", color = { 230, 96, 108 }, description = "途经 +50 生命 / 上限 +15% / 移速 -5% · 耗矿 2 · 2×2" },
    aim = { name = "幽灵瞄准台", short = "瞄", w = 1, h = 1, cost = 90, interval = 0,
        proc = "aim", color = { 138, 196, 108 }, description = "途经 远程伤害 +40% / 攻速 -10% · 需已持弓 · 1×1" },
    stable = { name = "骷髅马厩", short = "骑", w = 3, h = 3, cost = 220, interval = 0,
        proc = "stable", color = { 150, 116, 200 }, description = "途经 移速 +80% / 冲锋伤害 +50% · 耗矿 2 · 3×3" },
    horn = { name = "哀嚎号角", short = "号", w = 1, h = 1, cost = 120, interval = 0,
        proc = "horn", color = { 250, 202, 96 }, description = "途经 首次攻击伤害翻倍 · 仅生效一次 · 1×1" },
    -- 特殊建筑
    warehouse = { name = "南瓜仓库", short = "仓", w = 1, h = 1, cost = 30, interval = 0,
        blocking = false, color = { 196, 138, 84 }, description = "资源中转 · 不阻挡通行 · 共享全局库存 · 1×1" },
    tower = { name = "墓园箭塔", short = "塔", w = 1, h = 1, cost = 95, interval = 1.4,
        color = { 168, 166, 192 }, description = "仅建于墓墙 · 射程 8 格 · 不计入兵力上限 · 1×1" },
    -- 阻挡物
    block = { name = "墓碑障碍", short = "碑", w = 1, h = 1, cost = 12, interval = 0,
        color = { 168, 166, 192 }, description = "阻断格子，引导分流 · 1×1" },
}
Config.buildOrder = { "barracks", "farmerBarracks", "shield", "bow", "forge", "aim",
    "stable", "horn", "warehouse", "elephant", "tower", "block" }
Config.produceOrder = { "barracks", "farmerBarracks", "elephant" }
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
-- 重装工序：加工时额外消耗矿物资源值（V3.2 §7.1）。
Config.heavyProcessings = { shield = true, forge = true, stable = true }

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
---@field worker? boolean   -- 采集单位：不参与战斗，禁止出城

---@type table<string, FrontierTemplate>
Config.units = {
    -- 我方战斗单位：只有骷髅兵与亡灵巨象两种"原料"，装备差异全部由工序加工产生。
    -- 民兵 dps 约 9，5 人满编 45 dps；配合箭塔足以在第一波速清，避免僵持。
    militia = { name = "骷髅兵", hp = 45, armor = 0, damage = 10, range = 0.95,
        speed = 1.45, interval = 1.1, size = 1, color = { 246, 150, 66 }, sight = 6 },
    elephant = { name = "亡灵巨象", hp = 340, armor = 3, damage = 38, range = 1.8, aoe = 1.65,
        speed = 0.65, interval = 1.7, size = 2, color = { 168, 140, 216 }, sight = 7 },
    -- 采集单位：永久限制在营地内，不占战斗人口，不参与战斗。
    -- 移速偏快（1.55）以缩短往返周期，让采集收入在发育期内就有存在感。
    farmer = { name = "亡灵农夫", hp = 30, armor = 0, damage = 0, range = 0,
        speed = 1.55, interval = 1, size = 1, color = { 150, 220, 118 }, sight = 4,
        worker = true },
    -- 敌军：血量偏脆便于速清，但伤害必须够高，否则被护甲一压就完全没威胁。
    raider = { name = "捣蛋鬼", hp = 34, armor = 0, damage = 11, range = 0.95,
        speed = 1.05, interval = 1.25, size = 1, color = { 232, 96, 128 }, sight = 6 },
    brute = { name = "大块头捣蛋鬼", hp = 120, armor = 2, damage = 22, range = 1.1,
        speed = 0.8, interval = 1.6, size = 1, color = { 190, 78, 118 }, sight = 6 },
    shooter = { name = "糖果投手", hp = 35, armor = 0, damage = 11, range = 4.5, ranged = true,
        speed = 0.9, interval = 1.6, size = 1, color = { 236, 122, 150 }, sight = 7 },
    boss = { name = "南瓜王", hp = 1300, armor = 3, damage = 40, range = 2.0, aoe = 2.1,
        speed = 0.55, interval = 2, size = 2, color = { 240, 132, 52 }, sight = 8 },
}

---@class FrontierResourceDef
---@field name string
---@field value number      -- 每单位折算的资源值
---@field stockPerCell number
---@field gather number     -- 单次采集耗时（秒）
---@field count number[]    -- 单局生成数量区间
---@field color number[]

---@type table<string, FrontierResourceDef>
-- 采集单次耗时按 V3.2 §3.3 定为森林 3 秒 / 矿物 5 秒；储量下调，
-- 让"资源点会枯竭、要不断找新点"的节奏在单局内真正成立。
Config.resources = {
    forest = { name = "枯木林", value = 1, stockPerCell = 10, gather = 3.0, count = { 3, 4 },
        color = { 118, 88, 156 } },
    mineral = { name = "幽灵石", value = 2, stockPerCell = 15, gather = 5.0, count = { 2, 2 },
        color = { 104, 196, 196 } },
}
-- 采集位规则：标准 2×2 资源点 2 个采集位；森林按"每剩余 2 格 1 位、最少 1 位"。
Config.resourceSlots = { standard = 2, cellsPerSlot = 2, minSlots = 1 }

Config.commandNames = { defend = "驻守墓门", attack = "全力进攻", wait = "城外游荡" }
Config.commandNotes = { defend = "依墙固守 · 密集站位易受范围伤害", attack = "前压追击 · 远离墓墙，后方空虚" }
return Config
