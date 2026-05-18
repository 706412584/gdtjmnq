-- ============================================================================
-- QualityCalc - 品质评分引擎
-- Project Smith / P1-D5
--
-- 公式: FinalScore = BaseScore * MaterialCoeff * StepAvgCoeff * ToolCoeff
--                   * OrderMatchCoeff * BonusCoeff
--
-- 各系数范围:
--   BaseScore        100~230  (武器配方定义)
--   MaterialCoeff    0.8~1.5  (使用的材料等级)
--   StepAvgCoeff     0.75~1.15 (所有小游戏评分的均值系数)
--   ToolCoeff        1.0~1.3  (设施等级加成)
--   OrderMatchCoeff  0.9~1.1  (材料是否匹配订单要求)
--   BonusCoeff       1.0~1.2  (特殊条件加成)
-- ============================================================================

local QualityThreshold = require("Config.QualityThreshold")
local FacilityConfig   = require("Config.FacilityConfig")
local WeaponRecipes    = require("Config.WeaponRecipes")

local QualityCalc = {}

-- ============================================================================
-- 系数计算
-- ============================================================================

--- 材料等级系数
---@param usedTier number 实际使用材料等级 (1~5)
---@param requiredTier number 订单要求材料等级
---@return number 0.8 ~ 1.5
function QualityCalc.CalcMaterialCoeff(usedTier, requiredTier)
    local diff = usedTier - requiredTier
    -- 超出越多，系数越高
    if diff >= 2 then return 1.5
    elseif diff == 1 then return 1.3
    elseif diff == 0 then return 1.0
    elseif diff == -1 then return 0.9
    else return 0.8
    end
end

--- 步骤平均系数（由各小游戏精度计算）
---@param stepScores table[] { score:number(0~1), rating:string }
---@return number 加权平均系数
function QualityCalc.CalcStepAvgCoeff(stepScores)
    if #stepScores == 0 then
        return 0.75
    end

    local total = 0
    for i = 1, #stepScores do
        local coeff = QualityThreshold.GetStepCoefficient(stepScores[i].score)
        total = total + coeff
    end
    return total / #stepScores
end

--- 工具系数（多设施取平均）
---@param facilityLevels table { facilityId = level }
---@param relevantFacilities string[]|nil 参与计算的设施 ID 列表
---@return number
function QualityCalc.CalcToolCoeff(facilityLevels, relevantFacilities)
    if not relevantFacilities then
        -- 默认所有设施参与
        relevantFacilities = FacilityConfig.GetAllIds()
    end

    if #relevantFacilities == 0 then
        return 1.0
    end

    local total = 0
    for i = 1, #relevantFacilities do
        local id = relevantFacilities[i]
        local level = facilityLevels[id] or 1
        total = total + FacilityConfig.GetToolCoeff(id, level)
    end
    return total / #relevantFacilities
end

--- 订单匹配系数
---@param usedTier number 实际使用材料等级
---@param requiredTier number 订单要求材料等级
---@return number 0.9 ~ 1.1
function QualityCalc.CalcOrderMatchCoeff(usedTier, requiredTier)
    if usedTier >= requiredTier then
        return 1.1
    else
        return 0.9
    end
end

--- 加成系数
---@param isFirstForge boolean 是否首次锻造此武器
---@param consecutivePerfects number 连续完美次数
---@return number 1.0 ~ 1.2
function QualityCalc.CalcBonusCoeff(isFirstForge, consecutivePerfects)
    local bonus = 1.0
    if isFirstForge then
        bonus = bonus + 0.05
    end
    if consecutivePerfects >= 3 then
        bonus = bonus + 0.15
    elseif consecutivePerfects >= 2 then
        bonus = bonus + 0.10
    elseif consecutivePerfects >= 1 then
        bonus = bonus + 0.05
    end
    return math.min(bonus, 1.2)
end

-- ============================================================================
-- 综合计算
-- ============================================================================

--- 计算最终品质评分
---@param params table 计算参数
---   params.weaponId string         武器 ID
---   params.stepScores table[]      各步骤评分 { score, rating }
---   params.usedMaterialTier number 使用的材料等级
---   params.requiredMaterialTier number 订单要求材料等级
---   params.facilityLevels table    设施等级 { facilityId = level }
---   params.isFirstForge boolean    是否首次锻造
---   params.consecutivePerfects number 连续完美次数
---@return table { finalScore, qualityTier, rewards, breakdown }
function QualityCalc.Calculate(params)
    -- 获取武器基础分
    local recipe = WeaponRecipes.GetById(params.weaponId)
    local baseScore = recipe and recipe.baseScore or 100

    -- 计算各系数
    local materialCoeff = QualityCalc.CalcMaterialCoeff(
        params.usedMaterialTier or 1,
        params.requiredMaterialTier or 1
    )

    local stepAvgCoeff = QualityCalc.CalcStepAvgCoeff(params.stepScores or {})

    local toolCoeff = QualityCalc.CalcToolCoeff(params.facilityLevels or {})

    local orderMatchCoeff = QualityCalc.CalcOrderMatchCoeff(
        params.usedMaterialTier or 1,
        params.requiredMaterialTier or 1
    )

    local bonusCoeff = QualityCalc.CalcBonusCoeff(
        params.isFirstForge or false,
        params.consecutivePerfects or 0
    )

    -- 最终评分
    local finalScore = baseScore * materialCoeff * stepAvgCoeff * toolCoeff
                     * orderMatchCoeff * bonusCoeff
    finalScore = math.floor(finalScore + 0.5)  -- 四舍五入

    -- 查表获取品质等级
    local qualityTier = QualityThreshold.GetTierByScore(finalScore)
    local rewardMultiplier = qualityTier.rewardMultiplier

    return {
        finalScore = finalScore,
        qualityTier = qualityTier,
        rewardMultiplier = rewardMultiplier,
        breakdown = {
            baseScore = baseScore,
            materialCoeff = materialCoeff,
            stepAvgCoeff = stepAvgCoeff,
            toolCoeff = toolCoeff,
            orderMatchCoeff = orderMatchCoeff,
            bonusCoeff = bonusCoeff,
        },
    }
end

return QualityCalc
