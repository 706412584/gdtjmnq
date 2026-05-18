-- ============================================================================
-- OreSelectGame - 选矿去杂小游戏
-- Project Smith / P1-C2
--
-- 玩法: 屏幕显示若干矿石块，其中混有杂质。
--   - 玩家点击选择优质矿石（绿色高亮）
--   - 点击杂质会扣分（红色闪烁）
--   - 限时内选够指定数量的好矿即完成
--   - 精度 = 正确选择数 / 总点击数，速度加分
--
-- 渲染方式: UI 组件（按 dev-plan 规格）
-- 输入: 点击
-- ============================================================================

local UI = require("urhox-libs/UI")
local MiniGameBase = require("MiniGame.MiniGameBase")
local Timer = require("Utils.Timer")
local SFXManager = require("Utils.SFXManager")

local OreSelectGame = MiniGameBase.Extend()

-- ============================================================================
-- 色板
-- ============================================================================

local C = {
    bgPrimary    = { 26,  26,  46,  255 },
    bgCard       = { 30,  40,  68,  255 },
    gold         = { 212, 165, 116, 255 },
    textPrimary  = { 232, 224, 208, 255 },
    textSecondary = { 160, 147, 125, 255 },
    accent       = { 233, 69,  96,  255 },
    success      = { 78,  205, 196, 255 },
    warning      = { 255, 217, 61,  255 },

    oreGood      = { 90,  140, 110, 255 },   -- 优质矿石
    oreGoodBorder = { 120, 190, 140, 255 },
    oreBad       = { 100, 80,  70,  255 },   -- 杂质
    oreBadBorder = { 160, 100, 80,  255 },
    oreDefault   = { 70,  75,  95,  255 },   -- 未选中
    oreSelected  = { 60,  160, 120, 255 },   -- 已选中（好）
    oreWrong     = { 200, 60,  60,  255 },   -- 选错（坏）
}

-- 矿石名称池
local ORE_NAMES = {
    good = { "精铁矿", "黑铁矿", "玄铁矿", "锡矿石", "铜矿石", "银矿石" },
    bad  = { "ite岩渣", "土块", "碎石", "铁锈块", "风化石", "杂矿渣" },
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
-- UI 构建
-- ============================================================================

function OreSelectGame:buildUI_()
    local container = self.container_
    if not container then return end

    self.timerLabel_ = UI.Label {
        text = "剩余: " .. self.timeLimit_ .. "s",
        fontSize = 14,
        fontColor = C.warning,
    }

    self.progressLabel_ = UI.Label {
        text = "已选: 0/" .. self.goodCount_,
        fontSize = 14,
        fontColor = C.success,
    }

    self.feedbackLabel_ = UI.Label {
        text = "点选优质矿石，避开杂质",
        fontSize = 12,
        fontColor = C.textSecondary,
        textAlign = "center",
        width = "100%",
        height = 18,
    }

    -- 创建矿石按钮网格
    local oreWidgets = {}
    for i = 1, #self.ores_ do
        local ore = self.ores_[i]
        local idx = i
        local btn = UI.Button {
            text = ore.name,
            width = "30%",
            height = 56,
            fontSize = 12,
            backgroundColor = C.oreDefault,
            hoverBackgroundColor = { 85, 90, 110, 255 },
            pressedBackgroundColor = { 55, 60, 80, 255 },
            fontColor = C.textPrimary,
            borderRadius = 6,
            onClick = function(self_btn)
                self:onOrePick_(idx, self_btn)
            end,
        }
        ore.widget = btn
        oreWidgets[#oreWidgets + 1] = btn
    end

    self.gridContainer_ = UI.Panel {
        width = "100%",
        flexDirection = "row",
        flexWrap = "wrap",
        justifyContent = "space-around",
        gap = 8,
        paddingHorizontal = 8,
        children = oreWidgets,
    }

    -- 步骤指示
    local stepText = ""
    if self.config_ and self.config_.stepIndex and self.config_.totalSteps then
        stepText = "步骤 " .. self.config_.stepIndex .. "/" .. self.config_.totalSteps .. ": "
    end

    local panel = UI.Panel {
        width = "100%",
        height = "100%",
        flexDirection = "column",
        alignItems = "center",
        paddingTop = 20,
        paddingHorizontal = 12,
        gap = 10,
        children = {
            UI.Label {
                text = stepText .. "选矿去杂",
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
            -- 反馈文字
            self.feedbackLabel_,
            -- 矿石网格
            self.gridContainer_,
        },
    }

    container:AddChild(panel)
end

-- ============================================================================
-- 矿石点击
-- ============================================================================

function OreSelectGame:onOrePick_(index, btnWidget)
    if self.finished_ then return end

    local ore = self.ores_[index]
    if not ore or ore.picked then return end

    self.totalClicks_ = self.totalClicks_ + 1
    ore.picked = true

    if ore.isGood then
        -- 正确选择
        self.correctPicks_ = self.correctPicks_ + 1
        btnWidget.backgroundColor = C.oreSelected
        btnWidget.fontColor = C.textPrimary
        self.feedbackLabel_.text = "好矿! (" .. self.correctPicks_ .. "/" .. self.goodCount_ .. ")"
        self.feedbackLabel_.fontColor = C.success
        SFXManager.Play(SFXManager.SFX.ORE_DROP, 0.6)

        -- 更新进度
        self.progressLabel_.text = "已选: " .. self.correctPicks_ .. "/" .. self.goodCount_

        -- 检查是否完成
        if self.correctPicks_ >= self.goodCount_ then
            self:finishGame_()
        end
    else
        -- 选错杂质
        btnWidget.backgroundColor = C.oreWrong
        btnWidget.fontColor = C.textPrimary
        self.feedbackLabel_.text = "杂质! 小心选择"
        self.feedbackLabel_.fontColor = C.accent
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

    -- 更新倒计时
    if self.timerLabel_ then
        self.timerLabel_.text = "剩余: " .. string.format("%.1f", remaining) .. "s"
        if remaining < 3 then
            self.timerLabel_.fontColor = C.accent
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

    -- 更新 UI
    if self.feedbackLabel_ then
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
    end

    print("[OreSelectGame] Finished: score=" .. string.format("%.2f", finalScore)
        .. " rating=" .. rating
        .. " accuracy=" .. string.format("%.2f", accuracy)
        .. " picks=" .. self.correctPicks_ .. "/" .. self.goodCount_
        .. " clicks=" .. self.totalClicks_)
end

return OreSelectGame
