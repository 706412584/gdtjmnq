-- ============================================================================
-- StoryScreen - AVG 对话界面
-- Project Smith / P2-B4
--
-- 功能：
--   1. 全屏背景图展示
--   2. 角色立绘展示（左/右侧）
--   3. 底部对话框（半透明，显示说话人名+对话文本）
--   4. 点击任意位置推进对话
--   5. 分支选择按钮展示
--   6. 对话完毕后自动返回指定界面
-- ============================================================================

local UI           = require("urhox-libs/UI")
local StoryManager = require("Story.StoryManager")
local ScreenRouter = require("Utils.ScreenRouter")
local EventBus     = require("Core.EventBus")
local SFXManager   = require("Utils.SFXManager")

local StoryScreen = {}

-- ============================================================================
-- UI 素材路径（武侠水墨风）
-- ============================================================================

local UI_ASSETS = {
    panel_card = "image/ui/panel_card.png",
    btn_choice = "image/ui/btn_choice.png",
}

-- ============================================================================
-- 色板
-- ============================================================================

local C = {
    bgPrimary     = { 26,  26,  46,  255 },
    bgDialogue    = { 10,  10,  20,  220 },
    bgChoice      = { 40,  50,  80,  240 },
    bgChoiceHover = { 55,  65,  100, 255 },
    bgChoicePress = { 30,  40,  65,  255 },
    gold          = { 212, 165, 116, 255 },
    textPrimary   = { 232, 224, 208, 255 },
    textSecondary = { 160, 147, 125, 255 },
    textNarrator  = { 180, 190, 200, 255 },
    accent        = { 233, 69,  96,  255 },
    divider       = { 80,  80,  120, 100 },
}

-- ============================================================================
-- Screen 接口
-- ============================================================================

--- 创建 AVG 对话界面
---@param container table UI 容器
---@param params table|nil { returnTo = "home" }
---@return table screen
function StoryScreen.Create(container, params)
    local screen = {}

    local returnTo_ = (params and params.returnTo) or "home"

    -- 当前节点和行索引
    local currentNode_ = StoryManager.GetCurrentNode()
    local lineIndex_ = 0
    local isShowingChoices_ = false
    local finished_ = false

    -- UI 元素引用（增量更新）
    local bgPanel_
    local portraitPanel_
    local speakerLabel_
    local textLabel_
    local dialogueBox_
    local choiceContainer_
    local tapArea_

    -- ----------------------------------------------------------------
    -- 内部函数
    -- ----------------------------------------------------------------

    --- 更新背景图
    local function UpdateBackground(bgPath)
        if bgPanel_ and bgPath then
            bgPanel_.backgroundImage = bgPath
        end
    end

    --- 更新角色立绘
    local function UpdatePortrait(speakerId)
        if not portraitPanel_ then return end

        local charConfig = StoryManager.GetCharacterConfig(speakerId)
        if charConfig.portrait then
            portraitPanel_.backgroundImage = charConfig.portrait
            portraitPanel_.opacity = 1.0
            -- 根据站位调整位置
            if charConfig.side == "left" then
                portraitPanel_.alignSelf = "flex-start"
                portraitPanel_.marginLeft = 10
                portraitPanel_.marginRight = 0
            else
                portraitPanel_.alignSelf = "flex-end"
                portraitPanel_.marginLeft = 0
                portraitPanel_.marginRight = 10
            end
        else
            portraitPanel_.opacity = 0.0
        end
    end

    --- 显示下一行对话
    local function ShowNextLine()
        if not currentNode_ or finished_ then return end

        local lines = currentNode_.lines
        if not lines then
            finished_ = true
            return
        end

        lineIndex_ = lineIndex_ + 1

        if lineIndex_ > #lines then
            -- 所有台词播完
            if currentNode_.type == "choice" then
                -- 显示选择
                isShowingChoices_ = true
                ShowChoices()
            else
                -- 完成对话，推进节点
                FinishNode()
            end
            return
        end

        local line = lines[lineIndex_]
        local speakerId = line.speaker or "narrator"
        local charConfig = StoryManager.GetCharacterConfig(speakerId)

        -- 对话推进音效
        SFXManager.Play(SFXManager.SFX.UI_PAGE_TURN, 0.3)

        -- 人物语气音效（基于文本关键词自动推断情绪）
        if speakerId ~= "narrator" then
            local text = line.text or ""
            local sfx = nil
            if string.find(text, "哈") or string.find(text, "笑")
                or string.find(text, "哼哼") or string.find(text, "嘿嘿") then
                sfx = SFXManager.SFX.CHAR_LAUGH
            elseif string.find(text, "！") or string.find(text, "什么")
                or string.find(text, "竟然") or string.find(text, "不可能")
                or string.find(text, "怎么会") or string.find(text, "居然") then
                sfx = SFXManager.SFX.CHAR_SURPRISE
            elseif string.find(text, "不行") or string.find(text, "不可")
                or string.find(text, "不许") or string.find(text, "哼")
                or string.find(text, "别想") or string.find(text, "住手") then
                sfx = SFXManager.SFX.CHAR_DISAPPROVE
            elseif string.find(text, "好") or string.find(text, "不错")
                or string.find(text, "行") or string.find(text, "可以")
                or string.find(text, "善") or string.find(text, "妙") then
                sfx = SFXManager.SFX.CHAR_APPROVE
            elseif string.find(text, "唉") or string.find(text, "嗯")
                or string.find(text, "想想") or string.find(text, "也许")
                or string.find(text, "若是") or string.find(text, "恐怕") then
                sfx = SFXManager.SFX.CHAR_THINK
            elseif lineIndex_ == 1 then
                -- 角色在该节点的第一句话，播放问候音
                sfx = SFXManager.SFX.CHAR_GREET
            end
            if sfx then
                SFXManager.Play(sfx, 0.45)
            end
        end

        -- 更新 UI
        UpdatePortrait(speakerId)

        if speakerLabel_ then
            if speakerId == "narrator" then
                speakerLabel_.text = ""
            else
                speakerLabel_.text = line.name or charConfig.name or ""
            end
        end

        if textLabel_ then
            textLabel_.text = line.text or ""
            if speakerId == "narrator" then
                textLabel_.fontColor = C.textNarrator
            else
                textLabel_.fontColor = C.textPrimary
            end
        end
    end

    --- 显示选择按钮
    function ShowChoices()
        -- 选择出现音效
        SFXManager.Play(SFXManager.SFX.STORY_REVEAL, 0.4)

        if not choiceContainer_ or not currentNode_ or not currentNode_.choices then return end

        -- 隐藏点击继续提示，并让点击穿透到选项按钮
        if tapArea_ then
            tapArea_.opacity = 0.0
            tapArea_.pointerEvents = "none"
        end

        choiceContainer_:ClearChildren()

        local choices = currentNode_.choices
        for i = 1, #choices do
            local choice = choices[i]
            local idx = i  -- 闭包捕获

            choiceContainer_:AddChild(UI.Button {
                text = choice.text,
                width = "90%",
                height = 48,
                fontSize = 14,
                backgroundImage = UI_ASSETS.btn_choice,
                backgroundFit = "cover",
                fontColor = C.textPrimary,
                borderRadius = 8,
                marginBottom = 8,
                onClick = function()
                    OnChoiceSelected(idx)
                end,
            })
        end

        choiceContainer_.opacity = 1.0
    end

    --- 处理选择
    function OnChoiceSelected(choiceIndex)
        -- 选择确认音效
        SFXManager.Play(SFXManager.SFX.UI_TAP, 0.5)

        isShowingChoices_ = false

        if choiceContainer_ then
            choiceContainer_:ClearChildren()
            choiceContainer_.opacity = 0.0
        end

        -- 恢复点击区域
        if tapArea_ then
            tapArea_.opacity = 1.0
            tapArea_.pointerEvents = "auto"
        end

        -- 通知 StoryManager 应用选择效果并推进
        StoryManager.MakeChoice(choiceIndex)

        -- 加载下一个节点
        LoadNextNode()
    end

    --- 完成当前对话节点
    function FinishNode()
        -- 检查是否触发订单
        local shouldTriggerOrder = currentNode_.triggerOrder == true

        -- 通知 StoryManager 推进
        StoryManager.CompleteDialogueNode()

        if shouldTriggerOrder then
            -- 剧情触发订单：跳到订单板
            ScreenRouter.GoTo("orderBoard")
            return
        end

        -- 尝试加载下一个节点
        LoadNextNode()
    end

    --- 加载下一个节点
    function LoadNextNode()
        currentNode_ = StoryManager.GetCurrentNode()
        lineIndex_ = 0
        isShowingChoices_ = false

        if not currentNode_ then
            -- 没有更多节点，返回
            print("[StoryScreen] No more story nodes, returning to " .. returnTo_)
            ScreenRouter.GoTo(returnTo_)
            return
        end

        -- 检查条件
        if currentNode_.condition then
            -- 条件不满足，返回（等待下次触发）
            if not StoryManager.HasPendingStory() then
                print("[StoryScreen] Next node condition not met, returning")
                ScreenRouter.GoTo(returnTo_)
                return
            end
        end

        -- 更新背景
        if currentNode_.background then
            UpdateBackground(currentNode_.background)
        end

        -- 显示第一行
        ShowNextLine()
    end

    --- 点击处理
    local function OnTapAdvance()
        if finished_ then
            ScreenRouter.GoTo(returnTo_)
            return
        end

        if isShowingChoices_ then
            return  -- 选择模式下不响应点击推进
        end

        ShowNextLine()
    end

    -- ----------------------------------------------------------------
    -- UI 构建
    -- ----------------------------------------------------------------

    -- 角色立绘容器
    portraitPanel_ = UI.Panel {
        width = 180,
        height = 300,
        position = "absolute",
        bottom = 180,
        left = 10,
        backgroundFit = "contain",
        opacity = 0.0,
    }

    -- 说话人名字
    speakerLabel_ = UI.Label {
        text = "",
        fontSize = 15,
        fontColor = C.gold,
        fontWeight = "bold",
    }

    -- 对话文本（whiteSpace="normal" 启用自动换行）
    textLabel_ = UI.Label {
        text = "",
        fontSize = 14,
        fontColor = C.textPrimary,
        width = "100%",
        flexShrink = 1,
        whiteSpace = "normal",
        lineHeight = 1.6,
    }

    -- 点击继续提示
    local continueHint = UI.Label {
        text = "[ 点击继续 ]",
        fontSize = 11,
        fontColor = C.textSecondary,
        textAlign = "right",
        width = "100%",
    }

    -- 对话框（半透明底 + 水墨面板装饰）
    dialogueBox_ = UI.Panel {
        width = "100%",
        position = "absolute",
        bottom = 0,
        left = 0,
        right = 0,
        backgroundColor = { 10, 10, 20, 200 },
        backgroundImage = UI_ASSETS.panel_card,
        backgroundFit = "cover",
        paddingTop = 16,
        paddingBottom = 14,
        paddingHorizontal = 20,
        gap = 6,
        minHeight = 150,
        children = {
            speakerLabel_,
            textLabel_,
            continueHint,
        },
    }

    -- 选择容器（覆盖在对话框上方）
    choiceContainer_ = UI.Panel {
        width = "100%",
        position = "absolute",
        bottom = 150,
        left = 0,
        right = 0,
        alignItems = "center",
        opacity = 0.0,
    }

    -- 点击区域（覆盖整个屏幕用于推进对话）
    tapArea_ = UI.Panel {
        width = "100%",
        height = "100%",
        position = "absolute",
        top = 0,
        left = 0,
        onClick = function()
            OnTapAdvance()
        end,
    }

    -- 背景面板
    bgPanel_ = UI.Panel {
        width = "100%",
        height = "100%",
        backgroundColor = C.bgPrimary,
        backgroundFit = "cover",
    }

    -- 组装主面板
    -- 注意 children 顺序决定 z-index：后面的在上层
    -- tapArea_ 放在 choiceContainer_ 之前，确保选项按钮可点击
    local mainPanel = UI.Panel {
        width = "100%",
        height = "100%",
        children = {
            bgPanel_,
            portraitPanel_,
            dialogueBox_,
            tapArea_,
            choiceContainer_,
        },
    }

    container:AddChild(mainPanel)

    -- ----------------------------------------------------------------
    -- 启动对话
    -- ----------------------------------------------------------------
    if currentNode_ then
        -- 设置背景
        if currentNode_.background then
            UpdateBackground(currentNode_.background)
        end

        -- 显示第一行
        ShowNextLine()

        print("[StoryScreen] Started node: " .. (currentNode_.id or "?")
            .. " (" .. (currentNode_.title or "") .. ")")
    else
        -- 没有可用节点
        textLabel_.text = "暂无新剧情"
        speakerLabel_.text = ""
        continueHint.text = "[ 点击返回 ]"
        finished_ = true
    end

    -- ----------------------------------------------------------------
    -- screen 控制器
    -- ----------------------------------------------------------------
    function screen.Destroy()
        -- 清理
    end

    return screen
end

return StoryScreen
