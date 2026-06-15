-- ============================================================================
-- StoryScreen - AVG 对话界面（迁移版：使用 ui_StoryScreen 布局）
-- Project Smith
--
-- 功能：
--   1. 使用 ui_StoryScreen_剧情对话.Build() 作为视觉层
--   2. 通过 FindById 绑定动态元素
--   3. 保留完整对话推进逻辑（ShowNextLine/ShowChoices/FinishNode）
--   4. 角色立绘/背景图动态切换
--   5. 分支选择按钮展示
--   6. 对话完毕后自动返回指定界面
-- ============================================================================

local UI           = require("urhox-libs/UI")
local StoryManager = require("Story.StoryManager")
local ScreenRouter = require("Utils.ScreenRouter")
local EventBus     = require("Core.EventBus")
local SFXManager   = require("Utils.SFXManager")

local StoryLayout  = require("ui_StoryScreen_剧情对话")

local StoryScreen = {}

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

    -- ----------------------------------------------------------------
    -- 1. 构建 UI 树（从布局模块）
    -- ----------------------------------------------------------------
    local root = StoryLayout.Build()
    container:AddChild(root)

    -- ----------------------------------------------------------------
    -- 2. 通过 FindById 获取动态元素引用
    -- ----------------------------------------------------------------

    -- 背景图容器
    local bgPanel_ = root:FindById("ph_1")
    -- 角色立绘容器
    local portraitFrame_ = root:FindById("ph_i")
    local portraitImg_ = root:FindById("sr_j")
    -- 角色名标签（对话框上方）
    local nameTag_ = root:FindById("sr_10")
    local nameLabel_ = root:FindById("tx_11")
    -- 对话文本
    local textLabel_ = root:FindById("tx_12")
    -- 对话底板（用于点击推进）
    local dialogueBox_ = root:FindById("sr_z")
    -- 对话滚动容器
    local scrollText_ = root:FindById("scroll_text")

    -- 左侧面板信息（角色大名+描述）
    local charTitleLabel_ = root:FindById("tx_o")
    local charDescLabel_ = root:FindById("tx_p")

    -- 章节信息面板（横屏专属，竖屏下可能溢出，隐藏处理）
    local chapterPanel_ = root:FindById("df_q")
    local chapterTitle_ = root:FindById("tx_w")
    local chapterSummary_ = root:FindById("tx_y")

    -- 选项按钮（固定 4 个槽位）
    local choicePlates_ = {
        root:FindById("plate_13"),
        root:FindById("plate_16"),
        root:FindById("plate_19"),
        root:FindById("plate_1c"),
    }
    local choiceLabels_ = {
        root:FindById("tx_15"),
        root:FindById("tx_18"),
        root:FindById("tx_1b"),
        root:FindById("tx_1e"),
    }

    -- 顶部按钮
    local skipBtn_ = root:FindById("plate_1f")
    local backBtn_ = root:FindById("plate_1i")

    -- ----------------------------------------------------------------
    -- 3. 初始化：隐藏选项按钮 + 绑定顶部按钮
    -- ----------------------------------------------------------------

    -- 隐藏全部选项按钮
    for i = 1, #choicePlates_ do
        if choicePlates_[i] then
            choicePlates_[i].visible = false
        end
    end

    -- 横屏章节面板在竖屏下隐藏（坐标溢出）
    if chapterPanel_ then
        chapterPanel_.visible = false
    end
    if chapterTitle_ then
        chapterTitle_.visible = false
    end
    if chapterSummary_ then
        chapterSummary_.visible = false
    end

    -- 跳过按钮
    if skipBtn_ then
        skipBtn_.props.onClick = function()
            SFXManager.Play(SFXManager.SFX.UI_TAP, 0.5)
            -- 跳过当前全部剧情，标记完成
            StoryManager.SkipCurrentChapter()
            ScreenRouter.GoTo(returnTo_)
        end
    end

    -- 返回按钮
    if backBtn_ then
        backBtn_.props.onClick = function()
            SFXManager.Play(SFXManager.SFX.UI_TAP, 0.5)
            ScreenRouter.GoTo(returnTo_)
        end
    end

    -- ----------------------------------------------------------------
    -- 4. 对话逻辑函数
    -- ----------------------------------------------------------------

    --- 更新背景图
    local function UpdateBackground(bgPath)
        if bgPanel_ and bgPath then
            bgPanel_.backgroundImage = bgPath
        end
    end

    --- 更新角色立绘
    local function UpdatePortrait(speakerId)
        if not portraitImg_ then return end

        local charConfig = StoryManager.GetCharacterConfig(speakerId)
        if charConfig and charConfig.portrait then
            portraitImg_.backgroundImage = charConfig.portrait
            if portraitFrame_ then
                portraitFrame_.visible = true
            end
            -- 更新左侧角色名信息
            if charTitleLabel_ then
                charTitleLabel_.text = "· " .. (charConfig.name or "") .. " · "
            end
            if charDescLabel_ then
                charDescLabel_.text = charConfig.desc or ""
            end
        else
            -- 旁白或无立绘角色，隐藏立绘
            if portraitFrame_ then
                portraitFrame_.visible = false
            end
            if charTitleLabel_ then
                charTitleLabel_.text = ""
            end
            if charDescLabel_ then
                charDescLabel_.text = ""
            end
        end
    end

    --- 显示选择按钮
    local function ShowChoices()
        -- 选择出现音效
        SFXManager.Play(SFXManager.SFX.STORY_REVEAL, 0.4)

        if not currentNode_ or not currentNode_.choices then return end

        local choices = currentNode_.choices
        for i = 1, #choicePlates_ do
            if i <= #choices then
                -- 显示并设置文本
                choicePlates_[i].visible = true
                if choiceLabels_[i] then
                    choiceLabels_[i].text = choices[i].text or ""
                end
                -- 绑定点击
                local idx = i
                choicePlates_[i].props.onClick = function()
                    OnChoiceSelected(idx)
                end
            else
                -- 超出选项数量的按钮隐藏
                choicePlates_[i].visible = false
            end
        end
    end

    --- 处理选择
    function OnChoiceSelected(choiceIndex)
        -- 选择确认音效
        SFXManager.Play(SFXManager.SFX.UI_TAP, 0.5)

        isShowingChoices_ = false

        -- 隐藏所有选项
        for i = 1, #choicePlates_ do
            if choicePlates_[i] then
                choicePlates_[i].visible = false
            end
        end

        -- 通知 StoryManager 应用选择效果并推进
        StoryManager.MakeChoice(choiceIndex)

        -- 加载下一个节点
        LoadNextNode()
    end

    --- 完成当前对话节点
    local function FinishNode()
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

    --- 显示下一行对话
    function ShowNextLine()
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
                isShowingChoices_ = true
                ShowChoices()
            else
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
                sfx = SFXManager.SFX.CHAR_GREET
            end
            if sfx then
                SFXManager.Play(sfx, 0.45)
            end
        end

        -- 更新 UI（增量）
        UpdatePortrait(speakerId)

        if nameLabel_ then
            if speakerId == "narrator" then
                nameLabel_.text = "旁白"
                if nameTag_ then
                    nameTag_.backgroundColor = "#3A322B"
                end
            else
                nameLabel_.text = line.name or charConfig.name or ""
                if nameTag_ then
                    nameTag_.backgroundColor = "#C96A2B"
                end
            end
        end

        if textLabel_ then
            textLabel_.text = line.text or ""
        end
    end

    --- 点击处理（推进对话）
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
    -- 5. 绑定对话底板点击事件
    -- ----------------------------------------------------------------
    if dialogueBox_ then
        dialogueBox_.props.onClick = function()
            OnTapAdvance()
        end
    end
    -- 同时给滚动文本区绑定点击
    if scrollText_ then
        scrollText_.props.onClick = function()
            OnTapAdvance()
        end
    end

    -- ----------------------------------------------------------------
    -- 6. 立绘伪待机动画（呼吸浮动效果）
    -- ----------------------------------------------------------------
    local idleTime_ = 0.0
    local FLOAT_AMP = 3.0       -- 上下浮动幅度(px)
    local FLOAT_SPEED = 1.8     -- 浮动频率
    local BREATH_AMP = 0.006    -- 呼吸缩放幅度
    local BREATH_SPEED = 2.4    -- 呼吸频率（略快于浮动，产生节奏差）

    local function HandleIdleAnim(eventType, eventData)
        local dt = eventData:GetFloat("TimeStep")
        idleTime_ = idleTime_ + dt

        -- 仅在立绘可见时应用动画
        if not portraitFrame_ or not portraitFrame_.visible then return end
        if not portraitImg_ then return end

        -- 上下浮动（正弦波）
        local floatY = math.sin(idleTime_ * FLOAT_SPEED) * FLOAT_AMP
        portraitImg_.top = math.floor(floatY + 0.5)

        -- 呼吸缩放（用略不同频率产生自然感）
        local breathScale = 1.0 + math.sin(idleTime_ * BREATH_SPEED) * BREATH_AMP
        portraitImg_.scaleX = breathScale
        portraitImg_.scaleY = breathScale
    end

    SubscribeToEvent("Update", HandleIdleAnim)

    -- ----------------------------------------------------------------
    -- 7. 启动对话
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
        if textLabel_ then
            textLabel_.text = "暂无新剧情"
        end
        if nameLabel_ then
            nameLabel_.text = ""
        end
        finished_ = true
    end

    -- ----------------------------------------------------------------
    -- screen 控制器
    -- ----------------------------------------------------------------
    function screen.Destroy()
        UnsubscribeFromEvent("Update")
    end

    return screen
end

return StoryScreen
