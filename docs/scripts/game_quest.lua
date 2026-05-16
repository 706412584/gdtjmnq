-- ============================================================================
-- 《问道长生》任务系统
-- 职责：主线/每日任务进度追踪、条件检查、奖励领取
-- 设计：Can/Do 模式，进度由其他模块 NotifyAction 驱动
-- ============================================================================

local GamePlayer = require("game_player")
local DataWorld  = require("data_world")

---@diagnostic disable-next-line: undefined-global
local cjson = cjson

local M = {}

-- 网络模式：异步领取回调
---@type fun(ok: boolean, msg: string)|nil
local pendingClaimCallback_ = nil

-- ============================================================================
-- 每日任务动作映射：questId → actionType
-- ============================================================================
local DAILY_ACTIONS = {
    dq1 = "cultivate",        -- 静修
    dq2 = "gather_herb",      -- 采集灵草
    dq3 = "kill_monster",     -- 击败妖兽
    dq4 = "alchemy_success",  -- 炼丹成功
}

-- ============================================================================
-- 内部工具
-- ============================================================================

--- 确保任务数据结构存在
---@return table|nil
local function EnsureQuestData()
    local p = GamePlayer.Get()
    if not p then return nil end
    if not p.quests then p.quests = { daily = {}, main = {}, side = {} } end
    if not p.quests.mainClaimed then p.quests.mainClaimed = {} end
    if not p.quests.mainFlags then p.quests.mainFlags = {} end
    if not p.quests.dailyDate then p.quests.dailyDate = "" end
    if not p.quests.dailyCounters then p.quests.dailyCounters = {} end
    if not p.quests.dailyClaimed then p.quests.dailyClaimed = {} end
    return p
end

--- 检查每日任务是否需要重置（新一天）
---@param p table
local function CheckDailyReset(p)
    local today = os.date("%Y-%m-%d")
    if p.quests.dailyDate ~= today then
        p.quests.dailyDate = today
        p.quests.dailyCounters = {}
        p.quests.dailyClaimed = {}
        GamePlayer.MarkDirty()
    end
end

--- 获取每日计数器值
---@param p table
---@param actionType string
---@return number
local function GetDailyCounter(p, actionType)
    return p.quests.dailyCounters[actionType] or 0
end

--- 检查列表中是否包含指定 id
---@param list table
---@param id string
---@return boolean
local function ListContains(list, id)
    for _, v in ipairs(list) do
        if v == id then return true end
    end
    return false
end

-- ============================================================================
-- 主线任务条件检查器
-- 每个函数返回 (progress, maxProgress)
-- ============================================================================
local MAIN_CHECKERS = {
    mq1 = function(p)  -- 创角完成
        return 1, 1
    end,
    mq2 = function(p)  -- 静修1次
        local done = (p.cultivation or 0) > 0 or #(p.cultivationLogs or {}) > 0
        return done and 1 or 0, 1
    end,
    mq3 = function(p)  -- 游历1次
        local done = #(p.bagItems or {}) > 0
            or (p.quests.mainFlags and p.quests.mainFlags.explored)
        return done and 1 or 0, 1
    end,
    mq4 = function(p)  -- 修为达到5000
        if (p.tier or 1) >= 2 then return 5000, 5000 end
        return math.min(p.cultivation or 0, 5000), 5000
    end,
    mq5 = function(p)  -- 购买任意物品
        local done = p.quests.mainFlags and p.quests.mainFlags.purchased
        return done and 1 or 0, 1
    end,
}

-- ============================================================================
-- 公开接口：动作通知
-- ============================================================================

--- 通知一个动作发生（由其他游戏模块调用）
--- actionType: "cultivate" | "gather_herb" | "kill_monster" | "alchemy_success"
---@param actionType string
---@param count? number 默认1
function M.NotifyAction(actionType, count)
    local p = EnsureQuestData()
    if not p then return end
    CheckDailyReset(p)
    count = count or 1
    p.quests.dailyCounters[actionType] = (p.quests.dailyCounters[actionType] or 0) + count
    GamePlayer.MarkDirty()
end

--- 设置主线任务标记（由其他模块调用）
---@param flag string "explored" | "purchased"
---@param value any
function M.SetMainFlag(flag, value)
    local p = EnsureQuestData()
    if not p then return end
    p.quests.mainFlags[flag] = value
    GamePlayer.MarkDirty()
end

-- ============================================================================
-- 公开接口：查询
-- ============================================================================

--- 获取所有主线任务状态
---@return table[]
function M.GetMainQuests()
    local p = EnsureQuestData()
    if not p then return {} end

    local result = {}
    local prevCompleted = true  -- 主线任务顺序解锁

    for _, def in ipairs(DataWorld.MAIN_QUESTS) do
        local checker = MAIN_CHECKERS[def.id]
        local progress, maxProgress = 0, 1
        if checker then
            progress, maxProgress = checker(p)
        end

        local claimed = ListContains(p.quests.mainClaimed, def.id)

        ---@type string
        local status
        if claimed then
            status = "completed"
        elseif not prevCompleted then
            status = "locked"
        elseif progress >= maxProgress then
            status = "claimable"
        else
            status = "active"
        end

        result[#result + 1] = {
            id = def.id, name = def.name, desc = def.desc,
            reward = def.reward, rewardItems = def.rewardItems,
            progress = progress, maxProgress = maxProgress,
            status = status,
        }

        prevCompleted = claimed
    end
    return result
end

--- 获取所有每日任务状态
---@return table[]
function M.GetDailyQuests()
    local p = EnsureQuestData()
    if not p then return {} end
    CheckDailyReset(p)

    local result = {}
    for _, def in ipairs(DataWorld.DAILY_QUESTS) do
        local actionType = DAILY_ACTIONS[def.id] or "unknown"
        local progress = GetDailyCounter(p, actionType)
        local maxProgress = def.maxProgress or 1

        local claimed = ListContains(p.quests.dailyClaimed, def.id)

        ---@type string
        local status
        if claimed then
            status = "completed"
        elseif progress >= maxProgress then
            status = "claimable"
        else
            status = "active"
        end

        result[#result + 1] = {
            id = def.id, name = def.name, desc = def.desc,
            reward = def.reward, rewardItems = def.rewardItems,
            progress = math.min(progress, maxProgress),
            maxProgress = maxProgress,
            status = status,
        }
    end
    return result
end

--- 获取可领取任务总数（用于红点提示）
---@return number
function M.GetClaimableCount()
    local count = 0
    for _, q in ipairs(M.GetMainQuests()) do
        if q.status == "claimable" then count = count + 1 end
    end
    for _, q in ipairs(M.GetDailyQuests()) do
        if q.status == "claimable" then count = count + 1 end
    end
    return count
end

-- ============================================================================
-- 公开接口：领取奖励
-- ============================================================================

--- 检查是否可领取
---@param questId string
---@return boolean, string|nil
function M.CanClaim(questId)
    for _, q in ipairs(M.GetMainQuests()) do
        if q.id == questId then
            if q.status == "claimable" then return true, nil end
            return false, q.status == "completed" and "已领取" or "条件未达成"
        end
    end
    for _, q in ipairs(M.GetDailyQuests()) do
        if q.id == questId then
            if q.status == "claimable" then return true, nil end
            return false, q.status == "completed" and "已领取" or "条件未达成"
        end
    end
    return false, "未知任务"
end

--- 领取奖励
---@param questId string
---@param callback? fun(ok: boolean, msg: string) 网络模式异步回调
---@return boolean|nil, string|nil
function M.DoClaim(questId, callback)
    local ok, reason = M.CanClaim(questId)
    if not ok then
        if callback then callback(false, reason or "无法领取") end
        return false, reason or "无法领取"
    end

    ---@diagnostic disable-next-line: undefined-global
    if IsNetworkMode() then
        -- ── 网络模式：发送到服务端验证和发放 ──
        local GameServer = require("game_server")
        local Shared     = require("network.shared")
        local ClientNet  = require("network.client_net")

        local params = cjson.encode({
            serverId = GameServer.GetCurrentServer().id,
        })
        local vm = VariantMap()
        vm["QuestId"] = Variant(questId)
        vm["Params"]  = Variant(params)

        pendingClaimCallback_ = callback
        ClientNet.SendToServer(Shared.EVENTS.REQ_QUEST_CLAIM, vm)
        return nil, nil  -- 异步
    end

    -- ── 单机模式：原逻辑 ──
    local p = EnsureQuestData()
    if not p then return false, "数据未加载" end

    -- 查找任务定义
    ---@type table|nil
    local def = nil
    local isMain = false
    for _, q in ipairs(DataWorld.MAIN_QUESTS) do
        if q.id == questId then def = q; isMain = true; break end
    end
    if not def then
        for _, q in ipairs(DataWorld.DAILY_QUESTS) do
            if q.id == questId then def = q; break end
        end
    end
    if not def then return false, "未知任务" end

    -- 发放奖励
    if def.rewardItems then
        for itemName, count in pairs(def.rewardItems) do
            if itemName == "灵石" then
                GamePlayer.AddCurrency("lingStone", count)
            elseif itemName == "仙石" then
                GamePlayer.AddCurrency("spiritStone", count)
            else
                GamePlayer.AddItem({ name = itemName, count = count })
            end
        end
    end

    -- 标记已领取
    if isMain then
        p.quests.mainClaimed[#p.quests.mainClaimed + 1] = questId
    else
        p.quests.dailyClaimed[#p.quests.dailyClaimed + 1] = questId
    end

    GamePlayer.MarkDirty()
    local msg = "完成任务「<c=gold>" .. def.name .. "</c>」，获得 <c=yellow>" .. def.reward .. "</c>"
    GamePlayer.AddLog(msg)
    return true, msg
end

-- ============================================================================
-- 网络模式：服务端回复处理
-- ============================================================================

--- 处理任务领取回复（由 client_net.lua 调用）
---@param eventData any
function M.OnQuestClaimResp(eventData)
    local success = eventData["Success"]:GetBool()
    local dataStr = eventData["Data"]:GetString()
    local msgStr  = ""
    pcall(function() msgStr = eventData["Msg"]:GetString() end)

    local ok2, data = pcall(cjson.decode, dataStr)
    if not ok2 then data = {} end

    local cb = pendingClaimCallback_
    pendingClaimCallback_ = nil

    if success then
        local questId = data.questId or ""
        local rewards = data.rewards or {}

        -- 乐观同步本地状态
        local p = EnsureQuestData()
        if p then
            local isMain = questId:sub(1, 2) == "mq"
            local claimedList = isMain and p.quests.mainClaimed or p.quests.dailyClaimed
            if not ListContains(claimedList, questId) then
                claimedList[#claimedList + 1] = questId
            end

            -- 乐观同步奖励到本地（货币用 AddCurrencyLocal，物品用 AddItem）
            for _, rewardStr in ipairs(rewards) do
                local name, count = rewardStr:match("^(.+)x(%d+)$")
                count = tonumber(count) or 0
                if name == "灵石" then
                    GamePlayer.AddCurrencyLocal("lingStone", count)
                elseif name == "仙石" then
                    GamePlayer.AddCurrencyLocal("spiritStone", count)
                elseif name and count > 0 then
                    GamePlayer.AddItem({ name = name, count = count })
                end
            end

            GamePlayer.MarkDirty()
        end

        -- 查找任务名用于日志
        local questName = questId
        for _, q in ipairs(DataWorld.MAIN_QUESTS) do
            if q.id == questId then questName = q.name; break end
        end
        for _, q in ipairs(DataWorld.DAILY_QUESTS) do
            if q.id == questId then questName = q.name; break end
        end

        local msg = "完成任务「<c=gold>" .. questName .. "</c>」，获得 <c=yellow>" .. table.concat(rewards, ", ") .. "</c>"
        GamePlayer.AddLog(msg)
        if cb then cb(true, msg) end
    else
        local msg = msgStr or "领取失败"
        GamePlayer.AddLog("任务领取失败: " .. msg)
        if cb then cb(false, msg) end
    end
end

return M
