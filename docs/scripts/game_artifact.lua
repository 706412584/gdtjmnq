-- ============================================================================
-- 《问道长生》法宝操作模块
-- 职责：法宝装备/卸下/强化
-- 设计：Can/Do 模式
-- ============================================================================

local GamePlayer = require("game_player")
local DataItems  = require("data_items")
local GameItems  = require("game_items")
local Loading    = require("ui_loading")

local M = {}

-- ============================================================================
-- 装备 / 卸下
-- ============================================================================

--- 检查是否可装备
---@param artName string
---@return boolean, string|nil
function M.CanEquip(artName)
    local p = GamePlayer.Get()
    if not p then return false, "数据未加载" end

    local found = nil
    for _, a in ipairs(p.artifacts or {}) do
        if a.name == artName then
            found = a
            break
        end
    end
    if not found then return false, "未拥有该法宝" end
    if found.equipped then return false, "已经装备中" end

    return true, nil
end

--- 装备法宝（同槽位自动卸下旧法宝）
---@param artName string
---@return boolean, string
function M.DoEquip(artName)
    local ok, reason = M.CanEquip(artName)
    if not ok then return false, reason or "无法装备" end

    local p = GamePlayer.Get()
    local target = nil
    for _, a in ipairs(p.artifacts or {}) do
        if a.name == artName then
            target = a
            break
        end
    end

    -- 查找同槽位已装备的法宝并卸下
    local slot = target.slot or "weapon"
    for _, a in ipairs(p.artifacts or {}) do
        if a.equipped and (a.slot or "weapon") == slot and a.name ~= artName then
            a.equipped = false
            -- 移除旧法宝效果
            M.RemoveArtifactEffect(a)
        end
    end

    -- 装备新法宝
    target.equipped = true
    M.ApplyArtifactEffect(target)

    GamePlayer.RefreshDerived()
    GamePlayer.MarkDirty()

    local msg = "装备 <c=gold>" .. artName .. "</c>"
    GamePlayer.AddLog(msg)
    return true, msg
end

--- 卸下法宝
---@param artName string
---@return boolean, string
function M.DoUnequip(artName)
    local p = GamePlayer.Get()
    if not p then return false, "数据未加载" end

    local found = nil
    for _, a in ipairs(p.artifacts or {}) do
        if a.name == artName then
            found = a
            break
        end
    end
    if not found then return false, "未拥有该法宝" end
    if not found.equipped then return false, "未装备该法宝" end

    found.equipped = false
    M.RemoveArtifactEffect(found)

    GamePlayer.RefreshDerived()
    GamePlayer.MarkDirty()

    local msg = "卸下 <c=gold>" .. artName .. "</c>"
    GamePlayer.AddLog(msg)
    return true, msg
end

-- ============================================================================
-- 法宝效果应用/移除（基于 effect 字符串的 delta 叠加）
-- ============================================================================

--- 应用法宝效果（装备时调用）
---@param art table
function M.ApplyArtifactEffect(art)
    if not art or not art.effect then return end
    -- 基础效果 + 强化倍率
    local enhancePct = M.GetEnhancePct(art.level or 1)
    local effects = GameItems.ParseEffect(art.effect)
    local p = GamePlayer.Get()
    if not p then return end
    for _, e in ipairs(effects) do
        local boosted = math.floor(e.value * (1 + enhancePct / 100))
        M.ApplyStat(p, e.key, boosted)
    end
end

--- 移除法宝效果（卸下时调用）
---@param art table
function M.RemoveArtifactEffect(art)
    if not art or not art.effect then return end
    local enhancePct = M.GetEnhancePct(art.level or 1)
    local effects = GameItems.ParseEffect(art.effect)
    local p = GamePlayer.Get()
    if not p then return end
    for _, e in ipairs(effects) do
        local boosted = math.floor(e.value * (1 + enhancePct / 100))
        M.ApplyStat(p, e.key, -boosted)
    end
end

--- 获取强化等级的总增幅百分比
---@param level number
---@return number pct
function M.GetEnhancePct(level)
    if level <= 1 then return 0 end
    local total = 0
    for lv = 1, level - 1 do
        local info = DataItems.GetEnhanceInfo(lv)
        if info then total = total + info.pct end
    end
    return total
end

--- 直接修改玩家属性值
---@param p table 玩家数据
---@param keyword string 效果关键字
---@param value number 数值（正增负减）
function M.ApplyStat(p, keyword, value)
    if keyword == "攻击" then
        p.attack = (p.attack or 0) + value
    elseif keyword == "防御" then
        p.defense = (p.defense or 0) + value
    elseif keyword == "速度" then
        p.speed = (p.speed or 0) + value
    elseif keyword == "灵力上限" then
        p.mpMax = (p.mpMax or 200) + value
    elseif keyword == "暴击" then
        -- 忽略百分比符号，直接加数值
        p.crit = (p.crit or 0) + value
    end
    GamePlayer.MarkDirty()
end

-- ============================================================================
-- 法宝强化（炼化）
-- ============================================================================

--- 检查是否可以强化
---@param artName string
---@return boolean, string|nil
function M.CanEnhance(artName)
    local p = GamePlayer.Get()
    if not p then return false, "数据未加载" end

    local found = nil
    for _, a in ipairs(p.artifacts or {}) do
        if a.name == artName then
            found = a
            break
        end
    end
    if not found then return false, "未拥有该法宝" end
    if (found.level or 1) >= (found.maxLevel or 10) then
        return false, "已达最高强化等级"
    end

    local nextInfo = DataItems.GetEnhanceInfo(found.level or 1)
    if not nextInfo then return false, "无法获取强化配置" end

    -- 检查货币
    local currKey = nextInfo.currency == "仙石" and "spiritStone" or "lingStone"
    if (p[currKey] or 0) < nextInfo.cost then
        return false, nextInfo.currency .. "不足"
    end

    return true, nil
end

--- 执行法宝强化
---@param artName string
---@return boolean, string
function M.DoEnhance(artName)
    local ok, reason = M.CanEnhance(artName)
    if not ok then return false, reason or "无法强化" end

    -- 网络模式：发送到服务端判定（随机数+货币扣除在服务端完成）
    if IsNetworkMode() then
        local Shared    = require("network.shared")
        local ClientNet = require("network.client_net")
        local GameServer = require("game_server")
        ---@diagnostic disable-next-line: undefined-global
        local cjson     = cjson
        local data = VariantMap()
        data["Action"] = Variant("enhance_artifact")
        data["Params"] = Variant(cjson.encode({
            serverId = GameServer.GetCurrentServer().id,
            artName  = artName,
        }))
        ClientNet.SendToServer(Shared.EVENTS.REQ_ALCHEMY_OP, data)
        Loading.Start(nil, 0.5)
        return true
    end

    local p = GamePlayer.Get()
    local art = nil
    for _, a in ipairs(p.artifacts or {}) do
        if a.name == artName then
            art = a
            break
        end
    end

    local curLevel = art.level or 1
    local enhInfo = DataItems.GetEnhanceInfo(curLevel)

    -- 扣除费用
    local currKey = enhInfo.currency == "仙石" and "spiritStone" or "lingStone"
    GamePlayer.AddCurrency(currKey, -enhInfo.cost)

    -- 成功率判定
    local roll = math.random(1, 100)
    if roll > enhInfo.rate then
        local msg = "<c=gold>" .. art.name .. "</c> 强化失败，消耗<c=red>" .. enhInfo.currency .. enhInfo.cost .. "</c>"
        GamePlayer.AddLog(msg)
        return false, msg
    end

    -- 如果装备中，先移除旧效果
    if art.equipped then
        M.RemoveArtifactEffect(art)
    end

    -- 升级
    art.level = curLevel + 1

    -- 如果装备中，应用新效果
    if art.equipped then
        M.ApplyArtifactEffect(art)
    end

    GamePlayer.RefreshDerived()
    GamePlayer.MarkDirty()

    local msg = "<c=gold>" .. art.name .. "</c> 强化至 <c=yellow>Lv." .. art.level .. "</c>"
    GamePlayer.AddLog(msg)
    return true, msg
end

-- ============================================================================
-- 服务端回调（网络模式）
-- ============================================================================

--- 处理服务端法宝强化回复（由 game_alchemy.OnAlchemyResp 转发）
---@param data table { success, artName, oldLevel, newLevel, rate, roll, cost, currency, balance }
function M.OnEnhanceResp(data)
    local Toast = require("ui_toast")
    local p = GamePlayer.Get()
    if not p then return end

    local artName = data.artName or ""

    -- 同步货币余额
    if data.balance and data.currency then
        local currKey = data.currency == "仙石" and "spiritStone" or "lingStone"
        p[currKey] = data.balance
    end

    -- 查找本地法宝
    local art = nil
    for _, a in ipairs(p.artifacts or {}) do
        if a.name == artName then
            art = a
            break
        end
    end

    if data.success and art then
        -- 如果装备中，先移除旧效果
        if art.equipped then
            M.RemoveArtifactEffect(art)
        end
        art.level = data.newLevel or ((art.level or 1) + 1)
        -- 如果装备中，应用新效果
        if art.equipped then
            M.ApplyArtifactEffect(art)
        end
        GamePlayer.RefreshDerived()
        GamePlayer.MarkDirty()

        local msg = "<c=gold>" .. artName .. "</c> 强化至 <c=yellow>Lv." .. art.level .. "</c>"
        GamePlayer.AddLog(msg)
        Toast.Show(artName .. " 强化成功！Lv." .. art.level, "success")
    else
        GamePlayer.MarkDirty()
        local msg = "<c=gold>" .. artName .. "</c> 强化失败，消耗<c=red>" .. (data.currency or "") .. (data.cost or 0) .. "</c>"
        GamePlayer.AddLog(msg)
        Toast.Show(artName .. " 强化失败", "error")
    end
end

return M
