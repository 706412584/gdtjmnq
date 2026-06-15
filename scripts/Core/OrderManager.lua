-- ============================================================================
-- OrderManager - 订单管理器
-- Project Smith / P1-D6
--
-- 负责:
--   1. 根据玩家进度生成可接取的订单列表
--   2. 接单/完单流程控制
--   3. 奖励计算与发放（结合 QualityCalc）
--   4. 通过 EventBus 通知外部系统
-- ============================================================================

local EventBus           = require("Core.EventBus")
local GameState          = require("Core.GameState")
local OrderConfig        = require("Config.OrderConfig")
local WeaponRecipes      = require("Config.WeaponRecipes")
local FacilityConfig     = require("Config.FacilityConfig")
local QualityCalc        = require("Core.QualityCalc")
local ChallengeModifier  = require("Core.ChallengeModifier")

local OrderManager = {}

-- 材料中文名称映射
local MATERIAL_NAMES = {
    ore           = "矿石",
    charcoal      = "木炭",
    grinding_agent = "研磨剂",
    wood          = "木材",
    leather       = "皮革",
    iron          = "铁锭",
    steel         = "钢材",
    jade_dust     = "玉粉",
}

--- 获取材料中文名
---@param key string
---@return string
function OrderManager.GetMaterialName(key)
    return MATERIAL_NAMES[key] or key
end

-- 当前正在执行的订单
---@type table|nil
local activeOrder_ = nil

-- ============================================================================
-- 订单查询
-- ============================================================================

--- 获取当前可接取的订单列表
---@return table[]
function OrderManager.GetAvailableOrders()
    local progress = GameState.GetStoryProgress()
    local chapter = progress and progress.chapter or 1
    local completed = GameState.GetCompletedOrders()
    return OrderConfig.GetAvailable(chapter, completed)
end

--- 获取当前活跃订单
---@return table|nil
function OrderManager.GetActiveOrder()
    return activeOrder_
end

--- 是否有活跃订单
---@return boolean
function OrderManager.HasActiveOrder()
    return activeOrder_ ~= nil
end

-- ============================================================================
-- 接单流程
-- ============================================================================

--- 接受一个订单
---@param orderId string 订单 ID
---@return boolean success
---@return string|nil errorMsg
function OrderManager.AcceptOrder(orderId)
    if activeOrder_ then
        return false, "已有进行中的订单"
    end

    local order = OrderConfig.GetById(orderId)
    if not order then
        return false, "订单不存在: " .. orderId
    end

    -- 检查材料是否足够
    local recipe = WeaponRecipes.GetById(order.weaponId)
    if not recipe then
        return false, "武器配方不存在: " .. order.weaponId
    end

    for mat, count in pairs(recipe.requiredMaterials) do
        if not GameState.CanAffordMaterial(mat, count) then
            local name = MATERIAL_NAMES[mat] or mat
            local have = GameState.GetMaterial(mat) or 0
            return false, name .. "不足 (需" .. count .. "/有" .. have .. ")"
        end
    end

    -- 扣除材料
    for mat, count in pairs(recipe.requiredMaterials) do
        GameState.AddMaterial(mat, -count)
    end

    -- Roll 挑战修饰符
    local progress = GameState.GetStoryProgress()
    local chapter = progress and progress.chapter or 1
    local modifier = ChallengeModifier.Roll(chapter, order.tier or 1)

    -- 材料限制修饰符：降低可用材料等级
    if modifier and modifier.id == "material_cap" then
        -- 效果在小游戏中体现，此处仅记录
        print("[OrderManager] Modifier material_cap active: tier reduction = " .. (modifier.params.tierReduction or 1))
    end

    -- 设为活跃订单
    activeOrder_ = {
        orderId = orderId,
        template = order,
        recipe = recipe,
        startTime = os.time(),
        modifier = modifier,
    }

    EventBus.Emit("order_accepted", {
        orderId = orderId,
        weaponLine = recipe.line,
        steps = recipe.steps,
        modifier = modifier,
    })

    print("[OrderManager] Order accepted: " .. orderId .. " (" .. recipe.name .. ")")
    return true
end

--- 取消当前订单（退还材料）
function OrderManager.CancelOrder()
    if not activeOrder_ then return end

    -- 退还材料
    local recipe = activeOrder_.recipe
    if recipe and recipe.requiredMaterials then
        for mat, count in pairs(recipe.requiredMaterials) do
            GameState.AddMaterial(mat, count)
        end
    end

    local cancelledId = activeOrder_.orderId

    -- 取消订单重置连单计数
    ChallengeModifier.ResetChain()

    activeOrder_ = nil

    EventBus.Emit("order_cancelled", { orderId = cancelledId })
    print("[OrderManager] Order cancelled: " .. cancelledId)
end

-- ============================================================================
-- 完单 / 结算
-- ============================================================================

--- 完成当前订单并计算奖励
---@param stepScores table[] 各步骤评分 { score, rating }
---@param usedMaterialTier number 使用的材料等级
---@return table|nil result 结算结果
function OrderManager.CompleteOrder(stepScores, usedMaterialTier)
    if not activeOrder_ then
        print("[OrderManager] ERROR: No active order to complete")
        return nil
    end

    local order = activeOrder_.template
    local recipe = activeOrder_.recipe

    -- 收集设施等级
    local facilityLevels = {}
    local allFacilityIds = FacilityConfig.GetAllIds()
    for i = 1, #allFacilityIds do
        local id = allFacilityIds[i]
        facilityLevels[id] = GameState.GetFacilityLevel(id)
    end

    -- 判断是否首次锻造
    local codex = GameState.GetCodex()
    local isFirstForge = true
    for i = 1, #codex do
        if codex[i] == recipe.id then
            isFirstForge = false
            break
        end
    end

    -- 计算连续完美次数
    local consecutivePerfects = 0
    for i = #stepScores, 1, -1 do
        if stepScores[i].rating == "Perfect" then
            consecutivePerfects = consecutivePerfects + 1
        else
            break
        end
    end

    -- 品质评分
    local qualityResult = QualityCalc.Calculate({
        weaponId = recipe.id,
        stepScores = stepScores,
        usedMaterialTier = usedMaterialTier or order.requiredMaterialTier,
        requiredMaterialTier = order.requiredMaterialTier,
        facilityLevels = facilityLevels,
        isFirstForge = isFirstForge,
        consecutivePerfects = consecutivePerfects,
    })

    -- 计算奖励（含挑战修饰符加成）
    local modifier = activeOrder_.modifier
    local modifierBonus = ChallengeModifier.GetRewardBonus(modifier)
    local rewardMultiplier = qualityResult.rewardMultiplier * (1 + modifierBonus)
    local rewardCoins = math.floor(order.baseRewardCoins * rewardMultiplier + 0.5)
    local rewardFame = math.floor(order.baseRewardFame * rewardMultiplier + 0.5)
    local bonusMaterials = order.bonusMaterials or {}

    -- 连单修饰符：成功完成则递增计数
    if modifier and modifier.id == "chain_order" then
        ChallengeModifier.IncrementChain()
    end

    -- 发放奖励
    GameState.AddCoins(rewardCoins)
    GameState.AddFame(rewardFame)
    for mat, count in pairs(bonusMaterials) do
        GameState.AddMaterial(mat, count)
    end

    -- 记录完成
    GameState.CompleteOrder(order.id)

    -- 更新图鉴
    if isFirstForge then
        GameState.UnlockCodex(recipe.id)
    end

    -- 更新统计
    GameState.AddStat("totalForged", 1)
    local allPerfect = true
    for i = 1, #stepScores do
        if stepScores[i].rating ~= "Perfect" then
            allPerfect = false
            break
        end
    end
    if allPerfect then
        GameState.AddStat("perfectCount", 1)
    end
    local bestTier = GameState.GetStat("bestQualityTier")
    if qualityResult.qualityTier.tier > bestTier then
        GameState.AddStat("bestQualityTier", qualityResult.qualityTier.tier - bestTier)
    end

    -- 构建结算结果
    local result = {
        orderId = order.id,
        weaponId = recipe.id,
        weaponName = recipe.name,
        finalScore = qualityResult.finalScore,
        qualityTier = qualityResult.qualityTier,
        rewardCoins = rewardCoins,
        rewardFame = rewardFame,
        bonusMaterials = bonusMaterials,
        isFirstForge = isFirstForge,
        breakdown = qualityResult.breakdown,
        stepScores = stepScores,
        modifier = modifier,
        modifierBonus = modifierBonus,
    }

    -- 发送事件
    EventBus.Emit("quality_calculated", {
        finalScore = qualityResult.finalScore,
        qualityTier = qualityResult.qualityTier,
        rewards = {
            coins = rewardCoins,
            fame = rewardFame,
            materials = bonusMaterials,
        },
    })

    EventBus.Emit("reward_collected", {
        coins = rewardCoins,
        fame = rewardFame,
        materials = bonusMaterials,
        codexId = isFirstForge and recipe.id or nil,
        weaponLine = recipe.line,
    })

    -- 挑战修饰符完成事件（每周目标追踪用）
    if modifier then
        EventBus.Emit("order_completed_with_modifier", {
            orderId = order.id,
            modifierId = modifier.id,
            modifierName = modifier.name,
        })
    end

    -- 清理活跃订单
    activeOrder_ = nil

    print("[OrderManager] Order completed: " .. order.id
        .. " | Quality: " .. qualityResult.qualityTier.name
        .. " (" .. qualityResult.finalScore .. ")"
        .. " | Reward: " .. rewardCoins .. " coins, " .. rewardFame .. " fame")

    return result
end

-- ============================================================================
-- 设施升级
-- ============================================================================

--- 升级设施
---@param facilityId string 设施 ID
---@return boolean success
---@return string|nil errorMsg
function OrderManager.UpgradeFacility(facilityId)
    local currentLevel = GameState.GetFacilityLevel(facilityId)

    -- 检查是否满级
    if FacilityConfig.IsMaxLevel(facilityId, currentLevel) then
        return false, "已达最高等级"
    end

    -- 获取升级费用
    local cost = FacilityConfig.GetUpgradeCost(facilityId, currentLevel)
    if not cost then
        return false, "无升级数据"
    end

    -- 检查铜钱
    if not GameState.CanAffordCoins(cost.coins) then
        return false, "铜钱不足（需要 " .. cost.coins .. "）"
    end

    -- 检查声望
    if GameState.GetFame() < cost.fame then
        return false, "声望不足（需要 " .. cost.fame .. "）"
    end

    -- 扣费
    GameState.AddCoins(-cost.coins)
    GameState.AddFame(-cost.fame)

    -- 升级
    local newLevel = currentLevel + 1
    GameState.SetFacilityLevel(facilityId, newLevel)

    local facilityName = FacilityConfig.GetName(facilityId)
    local levelDesc = FacilityConfig.GetLevelDesc(facilityId, newLevel)

    EventBus.Emit("facility_upgraded", {
        facilityId = facilityId,
        newLevel = newLevel,
        name = facilityName,
        desc = levelDesc,
    })

    print("[OrderManager] Facility upgraded: " .. facilityName
        .. " -> Lv" .. newLevel .. " (" .. levelDesc .. ")")

    return true
end

return OrderManager
