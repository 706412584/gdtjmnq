-- ============================================================================
-- 《问道长生》修炼系统
-- 职责：每秒修为累积、修炼日志、突破 / 渡劫判定
-- 依赖：game_player (数据读写), data_formulas (产出公式), data_realms (境界)
-- ============================================================================

local GamePlayer  = require("game_player")
local DataFormulas = require("data_formulas")
local DataRealms  = require("data_realms")
local GameQuest   = require("game_quest")
local Loading     = require("ui_loading")

local M = {}

-- ============================================================================
-- 配置
-- ============================================================================
local TICK_INTERVAL   = 1.0   -- 每秒结算一次修为
local LOG_INTERVAL    = 5.0   -- 每5秒写一条日志
local INSIGHT_CHANCE  = 0.05  -- 5% 概率触发顿悟（修为翻倍）
local HP_REGEN_PCT    = 0.03  -- 每次日志周期恢复 3% 最大气血
local MP_REGEN_PCT    = 0.02  -- 每次日志周期恢复 2% 最大灵力

-- ============================================================================
-- 状态
-- ============================================================================
local tickTimer_ = 0
local logTimer_  = 0
local running_   = false   -- 是否正在修炼（进入洞府后开启）

-- ============================================================================
-- 启动 / 停止
-- ============================================================================

function M.Start()
    running_   = true
    tickTimer_ = 0
    logTimer_  = 0
    print("[Cultivation] 开始修炼")
end

function M.Stop()
    running_ = false
    print("[Cultivation] 停止修炼")
end

function M.IsRunning()
    return running_
end

-- ============================================================================
-- 计算当前每秒修为
-- ============================================================================

--- 获取当前每秒修为产出
---@return number
function M.GetPerSec()
    local p = GamePlayer.Get()
    if not p then return 0 end
    -- 计算功法修炼速度加成
    local skillBonus = 0
    for _, sk in ipairs(p.skills or {}) do
        if sk.name == "吐纳术" and sk.level and sk.level > 0 then
            skillBonus = skillBonus + 0.15 * sk.level
        end
    end
    return DataFormulas.CalcCultivationPerSec(
        p.tier or 1,
        p.rootBone or "中品灵根",
        skillBonus,
        0   -- 洞府灵气浓度（后续扩展）
    )
end

-- ============================================================================
-- 每帧更新（由 main.lua HandleUpdate 调用）
-- ============================================================================

---@param dt number
function M.Update(dt)
    if not running_ then return end
    local p = GamePlayer.Get()
    if not p then return end

    -- 修为结算
    tickTimer_ = tickTimer_ + dt
    if tickTimer_ >= TICK_INTERVAL then
        tickTimer_ = tickTimer_ - TICK_INTERVAL
        local perSec = M.GetPerSec()
        -- 顿悟判定
        local insight = false
        if math.random() < INSIGHT_CHANCE then
            perSec = perSec * 2
            insight = true
        end
        local gained = math.floor(perSec)
        if gained > 0 then
            GamePlayer.AddCultivation(gained)
        end
        -- 日志（控制频率）
        logTimer_ = logTimer_ + TICK_INTERVAL
        if logTimer_ >= LOG_INTERVAL then
            logTimer_ = 0
            -- 任务通知：静修（每次日志周期算1次修炼）
            GameQuest.NotifyAction("cultivate", 1)

            -- 静修恢复气血和灵力
            local hpMax = p.hpMax or 100
            local mpMax = p.mpMax or 50
            local hpHeal = math.floor(hpMax * HP_REGEN_PCT)
            local mpHeal = math.floor(mpMax * MP_REGEN_PCT)
            local hpBefore = p.hp or 0
            local mpBefore = p.mp or 0
            if hpHeal > 0 and hpBefore < hpMax then
                GamePlayer.HealHP(hpHeal)
            end
            if mpHeal > 0 and mpBefore < mpMax then
                GamePlayer.HealMP(mpHeal)
            end

            -- 日志文本
            local healNote = ""
            local actualHpHeal = math.min(hpHeal, hpMax - hpBefore)
            local actualMpHeal = math.min(mpHeal, mpMax - mpBefore)
            if actualHpHeal > 0 or actualMpHeal > 0 then
                local parts = {}
                if actualHpHeal > 0 then parts[#parts + 1] = "气血+" .. actualHpHeal end
                if actualMpHeal > 0 then parts[#parts + 1] = "灵力+" .. actualMpHeal end
                healNote = "，" .. table.concat(parts, "、")
            end

            if insight then
                GamePlayer.AddLog("偶有所悟，修为+" .. gained .. healNote .. "!")
            else
                GamePlayer.AddLog("你正在洞府静修，修为+" .. gained .. healNote .. "...")
            end
        end
    end
end

-- ============================================================================
-- 突破（小境界晋升）
-- ============================================================================

--- 检查是否满足小境界晋升条件
---@return boolean canBreak, string reason
function M.CanAdvanceSub()
    local p = GamePlayer.Get()
    if not p then return false, "无角色数据" end
    local cult = p.cultivation or 0
    local maxCult = p.cultivationMax or 0
    if cult < maxCult then
        return false, "修为不足"
    end
    return true, ""
end

--- 执行小境界晋升（不消耗修为，直接升级）
---@return boolean success, string message
function M.AdvanceSub()
    local ok, reason = M.CanAdvanceSub()
    if not ok then return false, reason end

    -- 网络模式：发送到服务端校验
    if IsNetworkMode() then
        local Shared    = require("network.shared")
        local ClientNet = require("network.client_net")
        local GameServer = require("game_server")
        ---@diagnostic disable-next-line: undefined-global
        local cjson_    = cjson
        local data = VariantMap()
        data["Action"] = Variant("advance_sub")
        data["Params"] = Variant(cjson_.encode({
            serverId = GameServer.GetCurrentServer().id,
        }))
        ClientNet.SendToServer(Shared.EVENTS.REQ_CULTIVATION_OP, data)
        Loading.Start(nil, 0.5)
        return true
    end

    local p = GamePlayer.Get()
    local tier = p.tier or 1
    local sub  = p.sub or 1

    if sub < 3 then
        -- 同大境界内晋升
        GamePlayer.SetRealm(tier, sub + 1)
        local newName = DataRealms.GetFullName(tier, sub + 1)
        GamePlayer.AddLog("恭喜！突破至" .. newName)
        return true, "突破至<c=gold>" .. newName .. "</c>"
    else
        -- 需要渡劫突破到下一大境界
        return false, "已达大成，需渡劫突破"
    end
end

-- ============================================================================
-- 渡劫（大境界突破）
-- ============================================================================

--- 检查是否满足渡劫条件
---@return boolean canTrib, string reason
function M.CanTribulation()
    local p = GamePlayer.Get()
    if not p then return false, "无角色数据" end
    local tier = p.tier or 1
    local sub  = p.sub or 1

    -- 必须在大成期
    if sub < 3 then
        return false, "需达到" .. DataRealms.GetFullName(tier, 3) .. "方可渡劫"
    end
    -- 修为需求
    local cult = p.cultivation or 0
    local maxCult = p.cultivationMax or 0
    if cult < maxCult then
        return false, "修为不足"
    end
    -- 最大阶数
    if tier >= 10 then
        return false, "已达最高境界"
    end
    return true, ""
end

--- 获取渡劫信息
---@return table|nil { name, successRate, pillBonus }
function M.GetTribulationInfo()
    local p = GamePlayer.Get()
    if not p then return nil end
    local targetTier = (p.tier or 1) + 1
    local trib = DataRealms.GetTribulation(targetTier)
    if not trib then return nil end
    return {
        name        = trib.name,
        targetTier  = targetTier,
        targetName  = DataRealms.GetFullName(targetTier, 1),
        baseRate    = trib.baseRate,
        pillBonus   = trib.pillBonus,
        successRate = DataFormulas.CalcBreakRate(targetTier, 0),
    }
end

--- 获取玩家持有的突破辅助丹药列表
---@return table[] { id, name, effect, count }
function M.GetBreakthroughPills()
    local p = GamePlayer.Get()
    if not p then return {} end

    local DataItems = require("data_items")
    local result = {}
    for _, def in ipairs(DataItems.PILLS_BREAKTHROUGH) do
        for _, pill in ipairs(p.pills or {}) do
            if pill.name == def.name and (pill.count or 0) > 0 then
                result[#result + 1] = {
                    id     = def.id,
                    name   = def.name,
                    effect = def.effect,
                    count  = pill.count,
                }
                break
            end
        end
    end
    return result
end

--- 执行渡劫
---@param pillNames? string[] 使用的突破丹药名称列表（每种最多1枚）
---@return boolean success, string message
function M.DoTribulation(pillNames)
    local ok, reason = M.CanTribulation()
    if not ok then return false, reason end

    -- 网络模式：发送到服务端判定（随机数在服务端生成）
    if IsNetworkMode() then
        local Shared    = require("network.shared")
        local ClientNet = require("network.client_net")
        local GameServer = require("game_server")
        ---@diagnostic disable-next-line: undefined-global
        local cjson_    = cjson
        local data = VariantMap()
        data["Action"] = Variant("tribulation")
        data["Params"] = Variant(cjson_.encode({
            serverId  = GameServer.GetCurrentServer().id,
            pillNames = pillNames or {},
        }))
        ClientNet.SendToServer(Shared.EVENTS.REQ_CULTIVATION_OP, data)
        Loading.Start(nil, 0.5)
        return true
    end

    local p = GamePlayer.Get()
    local tier = p.tier or 1
    local targetTier = tier + 1

    local trib = DataRealms.GetTribulation(targetTier)
    local pillBonus = 0
    local usedPills = {}
    local hasQingxin = false  -- 清心丹：失败不降道心

    -- 消耗选中的突破丹药并计算加成
    if pillNames and #pillNames > 0 then
        local DataItems = require("data_items")
        for _, pName in ipairs(pillNames) do
            local def = DataItems.FindPillByName(pName)
            if def then
                -- 检查玩家是否持有
                local found = false
                for _, pill in ipairs(p.pills or {}) do
                    if pill.name == pName and (pill.count or 0) > 0 then
                        pill.count = pill.count - 1
                        found = true
                        break
                    end
                end
                if found then
                    usedPills[#usedPills + 1] = pName
                    -- 解析加成效果
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
    end

    local rate = DataFormulas.CalcBreakRate(targetTier, pillBonus)
    local roll = math.random(100)

    local pillNote = ""
    if #usedPills > 0 then
        pillNote = "（使用" .. table.concat(usedPills, "、") .. "）"
    end

    if roll <= rate then
        -- 成功
        GamePlayer.SetRealm(targetTier, 1)
        GamePlayer.ApplyBreakBonus(tier)
        local newName = DataRealms.GetFullName(targetTier, 1)
        GamePlayer.AddLog("渡劫成功！突破至" .. newName .. pillNote)
        GamePlayer.ForceSave()
        return true, "渡劫成功！突破至<c=gold>" .. newName .. "</c>"
    else
        -- 失败
        local cost = DataFormulas.CalcBreakFailCost(p.cultivation or 0)
        GamePlayer.AddCultivation(-cost)
        if hasQingxin then
            GamePlayer.AddLog(string.format("渡劫失败%s，损失修为 %d（清心丹保护道心）", pillNote, cost))
        else
            GamePlayer.AddLog(string.format("渡劫失败%s，损失修为 %d", pillNote, cost))
        end
        GamePlayer.ForceSave()
        return false, "渡劫失败，损失<c=red>修为" .. cost .. "</c>"
    end
end

-- ============================================================================
-- 服务端回调（网络模式）
-- ============================================================================

--- 处理服务端修炼/渡劫回复（由 client_net.lua 中转调用）
---@param eventData any
function M.OnCultivationResp(eventData)
    Loading.Stop()

    local action  = eventData["Action"]:GetString()
    local success = eventData["Success"]:GetBool()
    local msg     = eventData["Msg"]:GetString()

    local Toast = require("ui_toast")

    if not success then
        Toast.Show(msg, "error")
        return
    end

    ---@diagnostic disable-next-line: undefined-global
    local cjson = cjson
    local dataStr = eventData["Data"]:GetString()
    local ok2, data = pcall(cjson.decode, dataStr)
    if not ok2 then
        Toast.Show("数据解析失败", "error")
        return
    end

    local p = GamePlayer.Get()
    if not p then return end

    if action == "tribulation" then
        if data.success then
            -- 渡劫成功：同步服务端数据到本地
            GamePlayer.SetRealm(data.targetTier, 1)
            GamePlayer.ApplyBreakBonus((data.targetTier or 2) - 1)
            local newName = data.newName or DataRealms.GetFullName(data.targetTier, 1)
            local pillNote = ""
            if data.usedPills and #data.usedPills > 0 then
                pillNote = "（使用" .. table.concat(data.usedPills, "、") .. "）"
            end
            GamePlayer.AddLog("渡劫成功！突破至" .. newName .. pillNote)
            Toast.Show("渡劫成功！突破至" .. newName, "success")
        else
            -- 渡劫失败：扣除修为
            local cost = data.failCost or 0
            if cost > 0 then
                GamePlayer.AddCultivation(-cost)
            end
            -- 同步丹药消耗
            if data.usedPills then
                for _, pName in ipairs(data.usedPills) do
                    GamePlayer.RemoveItemByName(pName, 1)
                end
            end
            local pillNote = ""
            if data.usedPills and #data.usedPills > 0 then
                pillNote = "（使用" .. table.concat(data.usedPills, "、") .. "）"
            end
            if data.hasQingxin then
                GamePlayer.AddLog(string.format("渡劫失败%s，损失修为 %d（清心丹保护道心）", pillNote, cost))
            else
                GamePlayer.AddLog(string.format("渡劫失败%s，损失修为 %d", pillNote, cost))
            end
            Toast.Show("渡劫失败，损失修为" .. cost, "error")
        end
        GamePlayer.ForceSave()

    elseif action == "advance_sub" then
        -- 小境界突破成功
        local tier = data.tier or (p.tier or 1)
        local sub  = data.sub or ((p.sub or 1) + 1)
        GamePlayer.SetRealm(tier, sub)
        local newName = data.newName or DataRealms.GetFullName(tier, sub)
        GamePlayer.AddLog("恭喜！突破至" .. newName)
        Toast.Show("突破至" .. newName, "success")
    end
end

-- ============================================================================
-- 离线收益结算
-- ============================================================================

--- 结算离线收益并写入数据
---@return number seconds, number cultivation
function M.ApplyOfflineGains()
    local secs, cult = GamePlayer.CalcOfflineGains()
    if cult > 0 then
        GamePlayer.AddCultivation(cult)
        local minutes = math.floor(secs / 60)
        GamePlayer.AddLog(string.format(
            "离线 %d 分钟，获得修为 %d", minutes, cult
        ))
        print(string.format(
            "[Cultivation] 离线收益: %d分钟, 修为+%d", minutes, cult
        ))
    end
    return secs, cult
end

return M
