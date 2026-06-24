---@diagnostic disable: param-type-mismatch
-- ============================================================================
-- ShopScreen - 采买 · 材料补给商店
-- Project Smith
--
-- 按 GDD §9.12 实现材料补给商店：
--   - 铜钱购买基础材料包（矿石/木炭/磨料/木材/皮绳）—— 经济闭环的铜钱回收口
--   - 玉璧购买稀有材料包（纹金/陨铁）—— 高级材料来源
-- 竖屏 9:16，暖色调，与主界面统一。
-- ============================================================================

local UI           = require("urhox-libs/UI")
local GameState    = require("Core.GameState")
local EventBus     = require("Core.EventBus")
local OrderManager = require("Core.OrderManager")
local ScreenRouter = require("Utils.ScreenRouter")
local SFXManager   = require("Utils.SFXManager")
local RelationshipTracker = require("Story.RelationshipTracker")

local ShopScreen = {}

-- ============================================================================
-- 折扣计算（沈绫商会线好感解锁）
-- ============================================================================

--- 计算应用折扣后的最终价格（向上取整，至少 1）
---@param basePrice number 原价
---@param rate number 折扣率（0~0.10）
---@return number
local function ApplyDiscount(basePrice, rate)
    if rate <= 0 then return basePrice end
    local discounted = math.ceil(basePrice * (1 - rate))
    return math.max(1, discounted)
end

-- ============================================================================
-- 商品配置（GDD §9.12）
-- ============================================================================

--- 材料包定义
--- currency: "coins"（铜钱）| "jade"（玉璧）
local PACKS = {
    {
        id = "pack_crude_iron", name = "粗铁补给",
        desc = "矿石 x8 · 木炭 x3 · 研磨剂 x1",
        currency = "coins", price = 60,
        materials = { ore = 8, charcoal = 3, grinding_agent = 1 },
    },
    {
        id = "pack_wrought_iron", name = "熟铁补给",
        desc = "矿石 x10 · 研磨剂 x4 · 木材 x3",
        currency = "coins", price = 120,
        materials = { ore = 10, grinding_agent = 4, wood = 3 },
    },
    {
        id = "pack_misc", name = "工坊杂料包",
        desc = "木材 x4 · 皮革 x4",
        currency = "coins", price = 80,
        materials = { wood = 4, leather = 4 },
    },
    {
        id = "pack_pattern_gold", name = "纹金小包",
        desc = "纹金 x3",
        currency = "jade", price = 18,
        materials = { pattern_gold = 3 },
    },
    {
        id = "pack_meteorite", name = "陨铁小片",
        desc = "陨铁 x1",
        currency = "jade", price = 30,
        materials = { meteorite = 1 },
    },
}

-- ============================================================================
-- Screen 接口
-- ============================================================================

---@param container table UI 容器
---@param params table|nil
---@return table screen
function ShopScreen.Create(container, params)
    local screen = {}
    local unsubs_ = {}

    -- 沈绫商会线好感折扣（本次进入商店时固定，session 内不变）
    local discountRate_ = RelationshipTracker.GetShopDiscountRate()

    --- 获取商品在当前折扣下的实际价格
    ---@param pack table
    ---@return number
    local function EffectivePrice(pack)
        return ApplyDiscount(pack.price, discountRate_)
    end

    -- 货币标签引用（用于增量刷新）
    local coinsLabel_ = nil
    local jadeLabel_  = nil
    -- 每个商品的购买按钮引用 { packId = button }
    local buyButtons_ = {}
    -- 购买操作（前向声明，正文在下方赋值；按钮闭包按引用捕获，调用时解析）
    ---@type fun(pack: table)
    local DoPurchase

    -- ----------------------------------------------------------------
    -- 顶栏：返回 + 标题 + 货币
    -- ----------------------------------------------------------------
    local backBtn = UI.Panel {
        width = 110, height = 56,
        borderRadius = 12,
        borderColor = "#21BDAE",
        borderWidth = 1.5,
        justifyContent = "center",
        alignItems = "center",
        onClick = function()
            SFXManager.Play(SFXManager.SFX.UI_TAP, 0.4)
            ScreenRouter.GoTo("home")
        end,
        children = {
            UI.Label { text = "< 返回", fontSize = 18, fontColor = "#21BDAE", textAlign = "center" },
        },
    }

    local titleLabel = UI.Label {
        text = "采买 · 材料补给",
        fontSize = 24,
        fontWeight = 700,
        fontColor = "#21BDAE",
        verticalAlign = "middle",
        marginLeft = 18,
        flexGrow = 1,
    }

    coinsLabel_ = UI.Label {
        text = "", fontSize = 18, fontColor = "#F0F0F0", verticalAlign = "middle", marginRight = 18,
    }
    jadeLabel_ = UI.Label {
        text = "", fontSize = 18, fontColor = "#50C878", verticalAlign = "middle",
    }

    local header = UI.Panel {
        width = "100%", height = 72,
        flexDirection = "row",
        alignItems = "center",
        paddingLeft = 24, paddingRight = 24,
        backgroundColor = "rgba(15,15,35,0.9)",
        borderColor = "#3A3A6A",
        borderWidth = 0,
        children = { backBtn, titleLabel, coinsLabel_, jadeLabel_ },
    }

    -- ----------------------------------------------------------------
    -- 商品卡片构建
    -- ----------------------------------------------------------------
    ---@param pack table
    ---@return table card
    local function BuildPackCard(pack)
        local isJade = pack.currency == "jade"
        local priceColor = isJade and "#50C878" or "#21BDAE"
        local unitName = isJade and "玉璧" or "铜钱"
        local finalPrice = EffectivePrice(pack)
        local hasDiscount = finalPrice < pack.price

        local buyBtn = UI.Button {
            text = "采买",
            variant = "primary",
            width = 110,
            height = 48,
            onClick = function()
                DoPurchase(pack)
            end,
        }
        buyButtons_[pack.id] = buyBtn

        -- 价格区：折扣时显示原价（划掉感用烟灰小字）+ 折后价
        local priceChildren = {}
        if hasDiscount then
            priceChildren[#priceChildren + 1] = UI.Label {
                text = "原价 " .. pack.price,
                fontSize = 12,
                fontColor = "#505070",
                textAlign = "right",
            }
        end
        priceChildren[#priceChildren + 1] = UI.Label {
            text = finalPrice .. " " .. unitName,
            fontSize = 18, fontWeight = 700,
            fontColor = priceColor,
            textAlign = "right",
        }

        return UI.Panel {
            width = "100%",
            marginBottom = 14,
            paddingLeft = 18, paddingRight = 18,
            paddingTop = 14, paddingBottom = 14,
            flexDirection = "row",
            alignItems = "center",
            borderRadius = 12,
            backgroundColor = "rgba(27,27,58,0.3)",
            borderColor = "#3A3A6A",
            borderWidth = 1,
            children = {
                -- 左侧：名称 + 内容
                UI.Panel {
                    flexGrow = 1,
                    flexShrink = 1,
                    flexDirection = "column",
                    children = {
                        UI.Label {
                            text = pack.name,
                            fontSize = 19, fontWeight = 700,
                            fontColor = "#F0F0F0",
                            marginBottom = 6,
                        },
                        UI.Label {
                            text = pack.desc,
                            fontSize = 14,
                            fontColor = "#A0A0C0",
                        },
                    },
                },
                -- 中间：价格（含折扣）
                UI.Panel {
                    flexDirection = "column",
                    alignItems = "flex-end",
                    marginRight = 16,
                    children = priceChildren,
                },
                -- 右侧：购买按钮
                buyBtn,
            },
        }
    end

    local listChildren = {}
    for i = 1, #PACKS do
        listChildren[i] = BuildPackCard(PACKS[i])
    end

    local scroll = UI.ScrollView {
        width = "100%",
        flexGrow = 1,
        flexBasis = 0,   -- 必须：否则 ScrollView 撑满内容高度无法滚动
        scrollY = true,
        paddingLeft = 24, paddingRight = 24, paddingTop = 18, paddingBottom = 18,
        children = {
            UI.Panel {
                width = "100%",
                flexDirection = "column",
                children = listChildren,
            },
        },
    }

    -- 底部提示（折扣生效时提示来源）
    local hintText = "提示 · 接「猎户小刀」等委托也可回补基础材料"
    if discountRate_ > 0 then
        hintText = "沈绫商会折扣已生效 · 全场 "
            .. math.floor(discountRate_ * 100 + 0.5) .. "% 优惠"
    end
    local hint = UI.Label {
        text = hintText,
        fontSize = 13,
        fontColor = discountRate_ > 0 and "#50C878" or "#A0A0C0",
        textAlign = "center",
        width = "100%",
        height = 36,
        verticalAlign = "middle",
    }

    local root = UI.Panel {
        width = "100%", height = "100%",
        flexDirection = "column",
        backgroundColor = "#0F0F23",
        children = { header, scroll, hint },
    }
    container:AddChild(root)

    -- ----------------------------------------------------------------
    -- 刷新逻辑
    -- ----------------------------------------------------------------
    local function RefreshCurrency()
        if coinsLabel_ then coinsLabel_.text = "铜钱 " .. tostring(GameState.GetCoins()) end
        if jadeLabel_ then jadeLabel_.text = "玉璧 " .. tostring(GameState.GetJade()) end
    end

    --- 刷新所有购买按钮可用状态
    local function RefreshButtons()
        for i = 1, #PACKS do
            local pack = PACKS[i]
            local btn = buyButtons_[pack.id]
            if btn then
                local price = EffectivePrice(pack)
                local affordable
                if pack.currency == "jade" then
                    affordable = GameState.GetJade() >= price
                else
                    affordable = GameState.CanAffordCoins(price)
                end
                btn:SetDisabled(not affordable)
                btn:SetText(affordable and "采买" or "不足")
            end
        end
    end

    -- ----------------------------------------------------------------
    -- 购买操作（赋值到前向声明的 local DoPurchase）
    -- ----------------------------------------------------------------
    DoPurchase = function(pack)
        local price = EffectivePrice(pack)
        local affordable
        if pack.currency == "jade" then
            affordable = GameState.GetJade() >= price
        else
            affordable = GameState.CanAffordCoins(price)
        end

        if not affordable then
            SFXManager.Play(SFXManager.SFX.UI_FAIL, 0.4)
            local cur = pack.currency == "jade" and "玉璧" or "铜钱"
            UI.Toast.Show(cur .. "不足", { type = "warning", duration = 2 })
            return
        end

        -- 扣费（按折后价）
        if pack.currency == "jade" then
            GameState.AddJade(-price)
        else
            GameState.AddCoins(-price)
        end

        -- 发放材料
        local gained = {}
        for mat, count in pairs(pack.materials) do
            GameState.AddMaterial(mat, count)
            gained[#gained + 1] = OrderManager.GetMaterialName(mat) .. " x" .. count
        end

        SFXManager.Play(SFXManager.SFX.UI_COIN, 0.6)
        UI.Toast.Show("已购入 " .. pack.name .. "：" .. table.concat(gained, " "), { duration = 2.5 })

        RefreshCurrency()
        RefreshButtons()
    end

    -- 初始刷新
    RefreshCurrency()
    RefreshButtons()

    -- 货币变化时刷新（如购买后或其他界面回来）
    unsubs_[#unsubs_ + 1] = EventBus.On("coins_changed", function()
        RefreshCurrency()
        RefreshButtons()
    end)
    -- 玉璧变化时刷新（玉璧材料包购买后）
    unsubs_[#unsubs_ + 1] = EventBus.On("jade_changed", function()
        RefreshCurrency()
        RefreshButtons()
    end)

    -- ----------------------------------------------------------------
    -- screen 控制器
    -- ----------------------------------------------------------------
    function screen.Destroy()
        for i = 1, #unsubs_ do
            unsubs_[i]()
        end
        unsubs_ = {}
    end

    print("[ShopScreen] Created")
    return screen
end

return ShopScreen
