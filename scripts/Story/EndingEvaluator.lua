-- ============================================================================
-- EndingEvaluator - 多结局判定系统
-- Project Smith / P3-A6
--
-- 职责：
--   根据 GDD §11.22 的阵营变量与结局条件总表，
--   评估玩家当前数据，返回最终结局 ID 及详细判定结果。
--
-- 结局优先级（从高到低）：
--   1. 断火残坊（失败结局，优先检测）
--   2. 守道匠宗（最高精神评价）
--   3. 御用神匠（权势路线）
--   4. 江湖名坊（江湖路线）
--   5. 商会铸局（商会路线）
--   6. 断火残坊（兜底）
--
-- 使用方式：
--   local EndingEvaluator = require("Story.EndingEvaluator")
--   local result = EndingEvaluator.Evaluate()
--   -- result.endingId    : string  结局 ID
--   -- result.endingName  : string  结局名称
--   -- result.description : string  风味说明
--   -- result.details     : table   各条件的判定明细
-- ============================================================================

local GameState = require("Core.GameState")

local EndingEvaluator = {}

-- ==================== 结局定义 ====================

---@class EndingDef
---@field id string
---@field name string
---@field description string
---@field priority number 数字越小优先级越高

local ENDINGS = {
    {
        id = "broken_forge",
        name = "断火残坊",
        description = "失败或半失败结局",
        priority = 1,
    },
    {
        id = "craftsman_way",
        name = "守道匠宗",
        description = "精神最高评价路线",
        priority = 2,
    },
    {
        id = "imperial_smith",
        name = "御用神匠",
        description = "权势最大，代价是自由",
        priority = 3,
    },
    {
        id = "jianghu_forge",
        name = "江湖名坊",
        description = "名声在外，长期受压",
        priority = 4,
    },
    {
        id = "guild_foundry",
        name = "商会铸局",
        description = "最赚钱，评价最灰",
        priority = 5,
    },
}

-- ==================== 条件检测 ====================

--- 获取关键角色断裂数（好感 <= -20 视为断裂）
---@return number
local function CountBrokenRelationships()
    local count = 0
    local keyNpcs = { "keeper", "shen", "luchen", "magistrate" }
    for i = 1, #keyNpcs do
        if GameState.GetRelationship(keyNpcs[i]) <= -20 then
            count = count + 1
        end
    end
    return count
end

--- 检测断火残坊条件
--- 核心条件：韩铸敌意 >= 80（即 hanzhu <= -80）或 关键角色断裂数 >= 3
--- 次级条件：真相揭露度 <= 2
---@return boolean matched
---@return table details
local function CheckBrokenForge()
    local hanzhu = GameState.GetRelationship("hanzhu")
    local brokenCount = CountBrokenRelationships()
    local truth = GameState.GetRelationship("truth")

    local hanHostile = hanzhu <= -80
    local manyBroken = brokenCount >= 3
    local lowTruth = truth <= 2

    local corePass = hanHostile or manyBroken
    local secondaryPass = lowTruth

    local details = {
        { label = "韩铸敌意 >= 80", value = hanzhu, pass = hanHostile, note = "hanzhu=" .. hanzhu .. " (<=−80即满足)" },
        { label = "角色断裂数 >= 3", value = brokenCount, pass = manyBroken },
        { label = "真相揭露度 <= 2", value = truth, pass = secondaryPass },
    }

    return corePass and secondaryPass, details
end

--- 检测守道匠宗条件
--- 核心条件：匠道倾向 >= 80
--- 次级条件：老掌柜 >= 70, 真相揭露度 >= 5
--- 排他条件：朝廷倾向 < 75
---@return boolean matched
---@return table details
local function CheckCraftsmanWay()
    local craftsman = GameState.GetFaction("craftsman")
    local keeper = GameState.GetRelationship("keeper")
    local truth = GameState.GetRelationship("truth")
    local court = GameState.GetFaction("court")

    local corePass = craftsman >= 80
    local keeperPass = keeper >= 70
    local truthPass = truth >= 5
    local exclusionPass = court < 75

    local details = {
        { label = "匠道倾向 >= 80", value = craftsman, pass = corePass },
        { label = "老掌柜好感 >= 70", value = keeper, pass = keeperPass },
        { label = "真相揭露度 >= 5", value = truth, pass = truthPass },
        { label = "朝廷倾向 < 75(排他)", value = court, pass = exclusionPass },
    }

    return corePass and keeperPass and truthPass and exclusionPass, details
end

--- 检测御用神匠条件
--- 核心条件：朝廷倾向 >= 70
--- 次级条件：县尉支持 >= 70, 真相揭露度 >= 3
--- 排他条件：匠道倾向 < 80
---@return boolean matched
---@return table details
local function CheckImperialSmith()
    local court = GameState.GetFaction("court")
    local magistrate = GameState.GetRelationship("magistrate")
    local truth = GameState.GetRelationship("truth")
    local craftsman = GameState.GetFaction("craftsman")

    local corePass = court >= 70
    local magistratePass = magistrate >= 70
    local truthPass = truth >= 3
    local exclusionPass = craftsman < 80

    local details = {
        { label = "朝廷倾向 >= 70", value = court, pass = corePass },
        { label = "县尉支持 >= 70", value = magistrate, pass = magistratePass },
        { label = "真相揭露度 >= 3", value = truth, pass = truthPass },
        { label = "匠道倾向 < 80(排他)", value = craftsman, pass = exclusionPass },
    }

    return corePass and magistratePass and truthPass and exclusionPass, details
end

--- 检测江湖名坊条件
--- 核心条件：江湖倾向 >= 70
--- 次级条件：陆沉好感 >= 70
--- 排他条件：朝廷倾向 < 75
---@return boolean matched
---@return table details
local function CheckJianghuForge()
    local rivers = GameState.GetFaction("rivers")
    local luchen = GameState.GetRelationship("luchen")
    local court = GameState.GetFaction("court")

    local corePass = rivers >= 70
    local luchenPass = luchen >= 70
    local exclusionPass = court < 75

    local details = {
        { label = "江湖倾向 >= 70", value = rivers, pass = corePass },
        { label = "陆沉好感 >= 70", value = luchen, pass = luchenPass },
        { label = "朝廷倾向 < 75(排他)", value = court, pass = exclusionPass },
    }

    return corePass and luchenPass and exclusionPass, details
end

--- 检测商会铸局条件
--- 核心条件：商会倾向 >= 70
--- 次级条件：沈绫好感 >= 65
--- 排他条件：匠道倾向 < 75
---@return boolean matched
---@return table details
local function CheckGuildFoundry()
    local guild = GameState.GetFaction("guild")
    local shen = GameState.GetRelationship("shen")
    local craftsman = GameState.GetFaction("craftsman")

    local corePass = guild >= 70
    local shenPass = shen >= 65
    local exclusionPass = craftsman < 75

    local details = {
        { label = "商会倾向 >= 70", value = guild, pass = corePass },
        { label = "沈绫好感 >= 65", value = shen, pass = shenPass },
        { label = "匠道倾向 < 75(排他)", value = craftsman, pass = exclusionPass },
    }

    return corePass and shenPass and exclusionPass, details
end

-- ==================== 判定入口列表 ====================

local CHECKERS = {
    { id = "broken_forge",    check = CheckBrokenForge },
    { id = "craftsman_way",   check = CheckCraftsmanWay },
    { id = "imperial_smith",  check = CheckImperialSmith },
    { id = "jianghu_forge",   check = CheckJianghuForge },
    { id = "guild_foundry",   check = CheckGuildFoundry },
}

-- ==================== 公共接口 ====================

--- 评估当前数据，返回最终结局
---@return table { endingId: string, endingName: string, description: string, details: table }
function EndingEvaluator.Evaluate()
    print("[EndingEvaluator] Evaluating endings...")

    -- 按优先级依次检测
    for i = 1, #CHECKERS do
        local checker = CHECKERS[i]
        local matched, details = checker.check()

        print(string.format("  [%s] %s", checker.id, matched and "MATCHED" or "no"))

        if matched then
            -- 查找结局定义
            for j = 1, #ENDINGS do
                if ENDINGS[j].id == checker.id then
                    local ending = ENDINGS[j]
                    return {
                        endingId = ending.id,
                        endingName = ending.name,
                        description = ending.description,
                        details = details,
                    }
                end
            end
        end
    end

    -- 兜底：没有任何正面结局达标，默认断火残坊
    print("  [fallback] -> broken_forge")
    local _, fallbackDetails = CheckBrokenForge()
    return {
        endingId = "broken_forge",
        endingName = "断火残坊",
        description = "失败或半失败结局（兜底）",
        details = fallbackDetails,
    }
end

--- 获取所有结局的判定详情（用于调试/结局回顾界面）
---@return table[] 每个结局的 { id, name, matched, details }
function EndingEvaluator.EvaluateAll()
    local results = {}
    for i = 1, #CHECKERS do
        local checker = CHECKERS[i]
        local matched, details = checker.check()

        -- 查找结局定义
        local endingDef = nil
        for j = 1, #ENDINGS do
            if ENDINGS[j].id == checker.id then
                endingDef = ENDINGS[j]
                break
            end
        end

        results[#results + 1] = {
            id = checker.id,
            name = endingDef and endingDef.name or checker.id,
            description = endingDef and endingDef.description or "",
            matched = matched,
            details = details,
        }
    end
    return results
end

--- 获取结局名称列表（用于 UI 展示）
---@return table[] { id: string, name: string }
function EndingEvaluator.GetEndingList()
    local list = {}
    for i = 1, #ENDINGS do
        list[#list + 1] = {
            id = ENDINGS[i].id,
            name = ENDINGS[i].name,
            description = ENDINGS[i].description,
        }
    end
    return list
end

return EndingEvaluator
