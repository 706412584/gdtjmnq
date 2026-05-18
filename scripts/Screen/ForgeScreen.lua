-- ============================================================================
-- ForgeScreen - 锻造界面
-- Project Smith / P1-D3
--
-- 承载小游戏调度器 MiniGameRunner 的主界面。
-- 流程:
--   1. 接收 params.orderId, params.order, params.recipe
--   2. 注册并启动小游戏序列
--   3. 驱动 MiniGameRunner.Update
--   4. 所有步骤完成后调用 OrderManager.CompleteOrder
--   5. 跳转 ResultScreen 展示结算
-- ============================================================================

local UI = require("urhox-libs/UI")

local EventBus      = require("Core.EventBus")
local GameState     = require("Core.GameState")
local OrderManager  = require("Core.OrderManager")
local MiniGameRunner = require("MiniGame.MiniGameRunner")
local ScreenRouter  = require("Utils.ScreenRouter")

-- 小游戏模块
local OreSelectGame  = require("MiniGame.OreSelectGame")
local SmeltingGame   = require("MiniGame.SmeltingGame")
local ForgingGame    = require("MiniGame.ForgingGame")
local QuenchingGame  = require("MiniGame.QuenchingGame")
local PolishingGame  = require("MiniGame.PolishingGame")
local AssemblyGame   = require("MiniGame.AssemblyGame")

local ForgeScreen = {}

-- ============================================================================
-- UI 素材路径（武侠水墨风）
-- ============================================================================

local UI_ASSETS = {
    panel_header  = "image/ui/panel_header.png",
    btn_primary   = "image/ui/btn_primary.png",
}

-- ============================================================================
-- 色板
-- ============================================================================

local C = {
    bgPrimary     = { 26,  26,  46,  255 },
    bgSecondary   = { 22,  33,  62,  255 },
    bgCard        = { 30,  40,  68,  255 },
    gold          = { 212, 165, 116, 255 },
    textPrimary   = { 232, 224, 208, 255 },
    textSecondary = { 160, 147, 125, 255 },
    accent        = { 233, 69,  96,  255 },
    success       = { 78,  205, 196, 255 },
    warning       = { 255, 217, 61,  255 },
}

-- ============================================================================
-- 注册小游戏模块（只执行一次）
-- ============================================================================

local gamesRegistered_ = false

local function EnsureGamesRegistered()
    if gamesRegistered_ then return end
    MiniGameRunner.Register("ore_select", OreSelectGame)
    MiniGameRunner.Register("smelting",   SmeltingGame)
    MiniGameRunner.Register("forging",    ForgingGame)
    MiniGameRunner.Register("quenching",  QuenchingGame)
    MiniGameRunner.Register("polishing",  PolishingGame)
    MiniGameRunner.Register("assembly",   AssemblyGame)
    gamesRegistered_ = true
end

-- ============================================================================
-- Screen 接口
-- ============================================================================

--- 创建锻造界面
---@param container table UI 容器
---@param params table { orderId, order, recipe }
---@return table screen
function ForgeScreen.Create(container, params)
    local screen = {}

    -- 获取订单数据
    local orderId = params and params.orderId
    local order   = params and params.order
    local recipe  = params and params.recipe

    if not orderId or not recipe then
        -- 无效参数，返回主界面
        print("[ForgeScreen] ERROR: Missing orderId or recipe in params")
        local errPanel = UI.Panel {
            width = "100%", height = "100%",
            justifyContent = "center", alignItems = "center",
            children = {
                UI.Label { text = "订单数据异常", fontSize = 16, fontColor = C.accent },
                UI.Button {
                    text = "返回工坊",
                    onClick = function() ScreenRouter.GoTo("home") end,
                },
            },
        }
        container:AddChild(errPanel)
        return screen
    end

    -- 确保小游戏已注册
    EnsureGamesRegistered()

    -- ----------------------------------------------------------------
    -- UI 构建
    -- ----------------------------------------------------------------

    -- 小游戏渲染区域
    local gameContainer = UI.Panel {
        id = "gameArea",
        width = "100%",
        flexGrow = 1,
        flexBasis = 0,
        flexShrink = 1,
        backgroundColor = C.bgSecondary,
    }

    -- 进度指示
    local progressLabel = UI.Label {
        text = "准备中...",
        fontSize = 12,
        fontColor = C.textSecondary,
        textAlign = "center",
        width = "100%",
    }

    -- 顶部导航栏
    local topBar = UI.Panel {
        width = "100%",
        flexDirection = "row",
        justifyContent = "space-between",
        alignItems = "center",
        paddingHorizontal = 12,
        paddingVertical = 8,
        backgroundImage = UI_ASSETS.panel_header,
        backgroundFit = "cover",
        children = {
            -- 放弃按钮
            UI.Button {
                text = "放弃",
                fontSize = 12,
                width = 56,
                height = 28,
                backgroundImage = UI_ASSETS.btn_primary,
                backgroundFit = "cover",
                fontColor = C.textPrimary,
                borderRadius = 4,
                onClick = function()
                    MiniGameRunner.Stop()
                    OrderManager.CancelOrder()
                    ScreenRouter.GoTo("home")
                end,
            },
            -- 武器名
            UI.Label {
                text = recipe.name,
                fontSize = 16,
                fontColor = C.gold,
            },
            -- 进度
            progressLabel,
        },
    }

    -- 主面板
    local panel = UI.Panel {
        width = "100%",
        height = "100%",
        flexDirection = "column",
        children = {
            topBar,
            gameContainer,
        },
    }

    container:AddChild(panel)

    -- ----------------------------------------------------------------
    -- 启动小游戏序列
    -- ----------------------------------------------------------------

    local steps = recipe.steps or {}
    local difficulty = 1  -- P1 默认难度

    -- 监听完成事件
    local unsubComplete
    unsubComplete = EventBus.On("all_steps_complete", function(data)
        if data.orderId ~= orderId then return end

        print("[ForgeScreen] All steps complete, calculating quality...")

        -- 转换评分格式（保留 stepType 供 ResultScreen 显示）
        local stepScores = {}
        for i = 1, #data.scores do
            stepScores[i] = {
                stepType = data.scores[i].stepType,
                score = data.scores[i].score,
                rating = data.scores[i].rating,
            }
        end

        -- 完成订单
        local result = OrderManager.CompleteOrder(stepScores, 1)

        -- 跳转结算界面
        if result then
            ScreenRouter.GoTo("result", { result = result })
        else
            print("[ForgeScreen] ERROR: CompleteOrder returned nil")
            ScreenRouter.GoTo("home")
        end
    end)

    -- 监听小游戏切换事件
    local unsubStart
    unsubStart = EventBus.On("minigame_start", function(data)
        if progressLabel then
            progressLabel.text = data.stepIndex .. "/" .. data.totalSteps
        end
    end)

    -- 监听单步完成
    local unsubStepComplete
    unsubStepComplete = EventBus.On("minigame_complete", function(data)
        print("[ForgeScreen] Step complete: " .. data.stepType
            .. " score=" .. string.format("%.2f", data.score)
            .. " rating=" .. data.rating)
    end)

    -- 启动
    MiniGameRunner.Start(orderId, steps, {
        difficulty = difficulty,
        materialTier = 1,
        facilityLevel = 1,
    }, gameContainer)

    -- ----------------------------------------------------------------
    -- Screen 生命周期
    -- ----------------------------------------------------------------

    function screen.Update(dt)
        MiniGameRunner.Update(dt)
    end

    function screen.Destroy()
        MiniGameRunner.Stop()
        if unsubComplete then unsubComplete() end
        if unsubStart then unsubStart() end
        if unsubStepComplete then unsubStepComplete() end
    end

    return screen
end

return ForgeScreen
