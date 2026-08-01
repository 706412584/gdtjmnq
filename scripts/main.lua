-- ============================================================================
-- 古代铁匠模拟器 - 入口文件
-- Project Smith
--
-- 初始化顺序: UI系统 -> 随机种子 -> 基础UI -> 事件订阅 -> Screen注册 -> 首页
-- ============================================================================

local UI = require("urhox-libs/UI")

-- Core modules
local EventBus      = require("Core.EventBus")
local GameState     = require("Core.GameState")
local OrderManager  = require("Core.OrderManager")
local Timer         = require("Utils.Timer")
local Tween         = require("Utils.Tween")
local ScreenRouter    = require("Utils.ScreenRouter")
local SettingsManager = require("Core.SettingsManager")
local WeeklyGoal      = require("Core.WeeklyGoal")
local Leaderboard     = require("Core.Leaderboard")

-- Screen modules
local HomeScreen       = require("Screen.HomeScreen")
local OrderBoardScreen = require("Screen.OrderBoardScreen")
local ForgeScreen      = require("Screen.ForgeScreen")
local ResultScreen     = require("Screen.ResultScreen")
local UpgradeScreen    = require("Screen.UpgradeScreen")
local StoryScreen      = require("Screen.StoryScreen")
local CodexScreen      = require("Screen.CodexScreen")
local SettingsScreen   = require("Screen.SettingsScreen")
local ShopScreen       = require("Screen.ShopScreen")
local EndingScreen     = require("Screen.EndingScreen")
local RelationshipScreen = require("Screen.RelationshipScreen")
local WeeklyScreen       = require("Screen.WeeklyScreen")

-- Audio
local BGMManager       = require("Utils.BGMManager")

-- Story system
local StoryManager     = require("Story.StoryManager")

-- Red dot system
local RedDotManager    = require("Utils.RedDotManager")

-- ============================================================================
-- 全局变量
-- ============================================================================

---@type table UI 根控件
local uiRoot_ = nil

---@type table 内容容器（Screen 挂载区域）
local contentContainer_ = nil

--- 游戏配置
local CONFIG = {
    Title = "古代铁匠模拟器",
}

-- ============================================================================
-- 生命周期
-- ============================================================================

function Start()
    graphics.windowTitle = CONFIG.Title

    -- 随机种子初始化（SecureStore 依赖）
    math.randomseed(math.floor(os.time() + os.clock() * 1000))
    for i = 1, 10 do math.random() end

    -- 1. 初始化 UI 系统（竖屏 9:16，设计高度 1920）
    InitUI()

    -- 2. 构建基础 UI 框架
    CreateUI()

    -- 3. 订阅引擎事件
    SubscribeToEvents()

    -- 4. 注册 Screen 模块
    RegisterScreens()

    -- 5. 异步加载存档，完成后初始化依赖存档的剧情系统并跳转主界面
    GameState.Load(function(success)
        print("[main] GameState loaded, success=" .. tostring(success))

        -- 应用全部已保存设置（音量、画质、字体、低功耗和语言可用性）
        SettingsManager.Apply(GameState.GetSettings())

        -- 初始化 BGM 自动切换（监听 screen_change 事件）
        BGMManager.Init()

        -- 初始化红点、剧情及运营系统（均依赖 GameState 已加载）
        StoryManager.Init()
        RedDotManager.Init()
        WeeklyGoal.Init()
        Leaderboard.Init()

        -- 红点消除：进入对应界面时自动 Dismiss（仅通知类红点）
        -- story/upgrade/specialOrder 为状态驱动，条件消失时自动隐藏，不做手动 dismiss
        EventBus.On("screen_change", function(data)
            local to = data and data.to or ""
            if to == "codex" then
                RedDotManager.Dismiss("codex")
            elseif to == "shop" then
                RedDotManager.Dismiss("shop")
            elseif to == "relationship" then
                RedDotManager.Dismiss("relationship")
            end
        end)

        -- 未结算订单优先恢复；材料已在接单时扣除，不能让玩家返回首页后遗失委托。
        local activeOrder = OrderManager.GetActiveOrder()
        if activeOrder then
            print("[main] Resuming active order: " .. tostring(activeOrder.orderId))
            ScreenRouter.GoTo("forge", { orderId = activeOrder.orderId })
        -- 新存档（首次启动）：如果有待展示剧情，先进入剧情
        elseif StoryManager.HasPendingStory() then
            local chapter, nodeId = StoryManager.GetProgress()
            print("[main] Pending story at " .. tostring(chapter) .. ":" .. tostring(nodeId) .. ", entering story screen")
            ScreenRouter.GoTo("story", { returnTo = "home" })
        else
            ScreenRouter.GoTo("home")
        end
    end)

    print("=== " .. CONFIG.Title .. " Started ===")
end

function Stop()
    GameState.ForceSave()
    EventBus.Clear()
    Timer.Clear()
    Tween.Clear()
    UI.Shutdown()
end

-- ============================================================================
-- 初始化
-- ============================================================================

function InitUI()
    -- 极简水墨武侠主题：深色水墨底、极细描边、柔和阴影
    local INK_SHADOW = {
        { x = 0, y = 3, blur = 10, color = {0, 0, 0, 92} },
    }

    local InkWuxiaTheme = UI.Theme.ExtendTheme(UI.Theme.defaultTheme, {
        colors = {
            primary = {212, 165, 116, 255},       -- #D4A574 鎏金
            primaryHover = {228, 186, 140, 255},
            primaryPressed = {180, 140, 98, 255},
            secondary = {78, 205, 196, 255},       -- #4ECDC4 青铜绿
            secondaryHover = {110, 220, 212, 255},
            secondaryPressed = {60, 180, 172, 255},
            background = {18, 16, 14, 255},        -- #12100E 烟墨
            surface = {26, 26, 46, 255},           -- #1A1A2E 炭黑
            surfaceHover = {42, 36, 30, 255},
            text = {232, 224, 208, 255},           -- #E8E0D0 暖白
            textSecondary = {160, 147, 125, 255},  -- #A0937D 烟灰
            textDisabled = {80, 68, 56, 255},
            border = {61, 43, 31, 255},            -- #3D2B1F 铁褐
            borderFocus = {212, 165, 116, 255},    -- #D4A574 鎏金
            disabled = {42, 36, 30, 255},
            disabledText = {80, 68, 56, 255},
            success = {78, 205, 196, 255},         -- #4ECDC4 青铜绿
            warning = {255, 217, 61, 255},         -- #FFD93D 淬火黄
            error = {233, 69, 96, 255},            -- #E94560 炉火红
            info = {212, 165, 116, 255},
            overlay = {0, 0, 0, 180},
        },
        radius = { sm = 4, md = 6, lg = 10, xl = 14, full = 9999 },
        componentDefaults = { borderRadius = 6 },
        components = {
            Button = { borderWidth = 1, boxShadow = INK_SHADOW },
            TextField = { borderWidth = 1 },
            Card = {
                borderWidth = 1,
                boxShadow = INK_SHADOW,
            },
            Modal = {
                borderWidth = 1,
                boxShadow = INK_SHADOW,
                headerBgColor = {20, 20, 46, 255},
                headerBorderWidth = 2,
                headerFullWidthBorder = true,
                footerBorderWidth = 2,
                footerFullWidthBorder = true,
                contentPadding = 16,
                footerPadding = {10, 16},
            },
            Toast = {
                borderWidth = 1,
                boxShadow = INK_SHADOW,
                accentBarWidth = 4,
                showIcon = false,
            },
            ProgressBar = { height = 10, borderWidth = 1 },
            Badge = { borderWidth = 1 },
            Checkbox = { borderWidth = 1, checkedBgColor = {33, 189, 174, 255} },
            Toggle = { borderWidth = 1, thumbSize = 18 },
            Slider = { borderWidth = 1, trackFillColor = {33, 189, 174, 255}, thumbColor = {33, 189, 174, 255} },
            Tabs = { borderWidth = 1, activeBorderColor = {33, 189, 174, 255} },
        },
    })

    UI.Init({
        theme = InkWuxiaTheme,
        scale = UI.Scale.DESIGN_RESOLUTION(1920, 1080),
    })
end

function CreateUI()
    -- 内容容器：Screen 的挂载区域
    contentContainer_ = UI.Panel {
        id = "content",
        width = "100%",
        height = "100%",
    }

    -- 根面板
    uiRoot_ = UI.Panel {
        id = "root",
        width = "100%",
        height = "100%",
        backgroundColor = "#12100E",
        children = {
            contentContainer_,
        }
    }

    UI.SetRoot(uiRoot_)

    -- 初始化 ScreenRouter
    ScreenRouter.Init(contentContainer_, EventBus)
end

function SubscribeToEvents()
    SubscribeToEvent("Update", "HandleUpdate")
    SubscribeToEvent("KeyDown", "HandleKeyDown")
end

-- ============================================================================
-- Screen 注册
-- ============================================================================

function RegisterScreens()
    ScreenRouter.Register("home", HomeScreen)
    ScreenRouter.Register("orderBoard", OrderBoardScreen)
    ScreenRouter.Register("forge", ForgeScreen)
    ScreenRouter.Register("result", ResultScreen)
    ScreenRouter.Register("upgrade", UpgradeScreen)
    ScreenRouter.Register("story", StoryScreen)
    ScreenRouter.Register("codex", CodexScreen)
    ScreenRouter.Register("settings", SettingsScreen)
    ScreenRouter.Register("shop", ShopScreen)
    ScreenRouter.Register("ending", EndingScreen)
    ScreenRouter.Register("relationship", RelationshipScreen)
    ScreenRouter.Register("weekly", WeeklyScreen)
end

-- ============================================================================
-- 事件处理
-- ============================================================================

---@param eventType string
---@param eventData UpdateEventData
function HandleUpdate(eventType, eventData)
    local dt = eventData["TimeStep"]:GetFloat()

    -- 驱动子系统
    Timer.Update(dt)
    Tween.Update(dt)
    ScreenRouter.Update(dt)
    GameState.Update(dt)
end

---@param eventType string
---@param eventData KeyDownEventData
function HandleKeyDown(eventType, eventData)
    local key = eventData["Key"]:GetInt()

    -- ESC 返回上级
    if key == KEY_ESCAPE then
        local current = ScreenRouter.GetCurrent()
        if current ~= "home" then
            ScreenRouter.GoTo("home")
        end
    end
end
