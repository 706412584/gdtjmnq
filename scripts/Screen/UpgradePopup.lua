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

---@type Modal|nil
local modal_ = nil
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
            local canAfford = GameState.CanAffordCoins(cost.coins)
            if costLabel_ then
                costLabel_.text = "升级费用: " .. cost.coins .. " 铜钱"
                costLabel_.fontColor = canAfford and "#D4A574" or "#E94560"
            end
            if upgradeBtn_ then
                upgradeBtn_:SetDisabled(not canAfford)
                upgradeBtn_:SetText(canAfford and "升阶锻造" or "铜钱不足")
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
    local level = GameState.GetFacilityLevel(facilityId)
    if FacilityConfig.IsMaxLevel(facilityId, level) then return end

    local cost = FacilityConfig.GetUpgradeCost(facilityId, level)
    if not cost then return end

    if not GameState.CanAffordCoins(cost.coins) then
        UI.Toast.Show("铜钱不足")
        return
    end

    -- 扣除资源
    GameState.AddCoins(-cost.coins)
    if cost.fame and cost.fame > 0 then
        GameState.AddFame(-cost.fame)
    end

    -- 提升等级
    GameState.SetFacilityLevel(facilityId, level + 1)

    SFXManager.Play(SFXManager.SFX.UI_COIN, 0.5)
    UI.Toast.Show(FacilityConfig.GetName(facilityId) .. " 升至 Lv." .. (level + 1))

    -- 刷新弹窗内容
    RefreshContent()

    -- 通知主界面刷新
    EventBus.Emit("facility_upgraded", { facilityId = facilityId })
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
        backgroundColor = "rgba(26,26,46,0.5)",
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
        fontSize = 22,
        fontWeight = 700,
        fontColor = "#E8E0D0",
    }

    levelLabel_ = UI.Label {
        text = "",
        fontSize = 14,
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
        fontSize = 11,
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
        fontSize = 13,
        fontColor = "#A0937D",
        width = "100%",
        marginBottom = 10,
    }

    -- 当前状态
    descLabel_ = UI.Label {
        text = "",
        fontSize = 14,
        fontColor = "#E8E0D0",
        width = "100%",
        marginBottom = 4,
    }

    -- 工具系数
    coeffLabel_ = UI.Label {
        text = "",
        fontSize = 14,
        fontColor = "#D4A574",
        fontWeight = 700,
        width = "100%",
        marginBottom = 8,
    }

    -- 下一级预览
    nextDescLabel_ = UI.Label {
        text = "",
        fontSize = 13,
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
        fontSize = 16,
        fontColor = "#D4A574",
        flexGrow = 1,
        verticalAlign = "middle",
        height = 44,
    }

    upgradeBtn_ = UI.Button {
        text = "升阶锻造",
        variant = "primary",
        width = "35%",
        minWidth = 120,
        height = 44,
        onClick = function()
            DoUpgrade()
        end,
    }

    local footerRow = UI.Panel {
        flexDirection = "row",
        width = "100%",
        alignItems = "center",
        justifyContent = "space-between",
        children = { costLabel_, upgradeBtn_ },
    }

    -- ============================
    -- 创建 Modal
    -- ============================
    modal_ = UI.Modal {
        title = "设施升级",
        size = "fullscreen",
        showCloseButton = true,
        closeOnOverlay = true,
        contentPadding = { 20, 24, 16, 24 },
        contentGap = 0,
    }

    modal_:AddContent(contentRow)
    modal_:SetFooter(footerRow)
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
