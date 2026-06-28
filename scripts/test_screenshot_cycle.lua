-- ============================================================================
-- test_screenshot_cycle.lua - 界面截图验证入口
-- 用途：配合 UrhoXRuntime -graphicssurfaceless 逐屏截图验证渲染效果
--
-- 工作方式：
--   1. Mock clientCloud（headless 无网络）→ 立即返回默认存档
--   2. 初始化 UI / 主题 / 屏幕注册（与 main.lua 一致）
--   3. 按帧序列切换界面，外部通过 -screenshot-frame 指定截哪一帧
--
-- 帧序列（每屏停留 80 帧，约 1.3 秒 @60fps）：
--   Frame 80  → home（主界面）
--   Frame 160 → orderBoard（订单板）
--   Frame 240 → codex（名器图鉴）
--   Frame 320 → shop（商店）
--   Frame 400 → relationship（人物关系）
--   Frame 480 → story（剧情对话）
-- ============================================================================

-- Mock clientCloud（headless 模式下不存在）
clientCloud = clientCloud or {
    Get = function(self, key, cbs)
        -- 模拟空存档，直接调 ok
        if cbs and cbs.ok then
            cbs.ok({}, {})
        end
    end,
    Set = function(self, key, value, cbs)
        if cbs and cbs.ok then cbs.ok() end
    end,
}

-- Mock cjson if missing
cjson = cjson or {
    encode = function(t) return "{}" end,
    decode = function(s) return {} end,
}

-- ============================================================================
-- 以下复制 main.lua 核心初始化逻辑
-- ============================================================================

local UI = require("urhox-libs/UI")

local EventBus      = require("Core.EventBus")
local GameState     = require("Core.GameState")
local Timer         = require("Utils.Timer")
local Tween         = require("Utils.Tween")
local ScreenRouter  = require("Utils.ScreenRouter")

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

local StoryManager     = require("Story.StoryManager")
local RedDotManager    = require("Utils.RedDotManager")

-- ============================================================================

local uiRoot_
local contentContainer_
local frameCount_ = 0

-- 界面切换序列（Lua 帧号，引擎帧偏移约 +60）
-- 每屏停留 50 Lua 帧（约 0.8 秒），确保 UI 完成渲染
local SCREEN_SCHEDULE = {
    { frame = 5,   screen = "home" },
    { frame = 35,  action = "upgrade_popup" },
    { frame = 105, screen = "orderBoard" },
    { frame = 155, screen = "codex" },
    { frame = 205, screen = "shop" },
    { frame = 255, screen = "relationship" },
    { frame = 305, screen = "story",  params = { returnTo = "home" } },
}

function Start()
    math.randomseed(42)

    -- PixelForge 主题初始化（与 main.lua 一致）
    local PIXEL_SHADOW = {
        { x = 1, y = 1, blur = 0, color = {10, 10, 26, 150} },
    }

    local PixelForgeTheme = UI.Theme.ExtendTheme(UI.Theme.defaultTheme, {
        colors = {
            primary = {212, 165, 116, 255},       -- #D4A574 鎏金
            primaryHover = {228, 186, 140, 255},
            primaryPressed = {180, 140, 98, 255},
            secondary = {78, 205, 196, 255},       -- #4ECDC4 青铜绿
            background = {18, 16, 14, 255},        -- #12100E 烟墨
            surface = {26, 26, 46, 255},           -- #1A1A2E 炭黑
            surfaceHover = {42, 36, 30, 255},
            text = {232, 224, 208, 255},           -- #E8E0D0 暖白
            textSecondary = {160, 147, 125, 255},  -- #A0937D 烟灰
            border = {61, 43, 31, 255},            -- #3D2B1F 铁褐
            error = {233, 69, 96, 255},            -- #E94560 炉火红
            success = {78, 205, 196, 255},         -- #4ECDC4 青铜绿
            warning = {255, 217, 61, 255},         -- #FFD93D 淬火黄
            info = {212, 165, 116, 255},
            overlay = {0, 0, 0, 180},
        },
        radius = { sm = 2, md = 3, lg = 4, xl = 6, full = 9999 },
        componentDefaults = { borderRadius = 2 },
        components = {
            Button = { borderWidth = 1, boxShadow = PIXEL_SHADOW },
            Modal = { borderWidth = 1 },
            Toast = { borderWidth = 1 },
            ProgressBar = { height = 10, borderWidth = 1 },
        },
    })

    UI.Init({
        theme = PixelForgeTheme,
        scale = UI.Scale.DESIGN_RESOLUTION(1920, 1080),
    })

    -- UI 容器
    contentContainer_ = UI.Panel { id = "content", width = "100%", height = "100%" }
    uiRoot_ = UI.Panel {
        id = "root", width = "100%", height = "100%",
        backgroundColor = "#12100E",
        children = { contentContainer_ },
    }
    UI.SetRoot(uiRoot_)

    -- 路由 + 屏幕注册
    ScreenRouter.Init(contentContainer_, EventBus)
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

    -- 故事系统
    StoryManager.Init()

    -- 加载存档（mock clientCloud 会立即回调）
    GameState.Load(function(success)
        print("[test] GameState loaded: " .. tostring(success))
        -- 标记剧情已完结，阻止 HomeScreen 自动跳转到 StoryScreen
        GameState.MarkStoryDone()
        RedDotManager.Init()
        -- 初始进入主界面
        ScreenRouter.GoTo("home")
    end)

    SubscribeToEvent("Update", "HandleUpdate")
    print("[test_screenshot_cycle] Started. Schedule: " .. #SCREEN_SCHEDULE .. " screens")
end

function HandleUpdate(eventType, eventData)
    local dt = eventData["TimeStep"]:GetFloat()
    Timer.Update(dt)
    Tween.Update(dt)
    ScreenRouter.Update(dt)
    GameState.Update(dt)

    frameCount_ = frameCount_ + 1

    -- 按序列切换界面
    for i = 1, #SCREEN_SCHEDULE do
        local entry = SCREEN_SCHEDULE[i]
        if frameCount_ == entry.frame then
            if entry.action == "upgrade_popup" then
                print("[test] Frame " .. frameCount_ .. " -> open upgrade popup")
                local UpgradePopup = require("Screen.UpgradePopup")
                UpgradePopup.Open("anvil")
            elseif entry.screen then
                print("[test] Frame " .. frameCount_ .. " -> " .. entry.screen)
                ScreenRouter.GoTo(entry.screen, entry.params)
            end
        end
    end
end
