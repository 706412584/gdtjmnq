-- ============================================================================
-- HomeScreen - 工坊主界面
-- Project Smith / P1-D1
--
-- 显示: 标题、货币栏、功能按钮（接单/升级/图鉴）、设施状态
-- 遵循增量更新策略: 货币/声望变化只更新对应 Label
-- ============================================================================

local UI          = require("urhox-libs/UI")
local EventBus    = require("Core.EventBus")
local GameState   = require("Core.GameState")
local FacilityConfig = require("Config.FacilityConfig")
local ScreenRouter   = require("Utils.ScreenRouter")
local StoryManager   = require("Story.StoryManager")
local SFXManager     = require("Utils.SFXManager")

local HomeScreen = {}

-- ============================================================================
-- 资源路径
-- ============================================================================

local ICONS = {
    coins   = "image/icon_coins.png",
    fame    = "image/icon_fame.png",
    jade    = "image/icon_jade.png",
    furnace = "image/icon_furnace.png",
    anvil   = "image/icon_anvil.png",
    grinder = "image/icon_grinder.png",
    quench_pool = "image/icon_quench_pool.png",
    display = "image/icon_display.png",
}

local BG_HOME = "image/bg_home.png"

-- UI 素材路径（武侠水墨风）
local UI_ASSETS = {
    btn_primary   = "image/ui/btn_primary.png",
    btn_gold      = "image/ui/btn_gold.png",
    btn_secondary = "image/ui/btn_secondary.png",
    btn_choice    = "image/ui/btn_choice.png",
    btn_accept    = "image/ui/btn_accept.png",
    panel_header  = "image/ui/panel_header.png",
    panel_header2 = "image/ui/panel_header2.png",
    panel_card    = "image/ui/panel_card.png",
    panel_card_blue = "image/ui/panel_card_blue.png",
    frame_item_sm = "image/ui/frame_item_sm.png",
    frame_item_xs = "image/ui/frame_item_xs.png",
    divider_moon      = "image/ui/divider_moon.png",
    divider_bamboo    = "image/ui/divider_bamboo.png",
    divider_mountain  = "image/ui/divider_mountain.png",
}

-- ============================================================================
-- 色板
-- ============================================================================

local C = {
    bgPrimary     = { 26,  26,  46,  255 },
    bgSecondary   = { 22,  33,  62,  255 },
    bgCard        = { 30,  40,  68,  200 },
    accent        = { 233, 69,  96,  255 },
    gold          = { 212, 165, 116, 255 },
    goldBright    = { 245, 200, 140, 255 },
    goldDark      = { 160, 120, 70,  255 },
    textPrimary   = { 232, 224, 208, 255 },
    textSecondary = { 160, 147, 125, 255 },
    textDim       = { 120, 110, 95,  180 },
    success       = { 78,  205, 196, 255 },
    warning       = { 255, 217, 61,  255 },
    overlay       = { 0,   0,   0,   100 },
    overlayLight  = { 0,   0,   0,   60  },
}

-- ============================================================================
-- Screen 接口
-- ============================================================================

--- 创建主界面
---@param container table UI 容器
---@param params table|nil 参数
---@return table screen
function HomeScreen.Create(container, params)
    local screen = {}

    -- UI 元素引用（用于增量更新）
    local coinsLabel_
    local fameLabel_
    local jadeLabel_
    local facilityCards_ = {}
    local storyBtn_

    -- 事件取消函数列表
    local unsubs_ = {}

    -- ================================================================
    -- 顶部标题区（游戏 Logo + 副标题）
    -- ================================================================
    local function CreateTitleSection()
        return UI.Panel {
            width = "100%",
            alignItems = "center",
            gap = 4,
            paddingTop = 8,
            children = {
                -- 游戏标题
                UI.Label {
                    text = "古代铁匠模拟器",
                    fontSize = 28,
                    fontColor = C.goldBright,
                    fontWeight = "bold",
                    textAlign = "center",
                    textShadow = { offsetX = 0, offsetY = 2, blur = 8, color = { 0, 0, 0, 180 } },
                    textStroke = { width = 1.5, color = { 80, 50, 20, 200 } },
                    letterSpacing = 4,
                },
                -- 副标题
                UI.Label {
                    text = "铁铺初立  万器待铸",
                    fontSize = 12,
                    fontColor = C.textDim,
                    textAlign = "center",
                    letterSpacing = 6,
                    textShadow = { offsetX = 0, offsetY = 1, blur = 4, color = { 0, 0, 0, 120 } },
                },
            }
        }
    end

    -- ================================================================
    -- 货币栏（紧凑横条）
    -- ================================================================
    local function CreateCurrencyItem(iconPath, label)
        return UI.Panel {
            flexDirection = "row",
            alignItems = "center",
            gap = 3,
            flexShrink = 1,
            children = {
                UI.Panel {
                    width = 18, height = 18,
                    backgroundImage = iconPath,
                    backgroundFit = "contain",
                },
                label,
            },
        }
    end

    local function CreateCurrencyBar()
        coinsLabel_ = UI.Label {
            text = tostring(GameState.GetCoins()),
            fontSize = 13,
            fontColor = C.gold,
            flexShrink = 1,
        }
        fameLabel_ = UI.Label {
            text = tostring(GameState.GetFame()),
            fontSize = 13,
            fontColor = C.success,
            flexShrink = 1,
        }
        jadeLabel_ = UI.Label {
            text = tostring(GameState.GetJade()),
            fontSize = 13,
            fontColor = C.warning,
            flexShrink = 1,
        }

        return UI.Panel {
            width = "90%",
            flexDirection = "row",
            justifyContent = "space-around",
            alignItems = "center",
            paddingVertical = 8,
            paddingHorizontal = 12,
            backgroundColor = C.overlay,
            borderRadius = 20,
            borderWidth = 1,
            borderColor = { 212, 165, 116, 40 },
            children = {
                CreateCurrencyItem(ICONS.coins, coinsLabel_),
                -- 分隔点
                UI.Panel { width = 3, height = 3, borderRadius = 2, backgroundColor = C.textDim },
                CreateCurrencyItem(ICONS.fame, fameLabel_),
                UI.Panel { width = 3, height = 3, borderRadius = 2, backgroundColor = C.textDim },
                CreateCurrencyItem(ICONS.jade, jadeLabel_),
            }
        }
    end

    -- ================================================================
    -- 核心 CTA 按钮区
    -- ================================================================
    local function CreateMainActions()
        -- 剧情按钮（仅在有待展示剧情时显示）
        local hasPending = StoryManager.HasPendingStory()
        storyBtn_ = UI.Panel {
            width = "88%",
            height = 50,
            backgroundImage = UI_ASSETS.btn_primary,
            backgroundFit = "cover",
            borderRadius = 10,
            justifyContent = "center",
            alignItems = "center",
            visible = hasPending,
            onClick = function()
                if StoryManager.HasPendingStory() then
                    SFXManager.Play(SFXManager.SFX.UI_TAP, 0.4)
                    ScreenRouter.GoTo("story", { returnTo = "home" })
                end
            end,
            children = {
                UI.Label {
                    text = "继续剧情",
                    fontSize = 16,
                    fontColor = C.textPrimary,
                    fontWeight = "bold",
                    textShadow = { offsetX = 0, offsetY = 1, blur = 3, color = { 0, 0, 0, 150 } },
                },
            }
        }

        -- 查看订单 — 主 CTA
        local orderBtn = UI.Panel {
            width = "88%",
            height = 56,
            backgroundImage = UI_ASSETS.btn_gold,
            backgroundFit = "cover",
            borderRadius = 10,
            justifyContent = "center",
            alignItems = "center",
            boxShadow = {
                { x = 0, y = 3, blur = 12, spread = 0, color = { 212, 165, 116, 60 } },
            },
            onClick = function()
                SFXManager.Play(SFXManager.SFX.UI_TAP, 0.4)
                ScreenRouter.GoTo("orderBoard")
            end,
            children = {
                UI.Label {
                    text = "查看订单",
                    fontSize = 18,
                    fontColor = C.textPrimary,
                    fontWeight = "bold",
                    letterSpacing = 2,
                    textShadow = { offsetX = 0, offsetY = 1, blur = 3, color = { 0, 0, 0, 150 } },
                },
            }
        }

        return UI.Panel {
            width = "100%",
            alignItems = "center",
            gap = 10,
            children = {
                storyBtn_,
                orderBtn,
            }
        }
    end

    -- ================================================================
    -- 次级功能按钮行（升级/图鉴/设置 横排紧凑）
    -- ================================================================
    local function CreateSecondaryButton(text, bgImage, fontColor, onClickFn)
        return UI.Panel {
            flexGrow = 1,
            flexBasis = 0,
            height = 42,
            backgroundImage = bgImage,
            backgroundFit = "cover",
            borderRadius = 8,
            justifyContent = "center",
            alignItems = "center",
            onClick = function()
                SFXManager.Play(SFXManager.SFX.UI_TAP, 0.4)
                onClickFn()
            end,
            children = {
                UI.Label {
                    text = text,
                    fontSize = 13,
                    fontColor = fontColor or C.textPrimary,
                    textShadow = { offsetX = 0, offsetY = 1, blur = 2, color = { 0, 0, 0, 120 } },
                },
            }
        }
    end

    local function CreateSecondaryActions()
        return UI.Panel {
            width = "88%",
            flexDirection = "row",
            gap = 8,
            children = {
                CreateSecondaryButton("升级设施", UI_ASSETS.btn_secondary, C.textPrimary, function()
                    ScreenRouter.GoTo("upgrade")
                end),
                CreateSecondaryButton("名器图鉴", UI_ASSETS.btn_choice, C.gold, function()
                    ScreenRouter.GoTo("codex")
                end),
                CreateSecondaryButton("设置", UI_ASSETS.btn_secondary, C.textSecondary, function()
                    ScreenRouter.GoTo("settings")
                end),
            }
        }
    end

    -- ================================================================
    -- 设施状态栏（横向紧凑条）
    -- ================================================================
    local function CreateFacilityChip(facilityId)
        local level = GameState.GetFacilityLevel(facilityId)
        local name = FacilityConfig.GetName(facilityId)
        local iconPath = ICONS[facilityId]

        local levelLabel = UI.Label {
            text = "Lv" .. level,
            fontSize = 10,
            fontColor = C.gold,
            textAlign = "center",
        }

        facilityCards_[facilityId] = { levelLabel = levelLabel }

        return UI.Panel {
            alignItems = "center",
            gap = 2,
            paddingVertical = 6,
            paddingHorizontal = 6,
            minWidth = 52,
            onClick = function()
                SFXManager.Play(SFXManager.SFX.UI_TAP, 0.4)
                ScreenRouter.GoTo("upgrade")
            end,
            children = {
                -- 图标框
                UI.Panel {
                    width = 36, height = 36,
                    backgroundImage = UI_ASSETS.frame_item_xs,
                    backgroundFit = "cover",
                    justifyContent = "center",
                    alignItems = "center",
                    children = {
                        iconPath and UI.Panel {
                            width = 24, height = 24,
                            backgroundImage = iconPath,
                            backgroundFit = "contain",
                        } or nil,
                    }
                },
                UI.Label {
                    text = name,
                    fontSize = 10,
                    fontColor = C.textSecondary,
                    textAlign = "center",
                },
                levelLabel,
            }
        }
    end

    local function CreateFacilitiesBar()
        local facilityIds = FacilityConfig.GetAllIds()
        local chips = {}
        for i = 1, #facilityIds do
            chips[#chips + 1] = CreateFacilityChip(facilityIds[i])
        end

        return UI.Panel {
            width = "92%",
            backgroundColor = C.overlayLight,
            borderRadius = 12,
            borderWidth = 1,
            borderColor = { 212, 165, 116, 25 },
            paddingVertical = 6,
            paddingHorizontal = 4,
            gap = 4,
            children = {
                -- 标题行
                UI.Panel {
                    width = "100%",
                    flexDirection = "row",
                    justifyContent = "center",
                    alignItems = "center",
                    paddingBottom = 2,
                    gap = 8,
                    children = {
                        UI.Panel {
                            width = 20, height = 1,
                            backgroundColor = { 212, 165, 116, 40 },
                        },
                        UI.Label {
                            text = "工坊设施",
                            fontSize = 11,
                            fontColor = C.textDim,
                            letterSpacing = 2,
                        },
                        UI.Panel {
                            width = 20, height = 1,
                            backgroundColor = { 212, 165, 116, 40 },
                        },
                    }
                },
                -- 设施图标行
                UI.Panel {
                    width = "100%",
                    flexDirection = "row",
                    justifyContent = "space-around",
                    alignItems = "flex-start",
                    children = chips,
                },
            }
        }
    end

    -- ================================================================
    -- 装饰分隔线
    -- ================================================================
    local function CreateDivider(asset, w, h)
        return UI.Panel {
            width = w or "60%",
            height = h or 20,
            alignSelf = "center",
            backgroundImage = asset,
            backgroundFit = "contain",
            opacity = 0.6,
        }
    end

    -- ================================================================
    -- 组装页面
    -- ================================================================
    local panel = UI.Panel {
        width = "100%",
        height = "100%",
        backgroundImage = BG_HOME,
        backgroundFit = "cover",
        children = {
            -- ========================================================
            -- 全局暗化遮罩层（压暗繁杂背景）
            -- ========================================================
            UI.Panel {
                position = "absolute",
                top = 0, left = 0, right = 0, bottom = 0,
                backgroundColor = { 10, 10, 25, 110 },  -- 约 43% 不透明度暗化
            },
            -- 底部额外加深渐变（操作区域更清晰）
            UI.Panel {
                position = "absolute",
                left = 0, right = 0, bottom = 0,
                height = "55%",
                backgroundGradient = {
                    type = "linear",
                    direction = "to-top",
                    from = { 8, 8, 20, 200 },   -- 底部深沉
                    to   = { 8, 8, 20, 0 },     -- 渐隐
                },
            },
            -- 顶部渐变（标题区可读性）
            UI.Panel {
                position = "absolute",
                left = 0, right = 0, top = 0,
                height = "25%",
                backgroundGradient = {
                    type = "linear",
                    direction = "to-bottom",
                    from = { 8, 8, 20, 180 },
                    to   = { 8, 8, 20, 0 },
                },
            },

            -- ========================================================
            -- 内容层（在遮罩之上）
            -- ========================================================
            UI.Panel {
                position = "absolute",
                top = 0, left = 0, right = 0, bottom = 0,
                flexDirection = "column",
                alignItems = "center",
                children = {
                    -- 顶部安全区留白
                    UI.Panel { height = 36 },

                    -- 标题
                    CreateTitleSection(),

                    -- 装饰分隔
                    CreateDivider(UI_ASSETS.divider_mountain, "50%", 16),

                    -- 货币栏
                    CreateCurrencyBar(),

                    -- 弹性间隔（把按钮推向中下部）
                    UI.Panel { flexGrow = 1 },

                    -- 主按钮区
                    CreateMainActions(),

                    -- 间距
                    UI.Panel { height = 10 },

                    -- 次级按钮行
                    CreateSecondaryActions(),

                    -- 间距
                    UI.Panel { height = 12 },

                    -- 装饰分隔
                    CreateDivider(UI_ASSETS.divider_bamboo, "40%", 14),

                    -- 间距
                    UI.Panel { height = 4 },

                    -- 设施状态栏
                    CreateFacilitiesBar(),

                    -- 底部版本号 + 安全区
                    UI.Panel {
                        width = "100%",
                        alignItems = "center",
                        paddingTop = 8,
                        paddingBottom = 16,
                        children = {
                            UI.Label {
                                text = "P2",
                                fontSize = 9,
                                fontColor = { 80, 80, 100, 80 },
                            },
                        }
                    },
                }
            },
        }
    }

    container:AddChild(panel)
    screen.panel = panel

    -- ================================================================
    -- 增量更新：监听 EventBus
    -- ================================================================
    local function RefreshCurrency()
        if coinsLabel_ then coinsLabel_.text = tostring(GameState.GetCoins()) end
        if fameLabel_ then fameLabel_.text = tostring(GameState.GetFame()) end
        if jadeLabel_ then jadeLabel_.text = tostring(GameState.GetJade()) end
    end

    local function RefreshFacility(data)
        if not data or not data.facilityId then return end
        local card = facilityCards_[data.facilityId]
        if card and card.levelLabel then
            card.levelLabel.text = "Lv" .. (data.newLevel or GameState.GetFacilityLevel(data.facilityId))
        end
    end

    local function RefreshStoryButton()
        if not storyBtn_ then return end
        storyBtn_.visible = StoryManager.HasPendingStory()
    end

    unsubs_[#unsubs_ + 1] = EventBus.On("reward_collected", function()
        SFXManager.Play(SFXManager.SFX.UI_COIN, 0.5)
        RefreshCurrency()
        RefreshStoryButton()
    end)
    unsubs_[#unsubs_ + 1] = EventBus.On("coins_changed", RefreshCurrency)
    unsubs_[#unsubs_ + 1] = EventBus.On("fame_changed", function()
        RefreshCurrency()
        RefreshStoryButton()
    end)
    unsubs_[#unsubs_ + 1] = EventBus.On("facility_upgraded", function(data)
        RefreshFacility(data)
        RefreshCurrency()
        RefreshStoryButton()
    end)
    unsubs_[#unsubs_ + 1] = EventBus.On("story_node_complete", RefreshStoryButton)
    unsubs_[#unsubs_ + 1] = EventBus.On("story_choice_made", RefreshStoryButton)

    -- ================================================================
    -- 清理
    -- ================================================================
    function screen.Destroy()
        for i = 1, #unsubs_ do
            unsubs_[i]()
        end
        unsubs_ = {}
        facilityCards_ = {}
    end

    return screen
end

return HomeScreen
