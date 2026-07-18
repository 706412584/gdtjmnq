---@diagnostic disable: assign-type-mismatch
-- ============================================================================
-- PolishingGame - 研磨开刃小游戏
-- Project Smith / P1-C4
--
-- 玩法: 分区研磨
--   - 刀刃被分为若干研磨区域，依次激活
--   - 玩家点击当前激活区域进行研磨（每区域需多次点击）
--   - 点击错误区域有惩罚
--   - 限时内完成所有区域 = 高分
--   - 完成度 * 精度 + 速度加分
--
-- 渲染方式: UI 组件
-- 输入: 点击
-- ============================================================================

local UI = require("urhox-libs/UI")
local MiniGameBase = require("MiniGame.MiniGameBase")
local SFXManager = require("Utils.SFXManager")

local PolishingGame = MiniGameBase.Extend()

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

    bladeInactive = { 80,  85,  100, 255 },
    bladeActive   = { 200, 170, 100, 255 },
    bladePolished = { 120, 190, 170, 255 },
    bladeLabel    = { 40,  42,  55,  255 },
}

local ZONE_IMAGE = "image/ui/btn_secondary.png"
local ZONE_ACTIVE_IMAGE = "image/ui/btn_gold.png"

local function InkButton(props)
    ---@diagnostic disable-next-line: param-type-mismatch
    local label = UI.Label {
        text = props.text,
        width = "100%",
        height = "100%",
        flexShrink = 1,
        fontSize = props.fontSize or 13,
        fontWeight = 700,
        fontColor = props.fontColor or C.textPrimary,
        textAlign = "center",
        verticalAlign = "middle",
    }
    local button = UI.Panel {
        width = props.width,
        height = props.height,
        backgroundImage = props.backgroundImage,
        backgroundFit = "stretch",
        backgroundColor = props.backgroundColor,
        borderWidth = props.borderWidth or 0,
        borderColor = props.borderColor or C.gold,
        borderRadius = props.borderRadius or 6,
        justifyContent = "center",
        alignItems = "center",
        onClick = props.onClick,
        children = { label },
    }
    return button, label
end

-- ============================================================================
-- 初始化
-- ============================================================================

function PolishingGame:init(config)
    MiniGameBase.init(self, config)

    local difficulty = config.difficulty or 1

    -- 游戏参数
    self.totalZones_  = 4 + difficulty                        -- 研磨区域数
    self.tapsPerZone_ = 2 + math.floor(difficulty / 2)        -- 每区域需点击次数
    self.timeLimit_   = 15 + (3 - difficulty) * 3             -- 时间限制

    -- 状态
    self.currentZone_    = 1
    self.tapCount_       = 0
    self.elapsed_        = 0
    self.zonesCompleted_ = 0
    self.wrongTaps_      = 0

    -- UI 引用
    self.zoneWidgets_   = {}
    self.zoneLabels_    = {}
    self.timerLabel_    = nil
    self.progressLabel_ = nil
    self.feedbackLabel_ = nil
    self.tapCountLabel_ = nil

    self:buildUI_()
end

-- ============================================================================
-- UI 构建
-- ============================================================================

function PolishingGame:buildUI_()
    local container = self.container_
    if not container then return end

    -- 步骤指示
    local stepText = ""
    if self.config_ and self.config_.stepIndex and self.config_.totalSteps then
        stepText = "步骤 " .. self.config_.stepIndex .. "/" .. self.config_.totalSteps .. ": "
    end

    self.timerLabel_ = UI.Label {
        text = "剩余: " .. self.timeLimit_ .. "s",
        fontSize = 14,
        fontColor = C.warning,
    }

    self.progressLabel_ = UI.Label {
        text = "研磨: 0/" .. self.totalZones_,
        fontSize = 14,
        fontColor = C.success,
    }

    self.feedbackLabel_ = UI.Label {
        text = "点击高亮区域研磨刀刃",
        fontSize = 12,
        fontColor = C.textSecondary,
        textAlign = "center",
        width = "100%",
        height = 18,
    }

    self.tapCountLabel_ = UI.Label {
        text = "0/" .. self.tapsPerZone_ .. " 次",
        fontSize = 16,
        fontColor = C.gold,
        textAlign = "center",
        width = "100%",
    }

    -- 刀刃区域列表
    local zoneChildren = {}
    for i = 1, self.totalZones_ do
        local idx = i
        local isFirst = (i == 1)
        local btn, label = InkButton {
            text = "研磨区域 " .. i,
            width = "46%",
            height = 66,
            fontSize = 15,
            backgroundImage = isFirst and ZONE_ACTIVE_IMAGE or ZONE_IMAGE,
            backgroundColor = "#00000000",
            borderWidth = isFirst and 2 or 0,
            borderColor = isFirst and C.gold or C.bgCard,
            fontColor = isFirst and C.bladeLabel or C.textPrimary,
            borderRadius = 8,
            onClick = function()
                self:onZoneTap_(idx)
            end,
        }
        self.zoneWidgets_[i] = btn
        self.zoneLabels_[i] = label
        zoneChildren[#zoneChildren + 1] = btn
    end

    local panel = UI.Panel {
        width = "100%",
        height = "100%",
        flexDirection = "column",
        alignItems = "center",
        paddingTop = 20,
        paddingHorizontal = 12,
        gap = 8,
        children = {
            UI.Label {
                text = stepText .. "研磨开刃",
                fontSize = 18,
                fontColor = C.gold,
            },
            -- 顶部信息栏
            UI.Panel {
                width = "100%",
                flexDirection = "row",
                justifyContent = "space-between",
                paddingHorizontal = 8,
                children = {
                    self.timerLabel_,
                    self.progressLabel_,
                },
            },
            -- 反馈
            self.feedbackLabel_,
            -- 点击计数
            self.tapCountLabel_,
            -- 刀刃区域
            UI.Panel {
                width = "100%",
                flexGrow = 1,
                flexShrink = 1,
                flexDirection = "row",
                flexWrap = "wrap",
                justifyContent = "center",
                alignContent = "center",
                gap = 10,
                paddingHorizontal = 16,
                children = zoneChildren,
            },
        },
    }

    container:AddChild(panel)
end

-- ============================================================================
-- 区域点击
-- ============================================================================

function PolishingGame:onZoneTap_(zoneIndex)
    if self.finished_ then return end

    -- 点击了非当前区域
    if zoneIndex ~= self.currentZone_ then
        self.wrongTaps_ = self.wrongTaps_ + 1
        self.feedbackLabel_.text = "请点击高亮区域!"
        self.feedbackLabel_.fontColor = C.accent
        return
    end

    self.tapCount_ = self.tapCount_ + 1
    self.tapCountLabel_.text = self.tapCount_ .. "/" .. self.tapsPerZone_ .. " 次"

    -- 研磨音效
    SFXManager.Play(SFXManager.SFX.METAL_SCRAPE, 0.5)

    self.feedbackLabel_.text = "研磨中..."
    self.feedbackLabel_.fontColor = C.gold

    -- 本区域完成
    if self.tapCount_ >= self.tapsPerZone_ then
        local w = self.zoneWidgets_[self.currentZone_]
        if w then
            w.backgroundImage = ZONE_ACTIVE_IMAGE
            w.backgroundColor = "#00000000"
            w.borderColor = C.success
            w.borderWidth = 2
            local label = self.zoneLabels_[self.currentZone_]
            if label then
                label.fontColor = C.bladeLabel
                label.text = "研磨区域 " .. self.currentZone_ .. " · 完成"
            end
        end

        self.zonesCompleted_ = self.zonesCompleted_ + 1
        self.progressLabel_.text = "研磨: " .. self.zonesCompleted_ .. "/" .. self.totalZones_
        SFXManager.Play(SFXManager.SFX.ANVIL_RING, 0.3)

        -- 切换到下一区域
        self.currentZone_ = self.currentZone_ + 1
        self.tapCount_ = 0
        self.tapCountLabel_.text = "0/" .. self.tapsPerZone_ .. " 次"

        if self.currentZone_ > self.totalZones_ then
            self:finishGame_()
            return
        end

        -- 高亮下一区域
        local nextW = self.zoneWidgets_[self.currentZone_]
        if nextW then
            nextW.backgroundImage = ZONE_ACTIVE_IMAGE
            nextW.backgroundColor = "#00000000"
            nextW.borderColor = C.gold
            nextW.borderWidth = 2
            local nextLabel = self.zoneLabels_[self.currentZone_]
            if nextLabel then
                nextLabel.fontColor = C.bladeLabel
            end
        end

        self.feedbackLabel_.text = "好! 继续下一区域"
        self.feedbackLabel_.fontColor = C.success
    end
end

-- ============================================================================
-- 每帧更新
-- ============================================================================

function PolishingGame:update(dt)
    if self.finished_ then return end

    self.elapsed_ = self.elapsed_ + dt
    local remaining = math.max(0, self.timeLimit_ - self.elapsed_)

    if self.timerLabel_ then
        self.timerLabel_.text = "剩余: " .. string.format("%.1f", remaining) .. "s"
        if remaining < 3 then
            self.timerLabel_.fontColor = C.accent
        end
    end

    if remaining <= 0 then
        self:finishGame_()
    end
end

-- ============================================================================
-- 结算
-- ============================================================================

function PolishingGame:finishGame_()
    if self.finished_ then return end

    -- 完成度
    local completionRatio = self.zonesCompleted_ / self.totalZones_

    -- 精度: 扣除错误点击
    local correctTaps = self.zonesCompleted_ * self.tapsPerZone_ + self.tapCount_
    local totalTaps = correctTaps + self.wrongTaps_
    local accuracy = 1.0
    if totalTaps > 0 then
        accuracy = correctTaps / totalTaps
    end

    -- 速度加分
    local timeBonus = 0
    if self.zonesCompleted_ >= self.totalZones_ then
        local usedRatio = self.elapsed_ / self.timeLimit_
        if usedRatio < 0.5 then
            timeBonus = 0.12
        elseif usedRatio < 0.75 then
            timeBonus = 0.06
        end
    end

    local finalScore = math.min(1.0, completionRatio * accuracy + timeBonus)

    local rating
    if finalScore >= 0.90 then rating = "Perfect"
    elseif finalScore >= 0.75 then rating = "Great"
    elseif finalScore >= 0.50 then rating = "Good"
    else rating = "Poor"
    end

    self:finish(finalScore, rating)

    -- 更新 UI
    self.feedbackLabel_.text = rating .. "! (得分: " .. string.format("%.0f", finalScore * 100) .. ")"
    if rating == "Perfect" then
        self.feedbackLabel_.fontColor = C.warning
    elseif rating == "Great" then
        self.feedbackLabel_.fontColor = C.success
    elseif rating == "Good" then
        self.feedbackLabel_.fontColor = C.textPrimary
    else
        self.feedbackLabel_.fontColor = C.accent
    end

    self.tapCountLabel_.text = ""

    print("[PolishingGame] Finished: score=" .. string.format("%.2f", finalScore)
        .. " rating=" .. rating
        .. " completed=" .. self.zonesCompleted_ .. "/" .. self.totalZones_
        .. " wrongTaps=" .. self.wrongTaps_)
end

return PolishingGame
