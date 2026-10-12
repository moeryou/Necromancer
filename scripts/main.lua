local UI = require("urhox-libs/UI")

local GAME_TITLE = "新玩法原型"
local DEBUG_ENABLED = true
local SCREEN_STATE = "menu"
local uiRoot_ = nil
local statusLabel_ = nil
local debugLabel_ = nil
local elapsedTime_ = 0

function Start()
    graphics.windowTitle = GAME_TITLE
    print("[Init] 正在初始化 UrhoX 玩法重构原型")

    UI.Init({
        theme = "default-dark",
        scale = UI.Scale.DEFAULT,
    })

    CreateUI()
    SubscribeToEvent("Update", "HandleUpdate")
    SubscribeToEvent("KeyDown", "HandleKeyDown")

    print("[Init] 原型启动完成；当前为可替换的空玩法基线")
end

function Stop()
    print("[Stop] 正在释放 UI 资源")
    UI.Shutdown()
    uiRoot_ = nil
    statusLabel_ = nil
    debugLabel_ = nil
end

function CreateUI()
    statusLabel_ = UI.Label {
        id = "statusLabel",
        text = "玩法基线已就绪",
        fontSize = 15,
        fontColor = { 205, 214, 230, 255 },
        textAlign = "center",
    }

    debugLabel_ = UI.Label {
        id = "debugLabel",
        text = "调试信息：等待输入",
        fontSize = 12,
        fontColor = { 135, 153, 181, 255 },
        textAlign = "center",
    }

    uiRoot_ = UI.Panel {
        id = "gameRoot",
        width = "100%",
        height = "100%",
        backgroundGradient = {
            type = "linear",
            direction = "to-bottom",
            from = { 12, 18, 31, 255 },
            to = { 24, 34, 52, 255 },
        },
        justifyContent = "center",
        alignItems = "center",
        padding = 24,
        children = {
            UI.SafeAreaView {
                width = "100%",
                height = "100%",
                justifyContent = "center",
                alignItems = "center",
                children = {
                    UI.Panel {
                        width = "90%",
                        maxWidth = 520,
                        padding = 28,
                        gap = 18,
                        alignItems = "center",
                        backgroundColor = { 27, 37, 56, 245 },
                        borderColor = { 75, 96, 128, 220 },
                        borderWidth = 1,
                        borderRadius = 18,
                        shadowBlur = 18,
                        shadowColor = { 0, 0, 0, 100 },
                        children = {
                            UI.Label {
                                text = "玩法重构 · 全新起点",
                                fontSize = 25,
                                fontColor = { 244, 247, 252, 255 },
                                textAlign = "center",
                            },
                            UI.Label {
                                text = "旧玩法源码已清理。这里是独立、可运行的基础原型。",
                                fontSize = 14,
                                fontColor = { 173, 187, 210, 255 },
                                textAlign = "center",
                                whiteSpace = "normal",
                                maxWidth = 430,
                            },
                            UI.Divider {
                                orientation = "horizontal",
                                thickness = 1,
                                color = { 75, 96, 128, 180 },
                                spacing = 4,
                            },
                            statusLabel_,
                            debugLabel_,
                            UI.Button {
                                id = "startButton",
                                text = "开始新原型",
                                variant = "primary",
                                width = 220,
                                onClick = function()
                                    StartPrototype()
                                end,
                            },
                            UI.Label {
                                text = "按 Enter 开始 · 按 Z 切换调试信息",
                                fontSize = 12,
                                fontColor = { 135, 153, 181, 255 },
                                textAlign = "center",
                            },
                        },
                    },
                },
            },
        },
    }

    UI.SetRoot(uiRoot_)
    print("[UI] 主界面与安全区布局已创建")
end

function StartPrototype()
    SCREEN_STATE = "prototype"
    elapsedTime_ = 0
    statusLabel_:SetText("新玩法原型已启动")
    print("[Gameplay] 原型启动；等待确定核心玩法循环")
end

---@param eventType string
---@param eventData UpdateEventData
function HandleUpdate(eventType, eventData)
    local timeStep = eventData:GetFloat("TimeStep")
    if SCREEN_STATE == "prototype" then
        elapsedTime_ = elapsedTime_ + timeStep
        if debugLabel_ and DEBUG_ENABLED then
            debugLabel_:SetText("运行时间：" .. string.format("%.1f", elapsedTime_) .. " 秒")
        end
    end
end

---@param eventType string
---@param eventData KeyDownEventData
function HandleKeyDown(eventType, eventData)
    local key = eventData:GetInt("Key")
    if key == KEY_RETURN then
        StartPrototype()
    elseif key == KEY_Z then
        DEBUG_ENABLED = not DEBUG_ENABLED
        if debugLabel_ then
            debugLabel_:SetVisible(DEBUG_ENABLED)
        end
        print("[Debug] 调试信息 " .. (DEBUG_ENABLED and "开启" or "关闭"))
    end
end
