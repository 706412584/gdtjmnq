-- ============================================================================
-- 《问道长生》试炼系统
-- 职责：四种试炼的挑战逻辑、进度追踪、奖励结算
-- 设计：Can/Do 模式，复用 DataFormulas 战斗系统
-- 改造：返回逐场逐回合战斗数据，供 UI 可视化播放
-- ============================================================================

local GamePlayer   = require("game_player")
local DataWorld    = require("data_world")
local DataFormulas = require("data_formulas")
local Theme        = require("ui_theme")

---@diagnostic disable-next-line: undefined-global
local cjson = cjson

local M = {}

-- ============================================================================
-- 常量
-- ============================================================================

local FLOOR_SCALE = {
    atk = 5,
    def = 3,
    hp  = 40,
}

local REWARD_PER_FLOOR  = 15
local REWARD_PER_WAVE   = 20
local REWARD_PER_KILL   = 10

local MIJING_MAX_ROUNDS = 30

-- ============================================================================
-- 内部工具
-- ============================================================================

---@return table|nil
local function EnsureTrialData()
    local p = GamePlayer.Get()
    if not p then return nil end
    if not p.trials then p.trials = {} end
    return p
end

---@param floor number
---@param baseName string
---@return table
local function MakeEnemy(floor, baseName)
    return {
        name    = baseName .. "（第" .. floor .. "层）",
        attack  = 10 + floor * FLOOR_SCALE.atk,
        defense = 5  + floor * FLOOR_SCALE.def,
        hp      = 50 + floor * FLOOR_SCALE.hp,
        hit     = 85,
        dodge   = math.min(30, 5 + math.floor(floor / 5)),
        crit    = math.min(25, 3 + math.floor(floor / 8)),
    }
end

---@return string
local function RandomMonsterName()
    local monsters = DataWorld.MONSTERS
    if #monsters == 0 then return "妖兽" end
    return monsters[math.random(1, #monsters)].name
end

--- 根据怪物名称匹配图片
---@param name string
---@return string
local function GetMonsterImageByName(name)
    -- 去掉"（第X层）"后缀取纯名
    local pureName = name:match("^(.+)（") or name
    for _, m in ipairs(Theme.monsters) do
        if m.name:find(pureName, 1, true) or pureName:find(m.name, 1, true) then
            return m.image
        end
    end
    -- 按哈希兜底
    local idx = (#pureName % #Theme.monsters) + 1
    return Theme.monsters[idx].image
end

--- 执行单场战斗，返回逐回合数据
---@param enemy table
---@return boolean win, string log, table roundsData
local function RunFight(enemy)
    local p = GamePlayer.Get()
    local pAtk   = p.attack or 30
    local pDef   = p.defense or 10
    local pHP    = p.hp or 800
    local pHPMax = p.hpMax or pHP
    local pCrit  = p.crit or 5
    local pHit   = p.hit or 90
    local pDodge = p.dodge or 5

    local eHP = enemy.hp
    local eHPMax = enemy.hp
    local maxRounds = 20
    local roundsData = {}
    local win = false
    local finished = false

    for r = 1, maxRounds do
        if finished then break end
        local round = {
            num = r,
            playerAction = nil,
            enemyAction = nil,
            playerHP = 0, playerHPMax = pHPMax,
            enemyHP = 0, enemyHPMax = eHPMax,
            finished = false, win = false,
        }

        -- 玩家攻击
        local pr = DataFormulas.ResolveAttack(
            { attack = pAtk, hit = pHit, crit = pCrit, skillAtkBonus = 0 },
            { defense = enemy.defense, dodge = enemy.dodge or 0, hp = eHP }
        )
        if pr.hit then
            eHP = eHP - pr.damage
            round.playerAction = { hit = true, crit = pr.crit, damage = pr.damage }
        else
            round.playerAction = { hit = false, crit = false, damage = 0 }
        end

        if eHP <= 0 then
            eHP = 0
            round.playerHP = pHP; round.enemyHP = eHP
            round.finished = true; round.win = true
            roundsData[#roundsData + 1] = round
            win = true; finished = true
            goto nextRound
        end

        -- 敌方攻击
        local er = DataFormulas.ResolveAttack(
            { attack = enemy.attack, hit = enemy.hit or 85, crit = enemy.crit or 5, skillAtkBonus = 0 },
            { defense = pDef, dodge = pDodge, hp = pHP }
        )
        if er.hit then
            pHP = pHP - er.damage
            round.enemyAction = { hit = true, crit = er.crit, damage = er.damage }
        else
            round.enemyAction = { hit = false, crit = false, damage = 0 }
        end

        if pHP <= 0 then
            pHP = 0
            round.playerHP = pHP; round.enemyHP = eHP
            round.finished = true; round.win = false
            roundsData[#roundsData + 1] = round
            win = false; finished = true
            goto nextRound
        end

        round.playerHP = pHP; round.enemyHP = eHP
        roundsData[#roundsData + 1] = round

        ::nextRound::
    end

    local log
    if win then
        log = "击败" .. enemy.name
    elseif finished then
        log = "败于" .. enemy.name
    else
        log = "与" .. enemy.name .. "僵持不下"
    end

    return win, log, roundsData
end

-- ============================================================================
-- 公开接口：查询
-- ============================================================================

---@return table[]
function M.GetAllTrials()
    local p = EnsureTrialData()
    if not p then return {} end
    local playerTier = p.tier or 1

    local result = {}
    for _, def in ipairs(DataWorld.TRIALS) do
        local unlocked = true
        if def.unlockTier and playerTier < def.unlockTier then
            unlocked = false
        end

        local best = p.trials[def.id] or 0
        local progressText = ""
        if def.type == "闯关" then
            progressText = "已通关: " .. best .. "/" .. (def.maxFloor or "?") .. "层"
        elseif def.type == "生存" then
            progressText = "最佳: 第" .. best .. "波"
        elseif def.type == "限时" then
            progressText = "最高击杀: " .. best
        end

        result[#result + 1] = {
            id         = def.id,
            name       = def.name,
            type       = def.type,
            desc       = def.desc,
            rewards    = def.rewards,
            maxFloor   = def.maxFloor,
            best       = best,
            unlocked   = unlocked,
            unlockTier = def.unlockTier,
            progressText = progressText,
        }
    end
    return result
end

-- ============================================================================
-- 公开接口：挑战（预计算，返回战斗数据给 UI）
-- ============================================================================

---@param trialId string
---@return boolean, string|nil
function M.CanChallenge(trialId)
    local p = EnsureTrialData()
    if not p then return false, "数据未加载" end
    if (p.hp or 0) <= 0 then return false, "气血耗尽，无法挑战" end

    local def = DataWorld.GetTrial(trialId)
    if not def then return false, "未知试炼" end

    if def.unlockTier and (p.tier or 1) < def.unlockTier then
        return false, "需要达到更高境界才能解锁"
    end

    return true, nil
end

--- 预计算闯关试炼（返回全部场次的战斗数据，不立即结算）
---@param trialId string
---@param maxAttemptFloors? number
---@return table|nil result, string|nil errMsg
function M.PrepareFloor(trialId, maxAttemptFloors)
    local ok, reason = M.CanChallenge(trialId)
    if not ok then return nil, reason end

    local p = EnsureTrialData()
    local def = DataWorld.GetTrial(trialId)
    if not def then return nil, "未知试炼" end

    maxAttemptFloors = maxAttemptFloors or 5
    local startFloor = (p.trials[trialId] or 0) + 1
    local maxFloor = def.maxFloor or 100

    local fights = {}   -- 每场战斗: { floor, enemy, win, log, rounds, monsterImg }
    local clearedCount = 0
    local stopped = false

    for f = startFloor, math.min(startFloor + maxAttemptFloors - 1, maxFloor) do
        if stopped then break end
        local enemyName = RandomMonsterName()
        local enemy = MakeEnemy(f, enemyName)
        local win, log, rounds = RunFight(enemy)

        fights[#fights + 1] = {
            floor      = f,
            enemy      = enemy,
            win        = win,
            log        = log,
            rounds     = rounds,
            monsterImg = GetMonsterImageByName(enemyName),
        }

        if win then
            clearedCount = clearedCount + 1
        else
            stopped = true
        end
        if (p.hp or 0) <= 0 then stopped = true end
    end

    local rewardStone = clearedCount * REWARD_PER_FLOOR
    return {
        trialId   = trialId,
        trialName = def.name,
        type      = "闯关",
        fights    = fights,
        cleared   = clearedCount,
        reward    = rewardStone,
        startFloor = startFloor,
    }, nil
end

--- 预计算生存试炼
---@param trialId string
---@return table|nil, string|nil
function M.PrepareSurvival(trialId)
    local ok, reason = M.CanChallenge(trialId)
    if not ok then return nil, reason end

    local p = EnsureTrialData()
    local def = DataWorld.GetTrial(trialId)
    if not def then return nil, "未知试炼" end

    local fights = {}
    local wave = 0
    local maxWaves = 50

    while wave < maxWaves do
        wave = wave + 1
        local enemyName = RandomMonsterName()
        local enemy = MakeEnemy(wave, enemyName)
        local win, log, rounds = RunFight(enemy)

        fights[#fights + 1] = {
            floor      = wave,
            enemy      = enemy,
            win        = win,
            log        = log,
            rounds     = rounds,
            monsterImg = GetMonsterImageByName(enemyName),
        }

        if not win then break end
        if (p.hp or 0) <= 0 then break end
    end

    local rewardStone = wave * REWARD_PER_WAVE
    return {
        trialId   = trialId,
        trialName = def.name,
        type      = "生存",
        fights    = fights,
        cleared   = wave,
        reward    = rewardStone,
    }, nil
end

--- 预计算限时击杀试炼
---@param trialId string
---@return table|nil, string|nil
function M.PrepareTimedKill(trialId)
    local ok, reason = M.CanChallenge(trialId)
    if not ok then return nil, reason end

    local p = EnsureTrialData()
    local def = DataWorld.GetTrial(trialId)
    if not def then return nil, "未知试炼" end

    local fights = {}
    local kills = 0
    local difficulty = 1

    for _ = 1, MIJING_MAX_ROUNDS do
        local enemyName = RandomMonsterName()
        local enemy = MakeEnemy(difficulty, enemyName)
        local win, log, rounds = RunFight(enemy)

        fights[#fights + 1] = {
            floor      = difficulty,
            enemy      = enemy,
            win        = win,
            log        = log,
            rounds     = rounds,
            monsterImg = GetMonsterImageByName(enemyName),
        }

        if win then
            kills = kills + 1
            difficulty = difficulty + 1
        else
            break
        end
        if (p.hp or 0) <= 0 then break end
    end

    local rewardStone = kills * REWARD_PER_KILL
    return {
        trialId   = trialId,
        trialName = def.name,
        type      = "限时",
        fights    = fights,
        cleared   = kills,
        reward    = rewardStone,
    }, nil
end

--- 统一预计算入口（根据类型分派）
---@param trialId string
---@return table|nil, string|nil
function M.PrepareChallenge(trialId)
    local def = DataWorld.GetTrial(trialId)
    if not def then return nil, "未知试炼" end

    if def.type == "闯关" then
        return M.PrepareFloor(trialId)
    elseif def.type == "生存" then
        return M.PrepareSurvival(trialId)
    elseif def.type == "限时" then
        return M.PrepareTimedKill(trialId)
    end
    return nil, "不支持的试炼类型"
end

--- 结算试炼（UI 播放完成后调用）
---@param result table PrepareChallenge 返回的结果
---@param callback? fun(ok: boolean, summary: string) 网络模式异步回调
---@return boolean|nil ok, string|nil summary
function M.SettleChallenge(result, callback)
    if not result then
        if callback then callback(false, "无数据") end
        return false, "无数据"
    end

    local p = EnsureTrialData()
    if not p then
        if callback then callback(false, "玩家数据未加载") end
        return false, "玩家数据未加载"
    end

    local def = DataWorld.GetTrial(result.trialId)
    if not def then
        if callback then callback(false, "未知试炼") end
        return false, "未知试炼"
    end

    ---@diagnostic disable-next-line: undefined-global
    if IsNetworkMode() then
        -- ── 网络模式：发送到服务端结算 ──
        local GameServer = require("game_server")
        local Shared     = require("network.shared")
        local ClientNet  = require("network.client_net")

        local params = cjson.encode({
            trialId   = result.trialId,
            trialType = result.type,
            cleared   = result.cleared,
            serverId  = GameServer.GetCurrentServer().id,
        })
        local vm = VariantMap()
        vm["Action"] = Variant("trial_settle")
        vm["Params"] = Variant(params)

        -- 保存回调和结果供回复时使用
        M._pendingTrialCallback = callback
        M._pendingTrialResult   = result

        ClientNet.SendToServer(Shared.EVENTS.REQ_COMBAT_SETTLE, vm)
        return nil, nil  -- 异步
    end

    -- ── 单机模式：原逻辑 ──
    local summary = ""

    if result.type == "闯关" then
        for _, fight in ipairs(result.fights) do
            if fight.win then
                p.trials[result.trialId] = fight.floor
            end
        end
        local best = p.trials[result.trialId] or 0
        if result.cleared > 0 then
            summary = "<c=gold>" .. result.trialName .. "</c>：闯过<c=yellow>" ..
                result.cleared .. "层</c>（当前第" .. best .. "层），获得<c=yellow>灵石" ..
                result.reward .. "</c>"
        else
            summary = "<c=gold>" .. result.trialName .. "</c>：挑战失败，止步第<c=red>" ..
                result.startFloor .. "层</c>"
        end

    elseif result.type == "生存" then
        local prevBest = p.trials[result.trialId] or 0
        if result.cleared > prevBest then
            p.trials[result.trialId] = result.cleared
        end
        local best = p.trials[result.trialId] or result.cleared
        summary = "<c=gold>" .. result.trialName .. "</c>：坚持到第<c=yellow>" ..
            result.cleared .. "波</c>（最佳第" .. best .. "波），获得<c=yellow>灵石" ..
            result.reward .. "</c>"

    elseif result.type == "限时" then
        local prevBest = p.trials[result.trialId] or 0
        if result.cleared > prevBest then
            p.trials[result.trialId] = result.cleared
        end
        local best = p.trials[result.trialId] or result.cleared
        summary = "<c=gold>" .. result.trialName .. "</c>：击杀<c=yellow>" ..
            result.cleared .. "只</c>（最高" .. best .. "只），获得<c=yellow>灵石" ..
            result.reward .. "</c>"
    end

    -- 发放灵石
    if result.reward > 0 then
        GamePlayer.AddCurrency("lingStone", result.reward)
    end

    GamePlayer.MarkDirty()
    GamePlayer.AddLog(summary)

    return result.cleared > 0, summary
end

-- ============================================================================
-- 网络模式：试炼结算回复处理（由 game_explore.OnCombatSettleResp 转发）
-- ============================================================================

--- 处理试炼结算服务端回复
---@param data table 解码后的 Data 字段
---@param success boolean
---@param msgStr string
function M.OnTrialSettleResp(data, success, msgStr)
    local p = EnsureTrialData()
    local cb = M._pendingTrialCallback
    local result = M._pendingTrialResult
    M._pendingTrialCallback = nil
    M._pendingTrialResult   = nil

    if not success then
        local msg = "试炼结算失败: " .. (msgStr or "未知错误")
        GamePlayer.AddLog(msg)
        if cb then cb(false, msg) end
        return
    end

    local trialId = data.trialId or (result and result.trialId) or ""
    local cleared = data.cleared or 0
    local reward  = data.reward or 0
    local best    = data.best or 0

    -- 乐观同步本地进度
    if p and p.trials then
        p.trials[trialId] = best
    end

    -- 乐观同步本地灵石
    if reward > 0 then
        GamePlayer.AddCurrencyLocal("lingStone", reward)
    end

    -- 生成摘要
    local trialName = (result and result.trialName) or trialId
    local trialType = (result and result.type) or ""
    local summary = ""

    if trialType == "闯关" then
        if cleared > 0 then
            summary = "<c=gold>" .. trialName .. "</c>：闯过<c=yellow>" ..
                cleared .. "层</c>（当前第" .. best .. "层），获得<c=yellow>灵石" ..
                reward .. "</c>"
        else
            summary = "<c=gold>" .. trialName .. "</c>：挑战失败"
        end
    elseif trialType == "生存" then
        summary = "<c=gold>" .. trialName .. "</c>：坚持到第<c=yellow>" ..
            cleared .. "波</c>（最佳第" .. best .. "波），获得<c=yellow>灵石" ..
            reward .. "</c>"
    elseif trialType == "限时" then
        summary = "<c=gold>" .. trialName .. "</c>：击杀<c=yellow>" ..
            cleared .. "只</c>（最高" .. best .. "只），获得<c=yellow>灵石" ..
            reward .. "</c>"
    else
        summary = "试炼完成，获得灵石" .. reward
    end

    GamePlayer.MarkDirty()
    GamePlayer.AddLog(summary)

    if cb then cb(cleared > 0, summary) end
end

-- ============================================================================
-- 兼容旧接口：DoChallenge（直接结算，无动画）
-- ============================================================================
function M.DoChallenge(trialId)
    local result, err = M.PrepareChallenge(trialId)
    if not result then return false, err or "挑战失败" end
    return M.SettleChallenge(result)
end

return M
