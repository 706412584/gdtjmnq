-- ============================================================================
-- QualityThreshold - 品质阈值数据接口
-- Project Smith / P1-B5
--
-- 提供品质等级和步骤评分的查询接口，数据来源于 quality_thresholds.json。
-- ============================================================================

local DataLoader = require("Config.DataLoader")

local QualityThreshold = {}

local DATA_PATH = "Config/data/quality_thresholds.json"

---@type table|nil
local data_ = nil

--- 确保数据已加载
local function EnsureLoaded()
    if not data_ then
        data_ = DataLoader.Load(DATA_PATH)
        if not data_ then
            data_ = { tiers = {}, stepRatings = {} }
            print("[QualityThreshold] WARNING: Failed to load " .. DATA_PATH)
        end
    end
end

--- 获取全部品质等级定义
---@return table[] 品质等级列表（从低到高）
function QualityThreshold.GetAllTiers()
    EnsureLoaded()
    return data_.tiers
end

--- 根据最终评分获取品质等级
---@param score number 最终评分
---@return table { name, minScore, maxScore, rewardMultiplier, tier }
function QualityThreshold.GetTierByScore(score)
    EnsureLoaded()
    local tiers = data_.tiers
    -- 从高到低匹配（优先返回更高品质）
    for i = #tiers, 1, -1 do
        if score >= tiers[i].minScore then
            return tiers[i]
        end
    end
    -- 兜底：返回最低品质
    return tiers[1]
end

--- 获取全部步骤评分定义
---@return table[] 步骤评分列表
function QualityThreshold.GetAllStepRatings()
    EnsureLoaded()
    return data_.stepRatings
end

--- 根据精度获取步骤评分等级
---@param accuracy number 精度值（0.0 ~ 1.0）
---@return table { name, coefficient, minAccuracy }
function QualityThreshold.GetStepRating(accuracy)
    EnsureLoaded()
    local ratings = data_.stepRatings
    -- 从高到低匹配（精度越高评级越好）
    for i = 1, #ratings do
        if accuracy >= ratings[i].minAccuracy then
            return ratings[i]
        end
    end
    -- 兜底：返回最低评分
    return ratings[#ratings]
end

--- 获取品质等级的奖励倍率
---@param score number 最终评分
---@return number 奖励倍率
function QualityThreshold.GetRewardMultiplier(score)
    local tier = QualityThreshold.GetTierByScore(score)
    return tier.rewardMultiplier
end

--- 获取步骤评分系数
---@param accuracy number 精度值（0.0 ~ 1.0）
---@return number 评分系数
function QualityThreshold.GetStepCoefficient(accuracy)
    local rating = QualityThreshold.GetStepRating(accuracy)
    return rating.coefficient
end

return QualityThreshold
