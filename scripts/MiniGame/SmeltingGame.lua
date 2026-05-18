-- ============================================================================
-- SmeltingGame - 控火熔炼小游戏
-- Project Smith / P2-A1
--
-- 玩法: 温度条控制
--   - 屏幕显示一个垂直温度条，指针自动上下移动
--   - 温度条上有"最佳温度区间"（绿色），指针经过时按下"定温"按钮
--   - 多轮操作（每轮代表一次加料/控温），连续命中高分区加分
--   - 得分 = 各轮距最佳区间中心的偏差加权平均
--
-- 渲染方式: UI 组件
-- 输入: 点击
-- ============================================================================

local UI = require("urhox-libs/UI")
local MiniGameBase = require("MiniGame.MiniGameBase")
local SFXManager = require("Utils.SFXManager")

local SmeltingGame = MiniGameBase.Extend()

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

    tempCold      = { 60,  100, 160, 255 },  -- 过冷区
    tempGood      = { 100, 180, 120, 255 },  -- 良好区
    tempPerfect   = { 255, 200, 60,  255 },  -- 最佳区
    tempHot       = { 220, 80,  50,  255 },  -- 过热区
    tempPointer   = { 255, 255, 255, 255 },  -- 指针
    barBg         = { 40,  45,  65,  255 },
}

-- ============================================================================
-- 初始化
-- ============================================================================

function SmeltingGame:init(config)
    MiniGameBase.init(self, config)

    local difficulty = config.difficulty or 1

    -- 游戏参数
    self.totalRounds_   = 3 + difficulty            -- 总轮数
    self.pointerSpeed_  = 0.6 + difficulty * 0.15   -- 指针速度（0~1范围/秒）
    self.perfectZoneSize_ = 0.18 - difficulty * 0.02 -- 最佳区间大小（占比）
    self.goodZoneSize_  = 0.30 - difficulty * 0.02   -- 良好区间大小

    -- 状态
    self.currentRound_  = 1
    self.pointerPos_    = 0.0   -- 0~1
    self.pointerDir_    = 1     -- 1=上, -1=下
    self.roundResults_  = {}
    self.gamePhase_     = "ready"  -- ready -> playing -> done
    self.readyTimer_    = 1.5
    self.locked_        = false

    -- 每轮的最佳区间中心位置（随机生成）
    self.targetCenters_ = {}
    for i = 1, self.totalRounds_ do
        self.targetCenters_[i] = 0.3 + math.random() * 0.4  -- 0.3~0.7
    end

    -- UI 引用
    self.pointerWidget_   = nil
    self.tempBarBg_       = nil
    self.feedbackLabel_   = nil
    self.roundLabel_      = nil
    self.lockButton_      = nil
    self.perfectZone_     = nil
    self.goodZoneLow_     = nil
    self.goodZoneHigh_    = nil

    -- 温度条布局参数
    self.barHeight_ = 280
    self.barWidth_  = 50

    self:buildUI_()
end

-- ============================================================================
-- UI 构建
-- ============================================================================

function SmeltingGame:buildUI_()
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
        text = "轮次: 1/" .. self.totalRounds_,
        fontSize = 14,
        fontColor = C.textSecondary,
        textAlign = "center",
        width = "100%",
    }

    -- 温度条区域
    local tc = self.targetCenters_[1]
    local halfPerfect = self.perfectZoneSize_ / 2
    local halfGood = self.goodZoneSize_ / 2

    -- 最佳区间标记
    self.perfectZone_ = UI.Panel {
        width = "100%",
        height = math.floor(self.perfectZoneSize_ * self.barHeight_),
        backgroundColor = C.tempPerfect,
        borderRadius = 2,
        position = "absolute",
        bottom = math.floor((tc - halfPerfect) * self.barHeight_),
    }

    -- 良好区间下半部分
    self.goodZoneLow_ = UI.Panel {
        width = "100%",
        height = math.floor((halfGood - halfPerfect) * self.barHeight_),
        backgroundColor = C.tempGood,
        position = "absolute",
        bottom = math.floor((tc - halfGood) * self.barHeight_),
    }

    -- 良好区间上半部分
    self.goodZoneHigh_ = UI.Panel {
        width = "100%",
        height = math.floor((halfGood - halfPerfect) * self.barHeight_),
        backgroundColor = C.tempGood,
        position = "absolute",
        bottom = math.floor((tc + halfPerfect) * self.barHeight_),
    }

    -- 指针
    self.pointerWidget_ = UI.Panel {
        width = self.barWidth_ + 20,
        height = 4,
        backgroundColor = C.tempPointer,
        borderRadius = 2,
        position = "absolute",
        bottom = 0,
        left = -10,
    }

    -- 温度条背景
    self.tempBarBg_ = UI.Panel {
        width = self.barWidth_,
        height = self.barHeight_,
        backgroundColor = C.barBg,
        borderRadius = 6,
        overflow = "hidden",
        children = {
            self.goodZoneLow_,
            self.goodZoneHigh_,
            self.perfectZone_,
            self.pointerWidget_,
        },
    }

    -- 温度标签
    local tempLabels = UI.Panel {
        height = self.barHeight_,
        flexDirection = "column",
        justifyContent = "space-between",
        paddingVertical = 4,
        children = {
            UI.Label { text = "过热", fontSize = 10, fontColor = C.accent },
            UI.Label { text = "最佳", fontSize = 10, fontColor = C.warning },
            UI.Label { text = "过冷", fontSize = 10, fontColor = C.tempCold },
        },
    }

    -- 定温按钮
    self.lockButton_ = UI.Button {
        text = "定温!",
        width = 140,
        height = 56,
        fontSize = 20,
        backgroundColor = C.accent,
        hoverBackgroundColor = { 250, 90, 110, 255 },
        pressedBackgroundColor = { 200, 50, 70, 255 },
        fontColor = C.textPrimary,
        borderRadius = 12,
        onClick = function()
            self:onLock_()
        end,
    }

    -- 历史指示灯
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
                text = stepText .. "控火熔炼",
                fontSize = 18,
                fontColor = C.gold,
            },
            -- 轮次指示灯
            UI.Panel {
                flexDirection = "row",
                gap = 6,
                children = dotChildren,
            },
            self.roundLabel_,
            -- 温度条 + 标签
            UI.Panel {
                flexDirection = "row",
                alignItems = "center",
                gap = 10,
                children = {
                    tempLabels,
                    self.tempBarBg_,
                },
            },
            -- 反馈
            self.feedbackLabel_,
            -- 按钮
            self.lockButton_,
            UI.Label {
                text = "在最佳温度时按下定温",
                fontSize = 11,
                fontColor = C.textSecondary,
            },
        },
    }

    container:AddChild(panel)
end

-- ============================================================================
-- 定温操作
-- ============================================================================

function SmeltingGame:onLock_()
    if self.finished_ then return end
    if self.gamePhase_ ~= "playing" then return end
    if self.locked_ then return end

    self.locked_ = true

    -- 计算与最佳区间的偏差
    local tc = self.targetCenters_[self.currentRound_]
    local offset = math.abs(self.pointerPos_ - tc)
    local halfPerfect = self.perfectZoneSize_ / 2
    local halfGood = self.goodZoneSize_ / 2

    local roundRating
    if offset <= halfPerfect then
        roundRating = "Perfect"
    elseif offset <= halfGood then
        roundRating = "Great"
    elseif offset <= halfGood + 0.1 then
        roundRating = "Good"
    else
        roundRating = "Poor"
    end

    -- 根据温度判定播放不同音效
    if roundRating == "Perfect" then
        SFXManager.Play(SFXManager.SFX.BELLOWS_PUMP, 0.6)
    elseif roundRating == "Great" then
        SFXManager.Play(SFXManager.SFX.QUENCH_SIZZLE, 0.5)
    else
        SFXManager.Play(SFXManager.SFX.HAMMER_LIGHT, 0.3)
    end

    self.roundResults_[self.currentRound_] = roundRating

    -- 更新指示灯
    local dot = self.roundDots_[self.currentRound_]
    if dot then
        if roundRating == "Perfect" then
            dot.backgroundColor = C.tempPerfect
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

    -- 延迟进入下一轮
    self.transitionTimer_ = 0.8
    self.gamePhase_ = "transition"
end

-- ============================================================================
-- 每帧更新
-- ============================================================================

function SmeltingGame:update(dt)
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
            self.feedbackLabel_.text = "定温!"
            self.feedbackLabel_.fontColor = C.gold
            -- 开始火焰环境音
            SFXManager.PlayLoop("smelting_fire", SFXManager.SFX.FIRE_CRACKLE, 0.3)
        end
        return
    end

    -- 过渡阶段
    if self.gamePhase_ == "transition" then
        self.transitionTimer_ = self.transitionTimer_ - dt
        if self.transitionTimer_ <= 0 then
            self.currentRound_ = self.currentRound_ + 1
            if self.currentRound_ > self.totalRounds_ then
                self:finishGame_()
                return
            end
            -- 更新目标区间位置
            self:updateZonePositions_()
            self.pointerPos_ = 0.0
            self.pointerDir_ = 1
            self.locked_ = false
            self.gamePhase_ = "playing"
            self.roundLabel_.text = "轮次: " .. self.currentRound_ .. "/" .. self.totalRounds_
            self.feedbackLabel_.text = "定温!"
            self.feedbackLabel_.fontColor = C.gold
        end
        return
    end

    if self.gamePhase_ ~= "playing" then return end

    -- 移动指针
    self.pointerPos_ = self.pointerPos_ + self.pointerDir_ * self.pointerSpeed_ * dt
    if self.pointerPos_ >= 1.0 then
        self.pointerPos_ = 1.0
        self.pointerDir_ = -1
    elseif self.pointerPos_ <= 0.0 then
        self.pointerPos_ = 0.0
        self.pointerDir_ = 1
    end

    -- 更新指针位置
    if self.pointerWidget_ then
        self.pointerWidget_.bottom = math.floor(self.pointerPos_ * (self.barHeight_ - 4))
    end
end

-- ============================================================================
-- 更新区间位置
-- ============================================================================

function SmeltingGame:updateZonePositions_()
    local tc = self.targetCenters_[self.currentRound_]
    local halfPerfect = self.perfectZoneSize_ / 2
    local halfGood = self.goodZoneSize_ / 2

    if self.perfectZone_ then
        self.perfectZone_.bottom = math.floor((tc - halfPerfect) * self.barHeight_)
        self.perfectZone_.height = math.floor(self.perfectZoneSize_ * self.barHeight_)
    end
    if self.goodZoneLow_ then
        self.goodZoneLow_.bottom = math.floor((tc - halfGood) * self.barHeight_)
        self.goodZoneLow_.height = math.floor((halfGood - halfPerfect) * self.barHeight_)
    end
    if self.goodZoneHigh_ then
        self.goodZoneHigh_.bottom = math.floor((tc + halfPerfect) * self.barHeight_)
        self.goodZoneHigh_.height = math.floor((halfGood - halfPerfect) * self.barHeight_)
    end
end

-- ============================================================================
-- 结算
-- ============================================================================

function SmeltingGame:finishGame_()
    if self.finished_ then return end

    -- 停止环境音
    SFXManager.StopLoop("smelting_fire")

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

    local finalScore = totalVal / self.totalRounds_
    finalScore = math.min(1.0, finalScore)

    local rating
    if finalScore >= 0.90 then rating = "Perfect"
    elseif finalScore >= 0.75 then rating = "Great"
    elseif finalScore >= 0.50 then rating = "Good"
    else rating = "Poor"
    end

    self:finish(finalScore, rating)
    self.gamePhase_ = "done"

    -- 更新 UI
    self.feedbackLabel_.text = rating .. "! (得分: " .. string.format("%.0f", finalScore * 100) .. ")"
    if rating == "Perfect" then
        self.feedbackLabel_.fontColor = C.warning
    elseif rating == "Great" then
        self.feedbackLabel_.fontColor = C.success
    else
        self.feedbackLabel_.fontColor = C.textPrimary
    end

    if self.lockButton_ then
        self.lockButton_.text = "完成"
        self.lockButton_.backgroundColor = C.bgCard
    end

    print("[SmeltingGame] Finished: score=" .. string.format("%.2f", finalScore)
        .. " rating=" .. rating)
end

return SmeltingGame
