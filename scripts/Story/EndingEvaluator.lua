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
        epilogue = "债没还清，人也散了。某个清晨，炉火彻底熄了。这间铺子，终究没能撑过那个寒冬。",
    },
    {
        id = "craftsman_way",
        name = "守道匠宗",
        description = "精神最高评价路线",
        priority = 2,
        epilogue = "你回绝了所有招揽，守着这间小铺，把残卷上的古法一锤一锤敲回人间。多年后，“守道”二字成了匠人之间的暗号——铁要烧透，心要烧硬。",
    },
    {
        id = "imperial_smith",
        name = "御用神匠",
        description = "权势最大，代价是自由",
        priority = 3,
        epilogue = "王都的诏书送到那天，炉火映红了半条街。你成了御用神匠，住进了高墙，再没人敢压你的价——也再没人敢直呼你的名字。",
    },
    {
        id = "jianghu_forge",
        name = "江湖名坊",
        description = "名声在外，长期受压",
        priority = 4,
        epilogue = "你的刀流落江湖，斩过不平，也染过血。庙堂始终容不下你，可每一个握过你刀的人，都记得这间小坊的名字。",
    },
    {
        id = "guild_foundry",
        name = "商会铸局",
        description = "最赚钱，评价最灰",
        priority = 5,
        epilogue = "账册越来越厚，炉子越来越多。商会的旗号挂上门楣，你赚到了所有人羡慕的银子，只是夜深时偶尔会想起，最初那把猎户的短刀。",
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

    -- 重标(可达)：关键角色断裂数 >= 2 且 真相揭露度 <= 1 才触发失败结局
    -- 即蓄意破坏关系 + 无视真相，普通玩法不会落到这里
    local manyBroken = brokenCount >= 2
    local lowTruth = truth <= 1

    local details = {
        { label = "角色断裂数 >= 2", value = brokenCount, pass = manyBroken },
        { label = "真相揭露度 <= 1", value = truth, pass = lowTruth },
        { label = "韩铸敌意(参考)", value = hanzhu, pass = false },
    }

    return manyBroken and lowTruth, details
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

    -- 重标(可达)：craftsman 上限99 / keeper 上限50 / truth 上限13
    local corePass = craftsman >= 55
    local keeperPass = keeper >= 28
    local truthPass = truth >= 4

    local details = {
        { label = "匠道倾向 >= 55", value = craftsman, pass = corePass },
        { label = "老掌柜好感 >= 28", value = keeper, pass = keeperPass },
        { label = "真相揭露度 >= 4", value = truth, pass = truthPass },
    }

    return corePass and keeperPass and truthPass, details
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

    -- 重标(可达)：court 上限82 / magistrate 上限26
    local corePass = court >= 50
    local magistratePass = magistrate >= 14

    local details = {
        { label = "朝廷倾向 >= 50", value = court, pass = corePass },
        { label = "县尉支持 >= 14", value = magistrate, pass = magistratePass },
    }

    return corePass and magistratePass, details
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

    -- 重标(可达)：rivers 上限48 / luchen 上限42
    local corePass = rivers >= 30
    local luchenPass = luchen >= 24

    local details = {
        { label = "江湖倾向 >= 30", value = rivers, pass = corePass },
        { label = "陆沉好感 >= 24", value = luchen, pass = luchenPass },
    }

    return corePass and luchenPass, details
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

    -- 重标(可达)：guild 上限48 / shen 上限28
    local corePass = guild >= 30
    local shenPass = shen >= 14

    local details = {
        { label = "商会倾向 >= 30", value = guild, pass = corePass },
        { label = "沈绫好感 >= 14", value = shen, pass = shenPass },
    }

    return corePass and shenPass, details
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
                        epilogue = ending.epilogue,
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
        epilogue = ENDINGS[1].epilogue,
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
