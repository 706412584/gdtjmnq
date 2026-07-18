---@diagnostic disable: assign-type-mismatch, param-type-mismatch
-- ============================================================================
-- OreSelectGame - 选矿去杂小游戏（古风手绘风格优化版）
-- Project Smith / P1-C2
--
-- 玩法: 屏幕显示若干矿石块，其中混有杂质。
--   - 玩家点击选择优质矿石（金色高亮）
--   - 点击杂质会扣分（红色闪烁）
--   - 限时内选够指定数量的好矿即完成
--   - 精度 = 正确选择数 / 总点击数，速度加分
--
-- 渲染方式: UI 组件（自定义绘制风格面板，匹配古风锻造界面）
-- 输入: 点击
-- ============================================================================

local UI = require("urhox-libs/UI")
local MiniGameBase = require("MiniGame.MiniGameBase")
local Timer = require("Utils.Timer")
local SFXManager = require("Utils.SFXManager")

local OreSelectGame = MiniGameBase.Extend()

-- ============================================================================
-- 色板（古代工坊风格）
-- ============================================================================

local C = {
    -- 基础
    bgOverlay    = "rgba(15,12,10,0.75)",       -- 半透明深色遮罩
    bgCard       = "rgba(26,20,15,0.85)",       -- 矿石牌底色
    borderGold   = "#7A5C32",                   -- 暗金色描边
    borderLight  = "#C9A45A",                   -- 亮金色描边（激活态）

    -- 文字
    textPrimary  = "#E8E0D0",                   -- 暖白正文
    textGold     = "#D4A574",                   -- 鎏金标题
    textSecondary = "#A0937D",                  -- 烟灰副文
    textAccent   = "#E94560",                   -- 炉火红（警告）
    textSuccess  = "#4ECDC4",                   -- 青铜绿（成功）
    textWarning  = "#FFD93D",                   -- 淬火黄

    -- 矿石状态
    oreDefault      = "rgba(40,35,30,0.80)",    -- 默认底色
    oreBorderNormal = "#5A4A3A",               -- 默认描边
    oreHover        = "rgba(60,50,40,0.90)",    -- 悬停底色
    oreSelected     = "rgba(35,75,55,0.85)",    -- 选中正确
    oreBorderGood   = "#4ECDC4",               -- 正确描边
    oreWrong        = "rgba(90,30,30,0.85)",    -- 选错
    oreBorderBad    = "#E94560",               -- 错误描边

    -- 进度
    progressBg      = "rgba(40,35,30,0.6)",
    progressFill    = "#C96A2B",               -- 炉火橙
}

local CARD_IMAGE = "image/ui/frame_item_md.png"
local CARD_SELECTED_IMAGE = "image/ui/btn_gold.png"
local ORE_ICON = "image/icon_ore.png"

-- 矿石名称池
local ORE_NAMES = {
    good = { "精铁矿", "黑铁矿", "玄铁矿", "锡矿石", "铜矿石", "银矿石" },
    bad  = { "炉渣", "土块", "碎石", "铁锈块", "风化石", "杂矿渣" },
}

-- ============================================================================
-- 初始化
-- ============================================================================

function OreSelectGame:init(config)
    MiniGameBase.init(self, config)

    local difficulty = config.difficulty or 1

    -- 游戏参数（根据难度调整）
    self.totalSlots_ = 6 + difficulty * 2            -- 总矿石数量
    self.goodCount_ = 3 + difficulty                 -- 需要选中的好矿数
    self.timeLimit_ = 12 + (3 - difficulty) * 2      -- 时间限制（秒）
    self.badCount_ = self.totalSlots_ - self.goodCount_

    -- 状态
    self.elapsed_ = 0
    self.correctPicks_ = 0
    self.totalClicks_ = 0
    self.ores_ = {}          -- { isGood, name, picked, widget }

    -- UI 引用
    self.timerLabel_ = nil
    self.progressLabel_ = nil
    self.feedbackLabel_ = nil
    self.gridContainer_ = nil
    self.timerBar_ = nil

    -- 生成矿石数据
    self:generateOres_()

    -- 构建 UI
    self:buildUI_()
end

-- ============================================================================
-- 矿石生成
-- ============================================================================

function OreSelectGame:generateOres_()
    self.ores_ = {}

    -- 添加好矿
    for i = 1, self.goodCount_ do
        local nameIdx = ((i - 1) % #ORE_NAMES.good) + 1
        self.ores_[#self.ores_ + 1] = {
            isGood = true,
            name = ORE_NAMES.good[nameIdx],
            picked = false,
        }
    end

    -- 添加杂质
    for i = 1, self.badCount_ do
        local nameIdx = ((i - 1) % #ORE_NAMES.bad) + 1
        self.ores_[#self.ores_ + 1] = {
            isGood = false,
            name = ORE_NAMES.bad[nameIdx],
            picked = false,
        }
    end

    -- Fisher-Yates 打乱
    for i = #self.ores_, 2, -1 do
        local j = math.random(1, i)
        self.ores_[i], self.ores_[j] = self.ores_[j], self.ores_[i]
    end
end

-- ============================================================================
-- UI 构建（古风绘制风格）
-- ============================================================================

function OreSelectGame:buildUI_()
    local container = self.container_
    if not container then return end

    -- ============================
    -- 顶部信息条（半透明条带）
    -- ============================
    self.timerLabel_ = UI.Label {
        text = string.format("%.1f", self.timeLimit_) .. "s",
        fontSize = 16,
        fontColor = C.textWarning,
    }

    self.progressLabel_ = UI.Label {
        text = "已选: 0/" .. self.goodCount_,
        fontSize = 15,
        fontColor = C.textSuccess,
    }

    -- 倒计时进度条
    self.timerBar_ = UI.Panel {
        width = "100%",
        height = "100%",
        backgroundColor = C.progressFill,
        borderRadius = 3,
    }

    local timerBarBg = UI.Panel {
        width = "40%",
        height = 6,
        backgroundColor = C.progressBg,
        borderRadius = 3,
        marginHorizontal = 12,
        children = { self.timerBar_ },
    }

    local topBar = UI.Panel {
        width = "100%",
        flexDirection = "row",
        alignItems = "center",
        justifyContent = "space-between",
        paddingHorizontal = 20,
        paddingVertical = 10,
        backgroundColor = C.bgOverlay,
        borderBottomWidth = 1,
        borderColor = C.borderGold,
        children = {
            self.timerLabel_,
            timerBarBg,
            self.progressLabel_,
        },
    }

    -- ============================
    -- 步骤标题
    -- ============================
    local stepText = ""
    if self.config_ and self.config_.stepIndex and self.config_.totalSteps then
        stepText = "步骤 " .. self.config_.stepIndex .. "/" .. self.config_.totalSteps .. ": "
    end

    local titleLabel = UI.Label {
        text = stepText .. "选矿去杂",
        fontSize = 18,
        fontColor = C.textGold,
        textAlign = "center",
        width = "100%",
        marginTop = 12,
    }

    -- ============================
    -- 提示/反馈文字
    -- ============================
    self.feedbackLabel_ = UI.Label {
        text = "点选优质矿石，避开杂质",
        fontSize = 13,
        fontColor = C.textSecondary,
        textAlign = "center",
        width = "100%",
        marginBottom = 8,
    }

    -- ============================
    -- 矿石网格（古风牌面风格）
    -- ============================
    local oreWidgets = {}
    local columns = 4  -- 每行4个，横屏更合适
    if self.totalSlots_ <= 6 then
        columns = 3
    end

    for i = 1, #self.ores_ do
        local ore = self.ores_[i]
        local idx = i

        local oreLabel = UI.Label {
            text = ore.name,
            fontSize = 14,
            fontWeight = 700,
            fontColor = C.textPrimary,
            textAlign = "center",
            width = "100%",
            marginTop = 3,
        }
        local oreTypeLabel = UI.Label {
            text = "待鉴别",
            fontSize = 10,
            fontColor = C.textSecondary,
            textAlign = "center",
            width = "100%",
        }

        local oreCard = UI.Panel {
            width = "22%",
            height = 112,
            backgroundImage = CARD_IMAGE,
            backgroundFit = "stretch",
            borderWidth = 0,
            borderRadius = 8,
            padding = 7,
            flexDirection = "column",
            justifyContent = "center",
            alignItems = "center",
            onClick = function(self_w)
                self:onOrePick_(idx, self_w, oreLabel, oreTypeLabel)
            end,
            children = {
                UI.Panel {
                    width = 48,
                    height = 48,
                    backgroundImage = ORE_ICON,
                    backgroundFit = "contain",
                },
                oreLabel,
                oreTypeLabel,
            },
        }

        ore.widget = oreCard
        ore.label = oreLabel
        ore.typeLabel = oreTypeLabel
        oreWidgets[#oreWidgets + 1] = oreCard
    end

    self.gridContainer_ = UI.Panel {
        width = "100%",
        flexGrow = 1,
        flexDirection = "row",
        flexWrap = "wrap",
        justifyContent = "center",
        alignContent = "center",
        gap = 10,
        paddingHorizontal = 16,
        children = oreWidgets,
    }

    -- ============================
    -- 组合主面板
    -- ============================
    local panel = UI.Panel {
        width = "100%",
        height = "100%",
        flexDirection = "column",
        children = {
            topBar,
            titleLabel,
            self.feedbackLabel_,
            self.gridContainer_,
        },
    }

    container:AddChild(panel)
end

-- ============================================================================
-- 矿石点击
-- ============================================================================

function OreSelectGame:onOrePick_(index, cardWidget, labelWidget, typeLabelWidget)
    if self.finished_ then return end

    local ore = self.ores_[index]
    if not ore or ore.picked then return end

    self.totalClicks_ = self.totalClicks_ + 1
    ore.picked = true

    if ore.isGood then
        -- 正确选择 — 金色/青铜绿高亮
        self.correctPicks_ = self.correctPicks_ + 1
        cardWidget.backgroundImage = CARD_SELECTED_IMAGE
        cardWidget.backgroundColor = "#00000000"
        cardWidget.borderColor = C.oreBorderGood
        cardWidget.borderWidth = 2
        if labelWidget then labelWidget.fontColor = "#2F2518" end
        if typeLabelWidget then
            typeLabelWidget.text = "优质矿石"
            typeLabelWidget.fontColor = "#2F2518"
        end

        self.feedbackLabel_.text = "好矿! (" .. self.correctPicks_ .. "/" .. self.goodCount_ .. ")"
        self.feedbackLabel_.fontColor = C.textSuccess
        SFXManager.Play(SFXManager.SFX.ORE_DROP, 0.6)

        -- 更新进度
        self.progressLabel_.text = "已选: " .. self.correctPicks_ .. "/" .. self.goodCount_

        -- 检查是否完成
        if self.correctPicks_ >= self.goodCount_ then
            self:finishGame_()
        end
    else
        -- 选错杂质 — 红色闪烁
        cardWidget.backgroundImage = CARD_IMAGE
        cardWidget.backgroundColor = C.oreWrong
        cardWidget.borderColor = C.oreBorderBad
        cardWidget.borderWidth = 2
        if labelWidget then labelWidget.fontColor = C.textAccent end
        if typeLabelWidget then
            typeLabelWidget.text = "杂质"
            typeLabelWidget.fontColor = C.textAccent
        end

        self.feedbackLabel_.text = "杂质! 小心辨别"
        self.feedbackLabel_.fontColor = C.textAccent
        SFXManager.Play(SFXManager.SFX.UI_FAIL, 0.4)
    end
end

-- ============================================================================
-- 每帧更新
-- ============================================================================

function OreSelectGame:update(dt)
    if self.finished_ then return end

    self.elapsed_ = self.elapsed_ + dt
    local remaining = math.max(0, self.timeLimit_ - self.elapsed_)
    local pct = remaining / self.timeLimit_

    -- 更新倒计时文字
    if self.timerLabel_ then
        self.timerLabel_.text = string.format("%.1f", remaining) .. "s"
        if remaining < 3 then
            self.timerLabel_.fontColor = C.textAccent
        end
    end

    -- 更新倒计时进度条
    if self.timerBar_ then
        self.timerBar_.width = math.floor(pct * 100) .. "%"
        if remaining < 3 then
            self.timerBar_.backgroundColor = C.textAccent
        end
    end

    -- 超时结束
    if remaining <= 0 then
        self:finishGame_()
    end
end

-- ============================================================================
-- 结算
-- ============================================================================

function OreSelectGame:finishGame_()
    if self.finished_ then return end

    -- 计算精度
    local accuracy = 0
    if self.totalClicks_ > 0 then
        accuracy = self.correctPicks_ / self.totalClicks_
    end

    -- 速度加分：越快完成，加分越多
    local timeBonus = 0
    if self.correctPicks_ >= self.goodCount_ then
        local usedRatio = self.elapsed_ / self.timeLimit_
        if usedRatio < 0.5 then
            timeBonus = 0.15
        elseif usedRatio < 0.75 then
            timeBonus = 0.08
        end
    end

    -- 完成度：选中了多少比例的好矿
    local completionRatio = self.correctPicks_ / self.goodCount_

    -- 最终分数 = 精度 * 完成度 + 速度加分
    local finalScore = math.min(1.0, accuracy * completionRatio + timeBonus)

    -- 映射评级
    local rating
    if finalScore >= 0.90 then rating = "Perfect"
    elseif finalScore >= 0.75 then rating = "Great"
    elseif finalScore >= 0.50 then rating = "Good"
    else rating = "Poor"
    end

    self:finish(finalScore, rating)

    -- 更新 UI — 禁用所有未选矿石
    for i = 1, #self.ores_ do
        local ore = self.ores_[i]
        if not ore.picked and ore.widget then
            ore.widget.backgroundColor = "rgba(30,25,20,0.5)"
            ore.widget.borderColor = "#3A322B"
            if ore.label then ore.label.fontColor = "#6A5A4A" end
        end
    end

    -- 更新反馈文字
    if self.feedbackLabel_ then
        local ratingName = {
            Perfect = "神匠之眼!",
            Great = "眼力不错!",
            Good = "尚可",
            Poor = "需要历练...",
        }
        self.feedbackLabel_.text = (ratingName[rating] or rating) .. " (得分: " .. string.format("%.0f", finalScore * 100) .. ")"
        if rating == "Perfect" then
            self.feedbackLabel_.fontColor = C.textWarning
        elseif rating == "Great" then
            self.feedbackLabel_.fontColor = C.textSuccess
        elseif rating == "Good" then
            self.feedbackLabel_.fontColor = C.textPrimary
        else
            self.feedbackLabel_.fontColor = C.textAccent
        end
    end

    print("[OreSelectGame] Finished: score=" .. string.format("%.2f", finalScore)
        .. " rating=" .. rating
        .. " accuracy=" .. string.format("%.2f", accuracy)
        .. " picks=" .. self.correctPicks_ .. "/" .. self.goodCount_
        .. " clicks=" .. self.totalClicks_)
end

return OreSelectGame
