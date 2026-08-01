-- ============================================================================
-- Leaderboard - 排行榜系统
-- Project Smith / P3-C2
--
-- 基于 clientCloud iscores 实现云排行榜。
-- 排行维度:
--   1. fame（声望）- 综合排行
--   2. best_quality_score（最佳品质分数）- 锻造实力排行
--
-- 使用方式:
--   local Leaderboard = require("Core.Leaderboard")
--   Leaderboard.SubmitScore(fame, bestScore)
--   Leaderboard.FetchRankList("fame", 20, function(list) ... end)
-- ============================================================================

local EventBus  = require("Core.EventBus")
local GameState = require("Core.GameState")

local Leaderboard = {}

-- ==================== 排行榜 Key ====================

local RANK_KEYS = {
    fame = "smith_fame",
    bestScore = "smith_best_score",
    totalForged = "smith_total_forged",
}

-- ==================== 提交分数 ====================

--- 提交当前玩家的排行榜数据
--- 在每次订单完成、声望变动时调用
function Leaderboard.SubmitScore()
    if not GameState.CanSaveToCloud() or not rawget(_G, "clientCloud") then
        return
    end

    local fame = GameState.GetFame()
    local bestTier = GameState.GetStat("bestQualityTier")
    local totalForged = GameState.GetStat("totalForged")

    clientCloud:BatchSet()
        :SetInt(RANK_KEYS.fame, math.floor(fame))
        :SetInt(RANK_KEYS.bestScore, math.floor(bestTier))
        :SetInt(RANK_KEYS.totalForged, math.floor(totalForged))
        :Save("排行榜更新", {
            ok = function()
                print("[Leaderboard] Score submitted: fame=" .. fame
                    .. " bestTier=" .. bestTier
                    .. " totalForged=" .. totalForged)
            end,
            error = function(code, reason)
                print("[Leaderboard] Submit error: " .. tostring(reason))
            end
        })
end

-- ==================== 获取排行榜 ====================

--- 获取排行榜列表（含昵称）
---@param rankType string "fame" | "bestScore" | "totalForged"
---@param topN number 获取前 N 名
---@param callback function(list:table[]) 回调，list 每项包含 { rank, userId, nickname, score, isMe }
function Leaderboard.FetchRankList(rankType, topN, callback)
    if not GameState.CanSaveToCloud() or not rawget(_G, "clientCloud") then
        if callback then callback({}) end
        return
    end

    local key = RANK_KEYS[rankType]
    if not key then
        print("[Leaderboard] Unknown rank type: " .. tostring(rankType))
        if callback then callback({}) end
        return
    end

    -- 附加字段：获取其他维度数据
    local extraKeys = {}
    for k, v in pairs(RANK_KEYS) do
        if k ~= rankType then
            extraKeys[#extraKeys + 1] = v
        end
    end

    clientCloud:GetRankList(key, 0, topN or 20, {
        ok = function(rankList)
            local leaderboard = {}
            local userIds = {}
            for i, item in ipairs(rankList) do
                local entry = {
                    rank = i,
                    userId = item.userId,
                    nickname = "",
                    score = item.iscore and item.iscore[key] or 0,
                    fame = item.iscore and item.iscore[RANK_KEYS.fame] or 0,
                    bestScore = item.iscore and item.iscore[RANK_KEYS.bestScore] or 0,
                    totalForged = item.iscore and item.iscore[RANK_KEYS.totalForged] or 0,
                    isMe = item.userId == clientCloud.userId,
                }
                leaderboard[#leaderboard + 1] = entry
                userIds[#userIds + 1] = item.userId
            end

            -- 查询昵称
            if #userIds > 0 then
                GetUserNickname({
                    userIds = userIds,
                    onSuccess = function(nicknames)
                        local map = {}
                        for _, info in ipairs(nicknames) do
                            map[info.userId] = info.nickname or ""
                        end
                        for _, entry in ipairs(leaderboard) do
                            entry.nickname = map[entry.userId] or "匿名铁匠"
                        end
                        if callback then callback(leaderboard) end
                    end,
                    onError = function(errorCode)
                        -- 昵称查询失败，仍返回数据
                        for _, entry in ipairs(leaderboard) do
                            entry.nickname = "匿名铁匠"
                        end
                        if callback then callback(leaderboard) end
                    end,
                })
            else
                if callback then callback(leaderboard) end
            end
        end,
        error = function(code, reason)
            print("[Leaderboard] Fetch error: " .. tostring(reason))
            if callback then callback({}) end
        end,
    }, table.unpack(extraKeys))
end

--- 获取当前玩家的排名
---@param rankType string "fame" | "bestScore" | "totalForged"
---@param callback function(rank:number|nil, score:number)
function Leaderboard.FetchMyRank(rankType, callback)
    if not GameState.CanSaveToCloud() or not rawget(_G, "clientCloud") then
        if callback then callback(nil, 0) end
        return
    end

    local key = RANK_KEYS[rankType]
    if not key then
        if callback then callback(nil, 0) end
        return
    end

    local myId = clientCloud.userId
    if not myId then
        if callback then callback(nil, 0) end
        return
    end

    clientCloud:GetUserRank(myId, key, {
        ok = function(rank, scoreValue)
            if callback then callback(rank, scoreValue or 0) end
        end,
        error = function(code, reason)
            print("[Leaderboard] MyRank error: " .. tostring(reason))
            if callback then callback(nil, 0) end
        end,
    })
end

--- 获取排行榜总人数
---@param rankType string
---@param callback function(total:number)
function Leaderboard.FetchTotal(rankType, callback)
    if not GameState.CanSaveToCloud() or not rawget(_G, "clientCloud") then
        if callback then callback(0) end
        return
    end

    local key = RANK_KEYS[rankType]
    if not key then
        if callback then callback(0) end
        return
    end

    clientCloud:GetRankTotal(key, {
        ok = function(total)
            if callback then callback(total or 0) end
        end,
        error = function(code, reason)
            print("[Leaderboard] Total error: " .. tostring(reason))
            if callback then callback(0) end
        end,
    })
end

-- ==================== 自动提交 ====================

--- 注册事件监听，在奖励领取后自动提交分数
function Leaderboard.Init()
    EventBus.On("reward_collected", function(data)
        -- 延迟一帧提交，确保 GameState 已更新
        Leaderboard.SubmitScore()
    end)
    print("[Leaderboard] Initialized, auto-submit on reward_collected")
end

return Leaderboard
