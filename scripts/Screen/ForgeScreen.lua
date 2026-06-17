-- ============================================================================
-- ForgeScreen - 锻造界面（Layout 迁移版）
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

local EventBus       = require("Core.EventBus")
local GameState      = require("Core.GameState")
local OrderManager   = require("Core.OrderManager")
local MiniGameRunner = require("MiniGame.MiniGameRunner")
local ScreenRouter   = require("Utils.ScreenRouter")
local BackButton     = require("Utils.BackButton")
local Layout         = require("ui_ForgeScreen_锻造界面")

-- 小游戏模块
local OreSelectGame  = require("MiniGame.OreSelectGame")
local SmeltingGame   = require("MiniGame.SmeltingGame")
local ForgingGame    = require("MiniGame.ForgingGame")
local QuenchingGame  = require("MiniGame.QuenchingGame")
local PolishingGame  = require("MiniGame.PolishingGame")
local AssemblyGame   = require("MiniGame.AssemblyGame")

local ForgeScreen = {}

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
-- 步骤名映射
-- ============================================================================

local STEP_NAMES = {
    ore_select = "选矿",
    smelting   = "熔炼",
    forging    = "锻打",
    quenching  = "淬火",
    polishing  = "研磨",
    assembly   = "组装",
}

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
        print("[ForgeScreen] ERROR: Missing orderId or recipe in params")
        local errPanel = UI.Panel {
            width = "100%", height = "100%",
            justifyContent = "center", alignItems = "center",
            children = {
                ---@diagnostic disable-next-line: param-type-mismatch
                UI.Label { text = "订单数据异常", fontSize = 16, fontColor = "#E94560" },
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
    -- 构建布局
    -- ----------------------------------------------------------------

    local root = Layout.Build()
    container:AddChild(root)

    -- 绑定关键元素
    local backBtn      = root:FindById("plate_3")
    local titleLabel   = root:FindById("tx_6")
    local gameArea     = root:FindById("ph_i")       -- 小游戏主区域
    local weaponIcon   = root:FindById("ph_t")       -- 武器图标区
    local weaponLabel  = root:FindById("tx_y")       -- 武器名称
    local materialLabel = root:FindById("tx_z")      -- 材料信息
    local expectLabel  = root:FindById("tx_10")      -- 客户期望
    local stepProgFill = root:FindById("sr_13")      -- 步骤进度条填充
    local stepProgText = root:FindById("tx_14")      -- 步骤进度文字
    local beatTitle    = root:FindById("tx_1b")      -- 节拍区标题
    local hammerBtn    = root:FindById("plate_1h")   -- 锤按钮
    local hammerHint   = root:FindById("tx_1k")      -- 按住提示
    local qualityTier  = root:FindById("tx_1n")      -- 品质等级文字
    local qualityFill  = root:FindById("sr_1q")      -- 品质进度条填充
    local qualityText  = root:FindById("tx_1r")      -- 品质评分文字
    local errorText    = root:FindById("tx_1v")      -- 失误容错文字
    local pauseBtn     = root:FindById("plate_1w")   -- 暂停按钮
    local itemBtn      = root:FindById("plate_1z")   -- 道具按钮

    -- 步骤进度点
    local stageIds = { "stage_7", "stage_8", "stage_9", "stage_a", "stage_b" }
    local stageDots = {}
    for i = 1, #stageIds do
        stageDots[i] = root:FindById(stageIds[i])
    end

    -- 失误心
    local heartIds = { "heart_1s", "heart_1t", "heart_1u" }
    local hearts = {}
    for i = 1, #heartIds do
        hearts[i] = root:FindById(heartIds[i])
    end

    -- 节拍点
    local beatIds = { "beat_1c", "beat_1d", "beat_1e", "beat_1f", "beat_1g" }
    local beats = {}
    for i = 1, #beatIds do
        beats[i] = root:FindById(beatIds[i])
    end

    -- ----------------------------------------------------------------
    -- 初始化显示数据
    -- ----------------------------------------------------------------

    local steps = recipe.steps or {}
    local totalSteps = #steps

    -- 标题
    if titleLabel then
        titleLabel.text = "锻造 · " .. (recipe.name or "未知")
    end

    -- 武器名称
    if weaponLabel then
        weaponLabel.text = recipe.name or "未知武器"
    end

    -- 材料信息
    if materialLabel then
        local mats = recipe.materials or {}
        local matNames = {}
        for i = 1, #mats do
            matNames[i] = mats[i].name or mats[i].id or "?"
        end
        materialLabel.text = "材料 · " .. table.concat(matNames, " + ")
    end

    -- 客户期望
    if expectLabel and order then
        local tierName = order.minQualityName or "良品"
        expectLabel.text = "客户期望 · " .. tierName
    end

    -- 隐藏超出实际步骤数的进度点
    for i = 1, #stageDots do
        if stageDots[i] then
            stageDots[i].visible = (i <= totalSteps)
        end
    end

    -- 隐藏暂时不需要的节拍区和锤按钮（由小游戏模块自行管理）
    -- 布局中的这些元素仅作为视觉参考，实际交互由小游戏渲染
    if beatTitle then beatTitle.visible = false end
    if hammerBtn then hammerBtn.visible = false end
    if hammerHint then hammerHint.visible = false end
    for i = 1, #beats do
        if beats[i] then beats[i].visible = false end
    end

    -- 初始化品质显示
    if qualityTier then qualityTier.text = "品质 · 评估中" end
    if qualityText then qualityText.text = "品质评分 0 / 100" end
    if qualityFill then qualityFill.width = 0 end

    -- 初始化步骤进度
    if stepProgText then stepProgText.text = "完成度 0%" end
    if stepProgFill then stepProgFill.width = 0 end

    -- 初始化失误容错
    local maxErrors = 3
    local currentErrors = 0
    if errorText then
        errorText.text = "失误容错 · " .. currentErrors .. "/" .. maxErrors
    end

    -- ----------------------------------------------------------------
    -- 小游戏容器（覆盖在 ph_i 区域上方）
    -- ----------------------------------------------------------------
    -- 隐藏背景遮罩文字，让小游戏模块在此区域渲染
    ---@diagnostic disable-next-line: assign-type-mismatch
    local gameContainer = gameArea  -- 小游戏直接渲染到 ph_i 区域

    -- ----------------------------------------------------------------
    -- 按钮事件
    -- ----------------------------------------------------------------

    BackButton.Setup(root, function()
        MiniGameRunner.Stop()
        OrderManager.CancelOrder()
        ScreenRouter.GoTo("home")
    end)

    -- 暂停 / 道具面板功能未实现，隐藏避免误导玩家
    if pauseBtn then pauseBtn.visible = false end
    if itemBtn then itemBtn.visible = false end

    -- ----------------------------------------------------------------
    -- 启动小游戏序列
    -- ----------------------------------------------------------------

    -- 难度随订单 tier 缩放，让高难订单的高奖励名副其实。
    -- 小游戏公式按 difficulty 1~3 设计，故把订单 tier(1~5) 映射到 1~3：
    --   T1→1(易)  T2→2(中)  T3→2(中)  T4→3(难)  T5→3(难)
    local tier = (order and order.tier) or 1
    local difficulty = (tier <= 1 and 1) or (tier >= 4 and 3) or 2
    local currentStepIdx = 0

    -- 辅助：更新步骤进度点高亮
    local function UpdateStageDots(idx)
        for i = 1, #stageDots do
            if stageDots[i] then
                if i < idx then
                    stageDots[i].backgroundColor = "#4ECDC4"  -- 已完成：青铜绿
                elseif i == idx then
                    stageDots[i].backgroundColor = "#C96A2B"  -- 当前：炉火橙
                else
                    stageDots[i].backgroundColor = "#5a4a3a"  -- 未达：默认深色
                end
            end
        end
    end

    -- 监听小游戏切换事件
    local unsubStart
    unsubStart = EventBus.On("minigame_start", function(data)
        currentStepIdx = data.stepIndex or 0
        local stepName = STEP_NAMES[data.stepType] or data.stepType or ""

        -- 更新标题
        if titleLabel then
            titleLabel.text = "锻造 · 步骤 [" .. currentStepIdx .. "/" .. totalSteps .. "] " .. stepName
        end

        -- 更新进度点
        UpdateStageDots(currentStepIdx)

        -- 更新步骤进度条
        local pct = math.floor((currentStepIdx - 1) / totalSteps * 100)
        if stepProgText then stepProgText.text = "完成度 " .. pct .. "%" end
        if stepProgFill then
            local maxWidth = 170  -- 布局中步骤进度条最大宽度约170
            stepProgFill.width = math.floor(pct / 100 * maxWidth)
        end
    end)

    -- 监听单步完成
    local unsubStepComplete
    unsubStepComplete = EventBus.On("minigame_complete", function(data)
        print("[ForgeScreen] Step complete: " .. (data.stepType or "?")
            .. " score=" .. string.format("%.2f", data.score or 0)
            .. " rating=" .. (data.rating or "?"))

        -- 更新品质评分（累计平均）
        local avgScore = data.avgScore or data.score or 0
        local scorePct = math.floor(avgScore * 100)
        if qualityText then
            qualityText.text = "品质评分 " .. scorePct .. " / 100"
        end
        if qualityFill then
            local maxWidth = 908  -- 布局中品质进度条最大宽度
            qualityFill.width = math.floor(avgScore * maxWidth)
        end
    end)

    -- 监听完成事件
    local unsubComplete
    unsubComplete = EventBus.On("all_steps_complete", function(data)
        if data.orderId ~= orderId then return end

        print("[ForgeScreen] All steps complete, calculating quality...")

        -- 转换评分格式
        local stepScores = {}
        for i = 1, #data.scores do
            stepScores[i] = {
                stepType = data.scores[i].stepType,
                score    = data.scores[i].score,
                rating   = data.scores[i].rating,
            }
        end

        -- 完成订单
        -- 不传 usedMaterialTier（=nil），OrderManager 会按订单 requiredMaterialTier 结算，
        -- 避免无材料选择系统时 T2+ 订单被材料等级失配惩罚（matCoeff 0.9 × matchCoeff 0.9）
        local result = OrderManager.CompleteOrder(stepScores, nil)

        -- 跳转结算界面
        if result then
            ScreenRouter.GoTo("result", { result = result })
        else
            print("[ForgeScreen] ERROR: CompleteOrder returned nil")
            ScreenRouter.GoTo("home")
        end
    end)

    -- 启动
    MiniGameRunner.Start(orderId, steps, {
        difficulty     = difficulty,
        materialTier   = 1,
        facilityLevel  = 1,
    }, gameContainer) ---@diagnostic disable-line: param-type-mismatch

    -- ----------------------------------------------------------------
    -- Screen 生命周期
    -- ----------------------------------------------------------------

    function screen.Update(dt)
        MiniGameRunner.Update(dt)
    end

    function screen.Destroy()
        MiniGameRunner.Stop()
        -- 安全网：任何非正常完成的离开路径（如 ESC 直接返回主界面）都要取消活跃订单，
        -- 否则 activeOrder_ 残留会导致订单板全部接单按钮被锁死。
        -- 正常完单时 CompleteOrder 已清空 activeOrder_，此处 CancelOrder 为 no-op，不会重复退料。
        OrderManager.CancelOrder()
        if unsubComplete then unsubComplete() end
        if unsubStart then unsubStart() end
        if unsubStepComplete then unsubStepComplete() end
    end

    return screen
end

return ForgeScreen
