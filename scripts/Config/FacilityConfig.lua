-- ============================================================================
-- FacilityConfig - 设施升级数据接口
-- Project Smith / P1-B5
--
-- 提供设施信息、升级费用、工具系数的查询接口，数据来源于 facility_upgrades.json。
-- ============================================================================

local DataLoader = require("Config.DataLoader")

local FacilityConfig = {}

local DATA_PATH = "Config/data/facility_upgrades.json"

---@type table|nil
local data_ = nil

--- 确保数据已加载
local function EnsureLoaded()
    if not data_ then
        data_ = DataLoader.Load(DATA_PATH)
        if not data_ then
            data_ = { facilities = {} }
            print("[FacilityConfig] WARNING: Failed to load " .. DATA_PATH)
        end
    end
end

--- 获取全部设施 ID 列表
---@return string[]
function FacilityConfig.GetAllIds()
    EnsureLoaded()
    local ids = {}
    for id, _ in pairs(data_.facilities) do
        ids[#ids + 1] = id
    end
    return ids
end

--- 获取设施基础信息
---@param facilityId string 设施 ID（如 "furnace"）
---@return table|nil { name, description, levels[] }
function FacilityConfig.GetFacility(facilityId)
    EnsureLoaded()
    return data_.facilities[facilityId]
end

--- 获取设施名称
---@param facilityId string 设施 ID
---@return string
function FacilityConfig.GetName(facilityId)
    local facility = FacilityConfig.GetFacility(facilityId)
    if facility then
        return facility.name
    end
    return facilityId
end

--- 获取指定等级的设施数据
---@param facilityId string 设施 ID
---@param level number 设施等级（1, 2, 3...）
---@return table|nil { level, toolCoeff, upgradeCost, upgradeFameCost, unlockChapter, desc }
function FacilityConfig.GetLevel(facilityId, level)
    local facility = FacilityConfig.GetFacility(facilityId)
    if not facility then return nil end

    local levels = facility.levels
    for i = 1, #levels do
        if levels[i].level == level then
            return levels[i]
        end
    end
    return nil
end

--- 获取设施当前等级的工具系数
---@param facilityId string 设施 ID
---@param level number 当前等级
---@return number 工具系数（默认 1.0）
function FacilityConfig.GetToolCoeff(facilityId, level)
    local levelData = FacilityConfig.GetLevel(facilityId, level)
    if levelData then
        return levelData.toolCoeff
    end
    return 1.0
end

--- 获取下一级升级费用
---@param facilityId string 设施 ID
---@param currentLevel number 当前等级
---@return table|nil { coins, fame } 升级费用，无下一级返回 nil
function FacilityConfig.GetUpgradeCost(facilityId, currentLevel)
    local nextLevel = FacilityConfig.GetLevel(facilityId, currentLevel + 1)
    if not nextLevel then
        return nil  -- 已满级
    end
    return {
        coins = nextLevel.upgradeCost,
        fame = nextLevel.upgradeFameCost,
    }
end

--- 获取设施最大等级
---@param facilityId string 设施 ID
---@return number 最大等级
function FacilityConfig.GetMaxLevel(facilityId)
    local facility = FacilityConfig.GetFacility(facilityId)
    if not facility then return 1 end
    return #facility.levels
end

--- 检查设施是否已满级
---@param facilityId string 设施 ID
---@param currentLevel number 当前等级
---@return boolean
function FacilityConfig.IsMaxLevel(facilityId, currentLevel)
    return currentLevel >= FacilityConfig.GetMaxLevel(facilityId)
end

--- 获取等级描述文本
---@param facilityId string 设施 ID
---@param level number 等级
---@return string
function FacilityConfig.GetLevelDesc(facilityId, level)
    local levelData = FacilityConfig.GetLevel(facilityId, level)
    if levelData then
        return levelData.desc
    end
    return ""
end

return FacilityConfig
