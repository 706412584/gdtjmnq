-- ============================================================================
-- 《问道长生》服务端战斗/探索/试炼结算模块
-- 职责：校验遭遇合法性 + 服务端发放奖励（灵石走 money:Add，物品写 playerData）
-- 安全：随机数/奖励在服务端生成，客户端无法伪造
-- ============================================================================

local Shared = require("network.shared")
local EVENTS = Shared.EVENTS
---@diagnostic disable-next-line: undefined-global
local cjson  = cjson

local M = {}

-- 依赖注入
local deps_ = nil

-- ============================================================================
-- 遭遇表（从 game_explore.lua 同步，仅保留服务端校验所需字段）
-- ============================================================================

local ENCOUNTERS = {
    { name = "灵草丛",       type = "gather",  tierMin = 1, tierMax = 10, drop = "灵草",     dropCount = { 1, 3 } },
    { name = "矿脉",         type = "gather",  tierMin = 1, tierMax = 10, drop = "矿石",     dropCount = { 1, 2 } },
    { name = "灵泉",         type = "gather",  tierMin = 2, tierMax = 10, drop = "灵泉水",   dropCount = { 1, 1 } },
    { name = "天材地宝",     type = "gather",  tierMin = 4, tierMax = 10, drop = "天材地宝", dropCount = { 1, 1 } },
    { name = "散修",         type = "combat",  tierMin = 1, tierMax = 3,  reward = 20 },
    { name = "妖兽",         type = "combat",  tierMin = 1, tierMax = 5,  reward = 40 },
    { name = "精英妖兽",     type = "combat",  tierMin = 3, tierMax = 7,  reward = 100 },
    { name = "上古凶兽",     type = "combat",  tierMin = 5, tierMax = 10, reward = 250 },
    { name = "兽骨遗骸",     type = "gather",  tierMin = 1, tierMax = 10, drop = "兽骨",     dropCount = { 1, 2 } },
}

--- 试炼奖励常量（与 game_trial.lua 保持一致）
local REWARD_PER_FLOOR = 15
local REWARD_PER_WAVE  = 20
local REWARD_PER_KILL  = 10

--- 试炼声称进度的合理上限（基于 tier）
local function MaxReasonableProgress(tier, trialType)
    -- 简单公式：基础值 + tier * 倍率
    if trialType == "闯关" then
        return 5 + (tier or 1) * 8   -- tier=1 → 13层, tier=5 → 45层
    elseif trialType == "生存" then
        return 3 + (tier or 1) * 6   -- tier=1 → 9波, tier=5 → 33波
    elseif trialType == "限时" then
        return 3 + (tier or 1) * 5   -- tier=1 → 8只, tier=5 → 28只
    end
    return 10
end

--- 试炼定义（与 data_world.lua 保持一致）
local TRIALS = {
    { id = "wanyao",  type = "闯关", maxFloor = 100, unlockTier = nil },
    { id = "mijing",  type = "限时", unlockTier = nil },
    { id = "shengsi", type = "生存", unlockTier = nil },
    { id = "xianmo",  type = "闯关", maxFloor = 50,  unlockTier = 4 },
}

local function GetTrialDef(trialId)
    for _, t in ipairs(TRIALS) do
        if t.id == trialId then return t end
    end
    return nil
end

--- 查找遭遇定义
local function FindEncounter(encName)
    for _, e in ipairs(ENCOUNTERS) do
        if e.name == encName then return e end
    end
    return nil
end

--- 获取玩家数据 key（需要 serverId）
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
    print("[ServerCombat] 战斗结算模块初始化完成")
end

-- ============================================================================
-- 工具函数
-- ============================================================================

local function Reply(userId, action, success, data, msg, reqKey)
    local vm = VariantMap()
    vm["Action"]  = Variant(action)
    vm["Success"] = Variant(success)
    vm["Data"]    = Variant(cjson.encode(data or {}))
    vm["Msg"]     = Variant(msg or "")
    if reqKey then
        vm["ReqKey"] = Variant(reqKey)
    end
    deps_.SendToClient(userId, EVENTS.COMBAT_SETTLE_RESP, vm)
end

-- ============================================================================
-- 请求分发
-- ============================================================================

---@param userId number
---@param eventData any
function M.HandleCombatSettle(userId, eventData)
    if not serverCloud then
        Reply(userId, "unknown", false, nil, "serverCloud 不可用")
        return
    end

    local action    = eventData["Action"]:GetString()
    local paramsStr = eventData["Params"]:GetString()
    local reqKey = ""
    pcall(function() reqKey = eventData["ReqKey"]:GetString() end)

    local ok, params = pcall(cjson.decode, paramsStr)
    if not ok then
        Reply(userId, action, false, nil, "参数解析失败", reqKey)
        return
    end

    if action == "explore_combat" then
        M.DoExploreCombat(userId, params, reqKey)
    elseif action == "explore_gather" then
        M.DoExploreGather(userId, params, reqKey)
    elseif action == "trial_settle" then
        M.DoTrialSettle(userId, params, reqKey)
    else
        Reply(userId, action, false, nil, "未知操作: " .. tostring(action), reqKey)
    end
end

-- ============================================================================
-- 探索战斗结算
-- ============================================================================

--- 探索战斗：服务端校验遭遇合法性 + 发放灵石奖励
---@param userId number
---@param params table { encName, win, serverId }
---@param reqKey string
function M.DoExploreCombat(userId, params, reqKey)
    local encName = params.encName
    local win     = params.win
    local enc     = FindEncounter(encName)

    if not enc or enc.type ~= "combat" then
        Reply(userId, "explore_combat", false, nil, "非法遭遇: " .. tostring(encName), reqKey)
        return
    end

    local playerKey = GetPlayerKey(params)

    -- 读取玩家数据校验 tier
    serverCloud:Get(userId, playerKey, {
        ok = function(scores)
            local playerData = scores or {}
            local tier = playerData.tier or 1

            if tier < enc.tierMin or tier > enc.tierMax then
                Reply(userId, "explore_combat", false, nil,
                    "境界不匹配: tier=" .. tier .. " 需要[" .. enc.tierMin .. "," .. enc.tierMax .. "]", reqKey)
                return
            end

            -- 更新任务标记和计数器
            if not playerData.quests then playerData.quests = {} end
            if not playerData.quests.mainFlags then playerData.quests.mainFlags = {} end
            playerData.quests.mainFlags.explored = true

            if win then
                local reward = enc.reward or 20

                -- 更新每日击杀计数
                if not playerData.quests.dailyCounters then playerData.quests.dailyCounters = {} end
                playerData.quests.dailyCounters.kill_monster =
                    (playerData.quests.dailyCounters.kill_monster or 0) + 1

                -- 战败扣血
                -- 注：服务端不模拟战斗，扣血仍由客户端处理
                -- 灵石通过 money:Add 发放
                serverCloud.money:Add(userId, "lingStone", reward)

                -- 回写 playerData（任务标记更新）
                serverCloud:Set(userId, playerKey, playerData, {
                    ok = function()
                        Reply(userId, "explore_combat", true, {
                            win = true,
                            reward = reward,
                            encName = encName,
                        }, nil, reqKey)
                    end,
                    error = function(code, reason)
                        -- money 已发放，标记写入失败不影响奖励
                        Reply(userId, "explore_combat", true, {
                            win = true,
                            reward = reward,
                            encName = encName,
                            warning = "标记更新失败",
                        }, nil, reqKey)
                    end,
                })
            else
                -- 战败：只更新标记
                serverCloud:Set(userId, playerKey, playerData, {
                    ok = function()
                        Reply(userId, "explore_combat", true, {
                            win = false, reward = 0, encName = encName,
                        }, nil, reqKey)
                    end,
                    error = function()
                        Reply(userId, "explore_combat", true, {
                            win = false, reward = 0, encName = encName,
                        }, nil, reqKey)
                    end,
                })
            end
        end,
        error = function(code, reason)
            Reply(userId, "explore_combat", false, nil,
                "读取玩家数据失败: " .. tostring(reason), reqKey)
        end,
    })
end

-- ============================================================================
-- 探索采集结算
-- ============================================================================

--- 探索采集：服务端随机掉落 + 追加背包
---@param userId number
---@param params table { encName, serverId }
---@param reqKey string
function M.DoExploreGather(userId, params, reqKey)
    local encName = params.encName
    local enc     = FindEncounter(encName)

    if not enc or enc.type ~= "gather" then
        Reply(userId, "explore_gather", false, nil, "非法采集遭遇: " .. tostring(encName), reqKey)
        return
    end

    local playerKey = GetPlayerKey(params)

    serverCloud:Get(userId, playerKey, {
        ok = function(scores)
            local playerData = scores or {}
            local tier = playerData.tier or 1

            if tier < enc.tierMin or tier > enc.tierMax then
                Reply(userId, "explore_gather", false, nil,
                    "境界不匹配", reqKey)
                return
            end

            -- 服务端随机掉落数量
            local min = enc.dropCount[1]
            local max = enc.dropCount[2]
            local count = math.random(min, max)

            -- 追加到背包
            if not playerData.bagItems then playerData.bagItems = {} end
            -- 检查是否已有同名物品（堆叠）
            local found = false
            for _, item in ipairs(playerData.bagItems) do
                if item.name == enc.drop then
                    item.count = (item.count or 0) + count
                    found = true
                    break
                end
            end
            if not found then
                playerData.bagItems[#playerData.bagItems + 1] = {
                    name = enc.drop,
                    count = count,
                    rarity = "common",
                    desc = "探索获得",
                }
            end

            -- 更新任务标记
            if not playerData.quests then playerData.quests = {} end
            if not playerData.quests.mainFlags then playerData.quests.mainFlags = {} end
            playerData.quests.mainFlags.explored = true

            -- 更新每日采集计数
            if enc.drop == "灵草" then
                if not playerData.quests.dailyCounters then playerData.quests.dailyCounters = {} end
                playerData.quests.dailyCounters.gather_herb =
                    (playerData.quests.dailyCounters.gather_herb or 0) + count
            end

            -- 回写
            serverCloud:Set(userId, playerKey, playerData, {
                ok = function()
                    Reply(userId, "explore_gather", true, {
                        drop = enc.drop,
                        count = count,
                        encName = encName,
                    }, nil, reqKey)
                end,
                error = function(code, reason)
                    Reply(userId, "explore_gather", false, nil,
                        "数据回写失败: " .. tostring(reason), reqKey)
                end,
            })
        end,
        error = function(code, reason)
            Reply(userId, "explore_gather", false, nil,
                "读取玩家数据失败: " .. tostring(reason), reqKey)
        end,
    })
end

-- ============================================================================
-- 试炼结算
-- ============================================================================

--- 试炼结算：校验声称进度 + 发放灵石
---@param userId number
---@param params table { trialId, trialType, cleared, serverId }
---@param reqKey string
function M.DoTrialSettle(userId, params, reqKey)
    local trialId   = params.trialId
    local trialType = params.trialType
    local cleared   = tonumber(params.cleared) or 0

    local def = GetTrialDef(trialId)
    if not def then
        Reply(userId, "trial_settle", false, nil, "未知试炼: " .. tostring(trialId), reqKey)
        return
    end

    if trialType ~= def.type then
        Reply(userId, "trial_settle", false, nil, "试炼类型不匹配", reqKey)
        return
    end

    local playerKey = GetPlayerKey(params)

    serverCloud:Get(userId, playerKey, {
        ok = function(scores)
            local playerData = scores or {}
            local tier = playerData.tier or 1

            -- 校验解锁条件
            if def.unlockTier and tier < def.unlockTier then
                Reply(userId, "trial_settle", false, nil,
                    "境界不足，需要达到 " .. def.unlockTier .. " 阶", reqKey)
                return
            end

            -- 校验声称进度合理性
            local maxProgress = MaxReasonableProgress(tier, trialType)
            if cleared > maxProgress then
                print("[ServerCombat] 试炼进度异常 uid=" .. tostring(userId)
                    .. " trial=" .. trialId .. " claimed=" .. cleared
                    .. " max=" .. maxProgress)
                cleared = maxProgress  -- 截断到合理值
            end

            -- 闯关类型：检查是否超过 maxFloor
            if trialType == "闯关" and def.maxFloor then
                if not playerData.trials then playerData.trials = {} end
                local startFloor = (playerData.trials[trialId] or 0) + 1
                local endFloor = startFloor + cleared - 1
                if endFloor > def.maxFloor then
                    cleared = math.max(0, def.maxFloor - startFloor + 1)
                end
            end

            -- 计算奖励
            local reward = 0
            if trialType == "闯关" then
                reward = cleared * REWARD_PER_FLOOR
            elseif trialType == "生存" then
                reward = cleared * REWARD_PER_WAVE
            elseif trialType == "限时" then
                reward = cleared * REWARD_PER_KILL
            end

            -- 更新进度
            if not playerData.trials then playerData.trials = {} end
            if trialType == "闯关" then
                -- 闯关：累加
                local prevBest = playerData.trials[trialId] or 0
                local newFloor = prevBest + cleared
                if def.maxFloor then
                    newFloor = math.min(newFloor, def.maxFloor)
                end
                playerData.trials[trialId] = newFloor
            else
                -- 生存/限时：取最大值
                local prevBest = playerData.trials[trialId] or 0
                if cleared > prevBest then
                    playerData.trials[trialId] = cleared
                end
            end

            -- 发放灵石
            if reward > 0 then
                serverCloud.money:Add(userId, "lingStone", reward)
            end

            -- 回写 playerData
            serverCloud:Set(userId, playerKey, playerData, {
                ok = function()
                    Reply(userId, "trial_settle", true, {
                        trialId = trialId,
                        cleared = cleared,
                        reward  = reward,
                        best    = playerData.trials[trialId] or 0,
                    }, nil, reqKey)
                end,
                error = function(code, reason)
                    -- money 已发放
                    Reply(userId, "trial_settle", true, {
                        trialId = trialId,
                        cleared = cleared,
                        reward  = reward,
                        warning = "进度回写失败",
                    }, nil, reqKey)
                end,
            })
        end,
        error = function(code, reason)
            Reply(userId, "trial_settle", false, nil,
                "读取玩家数据失败: " .. tostring(reason), reqKey)
        end,
    })
end

return M
