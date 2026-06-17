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

-- Audio
local BGMManager       = require("Utils.BGMManager")

-- Story system
local StoryManager     = require("Story.StoryManager")

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
    UI.Init({
        fonts = {
            { family = "sans", weights = {
                normal = "Fonts/MiSans-Regular.ttf",
            } }
        },
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
        backgroundColor = "#1A1A2E",
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
