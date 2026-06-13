---@diagnostic disable: assign-type-mismatch, return-type-mismatch, param-type-mismatch
-- ============================================================================
-- OrderBoardScreen - 订单板界面（迁移版：使用 ui_OrderBoardScreen 布局框架）
-- Project Smith
--
-- 策略：
--   布局提供顶栏（返回/标题/标签）和整体框架
--   订单列表区域 df_j 作为容器承载动态订单卡片
--   预设的卡片模板 cust_* 隐藏，替换为代码动态生成的订单卡片
-- ============================================================================

local UI             = require("urhox-libs/UI")
local EventBus       = require("Core.EventBus")
local GameState      = require("Core.GameState")
local OrderManager   = require("Core.OrderManager")
local WeaponRecipes  = require("Config.WeaponRecipes")
local ScreenRouter   = require("Utils.ScreenRouter")
local SFXManager     = require("Utils.SFXManager")

local OrderLayout = require("ui_OrderBoardScreen_订单板")

local OrderBoardScreen = {}

-- ============================================================================
-- 色板（用于动态卡片）
-- ============================================================================

local C = {
    gold         = "#C9A45A",
    textPrimary  = "#F1E5CC",
    textSecondary = "#9C8A6A",
    success      = "#4F7A63",
    accent       = "#C96A2B",
    cardBg       = "rgba(31,26,23,0.55)",
    cardBorder   = "#3A322B",
}

-- ============================================================================
-- Screen 接口
-- ============================================================================

function OrderBoardScreen.Create(container, params)
    local screen = {}
    local unsubs_ = {}

    -- ----------------------------------------------------------------
    -- 1. 构建布局框架
    -- ----------------------------------------------------------------
    local root = OrderLayout.Build()
    container:AddChild(root)

    -- ----------------------------------------------------------------
    -- 2. 获取关键元素引用
    -- ----------------------------------------------------------------

    -- 返回按钮
    local backBtn_ = root:FindById("plate_3")
    -- 标题
    local titleLabel_ = root:FindById("tx_6")
    -- 筛选标签按钮
    local tabAll_ = root:FindById("plate_7")
    local tabT1_ = root:FindById("plate_a")
    local tabT2_ = root:FindById("plate_d")
    local tabT3_ = root:FindById("plate_g")
    -- 主内容区域
    local contentArea_ = root:FindById("df_j")
    -- 右侧详情区（横屏特有，可能需隐藏预设内容）
    local detailTitle_ = root:FindById("tx_p")

    -- 预设卡片模板（隐藏，用动态替代）
    local presetCards = { "cust_q", "cust_11", "cust_1c", "cust_1n", "cust_1y" }
    for _, cardId in ipairs(presetCards) do
        local card = root:FindById(cardId)
        if card then card.display = "none" end
    end

    -- 隐藏横屏右侧详情面板中的预设内容
    if detailTitle_ then
        detailTitle_.text = ""
    end

    -- ----------------------------------------------------------------
    -- 3. 绑定按钮事件
    -- ----------------------------------------------------------------

    if backBtn_ then
        backBtn_.props.onClick = function()
            SFXManager.Play(SFXManager.SFX.UI_TAP, 0.4)
            ScreenRouter.GoTo("home")
        end
    end

    -- 当前筛选等级（nil 表示全部）
    local currentFilter_ = nil

    local function SetFilter(tier)
        currentFilter_ = tier
        RefreshOrderList()
    end

    if tabAll_ then
        tabAll_.props.onClick = function()
            SFXManager.Play(SFXManager.SFX.UI_TAP, 0.3)
            SetFilter(nil)
        end
    end
    if tabT1_ then
        tabT1_.props.onClick = function()
            SFXManager.Play(SFXManager.SFX.UI_TAP, 0.3)
            SetFilter(1)
        end
    end
    if tabT2_ then
        tabT2_.props.onClick = function()
            SFXManager.Play(SFXManager.SFX.UI_TAP, 0.3)
            SetFilter(2)
        end
    end
    if tabT3_ then
        tabT3_.props.onClick = function()
            SFXManager.Play(SFXManager.SFX.UI_TAP, 0.3)
            SetFilter(3)
        end
    end

    -- ----------------------------------------------------------------
    -- 4. 动态订单卡片容器（覆盖在 contentArea_ 之上）
    -- ----------------------------------------------------------------

    -- 创建一个滚动容器覆盖在 df_j 区域
    local orderScrollView_ = UI.ScrollView {
        id = "order_scroll",
        position = "absolute",
        left = "1.17%",
        top = 107,
        width = "97.66%",
        bottom = 34,
        scrollY = true,
        showScrollbar = true,
        bounces = true,
        paddingHorizontal = 12,
        paddingTop = 12,
        paddingBottom = 20,
        children = {},
    }
    root:AddChild(orderScrollView_)

    -- 隐藏原始的 df_j（预设内容）
    if contentArea_ then
        contentArea_.display = "none"
    end

    -- ----------------------------------------------------------------
    -- 5. 创建订单卡片
    -- ----------------------------------------------------------------
    local function CreateOrderCard(order)
        local recipe = WeaponRecipes.GetById(order.weaponId)
        local weaponName = recipe and recipe.name or "未知武器"

        -- 材料需求文本
        local matChildren = {}
        if recipe and recipe.requiredMaterials then
            for mat, count in pairs(recipe.requiredMaterials) do
                local has = GameState.GetMaterial(mat)
                local color = has >= count and C.success or C.accent
                matChildren[#matChildren + 1] = UI.Label {
                    text = mat .. " " .. has .. "/" .. count,
                    fontSize = 12,
                    fontColor = color,
                    marginRight = 8,
                }
            end
        end

        return UI.Panel {
            width = "100%",
            backgroundColor = C.cardBg,
            borderRadius = 8,
            borderWidth = 1,
            borderColor = C.cardBorder,
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
                            fontWeight = 700,
                            fontColor = C.textPrimary,
                        },
                        UI.Label {
                            text = "T" .. order.tier,
                            fontSize = 12,
                            fontColor = C.gold,
                        },
                    }
                },
                -- 对话
                UI.Label {
                    text = "\"" .. (order.dialogue or "") .. "\"",
                    fontSize = 12,
                    fontColor = C.textSecondary,
                    maxLines = 2,
                },
                -- 分割线
                UI.Panel {
                    width = "100%",
                    height = 1,
                    backgroundColor = C.cardBorder,
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
                                    text = "铜钱+" .. (order.baseRewardCoins or 0),
                                    fontSize = 11,
                                    fontColor = C.gold,
                                },
                                UI.Label {
                                    text = "声望+" .. (order.baseRewardFame or 0),
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
                    gap = 4,
                    children = matChildren,
                },
                -- 接单按钮
                UI.Panel {
                    width = "100%",
                    height = 40,
                    backgroundColor = C.success,
                    borderRadius = 6,
                    justifyContent = "center",
                    alignItems = "center",
                    marginTop = 6,
                    onClick = function()
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
                            print("[OrderBoard] Accept failed: " .. tostring(err))
                        end
                    end,
                    children = {
                        UI.Label {
                            text = "接受订单",
                            fontSize = 14,
                            fontWeight = 700,
                            fontColor = C.textPrimary,
                        },
                    },
                },
            }
        }
    end

    -- ----------------------------------------------------------------
    -- 6. 刷新订单列表
    -- ----------------------------------------------------------------
    function RefreshOrderList()
        orderScrollView_:ClearChildren()

        local orders = OrderManager.GetAvailableOrders()

        -- 筛选
        local filtered = {}
        for i = 1, #orders do
            if currentFilter_ == nil or orders[i].tier == currentFilter_ then
                filtered[#filtered + 1] = orders[i]
            end
        end

        if #filtered == 0 then
            orderScrollView_:AddChild(
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

        for i = 1, #filtered do
            orderScrollView_:AddChild(CreateOrderCard(filtered[i]))
        end

        print("[OrderBoard] Refreshed: " .. #filtered .. " orders displayed")
    end

    -- 初次加载
    RefreshOrderList()

    -- ----------------------------------------------------------------
    -- 7. 清理
    -- ----------------------------------------------------------------
    function screen.Destroy()
        for i = 1, #unsubs_ do
            unsubs_[i]()
        end
        unsubs_ = {}
    end

    print("[OrderBoard] Created (layout migration)")
    return screen
end

return OrderBoardScreen
