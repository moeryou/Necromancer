-- 基于 scaffold-2d 的生命周期：初始化UI → 创建玩法 → 建树 → 订阅更新。
-- 战场是自定义Widget；NanoVG帧、DPR和指针坐标全部由UI.Scale.DEFAULT统一处理。
local UI = require "urhox-libs/UI"
local C = require "Frontier.Config"
local Simulation = require "Frontier.Simulation"
local Interface = require "Frontier.Interface"

---@type FrontierSim?
local sim = nil
---@type FrontierInterface?
local hud = nil
local accumulator = 0

function Start()
    graphics.windowTitle = C.title
    input.mouseMode = MM_ABSOLUTE
    UI.Init({
        theme = require "Frontier.SpookyTheme",
        scale = UI.Scale.DEFAULT,
        fonts = { { family = "sans", weights = {
            normal = "Fonts/MiSans-Regular.ttf", bold = "Fonts/MiSans-Bold.ttf",
        } } },
    })
    sim = Simulation.New()
    hud = Interface.New(sim)
    SubscribeToEvent("Update", "HandleFrontierUpdate")
    SubscribeToEvent("KeyDown", "HandleFrontierKey")
    print("[启动] 亡灵工坊已就绪：网格规划、兵力上限5、有限库存加工、路面自发生成")
end

function Stop()
    UnsubscribeFromEvent("Update")
    UnsubscribeFromEvent("KeyDown")
    UI.Shutdown()
    sim, hud = nil, nil
end

---@param eventType string
---@param eventData UpdateEventData
function HandleFrontierUpdate(eventType, eventData)
    if not sim or not hud then return end
    local dt = math.min(0.15, eventData:GetFloat("TimeStep"))
    if not sim.paused then
        accumulator = accumulator + dt * sim.speed
        local steps = 0
        -- 单帧最多补 30 步（1 秒游戏时间），3× 速度下也不会追不上而拖慢节奏。
        while accumulator >= C.fixedStep and steps < 30 do
            sim:Step(C.fixedStep)
            accumulator = accumulator - C.fixedStep
            steps = steps + 1
        end
        -- 追不上就丢弃积压，避免长时间卡顿后出现"补帧风暴"。
        if accumulator > C.fixedStep * 30 then accumulator = 0 end
    else accumulator = 0 end
    hud:Update(dt)
end

---@param eventType string
---@param eventData KeyDownEventData
function HandleFrontierKey(eventType, eventData)
    if not sim or not hud then return end
    local key=eventData:GetInt("Key")
    if key==KEY_SPACE then sim.paused=not sim.paused
    elseif key==KEY_1 then sim:SetCommand("defend")
    elseif key==KEY_2 then sim:SetCommand("attack")
    elseif key==KEY_ESCAPE then hud:Select("inspect")
    elseif key==KEY_H then hud:Help(not hud.helpOpen) end
end
