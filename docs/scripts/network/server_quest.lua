-- ============================================================================
-- 《问道长生》服务端任务奖励模块
-- 职责：校验任务完成条件 + 防重复领取 + 服务端发放奖励
-- 安全：条件检查在服务端重新执行，客户端无法伪造
-- ============================================================================

local Shared = require("network.shared")
local EVENTS = Shared.EVENTS
---@diagnostic disable-next-line: undefined-global
local cjson  = cjson

local M = {}

-- 依赖注入
local deps_ = nil

-- ============================================================================
-- 奖励定义（与 data_world.lua 保持一致）
-- ============================================================================

local MAIN_QUEST_REWARDS = {
    mq1 = { ["灵石"] = 200 },
    mq2 = { ["培元丹"] = 3 },
    mq3 = { ["灵石"] = 300 },
    mq4 = { ["筑基丹"] = 1 },
    mq5 = { ["灵石"] = 100 },
}

local DAILY_QUEST_REWARDS = {
    dq1 = { ["灵石"] = 50 },
    dq2 = { ["灵草"] = 5 },
    dq3 = { ["灵石"] = 100 },
    dq4 = { ["培元丹"] = 2 },
}

--- 每日任务所需动作和目标进度
local DAILY_ACTIONS = {
    dq1 = { action = "cultivate",        maxProgress = 1 },
    dq2 = { action = "gather_herb",      maxProgress = 3 },
    dq3 = { action = "kill_monster",     maxProgress = 5 },
    dq4 = { action = "alchemy_success",  maxProgress = 1 },
}

-- ============================================================================
-- 主线任务条件检查器（简化版，与 game_quest.lua MAIN_CHECKERS 对齐）
-- ============================================================================

local MAIN_CHECKERS = {
    mq1 = function(p) return true end,    -- 创角完成（能领就是完成了）
    mq2 = function(p)                     -- 静修1次
        return (p.cultivation or 0) > 0
    end,
    mq3 = function(p)                     -- 游历1次
        return #(p.bagItems or {}) > 0
            or (p.quests and p.quests.mainFlags and p.quests.mainFlags.explored)
    end,
    mq4 = function(p)                     -- 修为达到5000 或 tier>=2
        if (p.tier or 1) >= 2 then return true end
        return (p.cultivation or 0) >= 5000
    end,
    mq5 = function(p)                     -- 购买任意物品
        return p.quests and p.quests.mainFlags and p.quests.mainFlags.purchased
    end,
}

--- 检查列表中是否包含指定值
local function ListContains(list, id)
    if not list then return false end
    for _, v in ipairs(list) do
        if v == id then return true end
    end
    return false
end

--- 获取玩家数据 key
local function GetPlayerKey(params)
    local serverId = params.serverId or 1
    return "s" .. serverId .. "_player"
end

-- ============================================================================
-- 初始化
-- ============================================================================

---@param deps table { SendToClient }
function M.Init(deps)
    deps_ = deps
    print("[ServerQuest] 任务奖励模块初始化完成")
end

-- ============================================================================
-- 工具函数
-- ============================================================================

local function Reply(userId, success, data, msg, reqKey)
    local vm = VariantMap()
    vm["Success"] = Variant(success)
    vm["Data"]    = Variant(cjson.encode(data or {}))
    vm["Msg"]     = Variant(msg or "")
    if reqKey then
        vm["ReqKey"] = Variant(reqKey)
    end
    deps_.SendToClient(userId, EVENTS.QUEST_CLAIM_RESP, vm)
end

-- ============================================================================
-- 请求处理
-- ============================================================================

---@param userId number
---@param eventData any
function M.HandleQuestClaim(userId, eventData)
    if not serverCloud then
        Reply(userId, false, nil, "serverCloud 不可用")
        return
    end

    local questId   = eventData["QuestId"]:GetString()
    local paramsStr = eventData["Params"]:GetString()
    local reqKey = ""
    pcall(function() reqKey = eventData["ReqKey"]:GetString() end)

    local ok, params = pcall(cjson.decode, paramsStr)
    if not ok then params = {} end
    params.questId = questId

    local playerKey = GetPlayerKey(params)

    -- 读取玩家数据
    serverCloud:Get(userId, playerKey, {
        ok = function(scores)
            local playerData = scores or {}
            M.ProcessClaim(userId, playerData, playerKey, params, reqKey)
        end,
        error = function(code, reason)
            Reply(userId, false, nil, "读取玩家数据失败: " .. tostring(reason), reqKey)
        end,
    })
end

--- 处理领取逻辑
---@param userId number
---@param playerData table
---@param playerKey string
---@param params table { questId, serverId }
---@param reqKey string
function M.ProcessClaim(userId, playerData, playerKey, params, reqKey)
    local questId = params.questId
    local isMain = questId:sub(1, 2) == "mq"

    -- 确保数据结构
    if not playerData.quests then playerData.quests = {} end
    if not playerData.quests.mainClaimed then playerData.quests.mainClaimed = {} end
    if not playerData.quests.dailyClaimed then playerData.quests.dailyClaimed = {} end
    if not playerData.quests.dailyCounters then playerData.quests.dailyCounters = {} end
    if not playerData.quests.mainFlags then playerData.quests.mainFlags = {} end

    -- 检查是否已领取
    local claimedList = isMain and playerData.quests.mainClaimed or playerData.quests.dailyClaimed
    if ListContains(claimedList, questId) then
        Reply(userId, false, nil, "已领取", reqKey)
        return
    end

    -- 主线任务：检查顺序解锁（前一个必须已领取）
    if isMain then
        local checker = MAIN_CHECKERS[questId]
        if not checker then
            Reply(userId, false, nil, "未知主线任务: " .. questId, reqKey)
            return
        end

        -- 条件检查
        if not checker(playerData) then
            Reply(userId, false, nil, "条件未达成", reqKey)
            return
        end

        -- 顺序解锁检查：mq2 需要 mq1 已领取，mq3 需要 mq2 已领取...
        local questNum = tonumber(questId:sub(3))
        if questNum and questNum > 1 then
            local prevId = "mq" .. (questNum - 1)
            if not ListContains(playerData.quests.mainClaimed, prevId) then
                Reply(userId, false, nil, "需先完成前置任务", reqKey)
                return
            end
        end
    else
        -- 每日任务：检查计数
        local dailyDef = DAILY_ACTIONS[questId]
        if not dailyDef then
            Reply(userId, false, nil, "未知每日任务: " .. questId, reqKey)
            return
        end

        local counter = playerData.quests.dailyCounters[dailyDef.action] or 0
        if counter < dailyDef.maxProgress then
            Reply(userId, false, nil, "进度不足: " .. counter .. "/" .. dailyDef.maxProgress, reqKey)
            return
        end
    end

    -- 查找奖励
    local rewardTable = isMain and MAIN_QUEST_REWARDS or DAILY_QUEST_REWARDS
    local rewards = rewardTable[questId]
    if not rewards then
        Reply(userId, false, nil, "无奖励定义: " .. questId, reqKey)
        return
    end

    -- 发放奖励
    local rewardSummary = {}
    for itemName, count in pairs(rewards) do
        if itemName == "灵石" then
            serverCloud.money:Add(userId, "lingStone", count)
            rewardSummary[#rewardSummary + 1] = itemName .. "x" .. count
        elseif itemName == "仙石" then
            serverCloud.money:Add(userId, "spiritStone", count)
            rewardSummary[#rewardSummary + 1] = itemName .. "x" .. count
        else
            -- 物品追加到背包
            if not playerData.bagItems then playerData.bagItems = {} end
            local found = false
            for _, item in ipairs(playerData.bagItems) do
                if item.name == itemName then
                    item.count = (item.count or 0) + count
                    found = true
                    break
                end
            end
            if not found then
                playerData.bagItems[#playerData.bagItems + 1] = {
                    name = itemName,
                    count = count,
                    rarity = "common",
                    desc = "任务奖励",
                }
            end
            rewardSummary[#rewardSummary + 1] = itemName .. "x" .. count
        end
    end

    -- 标记已领取
    claimedList[#claimedList + 1] = questId

    -- 回写 playerData
    serverCloud:Set(userId, playerKey, playerData, {
        ok = function()
            print("[ServerQuest] 任务领取 uid=" .. tostring(userId) .. " quest=" .. questId
                .. " rewards=" .. table.concat(rewardSummary, ","))
            Reply(userId, true, {
                questId = questId,
                rewards = rewardSummary,
            }, nil, reqKey)
        end,
        error = function(code, reason)
            -- money 已发放但 playerData 回写失败 → 仍算成功但警告
            Reply(userId, true, {
                questId = questId,
                rewards = rewardSummary,
                warning = "数据回写失败，奖励已发放",
            }, nil, reqKey)
        end,
    })
end

return M
