-- ============================================================================
-- RelationshipTracker - 角色关系与阵营追踪
-- Project Smith / P2-B3
--
-- 职责：
--   1. 封装 GameState 的好感度/阵营读写
--   2. 提供阈值检查（解锁条件判定）
--   3. 提供综合评估（结局判定用）
-- ============================================================================

local GameState = require("Core.GameState")

local RelationshipTracker = {}

-- ============================================================================
-- 角色好感度阈值
-- ============================================================================

local CHARACTER_THRESHOLDS = {
    keeper = {
        { level = 1, min = 40, desc = "旧案线索" },
        { level = 2, min = 70, desc = "真传秘法" },
    },
    shen = {
        { level = 1, min = 30, desc = "暗线交易" },
        { level = 2, min = 65, desc = "商会同盟" },
    },
    luchen = {
        { level = 1, min = 30, desc = "江湖门路" },
        { level = 2, min = 70, desc = "复仇终章" },
    },
    magistrate = {
        { level = 1, min = 35, desc = "官府优先" },
        { level = 2, min = 70, desc = "权势通道" },
    },
    disciple = {
        { level = 1, min = 20, desc = "旧事重提" },
        { level = 2, min = 60, desc = "回归之路" },
    },
}

-- ============================================================================
-- 阵营配置
-- ============================================================================

local FACTION_IDS = { "court", "guild", "rivers", "craftsman" }

local FACTION_NAMES = {
    court    = "朝廷",
    guild    = "商会",
    rivers   = "江湖",
    craftsman = "匠道",
}

-- ============================================================================
-- 好感度接口
-- ============================================================================

--- 获取角色好感度
---@param npcId string
---@return number
function RelationshipTracker.GetFavor(npcId)
    return GameState.GetRelationship(npcId)
end

--- 增加好感度
---@param npcId string
---@param delta number
function RelationshipTracker.AddFavor(npcId, delta)
    GameState.AddRelationship(npcId, delta)
end

--- 获取角色已解锁等级
---@param npcId string
---@return number level (0 = 未解锁任何)
function RelationshipTracker.GetUnlockedLevel(npcId)
    local favor = GameState.GetRelationship(npcId)
    local thresholds = CHARACTER_THRESHOLDS[npcId]
    if not thresholds then return 0 end

    local maxLevel = 0
    for i = 1, #thresholds do
        if favor >= thresholds[i].min then
            maxLevel = thresholds[i].level
        end
    end
    return maxLevel
end

--- 检查是否达到指定阈值
---@param npcId string
---@param level number
---@return boolean
function RelationshipTracker.HasReachedLevel(npcId, level)
    return RelationshipTracker.GetUnlockedLevel(npcId) >= level
end

--- 获取角色好感度摘要
---@return table[] { npcId, name, favor, unlockedLevel }
function RelationshipTracker.GetAllFavors()
    local result = {}
    for npcId, thresholds in pairs(CHARACTER_THRESHOLDS) do
        result[#result + 1] = {
            npcId = npcId,
            favor = GameState.GetRelationship(npcId),
            unlockedLevel = RelationshipTracker.GetUnlockedLevel(npcId),
        }
    end
    return result
end

-- ============================================================================
-- 阵营接口
-- ============================================================================

--- 获取阵营值
---@param factionId string
---@return number
function RelationshipTracker.GetFaction(factionId)
    return GameState.GetFaction(factionId)
end

--- 增加阵营值
---@param factionId string
---@param delta number
function RelationshipTracker.AddFaction(factionId, delta)
    GameState.AddFaction(factionId, delta)
end

--- 获取主导阵营
---@return string|nil factionId, number maxValue
function RelationshipTracker.GetDominantFaction()
    local maxId = nil
    local maxVal = -1

    for i = 1, #FACTION_IDS do
        local fId = FACTION_IDS[i]
        local val = GameState.GetFaction(fId)
        if val > maxVal then
            maxVal = val
            maxId = fId
        end
    end

    return maxId, maxVal
end

--- 获取全部阵营值
---@return table { [factionId] = value }
function RelationshipTracker.GetAllFactions()
    local result = {}
    for i = 1, #FACTION_IDS do
        local fId = FACTION_IDS[i]
        result[fId] = GameState.GetFaction(fId)
    end
    return result
end

--- 获取阵营名称
---@param factionId string
---@return string
function RelationshipTracker.GetFactionName(factionId)
    return FACTION_NAMES[factionId] or factionId
end

-- ============================================================================
-- 角色展示信息（供关系界面使用）
-- ============================================================================

--- 关键角色展示顺序与中文名（与 StoryManager.CHARACTER_CONFIG 对应）
RelationshipTracker.CHARACTER_DISPLAY = {
    { npcId = "keeper",     name = "老掌柜" },
    { npcId = "shen",       name = "沈绫" },
    { npcId = "luchen",     name = "陆沉" },
    { npcId = "magistrate", name = "县尉" },
    { npcId = "disciple",   name = "阿晦" },
}

--- 获取角色当前解锁等级的描述（未解锁返回 nil）
---@param npcId string
---@return string|nil
function RelationshipTracker.GetUnlockedDesc(npcId)
    local level = RelationshipTracker.GetUnlockedLevel(npcId)
    if level <= 0 then return nil end
    local thresholds = CHARACTER_THRESHOLDS[npcId]
    if not thresholds then return nil end
    for i = #thresholds, 1, -1 do
        if thresholds[i].level == level then
            return thresholds[i].desc
        end
    end
    return nil
end

-- 注：结局判定统一由 Story.EndingEvaluator 负责，此处不再重复实现。

return RelationshipTracker
