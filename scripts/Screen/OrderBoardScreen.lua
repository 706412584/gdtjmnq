---@diagnostic disable: assign-type-mismatch, return-type-mismatch, param-type-mismatch
-- ============================================================================
-- OrderBoardScreen - 订单板界面
-- Project Smith / P1-D2
--
-- 显示: 可接取订单列表（卡片式），含客户名/对话/武器/奖励/材料需求
-- 点击接单后跳转到 ForgeScreen
-- ============================================================================

local UI             = require("urhox-libs/UI")
local EventBus       = require("Core.EventBus")
local GameState      = require("Core.GameState")
local OrderManager   = require("Core.OrderManager")
local WeaponRecipes  = require("Config.WeaponRecipes")
local ScreenRouter   = require("Utils.ScreenRouter")
local SFXManager     = require("Utils.SFXManager")

local OrderBoardScreen = {}

-- ============================================================================
-- UI 素材路径（武侠水墨风）
-- ============================================================================

local UI_ASSETS = {
    panel_header    = "image/ui/panel_header.png",
    panel_card_blue = "image/ui/panel_card_blue.png",
    btn_accept      = "image/ui/btn_accept.png",
    divider_bamboo  = "image/ui/divider_bamboo.png",
}

-- ============================================================================
-- 色板
-- ============================================================================

local C = {
    bgPrimary    = { 26,  26,  46,  255 },
    bgSecondary  = { 22,  33,  62,  255 },
    bgCard       = { 30,  40,  68,  255 },
    bgCardHover  = { 38,  48,  78,  255 },
    accent       = { 233, 69,  96,  255 },
    gold         = { 212, 165, 116, 255 },
    textPrimary  = { 232, 224, 208, 255 },
    textSecondary = { 160, 147, 125, 255 },
    success      = { 78,  205, 196, 255 },
    warning      = { 255, 217, 61,  255 },
    btnAccept    = { 78,  165, 130, 255 },
    btnAcceptHover = { 90, 180, 145, 255 },
    btnBack      = { 80,  80,  100, 255 },
    divider      = { 60,  60,  90,  120 },
    tierColors   = {
        [1] = { 180, 180, 180, 255 },  -- T1 灰白
        [2] = { 120, 200, 120, 255 },  -- T2 绿
    },
}

-- ============================================================================
-- Screen 接口
-- ============================================================================

function OrderBoardScreen.Create(container, params)
    local screen = {}
    local unsubs_ = {}

    -- 订单列表容器引用
    local orderListContainer_
    -- 状态提示
    local statusLabel_

    -- ----------------------------------------------------------------
    -- 创建单张订单卡片
    -- ----------------------------------------------------------------
    local function CreateOrderCard(order)
        local recipe = WeaponRecipes.GetById(order.weaponId)
        local weaponName = recipe and recipe.name or "未知武器"

        -- 材料需求文本
        local materialTexts = {}
        if recipe and recipe.requiredMaterials then
            for mat, count in pairs(recipe.requiredMaterials) do
                local has = GameState.GetMaterial(mat)
                local color = has >= count and C.success or C.accent
                materialTexts[#materialTexts + 1] = {
                    text = mat .. " " .. has .. "/" .. count,
                    color = color,
                }
            end
        end

        -- 材料标签列表
        local matLabels = {}
        for i = 1, #materialTexts do
            matLabels[#matLabels + 1] = UI.Label {
                text = materialTexts[i].text,
                fontSize = 11,
                fontColor = materialTexts[i].color,
            }
        end

        local tierColor = C.tierColors[order.tier] or C.textSecondary

        return UI.Panel {
            width = "100%",
            backgroundImage = UI_ASSETS.panel_card_blue,
            backgroundFit = "cover",
            borderRadius = 8,
            padding = 12,
            gap = 6,
            marginBottom = 10,
            children = {
                -- 头部：客户名 + 等级
                UI.Panel {
                    width = "100%",
                    flexDirection = "row",
                    justifyContent = "space-between",
                    alignItems = "center",
                    children = {
                        UI.Label {
                            text = order.customerName,
                            fontSize = 15,
                            fontColor = C.textPrimary,
                        },
                        UI.Label {
                            text = "T" .. order.tier,
                            fontSize = 12,
                            fontColor = tierColor,
                        },
                    }
                },

                -- 对话
                UI.Label {
                    text = "\"" .. order.dialogue .. "\"",
                    fontSize = 12,
                    fontColor = C.textSecondary,
                    maxLines = 2,
                },

                -- 分隔线
                UI.Panel {
                    width = "100%",
                    height = 16,
                    backgroundImage = UI_ASSETS.divider_bamboo,
                    backgroundFit = "contain",
                    marginVertical = 4,
                },

                -- 武器名 + 奖励
                UI.Panel {
                    width = "100%",
                    flexDirection = "row",
                    justifyContent = "space-between",
                    alignItems = "center",
                    children = {
                        UI.Label {
                            text = "锻造: " .. weaponName,
                            fontSize = 13,
                            fontColor = C.gold,
                        },
                        UI.Panel {
                            flexDirection = "row",
                            gap = 10,
                            children = {
                                UI.Label {
                                    text = "铜钱+" .. order.baseRewardCoins,
                                    fontSize = 11,
                                    fontColor = C.gold,
                                },
                                UI.Label {
                                    text = "声望+" .. order.baseRewardFame,
                                    fontSize = 11,
                                    fontColor = C.success,
                                },
                            }
                        },
                    }
                },

                -- 材料需求
                UI.Panel {
                    width = "100%",
                    flexDirection = "row",
                    flexWrap = "wrap",
                    gap = 8,
                    children = matLabels,
                },

                -- 接单按钮
                UI.Button {
                    text = "接受订单",
                    width = "100%",
                    height = 42,
                    fontSize = 14,
                    backgroundImage = UI_ASSETS.btn_accept,
                    backgroundFit = "cover",
                    fontColor = C.textPrimary,
                    borderRadius = 6,
                    marginTop = 4,
                    onClick = function(self)
                        local ok, err = OrderManager.AcceptOrder(order.id)
                        if ok then
                            SFXManager.Play(SFXManager.SFX.ORDER_ACCEPT, 0.7)
                            ScreenRouter.GoTo("forge", {
                                orderId = order.id,
                                order = order,
                                recipe = recipe,
                            })
                        else
                            SFXManager.Play(SFXManager.SFX.UI_FAIL, 0.4)
                            if statusLabel_ then
                                statusLabel_.text = err or "无法接单"
                            end
                            print("[OrderBoard] Accept failed: " .. tostring(err))
                        end
                    end,
                },
            }
        }
    end

    -- ----------------------------------------------------------------
    -- 刷新订单列表
    -- ----------------------------------------------------------------
    local function RefreshOrderList()
        if not orderListContainer_ then return end
        orderListContainer_:ClearChildren()

        local orders = OrderManager.GetAvailableOrders()

        if #orders == 0 then
            orderListContainer_:AddChild(
                UI.Label {
                    text = "暂无可接取的订单",
                    fontSize = 14,
                    fontColor = C.textSecondary,
                    textAlign = "center",
                    width = "100%",
                    marginTop = 40,
                }
            )
            return
        end

        for i = 1, #orders do
            orderListContainer_:AddChild(CreateOrderCard(orders[i]))
        end
    end

    -- ----------------------------------------------------------------
    -- 组装页面
    -- ----------------------------------------------------------------
    statusLabel_ = UI.Label {
        text = "",
        fontSize = 12,
        fontColor = C.accent,
        textAlign = "center",
        width = "100%",
        height = 16,
    }

    orderListContainer_ = UI.Panel {
        width = "100%",
        gap = 0,
    }

    local panel = UI.Panel {
        width = "100%",
        height = "100%",
        flexDirection = "column",
        children = {
            -- 顶栏
            UI.Panel {
                width = "100%",
                flexDirection = "row",
                justifyContent = "space-between",
                alignItems = "center",
                paddingHorizontal = 16,
                paddingVertical = 12,
                backgroundImage = UI_ASSETS.panel_header,
                backgroundFit = "cover",
                children = {
                    UI.Button {
                        text = "< 返回",
                        fontSize = 14,
                        fontColor = C.textSecondary,
                        backgroundColor = { 0, 0, 0, 0 },
                        onClick = function(self)
                            ScreenRouter.GoTo("home")
                        end,
                    },
                    UI.Label {
                        text = "订单板",
                        fontSize = 18,
                        fontColor = C.gold,
                    },
                    -- 占位保持居中
                    UI.Panel { width = 60 },
                },
            },

            -- 状态提示
            statusLabel_,

            -- 可滚动订单列表
            UI.ScrollView {
                width = "100%",
                flexGrow = 1,
                flexBasis = 0,
                scrollY = true,
                showScrollbar = true,
                bounces = true,
                paddingHorizontal = 14,
                paddingTop = 8,
                paddingBottom = 20,
                children = {
                    orderListContainer_,
                },
            },
        }
    }

    container:AddChild(panel)
    screen.panel = panel

    -- 初次加载
    RefreshOrderList()

    -- ----------------------------------------------------------------
    -- 清理
    -- ----------------------------------------------------------------
    function screen.Destroy()
        for i = 1, #unsubs_ do
            unsubs_[i]()
        end
        unsubs_ = {}
    end

    return screen
end

return OrderBoardScreen
