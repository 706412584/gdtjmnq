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
local Timer         = require("Utils.Timer")
local Tween         = require("Utils.Tween")
local ScreenRouter  = require("Utils.ScreenRouter")

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

    -- 5. 初始化故事系统
    StoryManager.Init()

    -- 6. 异步加载存档，完成后跳转主界面（或剧情界面）
    GameState.Load(function(success)
        print("[main] GameState loaded, success=" .. tostring(success))

        -- 应用已保存的音量设置
        local settings = GameState.GetSettings()
        if settings then
            audio:SetMasterGain(SOUND_EFFECT, (settings.sfxVolume or 80) / 100)
            audio:SetMasterGain(SOUND_MUSIC, (settings.musicVolume or 60) / 100)
        end

        -- 初始化 BGM 自动切换（监听 screen_change 事件）
        BGMManager.Init()

        -- 初始化红点系统（依赖 GameState 已加载）
        RedDotManager.Init()

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

        -- 新存档（首次启动）：如果有待展示剧情，先进入剧情
        if StoryManager.HasPendingStory() then
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
    -- PixelForge 像素风主题
    -- Button shadow: 3px hard drop + top-left bevel
    local PIXEL_SHADOW = {
        { x = 3, y = 3, blur = 0, color = {10, 10, 26, 204} },
        { x = -1, y = -1, blur = 0, color = {255, 255, 255, 48} },
    }

    local PixelForgeTheme = UI.Theme.ExtendTheme(UI.Theme.defaultTheme, {
        fonts = {
            { family = "sans", weights = {
                normal = "Fonts/FusionPixel-12px-Prop-zh_hans.ttf",
                bold = "Fonts/FusionPixel-12px-Prop-zh_hans-Bold.ttf",
            }},
            { family = "mono", weights = {
                normal = "Fonts/FusionPixel-12px-Mono-zh_hans.ttf",
            }},
        },
        colors = {
            primary = {33, 189, 174, 255},
            primaryHover = {61, 208, 193, 255},
            primaryPressed = {25, 168, 153, 255},
            secondary = {108, 92, 231, 255},
            secondaryHover = {133, 119, 237, 255},
            secondaryPressed = {90, 75, 214, 255},
            background = {15, 15, 35, 255},
            surface = {27, 27, 58, 255},
            surfaceHover = {37, 37, 80, 255},
            text = {240, 240, 240, 255},
            textSecondary = {160, 160, 192, 255},
            textDisabled = {80, 80, 112, 255},
            border = {58, 58, 106, 255},
            borderFocus = {33, 189, 174, 255},
            disabled = {42, 42, 74, 255},
            disabledText = {80, 80, 112, 255},
            success = {80, 200, 120, 255},
            warning = {255, 217, 61, 255},
            error = {255, 71, 87, 255},
            info = {69, 170, 242, 255},
            overlay = {0, 0, 0, 180},
        },
        radius = { sm = 0, md = 0, lg = 0, xl = 0, full = 0 },
        componentDefaults = { borderRadius = 0 },
        components = {
            Button = { borderWidth = 2, boxShadow = PIXEL_SHADOW },
            TextField = { borderWidth = 2 },
            Card = {
                borderWidth = 2,
                boxShadow = {{ x = 4, y = 4, blur = 0, color = {10, 10, 26, 204} }},
            },
            Modal = {
                borderWidth = 2,
                boxShadow = {{ x = 4, y = 4, blur = 0, color = {0, 0, 0, 204} }},
                headerBgColor = {20, 20, 46, 255},
                headerBorderWidth = 2,
                headerFullWidthBorder = true,
                footerBorderWidth = 2,
                footerFullWidthBorder = true,
                contentPadding = 16,
                footerPadding = {10, 16},
            },
            Toast = {
                borderWidth = 2,
                boxShadow = {{ x = 3, y = 3, blur = 0, color = {10, 10, 26, 204} }},
                accentBarWidth = 4,
                showIcon = false,
            },
            ProgressBar = { height = 16, borderWidth = 2 },
            Badge = { borderWidth = 1 },
            Checkbox = { borderWidth = 2, checkedBgColor = {33, 189, 174, 255} },
            Toggle = { borderWidth = 2, thumbSize = 18 },
            Slider = { borderWidth = 1, trackFillColor = {33, 189, 174, 255}, thumbColor = {33, 189, 174, 255} },
            Tabs = { borderWidth = 2, activeBorderColor = {33, 189, 174, 255} },
        },
    })

    UI.Init({
        theme = PixelForgeTheme,
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
        backgroundColor = "#0F0F23",
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
