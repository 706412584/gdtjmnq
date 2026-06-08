---@diagnostic disable: assign-type-mismatch
-- ============================================================================
-- AssemblyGame - 组装装饰小游戏
-- Project Smith / P2-A3
--
-- 玩法: 顺序组装
--   - 屏幕上方显示一组零件/装饰部件（乱序排列）
--   - 下方显示空的装配槽位（有编号提示正确顺序）
--   - 玩家依次点击正确的零件，放入当前槽位
--   - 正确顺序加分，错误选择扣分
--   - 限时完成，速度加分
--
-- 渲染方式: UI 组件
-- 输入: 点击
-- ============================================================================

local UI = require("urhox-libs/UI")
local MiniGameBase = require("MiniGame.MiniGameBase")
local SFXManager = require("Utils.SFXManager")

local AssemblyGame = MiniGameBase.Extend()

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

    partDefault   = { 60,  70,  100, 255 },
    partCorrect   = { 60,  160, 130, 255 },
    partWrong     = { 180, 60,  60,  255 },
    partUsed      = { 50,  55,  70,  255 },
    slotEmpty     = { 45,  50,  70,  255 },
    slotFilled    = { 80,  130, 110, 255 },
    slotCurrent   = { 100, 90,  50,  255 },
}

-- 零件名称池（根据武器类型可扩展）
local PART_NAMES = {
    "刀柄缠绳",
    "护手铜环",
    "刀鞘内衬",
    "刃口淬油",
    "柄尾坠饰",
    "刀镡雕花",
    "鞘口铜箍",
    "刀身铭文",
    "柄木打磨",
    "刀脊修直",
}

-- ============================================================================
-- 初始化
-- ============================================================================

function AssemblyGame:init(config)
    MiniGameBase.init(self, config)

    local difficulty = config.difficulty or 1

    -- 游戏参数
    self.totalParts_  = 4 + difficulty             -- 零件数
    self.timeLimit_   = 18 + (3 - difficulty) * 3  -- 时间限制

    -- 状态
    self.currentSlot_ = 1
    self.elapsed_     = 0
    self.correctPicks_ = 0
    self.wrongPicks_  = 0
    self.parts_       = {}       -- { name, correctOrder, used, widget }
    self.slots_       = {}       -- { filled, widget }

    -- UI 引用
    self.timerLabel_    = nil
    self.progressLabel_ = nil
    self.feedbackLabel_ = nil

    self:generateParts_()
    self:buildUI_()
end

-- ============================================================================
-- 零件生成
-- ============================================================================

function AssemblyGame:generateParts_()
    self.parts_ = {}

    -- 选取不重复的零件名称
    local available = {}
    for i = 1, #PART_NAMES do
        available[i] = PART_NAMES[i]
    end
    -- Fisher-Yates 打乱选取
    for i = #available, 2, -1 do
        local j = math.random(1, i)
        available[i], available[j] = available[j], available[i]
    end

    -- 创建零件（按正确顺序）
    for i = 1, self.totalParts_ do
        self.parts_[i] = {
            name = available[((i - 1) % #available) + 1],
            correctOrder = i,
            used = false,
        }
    end

    -- 创建显示用打乱序列
    self.shuffledIndices_ = {}
    for i = 1, self.totalParts_ do
        self.shuffledIndices_[i] = i
    end
    for i = self.totalParts_, 2, -1 do
        local j = math.random(1, i)
        self.shuffledIndices_[i], self.shuffledIndices_[j] =
            self.shuffledIndices_[j], self.shuffledIndices_[i]
    end

    -- 创建槽位
    self.slots_ = {}
    for i = 1, self.totalParts_ do
        self.slots_[i] = { filled = false }
    end
end

-- ============================================================================
-- UI 构建
-- ============================================================================

function AssemblyGame:buildUI_()
    local container = self.container_
    if not container then return end

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
        text = "组装: 0/" .. self.totalParts_,
        fontSize = 14,
        fontColor = C.success,
    }

    self.feedbackLabel_ = UI.Label {
        text = "按顺序点击零件进行组装",
        fontSize = 12,
        fontColor = C.textSecondary,
        textAlign = "center",
        width = "100%",
        height = 18,
    }

    -- 零件按钮（打乱显示）
    local partWidgets = {}
    self.partWidgets_ = {}
    for displayIdx = 1, self.totalParts_ do
        local actualIdx = self.shuffledIndices_[displayIdx]
        local part = self.parts_[actualIdx]
        local btn = UI.Button {
            text = part.name,
            width = "45%",
            height = 48,
            fontSize = 12,
            backgroundColor = C.partDefault,
            hoverBackgroundColor = { 75, 85, 115, 255 },
            pressedBackgroundColor = { 50, 58, 85, 255 },
            fontColor = C.textPrimary,
            borderRadius = 6,
            onClick = function()
                self:onPartPick_(actualIdx)
            end,
        }
        part.widget = btn
        self.partWidgets_[actualIdx] = btn
        partWidgets[#partWidgets + 1] = btn
    end

    -- 装配槽位
    local slotWidgets = {}
    for i = 1, self.totalParts_ do
        local isFirst = (i == 1)
        local slot = UI.Panel {
            width = "80%",
            height = 36,
            borderRadius = 4,
            backgroundColor = isFirst and C.slotCurrent or C.slotEmpty,
            justifyContent = "center",
            alignItems = "center",
            children = {
                UI.Label {
                    text = "第 " .. i .. " 步",
                    fontSize = 11,
                    fontColor = C.textSecondary,
                },
            },
        }
        self.slots_[i].widget = slot
        slotWidgets[#slotWidgets + 1] = slot
    end

    local panel = UI.Panel {
        width = "100%",
        height = "100%",
        flexDirection = "column",
        alignItems = "center",
        paddingTop = 16,
        paddingHorizontal = 10,
        gap = 8,
        children = {
            UI.Label {
                text = stepText .. "组装装饰",
                fontSize = 18,
                fontColor = C.gold,
            },
            -- 信息栏
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
            self.feedbackLabel_,
            -- 零件区域（标题）
            UI.Label {
                text = "--- 可用零件 ---",
                fontSize = 11,
                fontColor = C.textSecondary,
            },
            -- 零件网格
            UI.Panel {
                width = "100%",
                flexDirection = "row",
                flexWrap = "wrap",
                justifyContent = "space-around",
                gap = 6,
                paddingHorizontal = 6,
                children = partWidgets,
            },
            -- 装配区域（标题）
            UI.Label {
                text = "--- 装配顺序 ---",
                fontSize = 11,
                fontColor = C.textSecondary,
            },
            -- 槽位列表
            UI.ScrollView {
                width = "100%",
                flexGrow = 1,
                flexBasis = 0,
                flexShrink = 1,
                children = {
                    UI.Panel {
                        width = "100%",
                        flexDirection = "column",
                        alignItems = "center",
                        gap = 4,
                        children = slotWidgets,
                    },
                },
            },
        },
    }

    container:AddChild(panel)
end

-- ============================================================================
-- 零件选择
-- ============================================================================

function AssemblyGame:onPartPick_(partIndex)
    if self.finished_ then return end

    local part = self.parts_[partIndex]
    if not part or part.used then return end

    if part.correctOrder == self.currentSlot_ then
        -- 正确选择
        part.used = true
        self.correctPicks_ = self.correctPicks_ + 1

        -- 更新零件外观
        if part.widget then
            part.widget.backgroundColor = C.partCorrect
            part.widget.fontColor = C.bgCard
            part.widget.text = part.name .. " [OK]"
        end

        -- 更新槽位
        local slot = self.slots_[self.currentSlot_]
        if slot and slot.widget then
            slot.filled = true
            slot.widget.backgroundColor = C.slotFilled
            -- 更新槽位文字
            slot.widget:ClearChildren()
            slot.widget:AddChild(UI.Label {
                text = part.name,
                fontSize = 11,
                fontColor = C.textPrimary,
            })
        end

        -- 音效
        SFXManager.Play(SFXManager.SFX.HAMMER_LIGHT, 0.5)

        self.progressLabel_.text = "组装: " .. self.correctPicks_ .. "/" .. self.totalParts_
        self.feedbackLabel_.text = "正确!"
        self.feedbackLabel_.fontColor = C.success

        -- 推进到下一槽位
        self.currentSlot_ = self.currentSlot_ + 1

        -- 高亮下一槽位
        if self.currentSlot_ <= self.totalParts_ then
            local nextSlot = self.slots_[self.currentSlot_]
            if nextSlot and nextSlot.widget then
                nextSlot.widget.backgroundColor = C.slotCurrent
            end
        end

        -- 检查完成
        if self.correctPicks_ >= self.totalParts_ then
            self:finishGame_()
        end
    else
        -- 错误选择
        self.wrongPicks_ = self.wrongPicks_ + 1

        -- 闪红提示
        if part.widget then
            part.widget.backgroundColor = C.partWrong
            -- 恢复颜色（简单方式：立即恢复，因为没有 tween 做 delay）
            -- 用 Timer 模块可以做延迟恢复，此处简化处理
            part.widget.backgroundColor = C.partDefault
        end

        self.feedbackLabel_.text = "顺序不对! 请选第 " .. self.currentSlot_ .. " 步"
        self.feedbackLabel_.fontColor = C.accent
        SFXManager.Play(SFXManager.SFX.UI_FAIL, 0.3)
    end
end

-- ============================================================================
-- 每帧更新
-- ============================================================================

function AssemblyGame:update(dt)
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

function AssemblyGame:finishGame_()
    if self.finished_ then return end

    -- 完成度
    local completionRatio = self.correctPicks_ / self.totalParts_

    -- 精度：错误选择扣分
    local totalAttempts = self.correctPicks_ + self.wrongPicks_
    local accuracy = 1.0
    if totalAttempts > 0 then
        accuracy = self.correctPicks_ / totalAttempts
    end

    -- 速度加分
    local timeBonus = 0
    if self.correctPicks_ >= self.totalParts_ then
        local usedRatio = self.elapsed_ / self.timeLimit_
        if usedRatio < 0.4 then
            timeBonus = 0.12
        elseif usedRatio < 0.65 then
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

    print("[AssemblyGame] Finished: score=" .. string.format("%.2f", finalScore)
        .. " rating=" .. rating
        .. " correct=" .. self.correctPicks_ .. "/" .. self.totalParts_
        .. " wrong=" .. self.wrongPicks_)
end

return AssemblyGame
