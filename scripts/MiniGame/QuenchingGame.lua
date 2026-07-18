---@diagnostic disable: assign-type-mismatch
-- ============================================================================
-- QuenchingGame - 淬火时机小游戏
-- Project Smith / P2-A2
--
-- 玩法: 长按释放时机
--   - 屏幕显示一个蓄力条，玩家长按按钮使蓄力条上升
--   - 目标区间在蓄力条的特定位置（闪烁高亮）
--   - 玩家需要在蓄力条到达目标区间时松手
--   - 多轮操作（代表多次淬火入水），每轮目标区间不同
--   - 得分 = 释放位置与目标区间中心的偏差
--
-- 渲染方式: UI 组件
-- 输入: 长按释放
-- ============================================================================

local UI = require("urhox-libs/UI")
local MiniGameBase = require("MiniGame.MiniGameBase")
local SFXManager = require("Utils.SFXManager")

local QuenchingGame = MiniGameBase.Extend()

-- ============================================================================
-- 色板
-- ============================================================================

local C = {
    bgPrimary     = { 26,  26,  46,  255 },
    bgCard        = { 30,  40,  68,  255 },
    gold          = { 212, 165, 116, 255 },
    textPrimary   = { 232, 224, 208, 255 },
    textSecondary = { 160, 147, 125, 255 },
    accent        = { 233, 69,  96,  255 },
    success       = { 78,  205, 196, 255 },
    warning       = { 255, 217, 61,  255 },

    waterBlue     = { 50,  120, 180, 255 },
    waterDeep     = { 30,  80,  140, 255 },
    steamWhite    = { 200, 210, 220, 200 },
    targetGlow    = { 255, 200, 60,  255 },
    barBg         = { 40,  45,  65,  255 },
    fillColor     = { 233, 120, 50,  255 },
    fillOverheat  = { 220, 50,  40,  255 },
}

local function InkButton(props)
    ---@diagnostic disable-next-line: param-type-mismatch
    local label = UI.Label {
        text = props.text,
        fontSize = props.fontSize or 18,
        fontWeight = 700,
        fontColor = props.fontColor or C.textPrimary,
        textAlign = "center",
        width = "100%",
    }
    local button = UI.Panel {
        width = props.width,
        height = props.height,
        backgroundColor = props.backgroundColor or C.waterBlue,
        borderWidth = 1,
        borderColor = props.borderColor or C.gold,
        borderRadius = props.borderRadius or 12,
        justifyContent = "center",
        alignItems = "center",
        onPointerDown = props.onPointerDown,
        onPointerUp = props.onPointerUp,
        onPointerCancel = props.onPointerCancel,
        children = { label },
    }
    return button, label
end

-- ============================================================================
-- 初始化
-- ============================================================================

function QuenchingGame:init(config)
    MiniGameBase.init(self, config)

    local difficulty = config.difficulty or 1

    -- 游戏参数
    self.totalRounds_     = 3 + math.floor(difficulty / 2)
    self.fillSpeed_       = 0.4 + difficulty * 0.08      -- 蓄力速度
    self.targetZoneSize_  = 0.16 - difficulty * 0.02     -- 目标区间大小（占比）
    self.overflowPenalty_ = true                         -- 溢出扣分

    -- 状态
    self.currentRound_  = 1
    self.fillAmount_    = 0.0  -- 0~1
    self.pressing_      = false
    self.roundResults_  = {}
    self.gamePhase_     = "ready"
    self.readyTimer_    = 1.5
    self.released_      = false
    self.overflowed_    = false

    -- 每轮目标区间中心位置
    self.targetCenters_ = {}
    for i = 1, self.totalRounds_ do
        self.targetCenters_[i] = 0.35 + math.random() * 0.35  -- 0.35~0.70
    end

    -- UI 引用
    self.fillBar_        = nil
    self.targetZone_     = nil
    self.feedbackLabel_  = nil
    self.roundLabel_     = nil
    self.holdButton_     = nil
    self.instructLabel_  = nil

    -- 条形布局参数
    self.barHeight_ = 260
    self.barWidth_  = 60

    self:buildUI_()
end

-- ============================================================================
-- UI 构建
-- ============================================================================

function QuenchingGame:buildUI_()
    local container = self.container_
    if not container then return end

    local stepText = ""
    if self.config_ and self.config_.stepIndex and self.config_.totalSteps then
        stepText = "步骤 " .. self.config_.stepIndex .. "/" .. self.config_.totalSteps .. ": "
    end

    self.feedbackLabel_ = UI.Label {
        text = "准备...",
        fontSize = 18,
        fontColor = C.warning,
        textAlign = "center",
        width = "100%",
        height = 24,
    }

    self.roundLabel_ = UI.Label {
        text = "淬火: 1/" .. self.totalRounds_,
        fontSize = 14,
        fontColor = C.textSecondary,
        textAlign = "center",
        width = "100%",
    }

    -- 蓄力条填充
    self.fillBar_ = UI.Panel {
        width = "100%",
        height = 0,
        backgroundColor = C.fillColor,
        position = "absolute",
        bottom = 0,
        left = 0,
    }

    -- 目标区间
    local tc = self.targetCenters_[1]
    local halfTarget = self.targetZoneSize_ / 2
    self.targetZone_ = UI.Panel {
        width = "100%",
        height = math.floor(self.targetZoneSize_ * self.barHeight_),
        backgroundColor = { 255, 200, 60, 80 },
        borderWidth = 2,
        borderColor = C.targetGlow,
        position = "absolute",
        bottom = math.floor((tc - halfTarget) * self.barHeight_),
    }

    -- 蓄力条背景
    local barBg = UI.Panel {
        width = self.barWidth_,
        height = self.barHeight_,
        backgroundColor = C.barBg,
        borderRadius = 8,
        overflow = "hidden",
        children = {
            self.fillBar_,
            self.targetZone_,
        },
    }

    -- 标签列
    local sideLabels = UI.Panel {
        height = self.barHeight_,
        flexDirection = "column",
        justifyContent = "space-between",
        paddingVertical = 4,
        children = {
            UI.Label { text = "溢出", fontSize = 10, fontColor = C.accent },
            UI.Label { text = "目标", fontSize = 10, fontColor = C.warning },
            UI.Label { text = "起始", fontSize = 10, fontColor = C.waterBlue },
        },
    }

    -- 长按按钮
    local holdButtonText
    self.holdButton_, holdButtonText = InkButton {
        text = "按住淬火",
        width = 160,
        height = 56,
        fontSize = 20,
        backgroundColor = C.waterBlue,
        borderColor = C.gold,
        borderRadius = 12,
        onPointerDown = function()
            self:onPressStart_()
        end,
        onPointerUp = function()
            self:onPressEnd_()
        end,
        onPointerCancel = function()
            self:onPressEnd_()
        end,
    }
    self.holdButtonText_ = holdButtonText

    self.instructLabel_ = UI.Label {
        text = "按住蓄力，松手淬火",
        fontSize = 11,
        fontColor = C.textSecondary,
    }

    -- 轮次指示灯
    self.roundDots_ = {}
    local dotChildren = {}
    for i = 1, self.totalRounds_ do
        local dot = UI.Panel {
            width = 20,
            height = 20,
            borderRadius = 10,
            backgroundColor = C.barBg,
            justifyContent = "center",
            alignItems = "center",
            children = {
                UI.Label {
                    text = tostring(i),
                    fontSize = 9,
                    fontColor = C.textSecondary,
                },
            },
        }
        self.roundDots_[i] = dot
        dotChildren[#dotChildren + 1] = dot
    end

    local panel = UI.Panel {
        width = "100%",
        height = "100%",
        flexDirection = "column",
        alignItems = "center",
        justifyContent = "space-between",
        paddingTop = 16,
        paddingBottom = 24,
        paddingHorizontal = 12,
        children = {
            UI.Label {
                text = stepText .. "淬火时机",
                fontSize = 18,
                fontColor = C.gold,
            },
            UI.Panel {
                flexDirection = "row",
                gap = 6,
                children = dotChildren,
            },
            self.roundLabel_,
            -- 蓄力条 + 标签
            UI.Panel {
                flexDirection = "row",
                alignItems = "center",
                gap = 10,
                children = {
                    sideLabels,
                    barBg,
                },
            },
            self.feedbackLabel_,
            self.holdButton_,
            self.instructLabel_,
        },
    }

    container:AddChild(panel)
end

-- ============================================================================
-- 长按处理
-- ============================================================================

function QuenchingGame:onPressStart_()
    if self.finished_ then return end
    if self.gamePhase_ ~= "playing" then return end
    if self.released_ then return end

    self.pressing_ = true
    if self.holdButtonText_ then
        self.holdButtonText_.text = "松手"
    end
    if self.holdButton_ then
        self.holdButton_.backgroundColor = C.waterDeep
    end
end

function QuenchingGame:onPressEnd_()
    if self.finished_ then return end
    if self.gamePhase_ ~= "playing" then return end
    if self.released_ then return end
    if not self.pressing_ then return end

    self.pressing_ = false
    self.released_ = true

    -- 音效
    SFXManager.Play(SFXManager.SFX.QUENCH_SIZZLE, 0.6)

    -- 判定
    local tc = self.targetCenters_[self.currentRound_]
    local halfTarget = self.targetZoneSize_ / 2
    local offset = math.abs(self.fillAmount_ - tc)

    local roundRating
    if self.overflowed_ then
        roundRating = "Poor"
    elseif offset <= halfTarget * 0.4 then
        roundRating = "Perfect"
    elseif offset <= halfTarget then
        roundRating = "Great"
    elseif offset <= halfTarget + 0.08 then
        roundRating = "Good"
    else
        roundRating = "Poor"
    end

    self.roundResults_[self.currentRound_] = roundRating

    -- 更新指示灯
    local dot = self.roundDots_[self.currentRound_]
    if dot then
        if roundRating == "Perfect" then
            dot.backgroundColor = C.targetGlow
        elseif roundRating == "Great" then
            dot.backgroundColor = C.success
        elseif roundRating == "Good" then
            dot.backgroundColor = C.textSecondary
        else
            dot.backgroundColor = C.accent
        end
    end

    -- 反馈
    self.feedbackLabel_.text = roundRating .. "!"
    if roundRating == "Perfect" then
        self.feedbackLabel_.fontColor = C.warning
    elseif roundRating == "Great" then
        self.feedbackLabel_.fontColor = C.success
    else
        self.feedbackLabel_.fontColor = C.textPrimary
    end

    -- 延迟下一轮
    self.transitionTimer_ = 0.8
    self.gamePhase_ = "transition"
end

-- ============================================================================
-- 每帧更新
-- ============================================================================

function QuenchingGame:update(dt)
    if self.finished_ then return end

    -- 开场倒计时
    if self.gamePhase_ == "ready" then
        self.readyTimer_ = self.readyTimer_ - dt
        local countdown = math.ceil(self.readyTimer_)
        if countdown > 0 then
            self.feedbackLabel_.text = "准备... " .. countdown
        end
        if self.readyTimer_ <= 0 then
            self.gamePhase_ = "playing"
            self.feedbackLabel_.text = "按住蓄力!"
            self.feedbackLabel_.fontColor = C.gold
        end
        return
    end

    -- 过渡
    if self.gamePhase_ == "transition" then
        self.transitionTimer_ = self.transitionTimer_ - dt
        if self.transitionTimer_ <= 0 then
            self.currentRound_ = self.currentRound_ + 1
            if self.currentRound_ > self.totalRounds_ then
                self:finishGame_()
                return
            end
            -- 重置本轮
            self.fillAmount_ = 0.0
            self.pressing_ = false
            self.released_ = false
            self.overflowed_ = false
            self:updateTargetPosition_()
            self:updateFillBar_()
            self.gamePhase_ = "playing"
            self.roundLabel_.text = "淬火: " .. self.currentRound_ .. "/" .. self.totalRounds_
            self.feedbackLabel_.text = "按住蓄力!"
            self.feedbackLabel_.fontColor = C.gold
            if self.holdButtonText_ then
                self.holdButtonText_.text = "按住淬火"
            end
            if self.holdButton_ then
                self.holdButton_.backgroundColor = C.waterBlue
            end
        end
        return
    end

    if self.gamePhase_ ~= "playing" then return end

    -- 蓄力
    if self.pressing_ and not self.released_ then
        self.fillAmount_ = self.fillAmount_ + self.fillSpeed_ * dt
        if self.fillAmount_ >= 1.0 then
            self.fillAmount_ = 1.0
            self.overflowed_ = true
            -- 自动释放（溢出惩罚）
            self:onPressEnd_()
        end
        self:updateFillBar_()
    end
end

-- ============================================================================
-- UI 更新
-- ============================================================================

function QuenchingGame:updateFillBar_()
    if self.fillBar_ then
        local h = math.floor(self.fillAmount_ * self.barHeight_)
        self.fillBar_.height = h
        -- 过热变色
        if self.fillAmount_ > 0.85 then
            self.fillBar_.backgroundColor = C.fillOverheat
        else
            self.fillBar_.backgroundColor = C.fillColor
        end
    end
end

function QuenchingGame:updateTargetPosition_()
    local tc = self.targetCenters_[self.currentRound_]
    local halfTarget = self.targetZoneSize_ / 2
    if self.targetZone_ then
        self.targetZone_.bottom = math.floor((tc - halfTarget) * self.barHeight_)
    end
end

-- ============================================================================
-- 结算
-- ============================================================================

function QuenchingGame:finishGame_()
    if self.finished_ then return end

    local ratingValues = {
        Perfect = 1.0,
        Great   = 0.80,
        Good    = 0.60,
        Poor    = 0.25,
    }

    local totalVal = 0
    for i = 1, self.totalRounds_ do
        local r = self.roundResults_[i] or "Poor"
        totalVal = totalVal + (ratingValues[r] or 0)
    end

    local finalScore = math.min(1.0, totalVal / self.totalRounds_)

    local rating
    if finalScore >= 0.90 then rating = "Perfect"
    elseif finalScore >= 0.75 then rating = "Great"
    elseif finalScore >= 0.50 then rating = "Good"
    else rating = "Poor"
    end

    self:finish(finalScore, rating)
    self.gamePhase_ = "done"

    self.feedbackLabel_.text = rating .. "! (得分: " .. string.format("%.0f", finalScore * 100) .. ")"
    if rating == "Perfect" then
        self.feedbackLabel_.fontColor = C.warning
    elseif rating == "Great" then
        self.feedbackLabel_.fontColor = C.success
    else
        self.feedbackLabel_.fontColor = C.textPrimary
    end

    if self.holdButtonText_ then
        self.holdButtonText_.text = "完成"
    end
    if self.holdButton_ then
        self.holdButton_.backgroundColor = C.bgCard
    end

    print("[QuenchingGame] Finished: score=" .. string.format("%.2f", finalScore)
        .. " rating=" .. rating)
end

return QuenchingGame
