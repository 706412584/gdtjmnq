---@diagnostic disable: assign-type-mismatch
-- ============================================================================
-- MiniGameRunner - 小游戏调度器
-- Project Smith / P1-C1
--
-- 按订单步骤列表依次运行小游戏模块。
-- 通过 EventBus 通知外部系统小游戏进度和完成状态。
--
-- 使用方式:
--   MiniGameRunner.Start(orderId, steps, config, container)
--   -- 在 HandleUpdate 中: MiniGameRunner.Update(dt)
--   -- 在输入事件中: MiniGameRunner.OnTouchStart(x, y) 等
-- ============================================================================

local EventBus          = require("Core.EventBus")
local ChallengeModifier = require("Core.ChallengeModifier")

local MiniGameRunner = {}

-- 已注册的小游戏类型 -> 模块（含 :new() 方法的原型表）
---@type table<string, table>
local registry_ = {}

-- 当前调度状态
---@type table|nil 当前运行的小游戏实例
local currentGame_ = nil

---@type string|nil 当前步骤类型
local currentStepType_ = nil

---@type string[]|nil 步骤列表
local steps_ = nil

---@type number 当前步骤索引（1-based）
local stepIndex_ = 0

---@type table[] 各步骤评分结果
local scores_ = {}

---@type string|nil 当前订单 ID
local orderId_ = nil

---@type table|nil 基础配置（difficulty, materialTier, facilityLevels）
local baseConfig_ = nil

---@type table|nil UI 容器
local container_ = nil

---@type boolean 是否正在运行
local running_ = false

---@type boolean 是否暂停当前小游戏（用于失败补救弹窗）
local paused_ = false

---@type table|nil 需要玩家决定的失败结果
local pendingFailure_ = nil

---@type table|nil 当前订单的挑战修饰符
local modifier_ = nil

-- 步骤间过渡延迟（秒），让玩家看到评分反馈
local TRANSITION_DELAY = 1.5
---@type number 过渡倒计时
local transitionTimer_ = 0
---@type boolean 是否处于过渡等待状态
local waitingTransition_ = false

-- ============================================================================
-- 注册 / 查询
-- ============================================================================

--- 注册一种小游戏类型
---@param stepType string 步骤类型名称（如 "ore_select", "forging", "polishing"）
---@param gameClass table 小游戏类（含 :new() 方法的原型表）
function MiniGameRunner.Register(stepType, gameClass)
    registry_[stepType] = gameClass
    print("[MiniGameRunner] Registered: " .. stepType)
end

--- 检查是否有对应的小游戏类型
---@param stepType string
---@return boolean
function MiniGameRunner.HasGame(stepType)
    return registry_[stepType] ~= nil
end

-- ============================================================================
-- 调度控制
-- ============================================================================

--- 开始执行一系列小游戏
---@param orderId string 订单 ID
---@param steps string[] 步骤类型列表（如 {"ore_select", "forging", "polishing"}）
---@param config table { difficulty:number, materialTier:number, facilityLevels:table|nil, modifier:table|nil, completedScores:table[]|nil }
---@param uiContainer table UI 容器控件
function MiniGameRunner.Start(orderId, steps, config, uiContainer)
    if running_ then
        print("[MiniGameRunner] WARNING: Already running, stopping previous")
        MiniGameRunner.Stop()
    end

    orderId_ = orderId
    steps_ = steps
    baseConfig_ = config
    container_ = uiContainer
    scores_ = config.completedScores or {}
    stepIndex_ = #scores_
    running_ = true
    paused_ = false
    pendingFailure_ = nil
    waitingTransition_ = false
    transitionTimer_ = 0
    modifier_ = config.modifier or nil

    local modInfo = modifier_ and (" [" .. modifier_.name .. "]") or ""
    print("[MiniGameRunner] Starting order: " .. orderId .. " (" .. #steps .. " steps)" .. modInfo)

    -- 启动第一个小游戏
    MiniGameRunner._NextStep()
end

--- 停止当前调度
function MiniGameRunner.Stop()
    if currentGame_ then
        currentGame_:cleanup()
        currentGame_ = nil
    end
    currentStepType_ = nil
    running_ = false
    paused_ = false
    pendingFailure_ = nil
    waitingTransition_ = false
    transitionTimer_ = 0
    modifier_ = nil
end

--- 是否正在运行
---@return boolean
function MiniGameRunner.IsRunning()
    return running_
end

function MiniGameRunner.SetPaused(paused)
    paused_ = paused == true
end

---@return boolean
function MiniGameRunner.IsPaused()
    return paused_
end

---@return table|nil
function MiniGameRunner.GetPendingFailure()
    return pendingFailure_
end

--- 放弃当前失败工序，以瑕疵记录继续锻造。
function MiniGameRunner.ContinueWithFlaw()
    if not pendingFailure_ then return end
    local result = pendingFailure_
    scores_[#scores_ + 1] = result
    pendingFailure_ = nil
    paused_ = false

    local avgScore = 0
    for i = 1, #scores_ do
        avgScore = avgScore + (scores_[i].score or 0)
    end
    avgScore = avgScore / #scores_
    EventBus.Emit("minigame_complete", {
        stepType = result.stepType,
        score = result.score,
        avgScore = avgScore,
        rating = result.rating,
        flawed = true,
    })

    waitingTransition_ = true
    transitionTimer_ = TRANSITION_DELAY
end

--- 重试当前小游戏，不影响已经完成的前序工序。
function MiniGameRunner.RetryCurrentStep()
    if not running_ or not currentStepType_ then return end
    paused_ = false
    pendingFailure_ = nil
    waitingTransition_ = false
    transitionTimer_ = 0
    stepIndex_ = stepIndex_ - 1
    MiniGameRunner._NextStep()
end

--- 获取当前进度
---@return number currentStep, number totalSteps
function MiniGameRunner.GetProgress()
    if not steps_ then return 0, 0 end
    return stepIndex_, #steps_
end

--- 获取已完成步骤评分（用于持久化恢复）。
---@return table[]
function MiniGameRunner.GetCompletedScores()
    return scores_
end

--- 获取当前步骤类型
---@return string|nil
function MiniGameRunner.GetCurrentStepType()
    return currentStepType_
end

--- 获取当前修饰符（UI 展示用）
---@return table|nil
function MiniGameRunner.GetModifier()
    return modifier_
end

-- ============================================================================
-- 内部方法
-- ============================================================================

--- 推进到下一个步骤
function MiniGameRunner._NextStep()
    -- 清理上一个小游戏
    if currentGame_ then
        currentGame_:cleanup()
        currentGame_ = nil
    end

    -- 清理容器
    if container_ then
        container_:ClearChildren()
    end

    stepIndex_ = stepIndex_ + 1

    -- 检查是否全部完成
    if stepIndex_ > #steps_ then
        MiniGameRunner._AllComplete()
        return
    end

    currentStepType_ = steps_[stepIndex_]
    local gameClass = registry_[currentStepType_]

    if not gameClass then
        -- 该步骤类型尚未注册，跳过并给默认分数
        print("[MiniGameRunner] WARNING: No game registered for step: " .. currentStepType_ .. ", skipping")
        scores_[#scores_ + 1] = { stepType = currentStepType_, score = 0.5, rating = "Good" }
        EventBus.Emit("minigame_complete", {
            stepType = currentStepType_,
            score = 0.5,
            rating = "Good",
        })
        MiniGameRunner._NextStep()
        return
    end

    -- 创建小游戏实例
    currentGame_ = gameClass:new()

    local facilityIdByStep = {
        smelting = "furnace",
        forging = "anvil",
        quenching = "quench_pool",
        polishing = "grinder",
    }
    local facilityId = facilityIdByStep[currentStepType_]

    -- 构建初始化配置
    local gameConfig = {
        difficulty = baseConfig_.difficulty or 1,
        materialTier = baseConfig_.materialTier or 1,
        facilityLevel = facilityId and ((baseConfig_.facilityLevels or {})[facilityId] or 1) or 1,
        container = container_,
        stepIndex = stepIndex_,
        totalSteps = #steps_,
    }

    -- 应用挑战修饰符参数到小游戏配置
    if modifier_ then
        gameConfig.modifier = modifier_
        if modifier_.id == "time_limit" and modifier_.params then
            gameConfig.timeMultiplier = modifier_.params.timeMultiplier or 0.7
        end
        if modifier_.id == "one_touch" and modifier_.params then
            gameConfig.operationMultiplier = modifier_.params.touchMultiplier or 0.5
        end
        if modifier_.id == "material_cap" and modifier_.params then
            local reduction = modifier_.params.tierReduction or 1
            gameConfig.materialTier = math.max(1, gameConfig.materialTier - reduction)
        end
    end

    -- 突发事件检测
    local suddenEvent = ChallengeModifier.RollSuddenEvent(modifier_)
    if suddenEvent then
        gameConfig.suddenEvent = suddenEvent
        if suddenEvent == "wind_gust" then
            gameConfig.operationMultiplier = (gameConfig.operationMultiplier or 1) * 1.25
        elseif suddenEvent == "ember_burst" then
            gameConfig.timeMultiplier = (gameConfig.timeMultiplier or 1) * 0.85
        elseif suddenEvent == "material_shift" then
            gameConfig.difficulty = math.min(3, gameConfig.difficulty + 1)
        end
        print("[MiniGameRunner] Sudden event triggered: " .. suddenEvent)
    end

    currentGame_:init(gameConfig)

    EventBus.Emit("minigame_start", {
        stepType = currentStepType_,
        difficulty = gameConfig.difficulty,
        stepIndex = stepIndex_,
        totalSteps = #steps_,
        modifier = modifier_,
        modifierName = modifier_ and modifier_.name or nil,
        modifierDescription = modifier_ and modifier_.description or nil,
        suddenEvent = suddenEvent,
    })

    print("[MiniGameRunner] Step " .. stepIndex_ .. "/" .. #steps_ .. ": " .. currentStepType_)
end

--- 全部步骤完成
function MiniGameRunner._AllComplete()
    running_ = false
    currentStepType_ = nil

    EventBus.Emit("all_steps_complete", {
        scores = scores_,
        orderId = orderId_,
    })

    print("[MiniGameRunner] All steps complete for order: " .. orderId_)
end

-- ============================================================================
-- 每帧更新（由 ForgeScreen 或 main 驱动）
-- ============================================================================

--- 每帧更新
---@param dt number
function MiniGameRunner.Update(dt)
    if not running_ or paused_ then return end

    -- 过渡等待阶段：让玩家看到上一步的评分反馈
    if waitingTransition_ then
        transitionTimer_ = transitionTimer_ - dt
        if transitionTimer_ <= 0 then
            waitingTransition_ = false
            MiniGameRunner._NextStep()
        end
        return
    end

    if not currentGame_ then return end

    currentGame_:update(dt)

    -- 检查是否完成
    if currentGame_:isFinished() then
        local result = currentGame_:getScore()
        if result.rating == "Poor" then
            pendingFailure_ = {
                stepType = currentStepType_,
                score = result.score,
                rating = result.rating,
            }
            paused_ = true
            EventBus.Emit("minigame_failed", {
                stepType = currentStepType_,
                score = result.score,
                rating = result.rating,
                stepIndex = stepIndex_,
                totalSteps = #steps_,
            })
            return
        end

        scores_[#scores_ + 1] = {
            stepType = currentStepType_,
            score = result.score,
            rating = result.rating,
        }

        local avgScore = 0
        for i = 1, #scores_ do
            avgScore = avgScore + (scores_[i].score or 0)
        end
        if #scores_ > 0 then
            avgScore = avgScore / #scores_
        end

        EventBus.Emit("minigame_complete", {
            stepType = currentStepType_,
            score = result.score,
            avgScore = avgScore,
            rating = result.rating,
        })

        -- 进入过渡等待，让玩家看到评分
        waitingTransition_ = true
        transitionTimer_ = TRANSITION_DELAY
    end
end

-- ============================================================================
-- 输入转发
-- ============================================================================

--- 触摸/鼠标按下
function MiniGameRunner.OnTouchStart(x, y)
    if currentGame_ and running_ and not paused_ then
        currentGame_:onTouchStart(x, y)
    end
end

--- 触摸/鼠标移动
function MiniGameRunner.OnTouchMove(x, y)
    if currentGame_ and running_ and not paused_ then
        currentGame_:onTouchMove(x, y)
    end
end

--- 触摸/鼠标释放
function MiniGameRunner.OnTouchEnd(x, y)
    if currentGame_ and running_ and not paused_ then
        currentGame_:onTouchEnd(x, y)
    end
end

return MiniGameRunner
