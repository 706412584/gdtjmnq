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
local SFXManager     = require("Utils.SFXManager")
local ThemedDialog   = require("Utils.ThemedDialog")
local TutorialManager = require("Core.TutorialManager")
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

    -- 获取订单数据；订单恢复时只传 orderId，其余数据从持久化快照重建。
    local orderId = params and params.orderId
    local order   = params and params.order
    local recipe  = params and params.recipe
    local activeOrder = OrderManager.GetActiveOrder()
    if orderId and activeOrder and activeOrder.orderId == orderId then
        order = order or activeOrder.template
        recipe = recipe or activeOrder.recipe
    end

    if not orderId or not recipe then
        print("[ForgeScreen] ERROR: Missing orderId or recipe in params")
        local errPanel = UI.Panel {
            width = "100%", height = "100%",
            justifyContent = "center", alignItems = "center",
            children = {
                ---@diagnostic disable-next-line: param-type-mismatch
                UI.Label { text = "订单数据异常", fontSize = 21, fontColor = "#E94560" },
                UI.Panel {
                    width = 140,
                    height = 48,
                    borderRadius = 10,
                    borderWidth = 1,
                    borderColor = "#D4A574",
                    backgroundColor = "rgba(15,12,10,0.75)",
                    justifyContent = "center",
                    alignItems = "center",
                    onClick = function() ScreenRouter.GoTo("home") end,
                    children = {
                        ---@diagnostic disable-next-line: param-type-mismatch
                        UI.Label {
                            text = "返回工坊",
                            fontSize = 18,
                            fontColor = "#D4A574",
                            textAlign = "center",
                        },
                    },
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
    local backBtn       = root:FindById("plate_3")
    local titleLabel    = root:FindById("tx_6")
    local stepHintLabel = root:FindById("step_hint_label")
    local gameArea      = root:FindById("ph_i")       -- 小游戏主区域
    local weaponIcon    = root:FindById("ph_t")       -- 武器图标区
    local weaponIconText = root:FindById("ph_t_x")    -- 武器图标文字
    local weaponLabel   = root:FindById("tx_y")       -- 武器名称
    local materialLabel = root:FindById("tx_z")       -- 材料信息
    local expectLabel   = root:FindById("tx_10")      -- 客户期望
    local stepProgFill  = root:FindById("sr_13")      -- 步骤进度条填充
    local stepProgText  = root:FindById("tx_14")      -- 步骤进度文字
    local qualityTier   = root:FindById("tx_1n")      -- 品质等级文字
    local qualityFill   = root:FindById("sr_1q")      -- 品质进度条填充
    local qualityText   = root:FindById("tx_1r")      -- 品质评分文字
    local errorText     = root:FindById("tx_1v")      -- 失误容错文字
    local customerNameLabel = root:FindById("customer_name_label")
    local customerDialogueLabel = root:FindById("customer_dialogue_label")
    local orderTierLabel = root:FindById("order_tier_label")

    -- 步骤进度点
    local stageIds = { "stage_7", "stage_8", "stage_9", "stage_a", "stage_b", "stage_c" }
    local stageDots = {}
    for i = 1, #stageIds do
        stageDots[i] = root:FindById(stageIds[i])
    end

    -- ----------------------------------------------------------------
    -- 初始化显示数据
    -- ----------------------------------------------------------------

    local steps = recipe.steps or {}
    local totalSteps = #steps
    local isTutorialOrder = TutorialManager.IsFirstOrder(orderId)
    local orderTierNames = {
        [1] = "寻常委托",
        [2] = "良品委托",
        [3] = "珍品委托",
        [4] = "名器委托",
        [5] = "传世委托",
    }
    local requiredQualityNames = {
        [1] = "良品",
        [2] = "上品",
        [3] = "珍品",
        [4] = "名器",
        [5] = "传世",
    }
    local lineIconText = {
        short_blade = "短\n刃",
        long_sword = "长\n剑",
        heavy_sword = "重\n剑",
        ceremony_blade = "礼\n剑",
    }

    -- 标题
    if titleLabel then
        titleLabel.text = "锻造 · " .. (recipe.name or "未知")
    end
    if stepHintLabel then
        stepHintLabel.text = "委托工序 " .. totalSteps .. " 步 · 稳住节奏，逐步提高成品品质。"
    end

    -- 武器与订单信息
    if weaponLabel then
        weaponLabel.text = recipe.name or "未知武器"
    end
    if weaponIconText then
        weaponIconText.text = lineIconText[recipe.line or ""] or "兵\n器"
    end
    if weaponIcon and recipe.line == "ceremony_blade" then
        weaponIcon.borderColor = "#FFD93D"
    end

    -- 材料信息
    local selectedMaterialTier = (activeOrder and activeOrder.materialTier) or 1
    local materialTierNames = { "粗料", "熟料", "精料", "纹金", "陨材" }
    if materialLabel then
        local materials = recipe.requiredMaterials or {}
        local materialOrder = {
            "ore", "charcoal", "grinding_agent", "wood", "leather",
            "iron", "steel", "jade_dust", "pattern_gold", "meteorite",
        }
        local matNames = {}
        local used = {}
        for i = 1, #materialOrder do
            local key = materialOrder[i]
            local count = materials[key]
            if count then
                matNames[#matNames + 1] = OrderManager.GetMaterialName(key) .. "×" .. count
                used[key] = true
            end
        end
        for key, count in pairs(materials) do
            if not used[key] then
                matNames[#matNames + 1] = OrderManager.GetMaterialName(key) .. "×" .. count
            end
        end
        materialLabel.text = "材料 · " .. (materialTierNames[selectedMaterialTier] or "未知")
            .. " T" .. selectedMaterialTier .. " · "
            .. (#matNames > 0 and table.concat(matNames, "  ") or "无")
    end

    -- 客户与对话
    local tier = (order and order.tier) or 1
    if customerNameLabel and order then
        customerNameLabel.text = order.customerName or "委托人"
    end
    if customerDialogueLabel and order then
        customerDialogueLabel.text = "「" .. (order.dialogue or "请按委托要求完成锻造。") .. "」"
    end
    if orderTierLabel then
        orderTierLabel.text = orderTierNames[tier] or ("T" .. tostring(tier) .. " 委托")
    end

    -- 客户期望
    if expectLabel and order then
        local tierName = order.minQualityName or requiredQualityNames[order.requiredMaterialTier or 1] or "良品"
        expectLabel.text = "客户期望 · " .. tierName
    end

    -- 隐藏超出实际步骤数的进度点
    for i = 1, #stageDots do
        if stageDots[i] then
            stageDots[i].visible = (i <= totalSteps)
        end
    end

    -- 初始化品质显示
    if qualityTier then qualityTier.text = "品质 · 评估中" end
    if qualityText then qualityText.text = "品质评分 0 / 100" end
    if qualityFill then qualityFill.width = "0%" end

    -- 初始化步骤进度
    if stepProgText then stepProgText.text = "完成度 0%" end
    if stepProgFill then stepProgFill.width = "0%" end

    -- 初始化失误容错
    local maxErrors = 3
    local currentErrors = 0
    if errorText then
        errorText.text = "失误容错 · " .. currentErrors .. "/" .. maxErrors
    end

    -- ----------------------------------------------------------------
    -- 小游戏容器
    -- ----------------------------------------------------------------
    ---@diagnostic disable-next-line: assign-type-mismatch
    local gameContainer = gameArea

    -- ----------------------------------------------------------------
    -- 按钮事件
    -- ----------------------------------------------------------------

    if backBtn then
        backBtn.props.onClick = function()
            SFXManager.Play(SFXManager.SFX.UI_TAP, 0.4)
            -- 二次确认：防误触导致丢失进度
            ThemedDialog.Confirm({
                title = "放弃锻造",
                message = "当前委托将取消，已消耗的材料将退还。确认退出？",
                confirmText = "确认退出",
                cancelText = "继续锻造",
                onConfirm = function()
                    MiniGameRunner.Stop()
                    OrderManager.CancelOrder()
                    ScreenRouter.GoTo("home")
                end,
            })
        end
    end

    -- ----------------------------------------------------------------
    -- 启动小游戏序列
    -- ----------------------------------------------------------------

    -- 难度随订单 tier 缩放，让高难订单的高奖励名副其实。
    -- 小游戏公式按 difficulty 1~3 设计，故把订单 tier(1~5) 映射到 1~3：
    --   T1→1(易)  T2→2(中)  T3→2(中)  T4→3(难)  T5→3(难)
    local difficulty = (tier <= 1 and 1) or (tier >= 4 and 3) or 2
    local currentStepIdx = 0

    -- 辅助：更新步骤进度点高亮
    local function UpdateStageDots(idx)
        for i = 1, #stageDots do
            if stageDots[i] then
                if i < idx then
                    stageDots[i].backgroundColor = "#4ECDC4"
                    stageDots[i].borderColor = "#4ECDC4"
                elseif i == idx then
                    stageDots[i].backgroundColor = "#C96A2B"
                    stageDots[i].borderColor = "#FFD93D"
                else
                    stageDots[i].backgroundColor = "#5a4a3a"
                    stageDots[i].borderColor = "rgba(212,165,116,0.45)"
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
        local pct = 0
        if totalSteps > 0 then
            pct = math.floor((currentStepIdx - 1) / totalSteps * 100)
        end
        if stepProgText then stepProgText.text = "完成度 " .. pct .. "%" end
        if stepProgFill then
            stepProgFill.width = tostring(pct) .. "%"
        end
        if stepHintLabel then
            if isTutorialOrder then
                TutorialManager.Advance(data.stepType)
                stepHintLabel.text = "首单指引 · " .. TutorialManager.GetMessage(data.stepType)
            else
                local challengeHint = data.modifierName and ("挑战 · " .. data.modifierName .. "：" .. (data.modifierDescription or "")) or ""
                local suddenHint = data.suddenEvent and "突发状况已出现，注意节奏。" or "按提示完成操作。"
                stepHintLabel.text = "当前工序 · " .. stepName .. "。" .. challengeHint .. suddenHint
            end
        end
    end)

    -- 监听单步完成
    local unsubStepComplete
    unsubStepComplete = EventBus.On("minigame_complete", function(data)
        print("[ForgeScreen] Step complete: " .. (data.stepType or "?")
            .. " score=" .. string.format("%.2f", data.score or 0)
            .. " rating=" .. (data.rating or "?"))

        OrderManager.UpdateActiveOrderProgress(MiniGameRunner.GetCompletedScores())

        -- 更新品质评分（累计平均）
        local avgScore = data.avgScore or data.score or 0
        local scorePct = math.floor(avgScore * 100)
        if qualityText then
            qualityText.text = "品质评分 " .. scorePct .. " / 100"
        end
        if qualityTier then
            local ratingName = data.rating or "Good"
            local ratingText = ratingName == "Perfect" and "极佳"
                or ratingName == "Great" and "优秀"
                or ratingName == "Good" and "稳定"
                or "需补救"
            qualityTier.text = "品质 · " .. ratingText
        end
        if qualityFill then
            qualityFill.width = tostring(math.max(0, math.min(100, scorePct))) .. "%"
        end
        local completedPct = 0
        if totalSteps > 0 then
            completedPct = math.floor(currentStepIdx / totalSteps * 100)
        end
        if stepProgText then stepProgText.text = "完成度 " .. completedPct .. "%" end
        if stepProgFill then stepProgFill.width = tostring(completedPct) .. "%" end
    end)

    local freeRetryUsed = OrderManager.HasUsedFreeRetry()
    local unsubFailed
    unsubFailed = EventBus.On("minigame_failed", function(data)
        if not MiniGameRunner.IsPaused() then return end
        local stepName = STEP_NAMES[data.stepType] or "当前工序"
        local canFreeRetry = not freeRetryUsed
        ThemedDialog.Confirm({
            title = "工序失手",
            message = isTutorialOrder
                and ("首单可以免费重试一次。" .. TutorialManager.GetMessage(data.stepType))
                or (canFreeRetry
                    and (stepName .. "未达标。可免费重试一次，或带着瑕疵继续锻造。")
                    or (stepName .. "未达标。可带着瑕疵继续锻造，或放弃当前委托。")),
            confirmText = canFreeRetry and "免费重试" or "带瑕继续",
            cancelText = canFreeRetry and "带瑕继续" or "放弃委托",
            onConfirm = function()
                if canFreeRetry and OrderManager.UseFreeRetry() then
                    freeRetryUsed = true
                    MiniGameRunner.RetryCurrentStep()
                else
                    MiniGameRunner.ContinueWithFlaw()
                    OrderManager.UpdateActiveOrderProgress(MiniGameRunner.GetCompletedScores())
                end
            end,
            onCancel = function()
                if canFreeRetry then
                    MiniGameRunner.ContinueWithFlaw()
                    OrderManager.UpdateActiveOrderProgress(MiniGameRunner.GetCompletedScores())
                else
                    MiniGameRunner.Stop()
                    OrderManager.CancelOrder()
                    ScreenRouter.GoTo("home")
                end
            end,
            danger = not canFreeRetry,
        })
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

        -- 实际材料品质由活跃订单快照锁定，结算层不接收页面参数。
        local result = OrderManager.CompleteOrder(stepScores)

        -- 跳转结算界面
        if result then
            ScreenRouter.GoTo("result", { result = result })
        else
            print("[ForgeScreen] ERROR: CompleteOrder returned nil")
            ScreenRouter.GoTo("home")
        end
    end)

    local recoveredScores = (activeOrder and activeOrder.stepScores) or {}
    local recoveredStepCount = #recoveredScores
    if recoveredStepCount > 0 then
        currentStepIdx = recoveredStepCount
        UpdateStageDots(recoveredStepCount + 1)
        local restoredPct = math.floor(recoveredStepCount / math.max(1, totalSteps) * 100)
        if stepProgText then stepProgText.text = "完成度 " .. restoredPct .. "%" end
        if stepProgFill then stepProgFill.width = tostring(restoredPct) .. "%" end
        if stepHintLabel then
            stepHintLabel.text = "已恢复前 " .. recoveredStepCount .. " 道工序，继续完成委托。"
        end
    end

    -- 每道工序只读取对应设施：升级直接改变该小游戏的容错窗口或时限。
    local facilityLevels = {
        furnace = GameState.GetFacilityLevel("furnace"),
        anvil = GameState.GetFacilityLevel("anvil"),
        quench_pool = GameState.GetFacilityLevel("quench_pool"),
        grinder = GameState.GetFacilityLevel("grinder"),
    }

    -- 启动
    MiniGameRunner.Start(orderId, steps, {
        difficulty     = difficulty,
        materialTier   = selectedMaterialTier,
        facilityLevels = facilityLevels,
        modifier       = activeOrder and activeOrder.modifier or nil,
        completedScores = recoveredScores,
    }, gameContainer) ---@diagnostic disable-line: param-type-mismatch

    -- ----------------------------------------------------------------
    -- Screen 生命周期
    -- ----------------------------------------------------------------

    function screen.Update(dt)
        MiniGameRunner.Update(dt)
    end

    function screen.Destroy()
        MiniGameRunner.Stop()
        -- 返回订单板、按 ESC 或关闭页面时，首单教程回到接单节点，材料与订单照常按取消规则处理。
        if isTutorialOrder and OrderManager.GetActiveOrder() then
            TutorialManager.ResetForFirstOrder()
        end
        -- 安全网：任何非正常完成的离开路径（如 ESC 直接返回主界面）都要取消活跃订单，
        -- 否则 activeOrder_ 残留会导致订单板全部接单按钮被锁死。
        -- 正常完单时 CompleteOrder 已清空 activeOrder_，此处 CancelOrder 为 no-op，不会重复退料。
        OrderManager.CancelOrder()
        if unsubComplete then unsubComplete() end
        if unsubFailed then unsubFailed() end
        if unsubStart then unsubStart() end
        if unsubStepComplete then unsubStepComplete() end
    end

    return screen
end

return ForgeScreen
