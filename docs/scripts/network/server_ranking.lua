-- ============================================================================
-- 《问道长生》服务端排行榜自动计算模块
-- 职责：玩家数据保存后自动计算并写入排行榜 iscores
-- 触发：由 server_cloud_proxy.DoBatchSet 成功后调用
-- ============================================================================

---@diagnostic disable-next-line: undefined-global
local cjson = cjson

local M = {}

-- ============================================================================
-- 排行榜计算逻辑（与 game_player.lua 保持一致）
-- ============================================================================

--- 编码境界为排行榜整数: tier*100 + sub*10
---@param tier number
---@param sub number
---@return number
local function EncodeRealm(tier, sub)
    return (tier or 1) * 100 + (sub or 1) * 10
end

--- 计算战力值
---@param data table 玩家数据
---@return number
local function CalcPower(data)
    return math.floor(
        (data.attack or 0)
        + (data.defense or 0) * 0.8
        + (data.speed or 0) * 0.5
        + (data.hpMax or 0) / 10
        + (data.mpMax or 0) / 10
    )
end

-- ============================================================================
-- 公开接口
-- ============================================================================

--- 根据玩家数据自动计算并写入排行榜
--- 由 cloud_proxy 在 BatchSet 写入 player 数据成功后调用
---@param userId number
---@param playerData table 刚写入的玩家数据
---@param groupId number 服务器组 ID（用于生成排行榜 key）
---@param callback? fun(success: boolean, reason?: string)
function M.CalcAndWrite(userId, playerData, groupId, callback)
    if not serverCloud then
        if callback then callback(false, "serverCloud 不可用") end
        return
    end

    local realmKey  = "g" .. groupId .. "_realm"
    local powerKey  = "g" .. groupId .. "_power"
    local wealthKey = "g" .. groupId .. "_wealth"

    local realmScore = EncodeRealm(playerData.tier, playerData.sub)
    local powerScore = CalcPower(playerData)

    -- 需要查询 serverCloud.money 获取财富
    serverCloud.money:Get(userId, {
        ok = function(moneys)
            local lingStone   = moneys.lingStone or 0
            local spiritStone = moneys.spiritStone or 0
            local wealthScore = lingStone + spiritStone * 100

            serverCloud:BatchSet(userId)
                :SetInt(realmKey,  realmScore)
                :SetInt(powerKey,  powerScore)
                :SetInt(wealthKey, wealthScore)
                :Save("auto_ranking", {
                    ok = function()
                        print("[ServerRanking] 排行榜更新 uid=" .. tostring(userId)
                            .. " realm=" .. realmScore
                            .. " power=" .. powerScore
                            .. " wealth=" .. wealthScore)
                        if callback then callback(true) end
                    end,
                    error = function(code, reason)
                        print("[ServerRanking] 排行榜写入失败 uid=" .. tostring(userId)
                            .. " " .. tostring(reason))
                        if callback then callback(false, tostring(reason)) end
                    end,
                })
        end,
        error = function(code, reason)
            -- money 查询失败，仍写入 realm 和 power（wealth 用 0）
            print("[ServerRanking] money查询失败，写入部分排行榜 uid=" .. tostring(userId))
            serverCloud:BatchSet(userId)
                :SetInt(realmKey,  realmScore)
                :SetInt(powerKey,  powerScore)
                :SetInt(wealthKey, 0)
                :Save("auto_ranking_partial", {
                    ok = function()
                        if callback then callback(true) end
                    end,
                    error = function(c2, r2)
                        if callback then callback(false, tostring(r2)) end
                    end,
                })
        end,
    })
end

return M
