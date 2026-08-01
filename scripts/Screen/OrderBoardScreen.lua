---@diagnostic disable: assign-type-mismatch, return-type-mismatch, param-type-mismatch
-- ============================================================================
-- OrderBoardScreen - 订单板界面（布局模板对接版）
-- Project Smith
--
-- 策略：
--   使用布局编辑器预设卡片作为模板，通过 FindById 填充数据
--   左侧客户列表：6 个预设卡片 (cust_q ~ cust_29)
--   右侧订单详情：3 个预设卡片 (card_2s, card_3j, card_4a)
-- ============================================================================

local UI             = require("urhox-libs/UI")
local EventBus       = require("Core.EventBus")
local GameState      = require("Core.GameState")
local OrderManager   = require("Core.OrderManager")
local WeaponRecipes  = require("Config.WeaponRecipes")
local ScreenRouter   = require("Utils.ScreenRouter")
local SFXManager     = require("Utils.SFXManager")
local TutorialManager = require("Core.TutorialManager")
local BackButton     = require("Utils.BackButton")

local OrderLayout = require("ui_OrderBoardScreen_订单板")

local OrderBoardScreen = {}

-- ============================================================================
-- 布局 ID 映射表
-- 左侧客户卡片：每个卡片的子元素 ID
-- ============================================================================

local CUST_CARDS = {
    {
        id = "cust_q",
        bg = "sr_r",         -- 背景色板
        avatar = "ph_s",     -- 头像容器
        name = "tx_x",       -- 客户名
        title = "tx_y",      -- 头衔
        moodBg = "sr_z",     -- 心情徽章背景
        moodTx = "tx_10",    -- 心情文字
    },
    {
        id = "cust_11",
        bg = "sr_12",
        avatar = "ph_13",
        name = "tx_18",
        title = "tx_19",
        moodBg = "sr_1a",
        moodTx = "tx_1b",
    },
    {
        id = "cust_1c",
        bg = "sr_1d",
        avatar = "ph_1e",
        name = "tx_1j",
        title = "tx_1k",
        moodBg = "sr_1l",
        moodTx = "tx_1m",
    },
    {
        id = "cust_1n",
        bg = "sr_1o",
        avatar = "ph_1p",
        name = "tx_1u",
        title = "tx_1v",
        moodBg = "sr_1w",
        moodTx = "tx_1x",
    },
    {
        id = "cust_1y",
        bg = "sr_1z",
        avatar = "ph_20",
        name = "tx_25",
        title = "tx_26",
        moodBg = "sr_27",
        moodTx = "tx_28",
    },
    {
        id = "cust_29",
        bg = "sr_2a",
        avatar = "ph_2b",
        name = "tx_2g",
        title = "tx_2h",
        moodBg = "sr_2i",
        moodTx = "tx_2j",
    },
}

-- ============================================================================
-- 右侧订单详情卡片 ID 映射表
-- ============================================================================

local ORDER_CARDS = {
    {
        id = "card_2s",
        avatar = "ph_2w",        -- 头像容器
        custName = "tx_31",      -- 客户名
        custTitle = "tx_32",     -- 头衔
        weaponName = "tx_33",    -- 【委托物】名称
        usage = "tx_34",         -- 用途描述
        deadline = "tx_35",      -- 期限
        preference = "tx_36",    -- 偏好
        qualityBar = "pg_37",    -- 品质条容器
        qualityFill = "sr_39",   -- 品质条填充
        qualityText = "tx_3a",   -- 品质文字
        rewardLabel = "tx_3b",   -- "酬金" 标签
        rewardValue = "tx_3c",   -- 酬金数额
        acceptBtn = "plate_3d",  -- 接单按钮
        declineBtn = "plate_3g", -- 婉拒按钮
    },
    {
        id = "card_3j",
        avatar = "ph_3n",
        custName = "tx_3s",
        custTitle = "tx_3t",
        weaponName = "tx_3u",
        usage = "tx_3v",
        deadline = "tx_3w",
        preference = "tx_3x",
        qualityBar = "pg_3y",
        qualityFill = "sr_40",
        qualityText = "tx_41",
        rewardLabel = "tx_42",
        rewardValue = "tx_43",
        acceptBtn = "plate_44",
        declineBtn = "plate_47",
    },
    {
        id = "card_4a",
        avatar = "ph_4e",
        custName = "tx_4j",
        custTitle = "tx_4k",
        weaponName = "tx_4l",
        usage = "tx_4m",
        deadline = "tx_4n",
        preference = "tx_4o",
        qualityBar = "pg_4p",
        qualityFill = "sr_4r",
        qualityText = "tx_4s",
        rewardLabel = "tx_4t",
        rewardValue = "tx_4u",
        acceptBtn = "plate_4v",
        declineBtn = "plate_4y",
    },
}

-- ============================================================================
-- 客户心情 → 颜色映射
-- ============================================================================

local MOOD_COLORS = {
    ["急"]  = "#D4A574",
    ["缓"]  = "#4ECDC4",
    ["常"]  = "#FFD93D",
}

-- 选中/未选中卡片背景色
local CUST_BG_SELECTED   = "#D4A574"
local CUST_BG_UNSELECTED = "#332A24"

-- 订单配置只有 customerName/customerType，没有头像字段；这里统一按客户身份映射，
-- 动态写入左右两侧头像容器，避免布局模板中的静态头像与客户错位。
local CUSTOMER_AVATARS = {
    ["猎户张三"] = "image/char_hunter.png",
    ["厨娘李婶"] = "image/char_widow.png",
    ["少年刘五"] = "image/char_apprentice.png",
    ["药农老孙"] = "image/char_keeper.png",
    ["镖师王铁"] = "image/char_guard.png",
    ["樵夫陈大"] = "image/char_hunter.png",
    ["游侠赵风"] = "image/char_han.png",
    ["女侠林翠"] = "image/char_swordwoman_20260604131630.png",
}

local CUSTOMER_TYPE_AVATARS = {
    common = "image/char_apprentice.png",
    skilled = "image/char_blacksmith_20260604131624.png",
    noble = "image/char_magistrate.png",
    story = "image/char_keeper.png",
}

local function SetAvatarImage(avatarContainer, imagePath)
    if not avatarContainer or not imagePath then return end
    local children = avatarContainer.children
    local imageLayer = children and children[2]
    if imageLayer then
        imageLayer.backgroundImage = imagePath
        imageLayer.backgroundFit = "cover"
    else
        avatarContainer.backgroundImage = imagePath
        avatarContainer.backgroundFit = "cover"
    end
end

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
    -- 筛选标签按钮
    local tabAll_ = root:FindById("plate_7")
    local tabT1_ = root:FindById("plate_a")
    local tabT2_ = root:FindById("plate_d")
    local tabT3_ = root:FindById("plate_g")
    -- 右侧区域标题
    local detailTitle_ = root:FindById("tx_2q")
    local detailSubtitle_ = root:FindById("tx_2r")
    -- 隐藏右侧标题行（"X的委托 · N笔可接订单"），腾出垂直空间给订单卡片
    if detailTitle_ then detailTitle_.visible = false end
    if detailSubtitle_ then detailSubtitle_.visible = false end
    -- 左侧面板
    local leftPanel_ = root:FindById("df_j")
    -- 右侧面板
    local rightPanel_ = root:FindById("df_2k")

    -- 预缓存所有卡片元素引用（避免每次刷新都 FindById）
    local custWidgets_ = {}
    for i = 1, #CUST_CARDS do
        local map = CUST_CARDS[i]
        custWidgets_[i] = {
            card = root:FindById(map.id),
            bg = root:FindById(map.bg),
            avatar = root:FindById(map.avatar),
            name = root:FindById(map.name),
            title = root:FindById(map.title),
            moodBg = root:FindById(map.moodBg),
            moodTx = root:FindById(map.moodTx),
        }
    end

    -- ----------------------------------------------------------------
    -- 将订单卡片重新定位到右面板内部（布局模板生成时卡片在root层）
    -- ----------------------------------------------------------------
    local CARD_TOP_OFFSETS = { "2%", "35%", "68%" }
    for i = 1, #ORDER_CARDS do
        local card = root:FindById(ORDER_CARDS[i].id)
        if card and rightPanel_ then
            rightPanel_:AddChild(card)
            card.props.position = "absolute"
            card.props.left = 0
            card.props.right = 0
            card.props.top = CARD_TOP_OFFSETS[i]
            card.props.height = 202.4
            card.props.width = nil  -- 由 left+right 自动计算
        end
    end

    local orderWidgets_ = {}
    for i = 1, #ORDER_CARDS do
        local map = ORDER_CARDS[i]
        orderWidgets_[i] = {
            card = rightPanel_:FindById(map.id),
            avatar = rightPanel_:FindById(map.avatar),
            custName = rightPanel_:FindById(map.custName),
            custTitle = rightPanel_:FindById(map.custTitle),
            weaponName = rightPanel_:FindById(map.weaponName),
            usage = rightPanel_:FindById(map.usage),
            deadline = rightPanel_:FindById(map.deadline),
            preference = rightPanel_:FindById(map.preference),
            qualityFill = rightPanel_:FindById(map.qualityFill),
            qualityText = rightPanel_:FindById(map.qualityText),
            rewardValue = rightPanel_:FindById(map.rewardValue),
            acceptBtn = rightPanel_:FindById(map.acceptBtn),
            declineBtn = rightPanel_:FindById(map.declineBtn),
        }
    end

    -- ----------------------------------------------------------------
    -- 3. 状态
    -- ----------------------------------------------------------------
    local currentFilter_ = nil         -- 当前筛选等级 (nil=全部)
    local focusedOrderId_ = params and params.focusOrderId
    local selectedCustIdx_ = 1         -- 当前选中的客户索引
    local customers_ = {}              -- 去重后的客户列表
    local ordersByCustomer_ = {}       -- 按客户名分组的订单

    local TIER_NAMES = { "粗料", "熟料", "精料", "纹金", "陨材" }

    local function OpenMaterialTierDialog(order, recipe)
        local tiers = GameState.GetAvailableMaterialTiers(recipe.requiredMaterials)
        if #tiers == 0 then
            UI.Toast.Show("没有可用的同品质材料组合", { type = "warning", duration = 2.5 })
            return
        end

        if TutorialManager.IsFirstOrder(order.id) then
            TutorialManager.Advance("choose_material")
            UI.Toast.Show(TutorialManager.GetMessage("choose_material"), { duration = 3.5 })
        end

        local modal = UI.Modal {
            title = "选择材料品质",
            size = "sm",
            showCloseButton = true,
            closeOnOverlay = true,
            backgroundColor = "#12100E",
            borderColor = "#D4A574",
            borderWidth = 1,
            titleTextColor = "#D4A574",
            contentBgColor = { 31, 26, 23, 255 },
            contentPadding = { 16, 20, 16, 20 },
        }
        modal:AddContent(UI.Label {
            text = "选用更高品质材料可提高成品评分。材料将在接单时扣除。",
            fontSize = 16,
            fontColor = "#E8E0D0",
            width = "100%",
            lineHeight = 1.25,
        })

        local choices = UI.Panel {
            width = "100%",
            flexDirection = "row",
            justifyContent = "center",
            gap = 8,
            paddingTop = 14,
        }
        for i = 1, #tiers do
            local tier = tiers[i]
            choices:AddChild(UI.Button {
                text = (TIER_NAMES[tier] or ("T" .. tier)) .. " T" .. tier,
                variant = "secondary",
                height = 40,
                paddingLeft = 12,
                paddingRight = 12,
                onClick = function()
                    local ok, err = OrderManager.AcceptOrder(order.id, tier)
                    if not ok then
                        SFXManager.Play(SFXManager.SFX.UI_FAIL, 0.4)
                        UI.Toast.Show(tostring(err), { type = "warning", duration = 2.5 })
                        return
                    end
                    modal:Close()
                    SFXManager.Play(SFXManager.SFX.ORDER_ACCEPT, 0.7)
                    ScreenRouter.GoTo("forge", {
                        orderId = order.id,
                        order = order,
                        recipe = recipe,
                    })
                end,
            })
        end
        modal:AddContent(choices)
        modal:Open()
    end

    -- ----------------------------------------------------------------
    -- 4. 数据填充函数
    -- ----------------------------------------------------------------

    --- 填充左侧客户卡片
    local function FillCustomerCard(idx, customer, isSelected)
        local w = custWidgets_[idx]
        if not w or not w.card then return end

        w.card.visible = true

        -- 背景色：选中高亮
        if w.bg then
            w.bg.backgroundColor = isSelected and CUST_BG_SELECTED or CUST_BG_UNSELECTED
        end

        -- 客户名
        if w.name then
            w.name.text = customer.name or ""
        end

        local avatarPath = CUSTOMER_AVATARS[customer.name] or CUSTOMER_TYPE_AVATARS[customer.customerType]
        SetAvatarImage(w.avatar, avatarPath)

        -- 头衔
        if w.title then
            w.title.text = customer.title or ""
        end

        -- 心情徽章
        local mood = customer.mood or "常"
        if w.moodTx then
            w.moodTx.text = mood
        end
        if w.moodBg then
            w.moodBg.backgroundColor = MOOD_COLORS[mood] or MOOD_COLORS["常"]
        end

        -- 点击选中
        w.card.props.onClick = function()
            SFXManager.Play(SFXManager.SFX.UI_TAP, 0.3)
            SelectCustomer(idx)
        end
    end

    --- 隐藏未使用的客户卡片
    local function HideCustomerCard(idx)
        local w = custWidgets_[idx]
        if w and w.card then
            w.card.visible = false
        end
    end

    --- 填充右侧订单详情卡片
    local function FillOrderCard(idx, order)
        local w = orderWidgets_[idx]
        if not w or not w.card then return end

        w.card.visible = true

        local recipe = WeaponRecipes.GetById(order.weaponId)
        local weaponName = recipe and recipe.name or "未知武器"

        -- 客户信息
        local avatarPath = CUSTOMER_AVATARS[order.customerName] or CUSTOMER_TYPE_AVATARS[order.customerType]
        SetAvatarImage(w.avatar, avatarPath)
        if w.custName then
            w.custName.text = order.customerName or ""
        end
        if w.custTitle then
            w.custTitle.text = order.customerType == "skilled" and "行家"
                or order.customerType == "noble" and "贵人"
                or "百姓"
        end

        -- 委托物名称
        if w.weaponName then
            local tierName = order.tier == 1 and "寻常"
                or order.tier == 2 and "良品"
                or "精品"
            local mark = order.completed and "  · 已锻" or ""
            if order.id == focusedOrderId_ then
                mark = mark .. "  · 主线委托"
            elseif order.favorRequirement then
                mark = mark .. "  · 专属"
            elseif order.isDaily then
                mark = mark .. "  · 日常"
            end
            w.weaponName.text = "【委托物】" .. weaponName .. " · " .. tierName .. mark
        end

        -- 用途（从对话中提取要点）
        if w.usage then
            w.usage.text = "· 用途：" .. (order.dialogue or "未知")
        end

        -- 期限
        if w.deadline then
            local deadlineText = order.tier == 1 and "充裕（不限时）"
                or order.tier == 2 and "明日午时（约 6 小时）"
                or "今晚酉时（约 1 小时）"
            w.deadline.text = "· 期限：" .. deadlineText
        end

        -- 偏好
        if w.preference then
            local prefText = recipe and recipe.line or "无特殊偏好"
            w.preference.text = "· 偏好：" .. prefText
        end

        -- 品质条
        if w.qualityText then
            local qualityName = order.tier == 1 and "寻"
                or order.tier == 2 and "良"
                or "精"
            w.qualityText.text = "推荐品质 · " .. qualityName
        end
        if w.qualityFill then
            -- 根据 tier 设置宽度和颜色
            local fillRatio = order.tier == 1 and "50%"
                or order.tier == 2 and "70%"
                or "90%"
            local fillColor = order.tier == 1 and "#FFD93D"
                or order.tier == 2 and "#4ECDC4"
                or "#D4A574"
            w.qualityFill.width = fillRatio
            w.qualityFill.backgroundColor = fillColor
        end

        -- 酬金
        if w.rewardValue then
            local coins = order.baseRewardCoins or 0
            w.rewardValue.text = coins .. " 铜钱"
        end

        -- 接单按钮
        if w.acceptBtn then
            -- 检查材料是否充足，决定按钮状态
            local canAccept = true
            local shortage = nil
            if recipe and recipe.requiredMaterials then
                for mat, count in pairs(recipe.requiredMaterials) do
                    if not GameState.CanAffordMaterial(mat, count) then
                        canAccept = false
                        local name = OrderManager.GetMaterialName(mat)
                        local have = GameState.GetMaterial(mat) or 0
                        -- 提示缺口数量并引导回补：完成入门委托（猎户/药农）可获得矿石与木炭
                        shortage = name .. "不足 (需" .. count .. "/有" .. have
                            .. ")，接「猎户小刀」等委托可回补材料"
                        break
                    end
                end
            end
            -- 如果有进行中的订单也禁用
            if OrderManager.GetActiveOrder() then
                canAccept = false
                shortage = "已有进行中的订单"
            end

            if canAccept then
                if TutorialManager.IsActive() and not TutorialManager.IsFirstOrder(order.id) then
                    canAccept = false
                    shortage = "先完成猎户张三的首单，熟悉锻造流程"
                end
            end

            if canAccept then
                w.acceptBtn.props.onClick = function()
                    print("[OrderBoard] Accept clicked! orderId=" .. tostring(order.id))
                    OpenMaterialTierDialog(order, recipe)
                end
            else
                -- 禁用状态 - 变灰并提示原因
                local kids = w.acceptBtn.children
                if kids and kids[1] then
                    kids[1].backgroundColor = "#5A5A5A"
                    kids[1].borderColor = "#3A3A3A"
                end
                w.acceptBtn.props.onClick = function()
                    SFXManager.Play(SFXManager.SFX.UI_FAIL, 0.4)
                    UI.Toast.Show(shortage or "无法接单", { type = "warning", duration = 3 })
                end
            end
        end

        -- 婉拒按钮
        if w.declineBtn then
            w.declineBtn.props.onClick = function()
                SFXManager.Play(SFXManager.SFX.UI_TAP, 0.3)
                print("[OrderBoard] Declined order: " .. order.id)
            end
        end
    end

    --- 隐藏未使用的订单卡片
    local function HideOrderCard(idx)
        local w = orderWidgets_[idx]
        if w and w.card then
            w.card.visible = false
        end
    end

    -- ----------------------------------------------------------------
    -- 5. 选中客户 → 刷新右侧
    -- ----------------------------------------------------------------

    function SelectCustomer(idx)
        selectedCustIdx_ = idx

        -- 更新左侧选中状态
        for i = 1, #customers_ do
            local w = custWidgets_[i]
            if w and w.bg then
                w.bg.backgroundColor = (i == idx) and CUST_BG_SELECTED or CUST_BG_UNSELECTED
            end
        end

        -- 获取该客户的订单
        local custName = customers_[idx] and customers_[idx].name
        local orders = ordersByCustomer_[custName] or {}

        -- 更新标题
        if detailTitle_ then
            detailTitle_.text = (custName or "") .. "的委托 · " .. #orders .. " 笔可接订单"
        end

        -- 填充右侧卡片
        for i = 1, #ORDER_CARDS do
            if i <= #orders then
                FillOrderCard(i, orders[i])
            else
                HideOrderCard(i)
            end
        end

        print("[OrderBoard] Selected customer: " .. tostring(custName) .. " (" .. #orders .. " orders)")
    end

    -- ----------------------------------------------------------------
    -- 6. 刷新订单列表（主入口）
    -- ----------------------------------------------------------------

    local function RefreshOrderList()
        -- 获取可用订单
        local allOrders = OrderManager.GetAvailableOrders()

        -- 筛选等级
        local filtered = {}
        for i = 1, #allOrders do
            if currentFilter_ == nil or allOrders[i].tier == currentFilter_ then
                filtered[#filtered + 1] = allOrders[i]
            end
        end

        -- 按客户名分组 + 去重客户列表
        ordersByCustomer_ = {}
        customers_ = {}
        local seen = {}
        for i = 1, #filtered do
            local order = filtered[i]
            local cName = order.customerName
            if not seen[cName] then
                seen[cName] = true
                customers_[#customers_ + 1] = {
                    name = cName,
                    customerType = order.customerType,
                    title = order.customerType == "skilled" and "行家"
                        or order.customerType == "noble" and "贵人"
                        or "百姓",
                    mood = order.tier >= 3 and "急" or order.tier == 2 and "缓" or "常",
                }
            end
            if not ordersByCustomer_[cName] then
                ordersByCustomer_[cName] = {}
            end
            local list = ordersByCustomer_[cName]
            list[#list + 1] = order
        end

        -- 填充左侧客户卡片
        for i = 1, #CUST_CARDS do
            if i <= #customers_ then
                FillCustomerCard(i, customers_[i], i == selectedCustIdx_)
            else
                HideCustomerCard(i)
            end
        end

        -- 确保 selectedCustIdx_ 有效
        if focusedOrderId_ then
            for i = 1, #customers_ do
                local orders = ordersByCustomer_[customers_[i].name] or {}
                for j = 1, #orders do
                    if orders[j].id == focusedOrderId_ then
                        selectedCustIdx_ = i
                        break
                    end
                end
            end
        end
        if selectedCustIdx_ > #customers_ then
            selectedCustIdx_ = 1
        end

        -- 刷新右侧
        if #customers_ > 0 then
            SelectCustomer(selectedCustIdx_)
        else
            -- 无订单：隐藏所有右侧卡片，显示空提示
            for i = 1, #ORDER_CARDS do
                HideOrderCard(i)
            end
            if detailTitle_ then
                detailTitle_.text = "暂无可接取的订单"
            end
            if detailSubtitle_ then
                detailSubtitle_.text = ""
            end
        end

        print("[OrderBoard] Refreshed: " .. #filtered .. " orders, " .. #customers_ .. " customers")
    end

    -- ----------------------------------------------------------------
    -- 7. 绑定顶栏按钮事件
    -- ----------------------------------------------------------------

    BackButton.Setup(root, "home")

    local function SetFilter(tier)
        currentFilter_ = tier
        selectedCustIdx_ = 1
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
    -- 8. 初始加载
    -- ----------------------------------------------------------------
    RefreshOrderList()

    -- ----------------------------------------------------------------
    -- 9. 清理
    -- ----------------------------------------------------------------
    function screen.Destroy()
        for i = 1, #unsubs_ do
            unsubs_[i]()
        end
        unsubs_ = {}
    end

    print("[OrderBoard] Created (layout template binding)")
    return screen
end

return OrderBoardScreen
