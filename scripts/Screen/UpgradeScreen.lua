-- ============================================================================
-- UpgradeScreen - 设施升级界面
-- Project Smith / P1-D (补充)
--
-- 展示所有设施卡片，显示当前等级/描述/升级费用，玩家可消耗铜钱+声望升级。
-- 升级后发送 EventBus("facility_upgraded")，HomeScreen 增量刷新。
-- ============================================================================

local UI             = require("urhox-libs/UI")
local EventBus       = require("Core.EventBus")
local GameState      = require("Core.GameState")
local FacilityConfig = require("Config.FacilityConfig")
local ScreenRouter   = require("Utils.ScreenRouter")

local UpgradeScreen = {}

-- ============================================================================
-- UI 素材路径（武侠水墨风）
-- ============================================================================

local UI_ASSETS = {
    panel_header    = "image/ui/panel_header.png",
    panel_header2   = "image/ui/panel_header2.png",
    panel_card_blue = "image/ui/panel_card_blue.png",
    btn_accept      = "image/ui/btn_accept.png",
    btn_disabled    = "image/ui/btn_disabled.png",
    divider_mountain = "image/ui/divider_mountain.png",
}

-- ============================================================================
-- 资源路径
-- ============================================================================

local ICONS = {
    coins       = "image/icon_coins.png",
    fame        = "image/icon_fame.png",
    furnace     = "image/icon_furnace.png",
    anvil       = "image/icon_anvil.png",
    grinder     = "image/icon_grinder.png",
    quench_pool = "image/icon_quench_pool.png",
    display     = "image/icon_display.png",
}

-- ============================================================================
-- 色板
-- ============================================================================

local C = {
    bgPrimary     = { 26,  26,  46,  255 },
    bgSecondary   = { 22,  33,  62,  255 },
    bgCard        = { 30,  40,  68,  255 },
    bgCardHover   = { 40,  50,  80,  255 },
    accent        = { 233, 69,  96,  255 },
    gold          = { 212, 165, 116, 255 },
    textPrimary   = { 232, 224, 208, 255 },
    textSecondary = { 160, 147, 125, 255 },
    success       = { 78,  205, 196, 255 },
    warning       = { 255, 217, 61,  255 },
    btnUpgrade    = { 78,  205, 196, 255 },
    btnDisabled   = { 80,  80,  100, 255 },
    btnHover      = { 100, 220, 210, 255 },
    btnPressed    = { 60,  170, 160, 255 },
    divider       = { 60,  60,  90,  255 },
    maxTag        = { 212, 165, 116, 200 },
}

-- ============================================================================
-- Screen 接口
-- ============================================================================

---@param container table UI 容器
---@param params table|nil
---@return table screen
function UpgradeScreen.Create(container, params)
    local screen = {}

    -- 各设施的可变 UI 引用
    ---@type table<string, table>
    local cardRefs_ = {}

    -- ScrollView 内容容器
    ---@type table|nil
    local scrollContent_ = nil

    -- ----------------------------------------------------------------
    -- 刷新单个设施卡片内容
    -- ----------------------------------------------------------------
    local function RefreshCard(facilityId)
        local refs = cardRefs_[facilityId]
        if not refs then return end

        local level  = GameState.GetFacilityLevel(facilityId)
        local desc   = FacilityConfig.GetLevelDesc(facilityId, level)
        local isMax  = FacilityConfig.IsMaxLevel(facilityId, level)
        local coeff  = FacilityConfig.GetToolCoeff(facilityId, level)

        refs.levelLabel.text = "Lv" .. level
        refs.descLabel.text  = desc
        refs.coeffLabel.text = "工具系数: x" .. string.format("%.2f", coeff)

        if isMax then
            refs.costLabel.text  = "已满级"
            refs.costLabel.fontColor = C.maxTag
            refs.upgradeBtn.text = "已满级"
            refs.upgradeBtn.disabled = true
            refs.upgradeBtn.backgroundImage = UI_ASSETS.btn_disabled
        else
            local cost = FacilityConfig.GetUpgradeCost(facilityId, level)
            if cost then
                refs.costLabel.text = "费用: " .. cost.coins .. "铜钱 + " .. cost.fame .. "声望"
                local canAffordCoins = GameState.CanAffordCoins(cost.coins)
                local canAffordFame  = GameState.GetFame() >= cost.fame
                local canAfford = canAffordCoins and canAffordFame

                if canAfford then
                    refs.costLabel.fontColor = C.textSecondary
                    refs.upgradeBtn.text = "升级 -> Lv" .. (level + 1)
                    refs.upgradeBtn.disabled = false
                    refs.upgradeBtn.backgroundImage = UI_ASSETS.btn_accept
                else
                    refs.costLabel.fontColor = C.accent
                    refs.upgradeBtn.text = "资源不足"
                    refs.upgradeBtn.disabled = true
                    refs.upgradeBtn.backgroundImage = UI_ASSETS.btn_disabled
                end
            end
        end
    end

    -- ----------------------------------------------------------------
    -- 升级操作
    -- ----------------------------------------------------------------
    local function DoUpgrade(facilityId)
        local level = GameState.GetFacilityLevel(facilityId)
        if FacilityConfig.IsMaxLevel(facilityId, level) then return end

        local cost = FacilityConfig.GetUpgradeCost(facilityId, level)
        if not cost then return end

        -- 检查资源是否足够
        if not GameState.CanAffordCoins(cost.coins) then
            print("[UpgradeScreen] Not enough coins for " .. facilityId)
            return
        end
        if GameState.GetFame() < cost.fame then
            print("[UpgradeScreen] Not enough fame for " .. facilityId)
            return
        end

        -- 扣除资源
        GameState.AddCoins(-cost.coins)
        GameState.AddFame(-cost.fame)

        -- 提升等级
        GameState.SetFacilityLevel(facilityId, level + 1)

        print("[UpgradeScreen] Upgraded " .. facilityId .. " to Lv" .. (level + 1))

        -- 刷新所有卡片（升级后资源变化，可能影响其他设施的可升级状态）
        local allIds = FacilityConfig.GetAllIds()
        for i = 1, #allIds do
            RefreshCard(allIds[i])
        end
    end

    -- ----------------------------------------------------------------
    -- 创建单个设施卡片
    -- ----------------------------------------------------------------
    local function CreateFacilityCard(facilityId)
        local level = GameState.GetFacilityLevel(facilityId)
        local name  = FacilityConfig.GetName(facilityId)
        local desc  = FacilityConfig.GetLevelDesc(facilityId, level)
        local coeff = FacilityConfig.GetToolCoeff(facilityId, level)
        local isMax = FacilityConfig.IsMaxLevel(facilityId, level)

        -- 可变 Label 引用
        local levelLabel = UI.Label {
            text = "Lv" .. level,
            fontSize = 16,
            fontColor = C.gold,
        }
        local descLabel = UI.Label {
            text = desc,
            fontSize = 12,
            fontColor = C.textSecondary,
        }
        local coeffLabel = UI.Label {
            text = "工具系数: x" .. string.format("%.2f", coeff),
            fontSize = 11,
            fontColor = C.success,
        }

        -- 费用文本
        local costText = ""
        local costColor = C.textSecondary
        if isMax then
            costText = "已满级"
            costColor = C.maxTag
        else
            local cost = FacilityConfig.GetUpgradeCost(facilityId, level)
            if cost then
                costText = "费用: " .. cost.coins .. "铜钱 + " .. cost.fame .. "声望"
            end
        end
        local costLabel = UI.Label {
            text = costText,
            fontSize = 11,
            fontColor = costColor,
        }

        -- 升级按钮
        local btnText = "已满级"
        local btnDisabled = true
        local btnImg = UI_ASSETS.btn_disabled
        if not isMax then
            local cost = FacilityConfig.GetUpgradeCost(facilityId, level)
            if cost then
                local canAfford = GameState.CanAffordCoins(cost.coins) and GameState.GetFame() >= cost.fame
                if canAfford then
                    btnText = "升级 -> Lv" .. (level + 1)
                    btnDisabled = false
                    btnImg = UI_ASSETS.btn_accept
                else
                    btnText = "资源不足"
                end
            end
        end

        local upgradeBtn = UI.Button {
            text = btnText,
            width = "100%",
            height = 42,
            fontSize = 13,
            fontColor = C.textPrimary,
            backgroundImage = btnImg,
            backgroundFit = "cover",
            borderRadius = 6,
            disabled = btnDisabled,
            onClick = function(self)
                DoUpgrade(facilityId)
            end,
        }

        -- 保存引用
        cardRefs_[facilityId] = {
            levelLabel = levelLabel,
            descLabel  = descLabel,
            coeffLabel = coeffLabel,
            costLabel  = costLabel,
            upgradeBtn = upgradeBtn,
        }

        local iconPath = ICONS[facilityId]

        return UI.Panel {
            width = "100%",
            backgroundImage = UI_ASSETS.panel_card_blue,
            backgroundFit = "cover",
            borderRadius = 8,
            padding = 14,
            gap = 6,
            marginBottom = 10,
            children = {
                -- 头部：图标 + 名称 + 等级
                UI.Panel {
                    width = "100%",
                    flexDirection = "row",
                    justifyContent = "space-between",
                    alignItems = "center",
                    children = {
                        UI.Panel {
                            flexDirection = "row",
                            alignItems = "center",
                            gap = 8,
                            flexShrink = 1,
                            children = {
                                iconPath and UI.Panel {
                                    width = 32, height = 32,
                                    backgroundImage = iconPath,
                                    backgroundFit = "contain",
                                } or nil,
                                UI.Label {
                                    text = name,
                                    fontSize = 16,
                                    fontColor = C.textPrimary,
                                },
                            },
                        },
                        levelLabel,
                    },
                },
                -- 描述
                descLabel,
                -- 工具系数
                coeffLabel,
                -- 分割线
                UI.Panel {
                    width = "100%",
                    height = 16,
                    backgroundImage = UI_ASSETS.divider_mountain,
                    backgroundFit = "contain",
                    marginVertical = 4,
                },
                -- 费用
                costLabel,
                -- 升级按钮
                upgradeBtn,
            },
        }
    end

    -- ----------------------------------------------------------------
    -- 货币摘要栏
    -- ----------------------------------------------------------------
    local coinsLabel_ = UI.Label {
        text = tostring(GameState.GetCoins()),
        fontSize = 13,
        fontColor = C.gold,
        flexShrink = 1,
    }
    local fameLabel_ = UI.Label {
        text = tostring(GameState.GetFame()),
        fontSize = 13,
        fontColor = C.success,
        flexShrink = 1,
    }

    local function RefreshCurrencyBar()
        coinsLabel_.text = tostring(GameState.GetCoins())
        fameLabel_.text  = tostring(GameState.GetFame())
    end

    local function CreateCurrencyItem(iconPath, label)
        return UI.Panel {
            flexDirection = "row",
            alignItems = "center",
            gap = 4,
            flexShrink = 1,
            children = {
                UI.Panel {
                    width = 20, height = 20,
                    backgroundImage = iconPath,
                    backgroundFit = "contain",
                },
                label,
            },
        }
    end

    local currencyBar = UI.Panel {
        width = "100%",
        flexDirection = "row",
        justifyContent = "space-around",
        alignItems = "center",
        paddingVertical = 8,
        paddingHorizontal = 12,
        backgroundImage = UI_ASSETS.panel_header2,
        backgroundFit = "cover",
        borderRadius = 8,
        children = {
            CreateCurrencyItem(ICONS.coins, coinsLabel_),
            CreateCurrencyItem(ICONS.fame,  fameLabel_),
        },
    }

    -- ----------------------------------------------------------------
    -- 创建全部设施卡片
    -- ----------------------------------------------------------------
    local facilityIds = FacilityConfig.GetAllIds()
    local facilityCards = {}
    for i = 1, #facilityIds do
        facilityCards[#facilityCards + 1] = CreateFacilityCard(facilityIds[i])
    end

    -- ----------------------------------------------------------------
    -- 页面组装
    -- ----------------------------------------------------------------
    scrollContent_ = UI.Panel {
        width = "100%",
        paddingHorizontal = 16,
        paddingVertical = 8,
        gap = 0,
        children = facilityCards,
    }

    local panel = UI.Panel {
        width = "100%",
        height = "100%",
        flexDirection = "column",
        children = {
            -- 顶部标题栏
            UI.Panel {
                width = "100%",
                flexDirection = "row",
                alignItems = "center",
                paddingHorizontal = 12,
                paddingVertical = 12,
                backgroundImage = UI_ASSETS.panel_header,
                backgroundFit = "cover",
                children = {
                    UI.Button {
                        text = "< 返回",
                        fontSize = 14,
                        fontColor = C.textPrimary,
                        backgroundColor = { 0, 0, 0, 0 },
                        onClick = function(self)
                            ScreenRouter.GoTo("home")
                        end,
                    },
                    UI.Panel { flexGrow = 1 },
                    UI.Label {
                        text = "设施升级",
                        fontSize = 18,
                        fontColor = C.gold,
                    },
                    UI.Panel { flexGrow = 1 },
                    -- 右侧占位，保持标题居中
                    UI.Panel { width = 60 },
                },
            },

            -- 货币摘要
            UI.Panel {
                width = "100%",
                paddingHorizontal = 16,
                paddingTop = 10,
                paddingBottom = 6,
                children = { currencyBar },
            },

            -- 设施列表（ScrollView）
            UI.ScrollView {
                width = "100%",
                flexGrow = 1,
                flexBasis = 0,
                children = { scrollContent_ },
            },
        },
    }

    container:AddChild(panel)
    screen.panel = panel

    -- ----------------------------------------------------------------
    -- EventBus 监听（升级后刷新货币）
    -- ----------------------------------------------------------------
    local unsubs_ = {}

    unsubs_[#unsubs_ + 1] = EventBus.On("coins_changed", function()
        RefreshCurrencyBar()
    end)
    unsubs_[#unsubs_ + 1] = EventBus.On("fame_changed", function()
        RefreshCurrencyBar()
    end)

    -- ----------------------------------------------------------------
    -- 清理
    -- ----------------------------------------------------------------
    function screen.Destroy()
        for i = 1, #unsubs_ do
            unsubs_[i]()
        end
        unsubs_ = {}
        cardRefs_ = {}
    end

    return screen
end

return UpgradeScreen
