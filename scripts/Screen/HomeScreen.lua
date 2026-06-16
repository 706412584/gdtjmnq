-- ============================================================================
-- HomeScreen - 工坊主界面（迁移版：使用 ui_HomeScreen 布局）
-- Project Smith
--
-- 功能：
--   1. 使用 ui_HomeScreen_工坊主界面.Build() 作为视觉层
--   2. 通过 FindById 绑定动态元素（货币、设施等级、名望进度）
--   3. 绑定底部导航、顶部按钮、设施卡片点击事件
--   4. 增量更新：EventBus 订阅只修改文本/进度条
-- ============================================================================

local UI             = require("urhox-libs/UI")
local EventBus       = require("Core.EventBus")
local GameState      = require("Core.GameState")
local FacilityConfig = require("Config.FacilityConfig")
local ScreenRouter   = require("Utils.ScreenRouter")
local StoryManager   = require("Story.StoryManager")
local SFXManager     = require("Utils.SFXManager")

local UpgradePopup  = require("Screen.UpgradePopup")
local HomeLayout = require("ui_HomeScreen_工坊主界面")

local HomeScreen = {}

-- ============================================================================
-- Screen 接口
-- ============================================================================

--- 创建主界面
---@param container table UI 容器
---@param params table|nil
---@return table screen
function HomeScreen.Create(container, params)
    local screen = {}

    -- 事件取消函数
    local unsubs_ = {}

    -- ----------------------------------------------------------------
    -- 1. 构建 UI 树（从布局模块）
    -- ----------------------------------------------------------------
    local root = HomeLayout.Build()
    container:AddChild(root)

    -- ----------------------------------------------------------------
    -- 2. 通过 FindById 获取动态元素引用
    -- ----------------------------------------------------------------

    -- 货币数值标签
    local coinsLabel_ = root:FindById("res_v_c")
    local jadeLabel_ = root:FindById("res_v_h")
    local fameLabel_ = root:FindById("res_v_m")

    -- 章节标题
    local chapterTitle_ = root:FindById("tx_6")

    -- 顶部功能按钮
    local mailBtn_ = root:FindById("plate_n")
    local taskBtn_ = root:FindById("plate_q")
    local friendBtn_ = root:FindById("plate_t")
    local settingsBtn_ = root:FindById("plate_w")

    -- 设施卡片
    local facilityFurnace_ = root:FindById("ph_1a")
    local facilityAnvil_ = root:FindById("ph_1f")
    local facilityGrinder_ = root:FindById("ph_1k")
    local facilityStorage_ = root:FindById("ph_1p")
    local facilityDisplay_ = root:FindById("ph_1u")

    -- 设施名称标签（用于显示等级）
    local facilityLabels_ = {
        furnace     = root:FindById("ph_t_1e"),
        anvil       = root:FindById("ph_t_1j"),
        grinder     = root:FindById("ph_t_1o"),
        storage     = root:FindById("ph_t_1t"),
        display     = root:FindById("ph_t_1y"),
    }

    -- 名望进度条
    local progressBar_ = root:FindById("sr_21")  -- 填充条
    local progressText_ = root:FindById("tx_22")

    -- 右侧功能按钮（功能未实现，暂时隐藏）
    local giftBtn_ = root:FindById("plate_23")
    local freeBoxBtn_ = root:FindById("plate_26")
    local adDoubleBtn_ = root:FindById("plate_29")
    if giftBtn_ then giftBtn_.visible = false end
    if freeBoxBtn_ then freeBoxBtn_.visible = false end
    if adDoubleBtn_ then adDoubleBtn_.visible = false end

    -- 底部导航按钮
    local navOrderBtn_ = root:FindById("plate_2e")
    local navWorkshopBtn_ = root:FindById("plate_2h")
    local navCodexBtn_ = root:FindById("plate_2k")
    local navStoryBtn_ = root:FindById("plate_2n")
    local navShopBtn_ = root:FindById("plate_2q")

    -- 剧情按钮红点徽标（有待展示剧情时显示）
    ---@type table|nil
    local storyBadge_ = nil
    if navStoryBtn_ then
        storyBadge_ = UI.Panel {
            id = "story_badge",
            position = "absolute",
            top = 6,
            right = 12,
            width = 14,
            height = 14,
            borderRadius = 7,
            backgroundColor = "#E94560",
            borderColor = "#E8E0D0",
            borderWidth = 1.5,
        }
        navStoryBtn_:AddChild(storyBadge_)
    end

    --- 刷新剧情红点（有待展示剧情则显示）
    local function RefreshStoryBadge()
        if storyBadge_ then
            storyBadge_.visible = StoryManager.HasPendingStory()
        end
    end

    -- ----------------------------------------------------------------
    -- 3. 初始化数据绑定
    -- ----------------------------------------------------------------

    --- 刷新货币显示
    local function RefreshCurrency()
        if coinsLabel_ then coinsLabel_.text = tostring(GameState.GetCoins()) end
        if jadeLabel_ then jadeLabel_.text = tostring(GameState.GetJade()) end
        if fameLabel_ then fameLabel_.text = tostring(GameState.GetFame()) end
    end

    --- 刷新设施等级显示
    local function RefreshFacilities()
        local facilityMap = {
            furnace = "熔炉",
            anvil = "锻台",
            grinder = "研磨台",
            storage = "库房",
            display = "陈列架",
        }
        for fId, baseName in pairs(facilityMap) do
            local label = facilityLabels_[fId]
            if label then
                local lv = GameState.GetFacilityLevel(fId)
                label.text = baseName .. " Lv" .. lv
            end
        end
    end

    --- 刷新名望进度条
    local function RefreshFameProgress()
        local fame = GameState.GetFame()
        -- 名望进阶阈值（简化：每 1000 声望一阶）
        local tier = math.floor(fame / 1000)
        local tierStart = tier * 1000
        local tierEnd = (tier + 1) * 1000
        local progress = (fame - tierStart) / (tierEnd - tierStart)
        progress = math.max(0, math.min(1, progress))

        -- 更新进度条宽度（父容器宽度的百分比）
        if progressBar_ then
            progressBar_.width = string.format("%.1f%%", progress * 100)
        end

        -- 更新进度文字
        if progressText_ then
            local pctText = math.floor(progress * 100)
            local tierNames = { "初入行", "学徒", "出师礼", "匠人", "名匠", "宗师" }
            local nextTierName = tierNames[math.min(tier + 2, #tierNames)] or "宗师"
            progressText_.text = string.format(
                "名望进阶  %d%%  下一阶 · %s (%d/%d)",
                pctText, nextTierName, fame, tierEnd
            )
        end
    end

    --- 刷新章节标题
    local function RefreshChapterTitle()
        if not chapterTitle_ then return end
        local chapter, _ = StoryManager.GetProgress()
        local chapterNames = {
            "第一章 · 入门徒",
            "第二章 · 初展锋",
            "第三章 · 名声起",
            "第四章 · 暗潮涌",
            "第五章 · 匠心成",
        }
        chapterTitle_.text = chapterNames[chapter] or ("第" .. chapter .. "章")
    end

    -- 初始刷新
    RefreshCurrency()
    RefreshFacilities()
    RefreshFameProgress()
    RefreshChapterTitle()
    RefreshStoryBadge()

    -- ----------------------------------------------------------------
    -- 4. 绑定点击事件
    -- ----------------------------------------------------------------

    -- 顶部按钮
    if mailBtn_ then
        mailBtn_.props.onClick = function()
            SFXManager.Play(SFXManager.SFX.UI_TAP, 0.4)
            print("[HomeScreen] Mail button tapped (not implemented)")
        end
    end
    if taskBtn_ then
        taskBtn_.props.onClick = function()
            SFXManager.Play(SFXManager.SFX.UI_TAP, 0.4)
            ScreenRouter.GoTo("orderBoard")
        end
    end
    if friendBtn_ then
        friendBtn_.props.onClick = function()
            SFXManager.Play(SFXManager.SFX.UI_TAP, 0.4)
            print("[HomeScreen] Friend button tapped (not implemented)")
        end
    end
    if settingsBtn_ then
        settingsBtn_.props.onClick = function()
            SFXManager.Play(SFXManager.SFX.UI_TAP, 0.4)
            ScreenRouter.GoTo("settings")
        end
    end

    -- 设施卡片 → 升级弹窗
    local function OnFacilityTap(facilityId)
        return function()
            SFXManager.Play(SFXManager.SFX.UI_TAP, 0.4)
            UpgradePopup.Open(facilityId)
        end
    end

    if facilityFurnace_ then facilityFurnace_.props.onClick = OnFacilityTap("furnace") end
    if facilityAnvil_ then facilityAnvil_.props.onClick = OnFacilityTap("anvil") end
    if facilityGrinder_ then facilityGrinder_.props.onClick = OnFacilityTap("grinder") end
    if facilityStorage_ then facilityStorage_.props.onClick = OnFacilityTap("storage") end
    if facilityDisplay_ then facilityDisplay_.props.onClick = OnFacilityTap("display") end

    -- 右侧功能按钮（已隐藏，功能待实现后再开放）

    -- 底部导航
    if navOrderBtn_ then
        navOrderBtn_.props.onClick = function()
            SFXManager.Play(SFXManager.SFX.UI_TAP, 0.4)
            ScreenRouter.GoTo("orderBoard")
        end
    end
    if navWorkshopBtn_ then
        navWorkshopBtn_.props.onClick = function()
            SFXManager.Play(SFXManager.SFX.UI_TAP, 0.4)
            -- 已在工坊主页，不跳转；或可刷新
            print("[HomeScreen] Already on workshop")
        end
    end
    if navCodexBtn_ then
        navCodexBtn_.props.onClick = function()
            SFXManager.Play(SFXManager.SFX.UI_TAP, 0.4)
            ScreenRouter.GoTo("codex")
        end
    end
    if navStoryBtn_ then
        navStoryBtn_.props.onClick = function()
            SFXManager.Play(SFXManager.SFX.UI_TAP, 0.4)
            ScreenRouter.GoTo("story", { returnTo = "home" })
        end
    end
    if navShopBtn_ then
        navShopBtn_.props.onClick = function()
            SFXManager.Play(SFXManager.SFX.UI_TAP, 0.4)
            UI.Toast.Show("商店功能即将开放，敬请期待")
        end
    end

    -- ----------------------------------------------------------------
    -- 5. 增量更新：EventBus 订阅
    -- ----------------------------------------------------------------

    unsubs_[#unsubs_ + 1] = EventBus.On("reward_collected", function()
        SFXManager.Play(SFXManager.SFX.UI_COIN, 0.5)
        RefreshCurrency()
        RefreshFameProgress()
    end)

    unsubs_[#unsubs_ + 1] = EventBus.On("coins_changed", RefreshCurrency)

    -- 声望/设施变化可能满足新剧情条件 → 刷新红点
    unsubs_[#unsubs_ + 1] = EventBus.On("fame_changed", function()
        RefreshCurrency()
        RefreshFameProgress()
        RefreshStoryBadge()
    end)

    unsubs_[#unsubs_ + 1] = EventBus.On("facility_upgraded", function(data)
        RefreshFacilities()
        RefreshCurrency()
        RefreshStoryBadge()
    end)

    unsubs_[#unsubs_ + 1] = EventBus.On("story_node_complete", function()
        RefreshChapterTitle()
        RefreshStoryBadge()
    end)

    unsubs_[#unsubs_ + 1] = EventBus.On("story_choice_made", function()
        RefreshChapterTitle()
        RefreshStoryBadge()
    end)

    unsubs_[#unsubs_ + 1] = EventBus.On("story_chapter_skipped", function()
        RefreshChapterTitle()
        RefreshStoryBadge()
    end)

    -- ----------------------------------------------------------------
    -- 5.5 运行中自动触发剧情
    -- 进入主界面首帧检查：若有"新的"待展示剧情（未被手动关闭），自动进入剧情
    -- 用首帧延迟而非 Create 内直接跳转，避免 ScreenRouter 重入导致状态错乱
    -- ----------------------------------------------------------------
    local autoStoryChecked_ = false
    function screen.Update(dt)
        if not autoStoryChecked_ then
            autoStoryChecked_ = true
            if StoryManager.HasNewPendingStory() then
                print("[HomeScreen] New pending story detected, auto-entering story screen")
                ScreenRouter.GoTo("story", { returnTo = "home" })
            end
        end
    end

    -- ----------------------------------------------------------------
    -- 6. screen 控制器
    -- ----------------------------------------------------------------

    function screen.Destroy()
        for i = 1, #unsubs_ do
            unsubs_[i]()
        end
        unsubs_ = {}
    end

    print("[HomeScreen] Created (layout migration)")
    return screen
end

return HomeScreen
