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
-- 结局评估（P3 完整实现，P2 提供框架）
-- ============================================================================

--- 评估可达成的结局
---@return table[] { endingId, name, met }
function RelationshipTracker.EvaluateEndings()
    local factions = RelationshipTracker.GetAllFactions()
    local keeperTrust = GameState.GetRelationship("keeper")

    local endings = {
        {
            endingId = "imperial_craftmaster",
            name = "御用神匠",
            met = factions.court >= 70 and factions.craftsman < 80,
        },
        {
            endingId = "craftsman_hermit",
            name = "守道匠宗",
            met = factions.craftsman >= 80 and keeperTrust >= 70,
        },
        {
            endingId = "wandering_legend",
            name = "江湖名坊",
            met = factions.rivers >= 70 and GameState.GetRelationship("luchen") >= 70,
        },
        {
            endingId = "guild_workshop",
            name = "商会铸局",
            met = factions.guild >= 70 and GameState.GetRelationship("shen") >= 65,
        },
        {
            endingId = "extinguished",
            name = "断火残坊",
            met = false,  -- P3 实现具体条件
        },
    }

    return endings
end

return RelationshipTracker
