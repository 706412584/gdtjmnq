-- ============================================================================
-- OrderConfig - 订单配置数据接口
-- Project Smith / P1-B5
--
-- 提供订单模板的查询接口，数据来源于 order_templates.json。
-- ============================================================================

local DataLoader = require("Config.DataLoader")

local OrderConfig = {}

local DATA_PATH = "Config/data/order_templates.json"

---@type table[]|nil
local orders_ = nil

--- 确保数据已加载
local function EnsureLoaded()
    if not orders_ then
        orders_ = DataLoader.Load(DATA_PATH)
        if not orders_ then
            orders_ = {}
            print("[OrderConfig] WARNING: Failed to load " .. DATA_PATH)
        end
    end
end

--- 获取全部订单模板
---@return table[]
function OrderConfig.GetAll()
    EnsureLoaded()
    return orders_
end

--- 按 ID 查找订单模板
---@param id string 订单 ID（如 "ORD_T1_001"）
---@return table|nil
function OrderConfig.GetById(id)
    EnsureLoaded()
    for i = 1, #orders_ do
        if orders_[i].id == id then
            return orders_[i]
        end
    end
    return nil
end

--- 按 Tier 查找订单模板
---@param tier number 订单等级（1, 2, 3...）
---@return table[]
function OrderConfig.GetByTier(tier)
    EnsureLoaded()
    local result = {}
    for i = 1, #orders_ do
        if orders_[i].tier == tier then
            result[#result + 1] = orders_[i]
        end
    end
    return result
end

--- 按章节查找可用订单模板
---@param chapter number 当前章节
---@return table[]
function OrderConfig.GetByChapter(chapter)
    EnsureLoaded()
    local result = {}
    for i = 1, #orders_ do
        if orders_[i].chapter <= chapter then
            result[#result + 1] = orders_[i]
        end
    end
    return result
end

--- 获取可用订单（未完成 + 当前章节可用）
---@param chapter number 当前章节
---@param completedIds string[] 已完成订单 ID 列表
---@return table[]
function OrderConfig.GetAvailable(chapter, completedIds)
    EnsureLoaded()

    -- 构建已完成 set
    local completedSet = {}
    for i = 1, #completedIds do
        completedSet[completedIds[i]] = true
    end

    local result = {}
    for i = 1, #orders_ do
        local order = orders_[i]
        if order.chapter <= chapter and not completedSet[order.id] then
            result[#result + 1] = order
        end
    end
    return result
end

--- 获取订单的基础奖励信息
---@param orderId string 订单 ID
---@return table|nil { coins, fame, bonusMaterials }
function OrderConfig.GetRewards(orderId)
    local order = OrderConfig.GetById(orderId)
    if not order then return nil end
    return {
        coins = order.baseRewardCoins,
        fame = order.baseRewardFame,
        bonusMaterials = order.bonusMaterials,
    }
end

return OrderConfig
