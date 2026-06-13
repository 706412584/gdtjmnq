-- ============================================================================
-- UpgradeScreen - 设施升级界面 (Layout Migration)
-- Project Smith / P1-D
--
-- 使用 ui_UpgradeScreen_设施升级 布局文件，绑定设施数据并实现升级逻辑。
-- 布局为横屏设计，6 张设施卡片（第 6 张无数据时隐藏）。
-- ============================================================================

local UI             = require("urhox-libs/UI")
local EventBus       = require("Core.EventBus")
local GameState      = require("Core.GameState")
local FacilityConfig = require("Config.FacilityConfig")
local ScreenRouter   = require("Utils.ScreenRouter")
local Layout         = require("ui_UpgradeScreen_设施升级")

local UpgradeScreen = {}

-- ============================================================================
-- 设施卡片 → 布局 ID 映射
-- ============================================================================

local CARD_DEFS = {
    {
        facilityId = "furnace",
        cardId     = "fc_c",
        nameId     = "tx_j",
        levelId    = "tx_k",
        fillId     = "sr_n",
        buffIds    = { "tx_o", "tx_p", "tx_q", "tx_r" },
        btnId      = "plate_s",
        btnTextId  = "tx_u",
        costId     = "tx_v",
    },
    {
        facilityId = "anvil",
        cardId     = "fc_w",
        nameId     = "tx_13",
        levelId    = "tx_14",
        fillId     = "sr_17",
        buffIds    = { "tx_18", "tx_19", "tx_1a", "tx_1b" },
        btnId      = "plate_1c",
        btnTextId  = "tx_1e",
        costId     = "tx_1f",
    },
    {
        facilityId = "grinder",
        cardId     = "fc_1g",
        nameId     = "tx_1n",
        levelId    = "tx_1o",
        fillId     = "sr_1r",
        buffIds    = { "tx_1s", "tx_1t", "tx_1u" },
        btnId      = "plate_1v",
        btnTextId  = "tx_1x",
        costId     = "tx_1y",
    },
    {
        facilityId = "quench_pool",
        cardId     = "fc_1z",
        nameId     = "tx_26",
        levelId    = "tx_27",
        fillId     = "sr_2b",
        buffIds    = { "tx_2b", "tx_2c", "tx_2d", "tx_2e" },
        btnId      = "plate_2f",
        btnTextId  = "tx_2h",
        costId     = "tx_2i",
    },
    {
        facilityId = "display",
        cardId     = "fc_2j",
        nameId     = "tx_2q",
        levelId    = "tx_2r",
        fillId     = "sr_2u",
        buffIds    = { "tx_2v", "tx_2w", "tx_2x" },
        btnId      = "plate_2y",
        btnTextId  = "tx_30",
        costId     = "tx_31",
    },
}

-- 第 6 张卡片（入口照壁）— 暂无对应数据，隐藏
local EXTRA_CARD_ID = "fc_32"

-- ============================================================================
-- Screen 接口
-- ============================================================================

---@param container table UI 容器
---@param params table|nil
---@return table screen
function UpgradeScreen.Create(container, params)
    local screen = {}

    -- 构建布局
    local root = Layout.Build()
    container:AddChild(root)
    screen.panel = root

    -- ----------------------------------------------------------------
    -- 顶栏绑定
    -- ----------------------------------------------------------------
    local backBtn    = root:FindById("plate_3")
    local coinsText  = root:FindById("tx_9")
    local matsText   = root:FindById("tx_b")

    if backBtn then
        backBtn.onClick = function()
            ScreenRouter.GoTo("home")
        end
    end

    -- 隐藏第 6 张无数据卡片
    local extraCard = root:FindById(EXTRA_CARD_ID)
    if extraCard then
        extraCard.display = "none"
    end

    -- 隐藏底部蓝图装饰区域（横屏装饰元素，竖屏不显示）
    local blueprintTitle = root:FindById("tx_3q")
    if blueprintTitle then blueprintTitle.display = "none" end
    local blueprintLine = root:FindById("sl_3r")
    if blueprintLine then blueprintLine.display = "none" end
    -- 解锁路径圆点和连线
    local decorIds = { "sc_3s", "sc_3t", "sc_3u", "sc_3v", "sc_3w", "sl_3x", "sl_3y", "sl_3z", "sl_40", "tx_41", "df_3k" }
    for i = 1, #decorIds do
        local el = root:FindById(decorIds[i])
        if el then el.display = "none" end
    end

    -- ----------------------------------------------------------------
    -- 卡片元素引用缓存
    -- ----------------------------------------------------------------
    ---@type table<string, table>
    local cardRefs_ = {}

    for i = 1, #CARD_DEFS do
        local def = CARD_DEFS[i]
        local refs = {
            card      = root:FindById(def.cardId),
            nameLabel = root:FindById(def.nameId),
            levelLabel = root:FindById(def.levelId),
            fill      = root:FindById(def.fillId),
            buffLabels = {},
            btn       = root:FindById(def.btnId),
            btnText   = root:FindById(def.btnTextId),
            costLabel = root:FindById(def.costId),
        }
        for j = 1, #def.buffIds do
            refs.buffLabels[j] = root:FindById(def.buffIds[j])
        end
        cardRefs_[def.facilityId] = refs
    end

    -- ----------------------------------------------------------------
    -- 刷新货币栏
    -- ----------------------------------------------------------------
    local function RefreshCurrencyBar()
        if coinsText then
            coinsText.text = "铜钱 " .. tostring(GameState.GetCoins())
        end
        if matsText then
            local jade = GameState.GetJade and GameState.GetJade() or 0
            matsText.text = "玉璧 " .. tostring(jade)
        end
    end

    -- ----------------------------------------------------------------
    -- 刷新单个设施卡片
    -- ----------------------------------------------------------------
    local function RefreshCard(facilityId)
        local refs = cardRefs_[facilityId]
        if not refs then return end

        local level    = GameState.GetFacilityLevel(facilityId)
        local maxLevel = FacilityConfig.GetMaxLevel(facilityId)
        local name     = FacilityConfig.GetName(facilityId)
        local desc     = FacilityConfig.GetLevelDesc(facilityId, level)
        local coeff    = FacilityConfig.GetToolCoeff(facilityId, level)
        local isMax    = FacilityConfig.IsMaxLevel(facilityId, level)

        -- 名称
        if refs.nameLabel then
            refs.nameLabel.text = name
        end

        -- 等级
        if refs.levelLabel then
            refs.levelLabel.text = "等阶  Lv." .. level .. " / " .. maxLevel
        end

        -- 进度条填充
        if refs.fill then
            local progress = level / maxLevel
            refs.fill.width = math.floor(progress * 98) .. "%"
        end

        -- buff 描述行
        local buffTexts = {}
        buffTexts[1] = "· " .. desc
        buffTexts[2] = "· 工具系数 x" .. string.format("%.2f", coeff)
        -- 剩余行留空隐藏
        for j = 1, #refs.buffLabels do
            local label = refs.buffLabels[j]
            if label then
                if buffTexts[j] then
                    label.text = buffTexts[j]
                    label.display = "flex"
                else
                    label.text = ""
                    label.display = "none"
                end
            end
        end

        -- 升级按钮与费用
        if isMax then
            if refs.costLabel then
                refs.costLabel.text = "已满级"
            end
            if refs.btnText then
                refs.btnText.text = "已满级"
            end
            if refs.btn then
                refs.btn.disabled = true
                refs.btn.opacity = 0.5
            end
        else
            local cost = FacilityConfig.GetUpgradeCost(facilityId, level)
            if cost then
                local canAffordCoins = GameState.CanAffordCoins(cost.coins)
                local canAffordFame  = GameState.GetFame() >= cost.fame
                local canAfford = canAffordCoins and canAffordFame

                if refs.costLabel then
                    refs.costLabel.text = "需 " .. cost.coins .. " 铜"
                    if not canAfford then
                        refs.costLabel.fontColor = "#E94560"
                    else
                        refs.costLabel.fontColor = "#c9a45a"
                    end
                end
                if refs.btnText then
                    refs.btnText.text = canAfford and "升阶" or "不足"
                end
                if refs.btn then
                    refs.btn.disabled = not canAfford
                    refs.btn.opacity = canAfford and 1.0 or 0.5
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

        -- 刷新所有卡片（资源变化可能影响其他设施可升级状态）
        for i = 1, #CARD_DEFS do
            RefreshCard(CARD_DEFS[i].facilityId)
        end
        RefreshCurrencyBar()
    end

    -- ----------------------------------------------------------------
    -- 绑定升级按钮点击事件
    -- ----------------------------------------------------------------
    for i = 1, #CARD_DEFS do
        local def = CARD_DEFS[i]
        local refs = cardRefs_[def.facilityId]
        if refs and refs.btn then
            refs.btn.onClick = function()
                DoUpgrade(def.facilityId)
            end
        end
    end

    -- ----------------------------------------------------------------
    -- 初始刷新
    -- ----------------------------------------------------------------
    for i = 1, #CARD_DEFS do
        RefreshCard(CARD_DEFS[i].facilityId)
    end
    RefreshCurrencyBar()

    -- ----------------------------------------------------------------
    -- EventBus 监听
    -- ----------------------------------------------------------------
    local unsubs_ = {}

    unsubs_[#unsubs_ + 1] = EventBus.On("coins_changed", function()
        RefreshCurrencyBar()
        for i = 1, #CARD_DEFS do
            RefreshCard(CARD_DEFS[i].facilityId)
        end
    end)

    unsubs_[#unsubs_ + 1] = EventBus.On("fame_changed", function()
        RefreshCurrencyBar()
        for i = 1, #CARD_DEFS do
            RefreshCard(CARD_DEFS[i].facilityId)
        end
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
