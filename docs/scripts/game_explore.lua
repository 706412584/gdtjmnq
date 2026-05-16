-- ============================================================================
-- 《问道长生》探索模块
-- 职责：继续探索（随机遭遇 + 简易回合战斗）
-- 设计：Can/Do 模式
-- ============================================================================

local GamePlayer  = require("game_player")
local DataItems   = require("data_items")
local DataFormulas = require("data_formulas")
local GameQuest   = require("game_quest")
local GamePet     = require("game_pet")

---@diagnostic disable-next-line: undefined-global
local cjson = cjson

local M = {}

-- ============================================================================
-- 网络模式：异步结算回调
-- ============================================================================

---@type fun(ok: boolean, msg: string)|nil
local pendingCombatCallback_ = nil
---@type fun(ok: boolean, msg: string)|nil
local pendingGatherCallback_ = nil

-- ============================================================================
-- 探索遭遇表（根据境界阶数范围匹配）
-- ============================================================================
local ENCOUNTERS = {
    -- tierMin/tierMax: 适用境界区间
    { name = "灵草丛",       type = "gather",  tierMin = 1, tierMax = 10, drop = "灵草",     dropCount = { 1, 3 } },
    { name = "矿脉",         type = "gather",  tierMin = 1, tierMax = 10, drop = "矿石",     dropCount = { 1, 2 } },
    { name = "灵泉",         type = "gather",  tierMin = 2, tierMax = 10, drop = "灵泉水",   dropCount = { 1, 1 } },
    { name = "天材地宝",     type = "gather",  tierMin = 4, tierMax = 10, drop = "天材地宝", dropCount = { 1, 1 }, weight = 5 },
    { name = "散修",         type = "combat",  tierMin = 1, tierMax = 3,  atk = 15, def = 10, hp = 100, reward = 20 },
    { name = "妖兽",         type = "combat",  tierMin = 1, tierMax = 5,  atk = 25, def = 15, hp = 200, reward = 40 },
    { name = "精英妖兽",     type = "combat",  tierMin = 3, tierMax = 7,  atk = 50, def = 30, hp = 500, reward = 100 },
    { name = "上古凶兽",     type = "combat",  tierMin = 5, tierMax = 10, atk = 80, def = 50, hp = 1000, reward = 250 },
    { name = "兽骨遗骸",     type = "gather",  tierMin = 1, tierMax = 10, drop = "兽骨",     dropCount = { 1, 2 } },
    { name = "无事发生",     type = "nothing", tierMin = 1, tierMax = 10 },
}

--- 根据当前境界筛选可用遭遇
---@param tier number
---@return table[]
local function GetAvailableEncounters(tier)
    local list = {}
    for _, e in ipairs(ENCOUNTERS) do
        if tier >= e.tierMin and tier <= e.tierMax then
            list[#list + 1] = e
        end
    end
    return list
end

--- 从列表中随机选一个（支持 weight 字段，默认 weight=10）
---@param list table[]
---@return table
local function PickRandom(list)
    local total = 0
    for _, e in ipairs(list) do total = total + (e.weight or 10) end
    local r = math.random(1, total)
    local acc = 0
    for _, e in ipairs(list) do
        acc = acc + (e.weight or 10)
        if r <= acc then return e end
    end
    return list[#list]
end

-- ============================================================================
-- 简易回合战斗（返回逐回合数据，供 UI 动态播放）
-- ============================================================================

--- 执行一次战斗，返回 win, summary, rounds 数据
---@param enemy table { name, atk, def, hp }
---@return boolean win, string summary, table roundsData
local function RunCombat(enemy)
    local p = GamePlayer.Get()
    local pAtk = p.attack or 30
    local pDef = p.defense or 10
    local pHP  = p.hp or 800
    local pHPMax = p.hpMax or pHP
    local pCrit = p.crit or 5
    local pHit  = p.hit or 90
    local pDodge = p.dodge or 5

    local eHP  = enemy.hp
    local eHPMax = enemy.hp
    local eAtk = enemy.atk
    local eDef = enemy.def

    local roundsData = {}
    local roundNum = 0
    local maxRounds = 20
    local win = false
    local finished = false

    while roundNum < maxRounds and not finished do
        roundNum = roundNum + 1
        local round = {
            num = roundNum,
            -- 玩家出手
            playerAction = nil,
            -- 敌方出手
            enemyAction = nil,
            -- 回合结束后双方状态
            playerHP = 0,
            playerHPMax = pHPMax,
            enemyHP = 0,
            enemyHPMax = eHPMax,
            finished = false,
            win = false,
        }

        -- 玩家攻击
        local pResult = DataFormulas.ResolveAttack(
            { attack = pAtk, hit = pHit, crit = pCrit, skillAtkBonus = 0 },
            { defense = eDef, dodge = 0, hp = eHP }
        )
        if pResult.hit then
            eHP = eHP - pResult.damage
            round.playerAction = { hit = true, crit = pResult.crit, damage = pResult.damage }
        else
            round.playerAction = { hit = false, crit = false, damage = 0 }
        end

        if eHP <= 0 then
            eHP = 0
            round.playerHP = pHP
            round.enemyHP = eHP
            round.finished = true
            round.win = true
            roundsData[#roundsData + 1] = round
            win = true
            finished = true
            goto continueLoop
        end

        -- 敌方攻击
        local eResult = DataFormulas.ResolveAttack(
            { attack = eAtk, hit = 85, crit = 5, skillAtkBonus = 0 },
            { defense = pDef, dodge = pDodge, hp = pHP }
        )
        if eResult.hit then
            pHP = pHP - eResult.damage
            round.enemyAction = { hit = true, crit = eResult.crit, damage = eResult.damage }
        else
            round.enemyAction = { hit = false, crit = false, damage = 0 }
        end

        if pHP <= 0 then
            pHP = 0
            round.playerHP = pHP
            round.enemyHP = eHP
            round.finished = true
            round.win = false
            roundsData[#roundsData + 1] = round
            win = false
            finished = true
            goto continueLoop
        end

        round.playerHP = pHP
        round.enemyHP = eHP
        roundsData[#roundsData + 1] = round

        ::continueLoop::
    end

    local summary
    if win then
        summary = "战胜" .. enemy.name .. "（" .. #roundsData .. "回合）"
    elseif finished then
        summary = "败于" .. enemy.name .. "（" .. #roundsData .. "回合）"
    else
        summary = "与" .. enemy.name .. "僵持不下，被迫撤退"
    end

    return win, summary, roundsData
end

-- ============================================================================
-- 公开接口
-- ============================================================================

--- 检查是否可以继续探索
---@return boolean, string|nil
function M.CanExplore()
    local p = GamePlayer.Get()
    if not p then return false, "数据未加载" end
    if (p.hp or 0) <= 0 then return false, "气血耗尽，无法探索" end
    return true, nil
end

--- 生成一次遭遇（不执行，仅返回遭遇信息）
---@return table|nil encounter, string|nil reason
function M.GenerateEncounter()
    local ok, reason = M.CanExplore()
    if not ok then return nil, reason end
    local p = GamePlayer.Get()
    local tier = p.tier or 1
    local available = GetAvailableEncounters(tier)
    if #available == 0 then return nil, "无可用遭遇" end
    return PickRandom(available), nil
end

--- 执行战斗遭遇（返回详细战斗数据）
---@param enc table 遭遇数据（combat 类型）
---@return boolean win, string summary, table roundsData
function M.DoCombat(enc)
    return RunCombat(enc)
end

--- 结算战斗结果（发放奖励或扣血）
---@param enc table 遭遇数据
---@param win boolean 是否胜利
---@param summary string 战斗摘要
---@param callback? fun(ok: boolean, msg: string) 网络模式异步回调
---@return boolean|nil ok, string|nil msg  单机模式同步返回；网络模式返回 nil（等回调）
function M.SettleCombat(enc, win, summary, callback)
    local p = GamePlayer.Get()

    ---@diagnostic disable-next-line: undefined-global
    if IsNetworkMode() then
        -- ── 网络模式：发送到服务端结算 ──
        local GameServer = require("game_server")
        local Shared     = require("network.shared")
        local ClientNet  = require("network.client_net")

        local params = cjson.encode({
            encName  = enc.name,
            win      = win,
            serverId = GameServer.GetCurrentServer().id,
        })
        local vm = VariantMap()
        vm["Action"] = Variant("explore_combat")
        vm["Params"] = Variant(params)

        pendingCombatCallback_ = function(ok, msg)
            -- 战败扣血仍由客户端处理（服务端不模拟战斗）
            if not win then
                local hpLoss = math.floor((p.hpMax or 800) * 0.1)
                p.hp = math.max(0, (p.hp or 0) - hpLoss)
                GamePlayer.MarkDirty()
                msg = summary .. "，损失<c=red>气血" .. hpLoss .. "</c>"
                GamePlayer.AddLog(msg)
            end
            if callback then callback(ok, msg) end
        end

        ClientNet.SendToServer(Shared.EVENTS.REQ_COMBAT_SETTLE, vm)
        return nil, nil  -- 异步，等回调
    end

    -- ── 单机模式：原逻辑 ──
    GameQuest.SetMainFlag("explored", true)
    if win then
        local reward = enc.reward or 20
        GamePlayer.AddCurrency("lingStone", reward)
        GameQuest.NotifyAction("kill_monster", 1)
        local captured, petMsg = GamePet.TryCapture()
        local msg = summary .. "，获得<c=yellow>灵石" .. reward .. "</c>"
        if captured and petMsg then
            msg = msg .. "；" .. petMsg
        end
        GamePlayer.AddLog(msg)
        return true, msg
    else
        local hpLoss = math.floor((p.hpMax or 800) * 0.1)
        p.hp = math.max(0, (p.hp or 0) - hpLoss)
        GamePlayer.MarkDirty()
        local msg = summary .. "，损失<c=red>气血" .. hpLoss .. "</c>"
        GamePlayer.AddLog(msg)
        return false, msg
    end
end

--- 执行一次探索（兼容旧逻辑，用于非战斗遭遇）
---@return boolean, string
function M.DoExplore()
    local ok, reason = M.CanExplore()
    if not ok then return false, reason or "无法探索" end

    local p = GamePlayer.Get()
    local tier = p.tier or 1

    local available = GetAvailableEncounters(tier)
    if #available == 0 then return false, "无可用遭遇" end

    local enc = PickRandom(available)

    -- 主线任务标记：已探索
    GameQuest.SetMainFlag("explored", true)

    if enc.type == "nothing" then
        local msg = "探索中...此行<c=gray>无事发生</c>"
        GamePlayer.AddLog(msg)
        return true, msg

    elseif enc.type == "gather" then
        ---@diagnostic disable-next-line: undefined-global
        if IsNetworkMode() then
            -- ── 网络模式：服务端随机 + 发放 ──
            local GameServer = require("game_server")
            local Shared     = require("network.shared")
            local ClientNet  = require("network.client_net")

            local params = cjson.encode({
                encName  = enc.name,
                serverId = GameServer.GetCurrentServer().id,
            })
            local vm = VariantMap()
            vm["Action"] = Variant("explore_gather")
            vm["Params"] = Variant(params)

            pendingGatherCallback_ = nil  -- 清除旧回调，回复在 OnCombatSettleResp 中处理
            ClientNet.SendToServer(Shared.EVENTS.REQ_COMBAT_SETTLE, vm)
            return true, "采集中..."  -- 异步，UI 会在回调后刷新
        end

        -- ── 单机模式：原逻辑 ──
        local min = enc.dropCount[1]
        local max = enc.dropCount[2]
        local count = math.random(min, max)
        GamePlayer.AddItem({
            name = enc.drop,
            count = count,
            rarity = "common",
            desc = "探索获得",
        })
        -- 任务通知：采集灵草
        if enc.drop == "灵草" then
            GameQuest.NotifyAction("gather_herb", count)
        end
        local msg = "发现<c=gold>" .. enc.name .. "</c>，获得<c=yellow>" .. enc.drop .. "x" .. count .. "</c>"
        GamePlayer.AddLog(msg)
        return true, msg

    elseif enc.type == "combat" then
        -- 战斗遭遇：使用新的分步 API
        local win, summary, _ = RunCombat(enc)
        return M.SettleCombat(enc, win, summary)
    end

    return false, "未知遭遇类型"
end

-- ============================================================================
-- 网络模式：服务端回复处理
-- ============================================================================

--- 处理战斗/探索结算回复（由 client_net.lua 调用）
---@param eventData any
function M.OnCombatSettleResp(eventData)
    local action  = eventData["Action"]:GetString()
    local success = eventData["Success"]:GetBool()
    local dataStr = eventData["Data"]:GetString()
    local msgStr  = ""
    pcall(function() msgStr = eventData["Msg"]:GetString() end)

    local ok2, data = pcall(cjson.decode, dataStr)
    if not ok2 then data = {} end

    if action == "explore_combat" then
        if success and data.win then
            local reward = data.reward or 0
            local encName = data.encName or "未知"
            -- 乐观更新客户端货币缓存（服务端已通过 money:Add 发放）
            GamePlayer.AddCurrencyLocal("lingStone", reward)
            GameQuest.SetMainFlag("explored", true)
            GameQuest.NotifyAction("kill_monster", 1)
            local captured, petMsg = GamePet.TryCapture()
            local msg = "战胜" .. encName .. "，获得<c=yellow>灵石" .. reward .. "</c>"
            if captured and petMsg then
                msg = msg .. "；" .. petMsg
            end
            GamePlayer.AddLog(msg)
            if pendingCombatCallback_ then
                pendingCombatCallback_(true, msg)
                pendingCombatCallback_ = nil
            end
        elseif success and not data.win then
            -- 战败：回调中已处理扣血
            if pendingCombatCallback_ then
                pendingCombatCallback_(false, "")
                pendingCombatCallback_ = nil
            end
        else
            -- 服务端返回失败
            local msg = "结算失败: " .. (msgStr or "未知错误")
            GamePlayer.AddLog(msg)
            if pendingCombatCallback_ then
                pendingCombatCallback_(false, msg)
                pendingCombatCallback_ = nil
            end
        end

    elseif action == "trial_settle" then
        -- 转发给 GameTrial 处理
        local GameTrial = require("game_trial")
        GameTrial.OnTrialSettleResp(data, success, msgStr)

    elseif action == "explore_gather" then
        if success then
            local drop  = data.drop or "物品"
            local count = data.count or 1
            -- 乐观同步客户端背包（服务端已更新 bagItems）
            GamePlayer.AddItem({ name = drop, count = count, rarity = "common", desc = "探索获得" })
            GameQuest.SetMainFlag("explored", true)
            if drop == "灵草" then
                GameQuest.NotifyAction("gather_herb", count)
            end
            local msg = "发现<c=gold>" .. (data.encName or "资源") .. "</c>，获得<c=yellow>" .. drop .. "x" .. count .. "</c>"
            GamePlayer.AddLog(msg)
        else
            GamePlayer.AddLog("采集失败: " .. (msgStr or "未知错误"))
        end
    end
end

--- 获取怪物图片（根据遭遇名/境界等级匹配）
---@param enc table 遭遇数据
---@return string imagePath
function M.GetMonsterImage(enc)
    local Theme = require("ui_theme")
    local monsters = Theme.monsters
    -- 根据遭遇的 tierMin 匹配最接近的怪物图
    local tierAvg = math.floor((enc.tierMin + enc.tierMax) / 2)
    local bestIdx = 1
    local bestDiff = 999
    for i, m in ipairs(monsters) do
        local diff = math.abs(m.level - tierAvg * 5)
        if diff < bestDiff then
            bestDiff = diff
            bestIdx = i
        end
    end
    -- 加入随机偏移以增加多样性
    local offset = math.random(-2, 2)
    local finalIdx = math.max(1, math.min(#monsters, bestIdx + offset))
    return monsters[finalIdx].image
end

return M
