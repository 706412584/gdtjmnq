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
local StoryManager       = require("Story.StoryManager")

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
    pattern_gold  = "纹金",
    meteorite     = "陨铁",
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

local DAILY_ORDER_COUNT = 3

local function GetDailyOrderById(orderId)
    local dailyData = GameState.GetDailyOrders()
    for i = 1, #(dailyData.orders or {}) do
        local order = dailyData.orders[i]
        if order.id == orderId then
            return order
        end
    end
    return nil
end

local function ResolveOrder(orderId)
    return OrderConfig.GetById(orderId) or GetDailyOrderById(orderId)
end

local function RefreshDailyOrders(chapter)
    local today = os.date("!%Y-%m-%d")
    local dailyData = GameState.GetDailyOrders()
    if dailyData.dayKey == today and #(dailyData.orders or {}) > 0 then
        return dailyData.orders
    end

    local candidates = OrderConfig.GetDailyCandidates(chapter)
    local orders = {}
    while #candidates > 0 and #orders < DAILY_ORDER_COUNT do
        local index = math.random(1, #candidates)
        local source = table.remove(candidates, index)
        orders[#orders + 1] = {
            id = "DAILY_" .. today .. "_" .. #orders + 1,
            templateId = source.id,
            isDaily = true,
            tier = source.tier,
            chapter = source.chapter,
            customerName = source.customerName,
            customerType = source.customerType,
            weaponId = source.weaponId,
            dialogue = source.dialogue,
            requiredMaterialTier = source.requiredMaterialTier,
            baseRewardCoins = math.floor(source.baseRewardCoins * 0.75),
            baseRewardFame = math.max(1, math.floor(source.baseRewardFame * 0.75)),
            bonusMaterials = source.bonusMaterials,
        }
    end
    GameState.SetDailyOrders({ dayKey = today, orders = orders })
    print("[OrderManager] Daily orders refreshed: " .. #orders)
    return orders
end

local function EnsureActiveOrderLoaded()
    if activeOrder_ then return activeOrder_ end

    local snapshot = GameState.GetActiveOrder()
    if not snapshot or not snapshot.orderId then return nil end

    local order = ResolveOrder(snapshot.orderId)
    if not order then
        print("[OrderManager] Discarding invalid active order snapshot: " .. tostring(snapshot.orderId))
        GameState.ClearActiveOrder()
        return nil
    end

    local recipe = WeaponRecipes.GetById(order.weaponId)
    if not recipe then
        print("[OrderManager] Discarding active order without recipe: " .. tostring(snapshot.orderId))
        GameState.ClearActiveOrder()
        return nil
    end

    activeOrder_ = {
        orderId = snapshot.orderId,
        template = order,
        recipe = recipe,
        startTime = snapshot.acceptedAt or os.time(),
        modifier = snapshot.modifier,
        consumedMaterials = snapshot.consumedMaterials or recipe.requiredMaterials,
        materialTier = snapshot.materialTier or 1,
        retryUsed = snapshot.retryUsed == true,
        stepScores = snapshot.stepScores or {},
    }
    print("[OrderManager] Restored active order: " .. snapshot.orderId
        .. " (completed steps=" .. #activeOrder_.stepScores .. ")")
    return activeOrder_
end

local function SaveActiveOrderSnapshot()
    if not activeOrder_ then return end
    GameState.SetActiveOrder({
        orderId = activeOrder_.orderId,
        acceptedAt = activeOrder_.startTime,
        modifier = activeOrder_.modifier,
        consumedMaterials = activeOrder_.consumedMaterials,
        materialTier = activeOrder_.materialTier,
        retryUsed = activeOrder_.retryUsed == true,
        stepScores = activeOrder_.stepScores or {},
        status = "forging",
    })
    GameState.ForceSave()
end

-- ============================================================================
-- 订单查询
-- ============================================================================

--- 获取当前可接取的订单列表
---@return table[]
function OrderManager.GetAvailableOrders()
    local progress = GameState.GetStoryProgress()
    local chapter = progress and progress.chapter or 1
    local completed = GameState.GetCompletedOrders()
    local permanentOrders = OrderConfig.GetAvailable(chapter, completed)
    local completedSet = {}
    for i = 1, #completed do
        completedSet[completed[i]] = true
    end
    local dailyOrders = RefreshDailyOrders(chapter)
    for i = 1, #dailyOrders do
        if not completedSet[dailyOrders[i].id] then
            permanentOrders[#permanentOrders + 1] = dailyOrders[i]
        end
    end

    local pendingStoryOrder = GameState.GetPendingStoryOrder()
    if pendingStoryOrder and pendingStoryOrder.required and not pendingStoryOrder.completed then
        local requiredOrders = {}
        for i = 1, #permanentOrders do
            if permanentOrders[i].id == pendingStoryOrder.orderId then
                requiredOrders[#requiredOrders + 1] = permanentOrders[i]
                break
            end
        end
        return requiredOrders
    end

    return permanentOrders
end

--- 获取当前活跃订单
---@return table|nil
function OrderManager.GetActiveOrder()
    return EnsureActiveOrderLoaded()
end

--- 是否有活跃订单
---@return boolean
function OrderManager.HasActiveOrder()
    return EnsureActiveOrderLoaded() ~= nil
end

-- ============================================================================
-- 接单流程
-- ============================================================================

--- 接受一个订单
---@param orderId string 订单 ID
---@param materialTier number|nil 使用的同阶材料等级，未传时自动选择最低可用等级
---@return boolean success
---@return string|nil errorMsg
function OrderManager.AcceptOrder(orderId, materialTier)
    if EnsureActiveOrderLoaded() then
        return false, "已有进行中的订单"
    end

    local order = ResolveOrder(orderId)
    if not order then
        return false, "订单不存在: " .. orderId
    end

    local availableOrders = OrderManager.GetAvailableOrders()
    local isAvailable = false
    for i = 1, #availableOrders do
        if availableOrders[i].id == orderId then
            isAvailable = true
            break
        end
    end
    if not isAvailable then
        return false, "该订单当前不可接取"
    end

    local recipe = WeaponRecipes.GetById(order.weaponId)
    if not recipe then
        return false, "武器配方不存在: " .. order.weaponId
    end

    local availableTiers = GameState.GetAvailableMaterialTiers(recipe.requiredMaterials)
    if #availableTiers == 0 then
        for mat, count in pairs(recipe.requiredMaterials) do
            local name = MATERIAL_NAMES[mat] or mat
            local have = GameState.GetMaterial(mat) or 0
            if have < count then
                return false, name .. "不足 (需" .. count .. "/有" .. have .. ")"
            end
        end
        return false, "没有可用的同品质材料组合"
    end

    materialTier = math.floor(materialTier or availableTiers[1])
    if not GameState.GetMaterialTier or not GameState.CanAffordMaterialTier then
        return false, "材料品质数据不可用"
    end
    local canUseTier = false
    for i = 1, #availableTiers do
        if availableTiers[i] == materialTier then
            canUseTier = true
            break
        end
    end
    if not canUseTier then
        return false, "所选品质材料不足"
    end

    -- 按所选品质扣除材料
    for mat, count in pairs(recipe.requiredMaterials) do
        GameState.AddMaterialTier(mat, materialTier, -count)
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
        consumedMaterials = recipe.requiredMaterials,
        materialTier = materialTier,
        retryUsed = false,
        stepScores = {},
    }
    SaveActiveOrderSnapshot()

    EventBus.Emit("order_accepted", {
        orderId = orderId,
        weaponLine = recipe.line,
        steps = recipe.steps,
        modifier = modifier,
    })

    print("[OrderManager] Order accepted: " .. orderId .. " (" .. recipe.name .. ")")
    return true
end

--- 记录已完成工序，确保意外退出后从下一道工序恢复。
---@param stepScores table[]
function OrderManager.UpdateActiveOrderProgress(stepScores)
    local activeOrder = EnsureActiveOrderLoaded()
    if not activeOrder then return end
    activeOrder.stepScores = stepScores or {}
    SaveActiveOrderSnapshot()
end

---@return boolean
function OrderManager.HasUsedFreeRetry()
    local activeOrder = EnsureActiveOrderLoaded()
    return activeOrder and activeOrder.retryUsed == true or false
end

function OrderManager.UseFreeRetry()
    local activeOrder = EnsureActiveOrderLoaded()
    if not activeOrder or activeOrder.retryUsed then return false end
    activeOrder.retryUsed = true
    SaveActiveOrderSnapshot()
    return true
end

--- 取消当前订单，仅返还已消耗材料的 40%。
function OrderManager.CancelOrder()
    local activeOrder = EnsureActiveOrderLoaded()
    if not activeOrder then return end

    local materialTier = activeOrder.materialTier or 1
    local consumedMaterials = activeOrder.consumedMaterials or {}
    for mat, count in pairs(consumedMaterials) do
        local refund = math.floor(count * 0.4)
        if refund > 0 then
            GameState.AddMaterialTier(mat, materialTier, refund)
        end
    end

    local cancelledId = activeOrder.orderId

    -- 取消订单重置连单计数
    ChallengeModifier.ResetChain()

    activeOrder_ = nil
    GameState.ClearActiveOrder()
    GameState.ForceSave()

    EventBus.Emit("order_cancelled", { orderId = cancelledId })
    print("[OrderManager] Order cancelled: " .. cancelledId .. " (40% material refund)")
end

-- ============================================================================
-- 完单 / 结算
-- ============================================================================

--- 完成当前订单并计算奖励
---@param stepScores table[] 各步骤评分 { score, rating }
---@return table|nil result 结算结果
function OrderManager.CompleteOrder(stepScores)
    if not EnsureActiveOrderLoaded() then
        print("[OrderManager] ERROR: No active order to complete")
        return nil
    end

    local order = activeOrder_.template
    local recipe = activeOrder_.recipe
    stepScores = stepScores or {}
    if #stepScores ~= #(recipe.steps or {}) then
        print("[OrderManager] ERROR: Incomplete step scores for order: " .. order.id)
        return nil
    end
    for i = 1, #stepScores do
        if type(stepScores[i]) ~= "table" or type(stepScores[i].score) ~= "number" then
            print("[OrderManager] ERROR: Invalid step score at index " .. i)
            return nil
        end
    end

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
        usedMaterialTier = activeOrder_.materialTier or 1,
        requiredMaterialTier = order.requiredMaterialTier,
        facilityLevels = facilityLevels,
        isFirstForge = isFirstForge,
        consecutivePerfects = consecutivePerfects,
    })

    -- 计算奖励（含挑战修饰符加成）
    local modifier = activeOrder_.modifier
    local modifierBonus = ChallengeModifier.GetRewardBonus(modifier)
    local displayLevel = GameState.GetFacilityLevel("display")
    local displayBonus = FacilityConfig.GetToolCoeff("display", displayLevel) - 1
    local rewardMultiplier = qualityResult.rewardMultiplier * (1 + modifierBonus) * (1 + displayBonus)
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
    local completedStoryOrder = StoryManager.MarkStoryOrderCompleted(order.id)

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
    GameState.ClearActiveOrder()
    GameState.ForceSave()

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
