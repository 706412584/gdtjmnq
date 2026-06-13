---@diagnostic disable: param-type-mismatch
-- ============================================================================
-- UpgradePopup - 设施升级弹窗
-- Project Smith
--
-- 点击主界面设施卡片后弹出，展示该设施的升级信息和操作按钮。
-- 使用 UI.Modal 组件，Open() 后自动挂载到 UI root。
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

---@type Modal|nil
local modal_ = nil
---@type string|nil
local currentFacility_ = nil

-- 内容元素引用
local nameLabel_   = nil
local levelLabel_  = nil
local descLabel_   = nil
local coeffLabel_  = nil
local costLabel_   = nil
local upgradeBtn_  = nil
local progressBar_ = nil
local imgPanel_    = nil

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
    if levelLabel_ then levelLabel_.text = "等阶 Lv." .. level .. " / " .. maxLevel end
    if descLabel_ then descLabel_.text = desc end
    if coeffLabel_ then coeffLabel_.text = "工具系数 x" .. string.format("%.2f", coeff) end

    -- 进度条
    if progressBar_ then
        local pct = math.floor(level / maxLevel * 100)
        progressBar_.width = pct .. "%"
    end

    -- 图片
    if imgPanel_ then
        local img = FACILITY_IMAGES[facilityId]
        if img then
            imgPanel_.backgroundImage = img
            imgPanel_.backgroundFit = "contain"
        end
    end

    -- 升级按钮
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
                costLabel_.text = "升级需要 " .. cost.coins .. " 铜钱"
                costLabel_.fontColor = canAfford and "#D4A574" or "#E94560"
            end
            if upgradeBtn_ then
                upgradeBtn_:SetDisabled(not canAfford)
                upgradeBtn_:SetText(canAfford and "升阶" or "铜钱不足")
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
    UI.Toast.Show(FacilityConfig.GetName(facilityId) .. " 升至 Lv." .. (level + 1), { type = "success" })

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

    -- 设施图片区
    imgPanel_ = UI.Panel {
        width = 120, height = 120,
        alignSelf = "center",
        borderRadius = 8,
        backgroundColor = "rgba(26,26,46,0.6)",
        marginBottom = 12,
    }

    -- 名称
    nameLabel_ = UI.Label {
        text = "",
        fontSize = 20,
        fontColor = "#E8E0D0",
        textAlign = "center",
        width = "100%",
        marginBottom = 4,
    }

    -- 等级
    levelLabel_ = UI.Label {
        text = "",
        fontSize = 14,
        fontColor = "#A0937D",
        textAlign = "center",
        width = "100%",
        marginBottom = 12,
    }

    -- 进度条背景
    progressBar_ = UI.Panel {
        width = "0%",
        height = "100%",
        backgroundColor = "#C9A45A",
        borderRadius = 3,
    }

    local progressBg = UI.Panel {
        width = "100%", height = 6,
        backgroundColor = "#3A322B",
        borderRadius = 3,
        marginBottom = 16,
        children = { progressBar_ },
    }

    -- 描述
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
        width = "100%",
        marginBottom = 16,
    }

    -- 费用
    costLabel_ = UI.Label {
        text = "",
        fontSize = 14,
        fontColor = "#D4A574",
        textAlign = "center",
        width = "100%",
        marginBottom = 12,
    }

    -- 升级按钮
    upgradeBtn_ = UI.Button {
        text = "升阶",
        variant = "primary",
        width = "100%",
        height = 44,
        onClick = function()
            DoUpgrade()
        end,
    }

    -- 创建 Modal
    modal_ = UI.Modal {
        title = "设施升级",
        size = "sm",
        showCloseButton = true,
        closeOnOverlay = true,
    }

    -- 添加内容
    modal_:AddContent(imgPanel_)
    modal_:AddContent(nameLabel_)
    modal_:AddContent(levelLabel_)
    modal_:AddContent(progressBg)
    modal_:AddContent(descLabel_)
    modal_:AddContent(coeffLabel_)
    modal_:AddContent(costLabel_)
    modal_:AddContent(upgradeBtn_)
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
