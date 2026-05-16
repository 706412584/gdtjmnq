-- ============================================================================
-- 《问道长生》服务端修炼/渡劫模块
-- 职责：渡劫结果服务端判定 + 小境界突破校验
-- 安全：随机数在服务端生成，客户端无法伪造渡劫结果
-- ============================================================================

local Shared = require("network.shared")
local EVENTS = Shared.EVENTS
local DataRealms  = require("data_realms")
local DataFormulas = require("data_formulas")
---@diagnostic disable-next-line: undefined-global
local cjson = cjson

local M = {}
local deps_ = nil

-- ============================================================================
-- 初始化
-- ============================================================================

---@param deps table { SendToClient }
function M.Init(deps)
    deps_ = deps
    print("[ServerCultivation] 修炼/渡劫模块初始化完成")
end

-- ============================================================================
-- 工具函数
-- ============================================================================

local function GetPlayerKey(params)
    local serverId = params.serverId or 1
    return "s" .. serverId .. "_player"
end

local function Reply(userId, action, success, data, msg)
    local vm = VariantMap()
    vm["Action"]  = Variant(action)
    vm["Success"] = Variant(success)
    vm["Data"]    = Variant(cjson.encode(data or {}))
    vm["Msg"]     = Variant(msg or "")
    deps_.SendToClient(userId, EVENTS.CULTIVATION_RESP, vm)
end

--- 计算 cultivationMax（与 game_player.lua AttachDerived 逻辑一致）
local function GetNextCultivationReq(tier, sub)
    if sub < 3 then
        return DataRealms.GetCultivationReq(tier, sub + 1)
    elseif tier < 10 then
        return DataRealms.GetCultivationReq(tier + 1, 1)
    else
        return DataRealms.GetCultivationReq(10, 3)
    end
end

--- 重算派生属性（服务端精简版，与 game_player.lua AttachDerived 保持一致）
local function RefreshDerived(data)
    local tier = data.tier or 1
    local sub  = data.sub or 1
    data.realmName      = DataRealms.GetFullName(tier, sub)
    data.cultivationMax = GetNextCultivationReq(tier, sub)
    local realm = DataRealms.GetRealm(tier)
    data.lifespanMax    = realm and realm.lifespan or 100
end

-- ============================================================================
-- 请求分发
-- ============================================================================

---@param userId number
---@param eventData any
function M.HandleCultivationOp(userId, eventData)
    if not serverCloud then
        Reply(userId, "unknown", false, nil, "serverCloud 不可用")
        return
    end

    local action    = eventData["Action"]:GetString()
    local paramsStr = eventData["Params"]:GetString()

    local ok, params = pcall(cjson.decode, paramsStr)
    if not ok then
        Reply(userId, action, false, nil, "参数解析失败")
        return
    end

    if action == "tribulation" then
        M.DoTribulation(userId, params)
    elseif action == "advance_sub" then
        M.DoAdvanceSub(userId, params)
    else
        Reply(userId, action, false, nil, "未知操作: " .. tostring(action))
    end
end

-- ============================================================================
-- 渡劫（服务端判定）
-- ============================================================================

--- 渡劫：服务端校验条件 + 消耗丹药 + 投骰判定 + 写入结果
---@param userId number
---@param params table { serverId, pillNames?: string[] }
function M.DoTribulation(userId, params)
    local playerKey = GetPlayerKey(params)
    local pillNames = params.pillNames or {}

    serverCloud:Get(userId, playerKey, {
        ok = function(playerData)
            playerData = playerData or {}
            local tier = playerData.tier or 1
            local sub  = playerData.sub or 1
            local cult = playerData.cultivation or 0
            local cultMax = GetNextCultivationReq(tier, sub)

            -- 校验渡劫条件
            if sub ~= 3 then
                Reply(userId, "tribulation", false, nil, "必须在大成期才能渡劫")
                return
            end
            if cult < cultMax then
                Reply(userId, "tribulation", false, nil, "修为不足")
                return
            end
            if tier >= 10 then
                Reply(userId, "tribulation", false, nil, "已达最高境界")
                return
            end

            local targetTier = tier + 1
            local trib = DataRealms.GetTribulation(targetTier)
            if not trib then
                Reply(userId, "tribulation", false, nil, "渡劫配置不存在")
                return
            end

            -- 消耗丹药并计算加成
            local pillBonus = 0
            local usedPills = {}
            local hasQingxin = false

            if #pillNames > 0 then
                for _, pName in ipairs(pillNames) do
                    local found = false
                    for _, pill in ipairs(playerData.pills or {}) do
                        if pill.name == pName and (pill.count or 0) > 0 then
                            pill.count = pill.count - 1
                            found = true
                            break
                        end
                    end
                    if found then
                        usedPills[#usedPills + 1] = pName
                        if pName == "筑基丹" then
                            pillBonus = pillBonus + 20
                        elseif pName == "破劫丹" then
                            pillBonus = pillBonus + 30
                        elseif pName == "清心丹" then
                            hasQingxin = true
                        end
                    end
                end
            end

            -- 服务端投骰
            local rate = DataFormulas.CalcBreakRate(targetTier, pillBonus)
            local roll = math.random(100)
            local success = roll <= rate

            if success then
                -- 成功：更新境界 + 应用突破加成
                playerData.tier = targetTier
                playerData.sub  = 1
                playerData.cultivation = 0

                -- 属性加成（与 GamePlayer.ApplyBreakBonus 一致）
                local b = DataRealms.GetBreakBonus(tier)
                if b then
                    playerData.attack  = (playerData.attack or 0)  + b.atk
                    playerData.defense = (playerData.defense or 0) + b.def
                    playerData.hpMax   = (playerData.hpMax or 0)   + b.hp
                    playerData.hp      = playerData.hpMax
                    playerData.speed   = (playerData.speed or 0)   + b.spd
                    playerData.crit    = (playerData.crit or 0)    + b.crit
                    playerData.sense   = (playerData.sense or 0)   + (b.sense or 0)
                end

                RefreshDerived(playerData)
            else
                -- 失败：扣修为
                local cost = DataFormulas.CalcBreakFailCost(cult)
                playerData.cultivation = math.max(0, cult - cost)
                -- 清心丹保护道心（目前无 daoHeart 数值系统，预留）
            end

            -- 回写 playerData
            serverCloud:Set(userId, playerKey, playerData, {
                ok = function()
                    local newName = DataRealms.GetFullName(
                        playerData.tier or 1, playerData.sub or 1)
                    Reply(userId, "tribulation", true, {
                        success     = success,
                        targetTier  = targetTier,
                        newName     = newName,
                        rate        = rate,
                        roll        = roll,
                        usedPills   = usedPills,
                        hasQingxin  = hasQingxin,
                        failCost    = not success and DataFormulas.CalcBreakFailCost(cult) or 0,
                    })
                end,
                error = function(code, reason)
                    Reply(userId, "tribulation", false, nil,
                        "数据回写失败: " .. tostring(reason))
                end,
            })
        end,
        error = function(code, reason)
            Reply(userId, "tribulation", false, nil,
                "读取数据失败: " .. tostring(reason))
        end,
    })
end

-- ============================================================================
-- 小境界突破
-- ============================================================================

--- 小境界突破：服务端校验修为 + 直接升级
---@param userId number
---@param params table { serverId }
function M.DoAdvanceSub(userId, params)
    local playerKey = GetPlayerKey(params)

    serverCloud:Get(userId, playerKey, {
        ok = function(playerData)
            playerData = playerData or {}
            local tier = playerData.tier or 1
            local sub  = playerData.sub or 1
            local cult = playerData.cultivation or 0
            local cultMax = GetNextCultivationReq(tier, sub)

            if sub >= 3 then
                Reply(userId, "advance_sub", false, nil, "已达大成期，需渡劫突破")
                return
            end
            if cult < cultMax then
                Reply(userId, "advance_sub", false, nil, "修为不足")
                return
            end

            -- 升级
            playerData.sub = sub + 1
            playerData.cultivation = 0
            RefreshDerived(playerData)

            serverCloud:Set(userId, playerKey, playerData, {
                ok = function()
                    Reply(userId, "advance_sub", true, {
                        tier    = tier,
                        sub     = playerData.sub,
                        newName = DataRealms.GetFullName(tier, playerData.sub),
                    })
                end,
                error = function(code, reason)
                    Reply(userId, "advance_sub", false, nil,
                        "数据回写失败: " .. tostring(reason))
                end,
            })
        end,
        error = function(code, reason)
            Reply(userId, "advance_sub", false, nil,
                "读取数据失败: " .. tostring(reason))
        end,
    })
end

return M
