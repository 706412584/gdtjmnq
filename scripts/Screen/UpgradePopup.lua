---@diagnostic disable: param-type-mismatch
-- ============================================================================
-- UpgradePopup - 设施升级弹窗（横屏优化版）
-- Project Smith
--
-- 点击主界面设施卡片后弹出，展示该设施的升级信息和操作按钮。
-- 横屏布局：左侧设施大图 + 右侧详细信息，底部升级操作栏。
-- ============================================================================

local UI             = require("urhox-libs/UI")
local GameState      = require("Core.GameState")
local FacilityConfig = require("Config.FacilityConfig")
local EventBus       = require("Core.EventBus")
local SFXManager     = require("Utils.SFXManager")
local OrderManager   = require("Core.OrderManager")

local UpgradePopup = {}

-- 设施图片映射
local FACILITY_IMAGES = {
    furnace      = "image/card_furnace_20260613074302.png",
    anvil        = "image/card_anvil_20260613074251.png",
    grinder      = "image/card_grinder_20260613074243.png",
    storage      = "image/card_storage_20260613074346.png",
    display      = "image/card_display_20260613074325.png",
}

-- 设施描述补充
local FACILITY_FLAVOR = {
    furnace = "熔炼矿石的核心设备，温度越高越能提炼精纯金属。",
    anvil   = "锻打定型的工作台，坚实的锻台让每一锤都更精准。",
    grinder = "研磨开刃的利器，精细的磨石让刀剑锋利无匹。",
    storage = "存放材料的仓库，扩容后可囤积更多珍稀矿料。",
    display = "展示成品的架子，精美的陈列架能提升铁匠声望。",
}

---@type table|nil
local modal_ = nil
local popupPanel_ = nil
local overlayPanel_ = nil
---@type string|nil
local currentFacility_ = nil

-- 内容元素引用
local nameLabel_      = nil
local levelLabel_     = nil
local descLabel_      = nil
local flavorLabel_    = nil
local coeffLabel_     = nil
local costLabel_      = nil
local upgradeBtn_     = nil
local progressBar_    = nil
local progressText_   = nil
local imgPanel_       = nil
local nextDescLabel_  = nil

-- ============================================================================
-- 刷新弹窗内容
-- ============================================================================

local function RefreshContent()
    if not currentFacility_ then return end

    local facilityId = currentFacility_
    local level    = GameState.GetFacilityLevel(facilityId)
    local maxLevel = FacilityConfig.GetMaxLevel(facilityId)
    local name     = FacilityConfig.GetName(facilityId)
    local desc     = FacilityConfig.GetLevelDesc(facilityId, level)
    local coeff    = FacilityConfig.GetToolCoeff(facilityId, level)
    local isMax    = FacilityConfig.IsMaxLevel(facilityId, level)

    if nameLabel_ then nameLabel_.text = name end
    if levelLabel_ then levelLabel_.text = "Lv." .. level .. " / " .. maxLevel end
    if descLabel_ then descLabel_.text = "当前: " .. desc end
    if flavorLabel_ then flavorLabel_.text = FACILITY_FLAVOR[facilityId] or "" end
    if coeffLabel_ then coeffLabel_.text = "工具系数  x" .. string.format("%.2f", coeff) end

    -- 进度条
    if progressBar_ then
        local pct = math.floor(level / maxLevel * 100)
        progressBar_.width = pct .. "%"
    end
    if progressText_ then
        progressText_.text = level .. " / " .. maxLevel
    end

    -- 图片
    if imgPanel_ then
        local img = FACILITY_IMAGES[facilityId]
        if img then
            imgPanel_.backgroundImage = img
            imgPanel_.backgroundFit = "contain"
        end
    end

    -- 下一级预览
    if not isMax then
        local nextDesc = FacilityConfig.GetLevelDesc(facilityId, level + 1)
        local nextCoeff = FacilityConfig.GetToolCoeff(facilityId, level + 1)
        if nextDescLabel_ then
            nextDescLabel_.text = "下一级: " .. nextDesc .. "  (x" .. string.format("%.2f", nextCoeff) .. ")"
            nextDescLabel_.visible = true
        end
    else
        if nextDescLabel_ then
            nextDescLabel_.visible = false
        end
    end

    -- 升级按钮 & 费用
    if isMax then
        if costLabel_ then
            costLabel_.text = "已达满级"
            costLabel_.fontColor = "#A0937D"
        end
        if upgradeBtn_ then
            upgradeBtn_:SetDisabled(true)
            upgradeBtn_:SetText("已满级")
        end
    else
        local cost = FacilityConfig.GetUpgradeCost(facilityId, level)
        if cost then
            local needFame = cost.fame or 0
            local canAffordCoins = GameState.CanAffordCoins(cost.coins)
            local canAffordFame = GameState.GetFame() >= needFame
            local canAfford = canAffordCoins and canAffordFame
            if costLabel_ then
                local costText = "升级费用: " .. cost.coins .. " 铜钱"
                if needFame > 0 then
                    costText = costText .. " · " .. needFame .. " 声望"
                end
                costLabel_.text = costText
                costLabel_.fontColor = canAfford and "#D4A574" or "#E94560"
            end
            if upgradeBtn_ then
                local btnText = "升阶锻造"
                if not canAffordCoins then
                    btnText = "铜钱不足"
                elseif not canAffordFame then
                    btnText = "声望不足"
                end
                -- 切换按钮背景图（金色/灰色）
                upgradeBtn_.backgroundImage = canAfford
                    and "image/ui/btn_gold.png"
                    or "image/ui/btn_disabled.png"
                -- 更新按钮文字
                local txtLabel = upgradeBtn_:FindById("upgrade_btn_text")
                if txtLabel then
                    txtLabel.text = btnText
                    txtLabel.fontColor = canAfford and "#1A1A2E" or "#888888"
                end
            end
        end
    end
end

-- ============================================================================
-- 执行升级
-- ============================================================================

local function DoUpgrade()
    if not currentFacility_ then return end

    local facilityId = currentFacility_

    -- 委托 OrderManager 统一处理（含铜钱 + 声望双重检查、扣费、升级、事件）
    local success, errorMsg = OrderManager.UpgradeFacility(facilityId)
    if not success then
        UI.Toast.Show(errorMsg or "升级失败")
        return
    end

    local newLevel = GameState.GetFacilityLevel(facilityId)
    SFXManager.Play(SFXManager.SFX.UI_COIN, 0.5)
    UI.Toast.Show(FacilityConfig.GetName(facilityId) .. " 升至 Lv." .. newLevel)

    -- 刷新弹窗内容（OrderManager 已 emit facility_upgraded，主界面会自动刷新）
    RefreshContent()
end

-- ============================================================================
-- 构建 Modal（懒初始化，只创建一次）
-- ============================================================================

local function EnsureModal()
    if modal_ then return end

    -- ============================
    -- 左侧：设施大图区（百分比自适应）
    -- ============================
    imgPanel_ = UI.Panel {
        width = "100%",
        aspectRatio = 1,
        borderRadius = 12,
        backgroundColor = "rgba(31,26,23,0.5)",
        borderColor = "#3A322B",
        borderWidth = 1,
    }

    local leftColumn = UI.Panel {
        width = "35%",
        alignItems = "center",
        justifyContent = "center",
        paddingRight = 16,
        children = {
            imgPanel_,
        },
    }

    -- ============================
    -- 右侧：信息区
    -- ============================

    -- 名称 + 等级行
    nameLabel_ = UI.Label {
        text = "",
        fontSize = 29,
        fontWeight = 700,
        fontColor = "#E8E0D0",
    }

    levelLabel_ = UI.Label {
        text = "",
        fontSize = 18,
        fontColor = "#C9A45A",
        marginLeft = 12,
    }

    local headerRow = UI.Panel {
        flexDirection = "row",
        alignItems = "baseline",
        width = "100%",
        marginBottom = 8,
        children = { nameLabel_, levelLabel_ },
    }

    -- 进度条
    progressBar_ = UI.Panel {
        width = "0%",
        height = "100%",
        backgroundColor = "#C9A45A",
        borderRadius = 4,
    }

    progressText_ = UI.Label {
        text = "",
        fontSize = 14,
        fontColor = "#E8E0D0",
        position = "absolute",
        right = 8,
        top = 0,
        height = "100%",
        verticalAlign = "middle",
    }

    local progressBg = UI.Panel {
        width = "100%", height = 18,
        backgroundColor = "#3A322B",
        borderRadius = 4,
        marginBottom = 14,
        children = { progressBar_, progressText_ },
    }

    -- 风味描述
    flavorLabel_ = UI.Label {
        text = "",
        fontSize = 17,
        fontColor = "#A0937D",
        width = "100%",
        marginBottom = 10,
    }

    -- 当前状态
    descLabel_ = UI.Label {
        text = "",
        fontSize = 18,
        fontColor = "#E8E0D0",
        width = "100%",
        marginBottom = 4,
    }

    -- 工具系数
    coeffLabel_ = UI.Label {
        text = "",
        fontSize = 18,
        fontColor = "#D4A574",
        fontWeight = 700,
        width = "100%",
        marginBottom = 8,
    }

    -- 下一级预览
    nextDescLabel_ = UI.Label {
        text = "",
        fontSize = 17,
        fontColor = "#4ECDC4",
        width = "100%",
        marginBottom = 4,
    }

    local rightColumn = UI.Panel {
        width = "65%",
        flexShrink = 1,
        justifyContent = "center",
        children = {
            headerRow,
            progressBg,
            flavorLabel_,
            descLabel_,
            coeffLabel_,
            nextDescLabel_,
        },
    }

    -- ============================
    -- 主内容区：左右横排
    -- ============================
    local contentRow = UI.Panel {
        flexDirection = "row",
        width = "100%",
        height = "100%",
        alignItems = "center",
        children = { leftColumn, rightColumn },
    }

    -- ============================
    -- 底部操作栏（作为 Footer）
    -- ============================
    costLabel_ = UI.Label {
        text = "",
        fontSize = 21,
        fontColor = "#D4A574",
        flexGrow = 1,
        verticalAlign = "middle",
        height = 44,
    }

    upgradeBtn_ = UI.Panel {
        width = 160,
        height = 48,
        backgroundImage = "image/ui/btn_gold.png",
        backgroundSlice = { 12, 12, 12, 12 },
        justifyContent = "center",
        alignItems = "center",
        onClick = function() DoUpgrade() end,
        children = {
            UI.Label {
                id = "upgrade_btn_text",
                text = "升阶锻造",
                fontSize = 19,
                fontWeight = 700,
                fontColor = "#1A1A2E",
                textAlign = "center",
            },
        },
    }

    local footerRow = UI.Panel {
        flexDirection = "row",
        width = "100%",
        height = 56,
        alignItems = "center",
        justifyContent = "space-between",
        paddingLeft = 16,
        paddingRight = 16,
        children = { costLabel_, upgradeBtn_ },
    }

    -- ============================
    -- 自定义弹窗（支持九宫格背景图）
    -- ============================
    -- 标题行
    local titleRow = UI.Panel {
        width = "100%",
        height = 40,
        flexDirection = "row",
        alignItems = "center",
        justifyContent = "space-between",
        paddingLeft = 16,
        paddingRight = 16,
        children = {
            UI.Label { text = "设施升级", fontSize = 20, fontWeight = 700, fontColor = "#D4A574" },
            UI.Label {
                text = "x",
                fontSize = 20,
                fontColor = "#A0937D",
                onClick = function() UpgradePopup.Close() end,
            },
        },
    }

    -- 弹窗主体面板（九宫格背景）
    popupPanel_ = UI.Panel {
        width = "88%",
        height = "82%",
        backgroundImage = "image/ui/ui_slice_01.png",
        backgroundSlice = { 25, 25, 25, 25 },
        borderRadius = 0,
        flexDirection = "column",
        padding = 4,
        children = {
            titleRow,
            contentRow,
            footerRow,
        },
    }

    -- 全屏遮罩
    overlayPanel_ = UI.Panel {
        id = "upgrade_overlay",
        position = "absolute",
        left = 0, top = 0, right = 0, bottom = 0,
        backgroundColor = "rgba(0,0,0,0.6)",
        justifyContent = "center",
        alignItems = "center",
        visible = false,
        onClick = function() UpgradePopup.Close() end,
        children = { popupPanel_ },
    }

    -- 阻止点击弹窗本体时关闭
    popupPanel_.props.onClick = function() end

    -- 挂载到 UI 根
    local uiRoot = UI.GetRoot()
    if uiRoot then uiRoot:AddChild(overlayPanel_) end

    -- 模拟 Modal 接口
    modal_ = {
        Open = function()
            overlayPanel_.visible = true
        end,
        Close = function()
            overlayPanel_.visible = false
        end,
    }
end

-- ============================================================================
-- 公开接口
-- ============================================================================

--- 打开设施升级弹窗
---@param facilityId string 设施 ID（furnace/anvil/grinder/storage/display）
function UpgradePopup.Open(facilityId)
    EnsureModal()
    currentFacility_ = facilityId
    RefreshContent()
    modal_:Open()
end

--- 关闭弹窗
function UpgradePopup.Close()
    if modal_ then
        modal_:Close()
    end
end

return UpgradePopup
