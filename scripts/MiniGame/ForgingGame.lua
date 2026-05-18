-- ============================================================================
-- ForgingGame - 锻打塑形小游戏
-- Project Smith / P1-C3
--
-- 玩法: 节奏锻打
--   - 屏幕显示一排"锻打节拍点"，依次激活（高亮）
--   - 玩家在节拍点激活时按下"锤击"按钮
--   - 击中时机越接近节拍中心，得分越高
--   - 错过节拍 = Miss，0 分
--   - 连击加分
--
-- 渲染方式: UI 组件
-- 输入: 点击"锤击"按钮
-- ============================================================================

local UI = require("urhox-libs/UI")
local MiniGameBase = require("MiniGame.MiniGameBase")
local SFXManager = require("Utils.SFXManager")

local ForgingGame = MiniGameBase.Extend()

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

    beatInactive  = { 60,  65,  85,  255 },
    beatActive    = { 255, 180, 60,  255 },
    beatPerfect   = { 78,  205, 196, 255 },
    beatGreat     = { 100, 180, 140, 255 },
    beatGood      = { 180, 180, 100, 255 },
    beatMiss      = { 150, 60,  60,  255 },

    strikeBtn        = { 200, 80,  50,  255 },
    strikeBtnHover   = { 230, 100, 60,  255 },
    strikeBtnPressed = { 170, 60,  40,  255 },
}

-- ============================================================================
-- 初始化
-- ============================================================================

function ForgingGame:init(config)
    MiniGameBase.init(self, config)

    local difficulty = config.difficulty or 1

    -- 游戏参数
    self.totalBeats_    = 5 + difficulty             -- 节拍数
    self.beatDuration_  = 1.4 - difficulty * 0.15    -- 每拍窗口时间（秒）
    self.perfectWindow_ = 0.15                       -- Perfect 判定半径（±秒）
    self.greatWindow_   = 0.30                       -- Great 判定半径

    -- 状态
    self.currentBeat_ = 1
    self.beatTimer_   = 0
    self.beatResults_ = {}
    self.struck_      = false
    self.gamePhase_   = "ready"    -- ready -> playing -> done
    self.readyTimer_  = 1.5

    -- 连击
    self.combo_    = 0
    self.maxCombo_ = 0

    -- UI 引用
    self.beatWidgets_  = {}
    self.strikeButton_ = nil
    self.feedbackLabel_ = nil
    self.comboLabel_    = nil
    self.timerBar_      = nil
    self.timerBarBg_    = nil

    self:buildUI_()
end

-- ============================================================================
-- UI 构建
-- ============================================================================

function ForgingGame:buildUI_()
    local container = self.container_
    if not container then return end

    -- 步骤指示
    local stepText = ""
    if self.config_ and self.config_.stepIndex and self.config_.totalSteps then
        stepText = "步骤 " .. self.config_.stepIndex .. "/" .. self.config_.totalSteps .. ": "
    end

    -- 节拍指示灯
    local beatChildren = {}
    for i = 1, self.totalBeats_ do
        local w = UI.Panel {
            width = 32,
            height = 32,
            borderRadius = 16,
            backgroundColor = C.beatInactive,
            justifyContent = "center",
            alignItems = "center",
            children = {
                UI.Label {
                    text = tostring(i),
                    fontSize = 11,
                    fontColor = C.textSecondary,
                },
            },
        }
        self.beatWidgets_[i] = w
        beatChildren[#beatChildren + 1] = w
    end

    -- 计时条
    self.timerBar_ = UI.Panel {
        width = "100%",
        height = "100%",
        borderRadius = 4,
        backgroundColor = C.gold,
    }
    self.timerBarBg_ = UI.Panel {
        width = "90%",
        height = 8,
        borderRadius = 4,
        backgroundColor = { 40, 45, 65, 255 },
        children = { self.timerBar_ },
    }

    -- 反馈文字
    self.feedbackLabel_ = UI.Label {
        text = "准备...",
        fontSize = 20,
        fontColor = C.warning,
        textAlign = "center",
        width = "100%",
        height = 28,
    }

    self.comboLabel_ = UI.Label {
        text = "",
        fontSize = 14,
        fontColor = C.success,
        textAlign = "center",
        width = "100%",
        height = 18,
    }

    -- 锤击按钮
    self.strikeButton_ = UI.Button {
        text = "锤击!",
        width = 160,
        height = 64,
        fontSize = 22,
        backgroundColor = C.strikeBtn,
        hoverBackgroundColor = C.strikeBtnHover,
        pressedBackgroundColor = C.strikeBtnPressed,
        fontColor = C.textPrimary,
        borderRadius = 12,
        onClick = function()
            self:onStrike_()
        end,
    }

    local panel = UI.Panel {
        width = "100%",
        height = "100%",
        flexDirection = "column",
        alignItems = "center",
        justifyContent = "space-between",
        paddingTop = 20,
        paddingBottom = 30,
        paddingHorizontal = 12,
        children = {
            -- 标题
            UI.Label {
                text = stepText .. "锻打塑形",
                fontSize = 18,
                fontColor = C.gold,
            },
            -- 节拍灯
            UI.Panel {
                width = "100%",
                flexDirection = "row",
                justifyContent = "center",
                alignItems = "center",
                gap = 6,
                flexWrap = "wrap",
                paddingHorizontal = 12,
                children = beatChildren,
            },
            -- 计时条
            self.timerBarBg_,
            -- 反馈
            self.feedbackLabel_,
            self.comboLabel_,
            -- 锤击按钮
            self.strikeButton_,
            -- 提示
            UI.Label {
                text = "在节拍高亮时按下锤击",
                fontSize = 11,
                fontColor = C.textSecondary,
            },
        },
    }

    container:AddChild(panel)
end

-- ============================================================================
-- 锤击判定
-- ============================================================================

function ForgingGame:onStrike_()
    if self.finished_ then return end
    if self.gamePhase_ ~= "playing" then return end
    if self.struck_ then return end

    self.struck_ = true

    -- 计算时机偏差: 最佳击中点在节拍中心
    local center = self.beatDuration_ * 0.5
    local offset = math.abs(self.beatTimer_ - center)

    local rating
    if offset <= self.perfectWindow_ then
        rating = "Perfect"
        self.combo_ = self.combo_ + 1
    elseif offset <= self.greatWindow_ then
        rating = "Great"
        self.combo_ = self.combo_ + 1
    else
        rating = "Good"
        self.combo_ = 0
    end

    -- 根据判定播放不同锤击音效
    if rating == "Perfect" then
        SFXManager.Play(SFXManager.SFX.HAMMER_PERFECT, 0.8)
    elseif rating == "Great" then
        SFXManager.Play(SFXManager.SFX.HAMMER_HEAVY, 0.7)
    else
        SFXManager.Play(SFXManager.SFX.HAMMER_LIGHT, 0.6)
    end

    if self.combo_ > self.maxCombo_ then
        self.maxCombo_ = self.combo_
    end

    self.beatResults_[self.currentBeat_] = rating

    -- 视觉反馈: 节拍灯变色
    local w = self.beatWidgets_[self.currentBeat_]
    if w then
        if rating == "Perfect" then
            w.backgroundColor = C.beatPerfect
        elseif rating == "Great" then
            w.backgroundColor = C.beatGreat
        else
            w.backgroundColor = C.beatGood
        end
    end

    -- 反馈文字
    self.feedbackLabel_.text = rating .. "!"
    if rating == "Perfect" then
        self.feedbackLabel_.fontColor = C.warning
    elseif rating == "Great" then
        self.feedbackLabel_.fontColor = C.success
    else
        self.feedbackLabel_.fontColor = C.textPrimary
    end

    -- 连击显示
    if self.combo_ >= 2 then
        self.comboLabel_.text = self.combo_ .. " 连击!"
        self.comboLabel_.fontColor = C.warning
    else
        self.comboLabel_.text = ""
    end
end

-- ============================================================================
-- 每帧更新
-- ============================================================================

function ForgingGame:update(dt)
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
            self.beatTimer_ = 0
            self.struck_ = false
            if self.beatWidgets_[1] then
                self.beatWidgets_[1].backgroundColor = C.beatActive
            end
            self.feedbackLabel_.text = "锤击!"
            self.feedbackLabel_.fontColor = C.gold
            -- 开始火焰环境音
            SFXManager.PlayLoop("forge_fire", SFXManager.SFX.FIRE_CRACKLE, 0.25)
        end
        return
    end

    if self.gamePhase_ ~= "playing" then return end

    self.beatTimer_ = self.beatTimer_ + dt

    -- 更新计时条宽度
    if self.timerBar_ then
        local pct = math.max(0, 1.0 - self.beatTimer_ / self.beatDuration_)
        self.timerBar_.width = tostring(math.floor(pct * 100)) .. "%"
    end

    -- 节拍超时
    if self.beatTimer_ >= self.beatDuration_ then
        if not self.struck_ then
            -- 错过本拍
            self.beatResults_[self.currentBeat_] = "Miss"
            self.combo_ = 0
            self.comboLabel_.text = ""

            local w = self.beatWidgets_[self.currentBeat_]
            if w then
                w.backgroundColor = C.beatMiss
            end

            self.feedbackLabel_.text = "错过!"
            self.feedbackLabel_.fontColor = C.accent
        end

        -- 推进到下一拍
        self.currentBeat_ = self.currentBeat_ + 1

        if self.currentBeat_ > self.totalBeats_ then
            self:finishGame_()
            return
        end

        self.beatTimer_ = 0
        self.struck_ = false

        -- 高亮当前节拍
        if self.beatWidgets_[self.currentBeat_] then
            self.beatWidgets_[self.currentBeat_].backgroundColor = C.beatActive
        end

        self.feedbackLabel_.text = "锤击!"
        self.feedbackLabel_.fontColor = C.gold
    end
end

-- ============================================================================
-- 结算
-- ============================================================================

function ForgingGame:finishGame_()
    if self.finished_ then return end

    -- 停止火焰环境音
    SFXManager.StopLoop("forge_fire")

    local ratingValues = {
        Perfect = 1.0,
        Great   = 0.80,
        Good    = 0.60,
        Miss    = 0.0,
    }

    local totalWeight = 0
    local weightedSum = 0

    for i = 1, self.totalBeats_ do
        local r = self.beatResults_[i] or "Miss"
        local val = ratingValues[r] or 0
        weightedSum = weightedSum + val
        totalWeight = totalWeight + 1
    end

    local baseScore = weightedSum / totalWeight

    -- 连击加分
    local comboBonus = 0
    if self.maxCombo_ >= self.totalBeats_ then
        comboBonus = 0.10   -- 全连
    elseif self.maxCombo_ >= self.totalBeats_ * 0.6 then
        comboBonus = 0.05
    end

    local finalScore = math.min(1.0, baseScore + comboBonus)

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

    if self.maxCombo_ >= 2 then
        self.comboLabel_.text = "最大连击: " .. self.maxCombo_
    end

    -- 禁用锤击按钮
    if self.strikeButton_ then
        self.strikeButton_.text = "完成"
        self.strikeButton_.backgroundColor = C.bgCard
    end

    print("[ForgingGame] Finished: score=" .. string.format("%.2f", finalScore)
        .. " rating=" .. rating
        .. " maxCombo=" .. self.maxCombo_)
end

return ForgingGame
