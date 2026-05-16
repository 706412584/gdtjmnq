-- ============================================================================
-- 《问道长生》物品操作模块
-- 职责：丹药服用、背包整理/出售/使用、效果字符串解析
-- 设计：Can/Do 模式，所有操作先检查后执行
-- ============================================================================

local GamePlayer = require("game_player")
local DataItems  = require("data_items")

local M = {}

-- 品质 → 出售基础价
local SELL_PRICE = {
    common   = 5,
    uncommon = 15,
    rare     = 50,
    epic     = 150,
    legend   = 500,
    mythic   = 2000,
}

-- ============================================================================
-- 分类查询
-- ============================================================================

--- 获取物品的实际分类（优先用字段，无则推断）
---@param item table
---@return string category, string|nil subType
local function resolveCategory(item)
    if item.category then
        return item.category, item.subType
    end
    local cat, sub = DataItems.InferCategory(item.name)
    -- 顺便回写，减少后续推断
    item.category = cat
    item.subType  = sub
    return cat, sub
end

--- 获取指定分类的背包物品
---@param category string "fabao"|"material"|"item"|"pet"
---@param subTab? string 子分类标签（如 "头戴"、"丹药"）
---@return table[]
function M.GetItemsByCategory(category, subTab)
    local p = GamePlayer.Get()
    if not p then return {} end
    local items = p.bagItems or {}
    local result = {}
    for _, item in ipairs(items) do
        local cat, sub = resolveCategory(item)
        if cat == category then
            if subTab == nil or (sub or "") == subTab then
                result[#result + 1] = item
            end
        end
    end
    return result
end

--- 获取各分类的物品数量（用于标签页角标）
---@return table<string, number>
function M.GetCategoryCounts()
    local p = GamePlayer.Get()
    if not p then return {} end
    local counts = {}
    for _, item in ipairs(p.bagItems or {}) do
        local cat = resolveCategory(item)
        counts[cat] = (counts[cat] or 0) + 1
    end
    return counts
end

--- 确保背包中所有物品都有 category/subType 字段（兼容旧数据迁移）
function M.MigrateBagCategories()
    local p = GamePlayer.Get()
    if not p then return end
    local changed = false
    for _, item in ipairs(p.bagItems or {}) do
        if not item.category then
            item.category, item.subType = DataItems.InferCategory(item.name)
            changed = true
        end
    end
    if changed then GamePlayer.MarkDirty() end
end

-- ============================================================================
-- 背包容量 & 扩容
-- ============================================================================

--- 获取当前背包容量
---@return number
function M.GetBagCapacity()
    local p = GamePlayer.Get()
    if not p then return DataItems.BAG_EXPAND.initialCapacity end
    return p.bagCapacity or DataItems.BAG_EXPAND.initialCapacity
end

--- 获取当前已用格数
---@return number
function M.GetBagUsed()
    local p = GamePlayer.Get()
    if not p then return 0 end
    return #(p.bagItems or {})
end

--- 获取扩容费用
---@return number cost, string currency
function M.GetExpandCost()
    local cap = M.GetBagCapacity()
    local cost = cap * DataItems.BAG_EXPAND.costPerSlot
    return cost, "灵石"
end

--- 检查是否可以扩容
---@return boolean, string|nil
function M.CanExpandBag()
    local p = GamePlayer.Get()
    if not p then return false, "数据未加载" end
    local cap = p.bagCapacity or DataItems.BAG_EXPAND.initialCapacity
    if cap >= DataItems.BAG_EXPAND.maxCapacity then
        return false, "已达容量上限(" .. DataItems.BAG_EXPAND.maxCapacity .. "格)"
    end
    local cost = cap * DataItems.BAG_EXPAND.costPerSlot
    if (p.lingStone or 0) < cost then
        return false, "灵石不足(需" .. cost .. ")"
    end
    return true, nil
end

--- 执行扩容
---@return boolean, string
function M.DoExpandBag()
    local ok, reason = M.CanExpandBag()
    if not ok then return false, reason or "无法扩容" end
    local p = GamePlayer.Get()
    local cap = p.bagCapacity or DataItems.BAG_EXPAND.initialCapacity
    local cost = cap * DataItems.BAG_EXPAND.costPerSlot
    GamePlayer.AddCurrency("lingStone", -cost)
    p.bagCapacity = cap + DataItems.BAG_EXPAND.perExpand
    GamePlayer.MarkDirty()
    local msg = "扩容成功! 容量: " .. p.bagCapacity .. "/" .. DataItems.BAG_EXPAND.maxCapacity
    GamePlayer.AddLog("<c=gold>储物扩容</c>: 消耗灵石" .. cost .. "，当前容量" .. p.bagCapacity)
    return true, msg
end

--- 检查背包是否已满
---@return boolean
function M.IsBagFull()
    return M.GetBagUsed() >= M.GetBagCapacity()
end

-- ============================================================================
-- 物品锁定
-- ============================================================================

--- 切换物品锁定状态
---@param index number
---@return boolean success, string msg
function M.ToggleLock(index)
    local p = GamePlayer.Get()
    if not p then return false, "数据未加载" end
    local item = (p.bagItems or {})[index]
    if not item then return false, "无效的物品索引" end
    item.locked = not (item.locked or false)
    GamePlayer.MarkDirty()
    local state = item.locked and "锁定" or "解锁"
    return true, item.name .. "已" .. state
end

-- ============================================================================
-- 回收面板
-- ============================================================================

--- 获取符合回收条件的物品（按品质筛选，排除已锁定）
---@param selectedQualities table<string, boolean> 如 { common=true, uncommon=true }
---@return table[] items, number totalPrice
function M.GetRecyclableItems(selectedQualities)
    local p = GamePlayer.Get()
    if not p then return {}, 0 end
    local result = {}
    local totalPrice = 0
    for i, item in ipairs(p.bagItems or {}) do
        local rarity = item.rarity or "common"
        if selectedQualities[rarity] and not item.locked then
            result[#result + 1] = { index = i, item = item }
            local unitPrice = SELL_PRICE[rarity] or 5
            totalPrice = totalPrice + unitPrice * (item.count or 1)
        end
    end
    return result, totalPrice
end

--- 执行批量回收（按品质，排除锁定物品）
---@param selectedQualities table<string, boolean>
---@return boolean, string
function M.DoRecycle(selectedQualities)
    local p = GamePlayer.Get()
    if not p then return false, "数据未加载" end
    local items = p.bagItems or {}
    local totalPrice = 0
    local totalCount = 0
    -- 倒序遍历安全删除
    for i = #items, 1, -1 do
        local item = items[i]
        local rarity = item.rarity or "common"
        if selectedQualities[rarity] and not item.locked then
            local unitPrice = SELL_PRICE[rarity] or 5
            local cnt = item.count or 1
            totalPrice = totalPrice + unitPrice * cnt
            totalCount = totalCount + cnt
            table.remove(items, i)
        end
    end
    if totalCount == 0 then
        return false, "没有符合条件的可回收物品"
    end
    GamePlayer.AddCurrency("lingStone", totalPrice)
    GamePlayer.MarkDirty()
    local msg = "回收<c=gold>" .. totalCount .. "件</c>物品，获得<c=yellow>灵石" .. totalPrice .. "</c>"
    GamePlayer.AddLog(msg)
    return true, msg
end

-- ============================================================================
-- 品质排序权重（值越大越靠前）
-- ============================================================================
local QUALITY_WEIGHT = {
    mythic   = 60,
    legend   = 50,
    epic     = 40,
    rare     = 30,
    uncommon = 20,
    common   = 10,
}

-- ============================================================================
-- 效果字符串解析器
-- 支持格式: "修为+200", "气血+50(永久)", "攻击+10(永久)", "灵力恢复100" 等
-- ============================================================================

--- 解析效果字符串为 { {key, value}, ... }
---@param effectStr string
---@return table[]
function M.ParseEffect(effectStr)
    if not effectStr or effectStr == "" then return {} end
    local results = {}

    -- 模式1: "关键字+数值" 或 "关键字-数值"（如 "修为+200"）
    for keyword, sign, num in effectStr:gmatch("(%D+)([%+%-])(%d+)") do
        -- 去除括号等非中文后缀
        keyword = keyword:match("^(.-)%s*$") or keyword
        local val = tonumber(num) or 0
        if sign == "-" then val = -val end
        results[#results + 1] = { key = keyword, value = val }
    end

    -- 模式2: "灵力恢复100" 格式（关键字+数值，无符号）
    if #results == 0 then
        for keyword, num in effectStr:gmatch("(%D+)(%d+)") do
            keyword = keyword:match("^(.-)%s*$") or keyword
            local val = tonumber(num) or 0
            results[#results + 1] = { key = keyword, value = val }
        end
    end

    return results
end

--- 应用效果到玩家数据
---@param effectStr string
---@return string 应用结果描述
function M.ApplyEffect(effectStr)
    local effects = M.ParseEffect(effectStr)
    if #effects == 0 then return "" end

    local p = GamePlayer.Get()
    if not p then return "" end

    local msgs = {}
    for _, e in ipairs(effects) do
        local k, v = e.key, e.value
        if k == "修为" then
            GamePlayer.AddCultivation(v)
            msgs[#msgs + 1] = "修为+" .. v
        elseif k == "气血" then
            p.hpMax = (p.hpMax or 800) + v
            GamePlayer.HealHP(v)
            msgs[#msgs + 1] = "气血上限+" .. v
        elseif k == "灵力" or k == "灵力恢复" then
            GamePlayer.HealMP(v)
            msgs[#msgs + 1] = "灵力恢复" .. v
        elseif k == "灵石" then
            GamePlayer.AddCurrency("lingStone", v)
            msgs[#msgs + 1] = "灵石+" .. v
        elseif k == "攻击" then
            p.attack = (p.attack or 0) + v
            GamePlayer.MarkDirty()
            msgs[#msgs + 1] = "攻击+" .. v
        elseif k == "防御" then
            p.defense = (p.defense or 0) + v
            GamePlayer.MarkDirty()
            msgs[#msgs + 1] = "防御+" .. v
        elseif k == "速度" then
            p.speed = (p.speed or 0) + v
            GamePlayer.MarkDirty()
            msgs[#msgs + 1] = "速度+" .. v
        elseif k == "神识" then
            p.sense = (p.sense or 0) + v
            GamePlayer.MarkDirty()
            msgs[#msgs + 1] = "神识+" .. v
        elseif k == "悟性" then
            p.wisdom = (p.wisdom or 0) + v
            GamePlayer.MarkDirty()
            msgs[#msgs + 1] = "悟性+" .. v
        elseif k == "气运" then
            p.fortune = (p.fortune or 0) + v
            GamePlayer.MarkDirty()
            msgs[#msgs + 1] = "气运+" .. v
        elseif k == "寿元" then
            GamePlayer.AddLifespan(v)
            msgs[#msgs + 1] = "寿元+" .. v
        end
    end

    return table.concat(msgs, ", ")
end

-- ============================================================================
-- 丹药服用
-- ============================================================================

--- 检查是否可以服用某丹药
---@param pillName string
---@return boolean, string|nil
function M.CanUsePill(pillName)
    local p = GamePlayer.Get()
    if not p then return false, "数据未加载" end

    -- 在 p.pills 中查找
    local found = nil
    for _, pill in ipairs(p.pills or {}) do
        if pill.name == pillName then
            found = pill
            break
        end
    end
    if not found then return false, "未拥有该丹药" end
    if found.locked then return false, "该丹药暂未解锁" end
    if (found.count or 0) <= 0 then return false, "丹药数量不足" end

    -- 检查限制丹药的 perRealm 限制
    local def = DataItems.FindPillByName(pillName)
    if def and def.perRealm then
        local usage = GamePlayer.GetPillUsage(pillName)
        if usage >= def.perRealm then
            return false, "本境界已达服用上限(" .. def.perRealm .. "次)"
        end
    end

    return true, nil
end

--- 服用丹药
---@param pillName string
---@return boolean, string
function M.DoUsePill(pillName)
    local ok, reason = M.CanUsePill(pillName)
    if not ok then return false, reason or "无法服用" end

    local p = GamePlayer.Get()

    -- 扣除丹药
    for i, pill in ipairs(p.pills or {}) do
        if pill.name == pillName then
            pill.count = pill.count - 1
            break
        end
    end

    -- 应用效果
    local def = DataItems.FindPillByName(pillName)
    local effectMsg = ""
    if def then
        effectMsg = M.ApplyEffect(def.effect)
        -- 更新限制次数
        if def.perRealm then
            GamePlayer.AddPillUsage(pillName)
        end
    end

    GamePlayer.MarkDirty()
    local msg = "服用<c=gold>" .. pillName .. "</c>成功"
    if effectMsg ~= "" then msg = msg .. "，<c=yellow>" .. effectMsg .. "</c>" end
    GamePlayer.AddLog(msg)
    return true, msg
end

-- ============================================================================
-- 背包操作
-- ============================================================================

--- 整理背包（按品质降序排列）
---@return string
function M.SortBag()
    local p = GamePlayer.Get()
    if not p then return "数据未加载" end

    local items = p.bagItems or {}
    if #items <= 1 then return "背包已整理" end

    table.sort(items, function(a, b)
        local wa = QUALITY_WEIGHT[a.rarity or "common"] or 0
        local wb = QUALITY_WEIGHT[b.rarity or "common"] or 0
        if wa ~= wb then return wa > wb end
        return (a.name or "") < (b.name or "")
    end)

    GamePlayer.MarkDirty()
    return "背包整理完成"
end

--- 检查是否可出售物品
---@param index number
---@return boolean, string|nil
function M.CanSellItem(index)
    local p = GamePlayer.Get()
    if not p then return false, "数据未加载" end
    local items = p.bagItems or {}
    if index < 1 or index > #items then return false, "无效的物品索引" end
    return true, nil
end

--- 出售单件物品
---@param index number
---@param count? number
---@return boolean, string
function M.DoSellItem(index, count)
    local ok, reason = M.CanSellItem(index)
    if not ok then return false, reason or "无法出售" end

    local p = GamePlayer.Get()
    local item = p.bagItems[index]
    local sellCount = math.min(count or 1, item.count or 1)
    local unitPrice = SELL_PRICE[item.rarity or "common"] or 5
    local totalPrice = unitPrice * sellCount

    GamePlayer.RemoveItem(index, sellCount)
    GamePlayer.AddCurrency("lingStone", totalPrice)

    local msg = "出售<c=gold>" .. item.name .. "x" .. sellCount .. "</c>，获得<c=yellow>灵石" .. totalPrice .. "</c>"
    GamePlayer.AddLog(msg)
    return true, msg
end

--- 预览批量出售（不执行，仅返回预估数量和价格）
---@param maxQuality? string 最高出售品质key(默认 "uncommon")
---@return number totalCount, number totalPrice
function M.PreviewBatchSell(maxQuality)
    local p = GamePlayer.Get()
    if not p then return 0, 0 end
    maxQuality = maxQuality or "uncommon"
    local maxWeight = QUALITY_WEIGHT[maxQuality] or 20
    local items = p.bagItems or {}
    local totalPrice = 0
    local totalCount = 0
    for _, item in ipairs(items) do
        if not item.locked then
            local w = QUALITY_WEIGHT[item.rarity or "common"] or 0
            if w <= maxWeight then
                local unitPrice = SELL_PRICE[item.rarity or "common"] or 5
                local cnt = item.count or 1
                totalPrice = totalPrice + unitPrice * cnt
                totalCount = totalCount + cnt
            end
        end
    end
    return totalCount, totalPrice
end

--- 批量出售指定品质及以下的所有物品
---@param maxQuality? string 最高出售品质key(默认 "uncommon")
---@return boolean, string
function M.DoBatchSell(maxQuality)
    local p = GamePlayer.Get()
    if not p then return false, "数据未加载" end

    maxQuality = maxQuality or "uncommon"
    local maxWeight = QUALITY_WEIGHT[maxQuality] or 20
    local items = p.bagItems or {}

    local totalPrice = 0
    local totalCount = 0

    -- 倒序遍历，安全删除（跳过锁定物品）
    for i = #items, 1, -1 do
        local item = items[i]
        if not item.locked then
            local w = QUALITY_WEIGHT[item.rarity or "common"] or 0
            if w <= maxWeight then
                local unitPrice = SELL_PRICE[item.rarity or "common"] or 5
                local cnt = item.count or 1
                totalPrice = totalPrice + unitPrice * cnt
                totalCount = totalCount + cnt
                table.remove(items, i)
            end
        end
    end

    if totalCount == 0 then
        return false, "没有可出售的物品"
    end

    GamePlayer.AddCurrency("lingStone", totalPrice)
    GamePlayer.MarkDirty()

    local msg = "批量出售<c=gold>" .. totalCount .. "件</c>物品，获得<c=yellow>灵石" .. totalPrice .. "</c>"
    GamePlayer.AddLog(msg)
    return true, msg
end

--- 使用物品（按类型分发）
---@param index number
---@return boolean, string
function M.DoUseItem(index)
    local p = GamePlayer.Get()
    if not p then return false, "数据未加载" end
    local items = p.bagItems or {}
    if index < 1 or index > #items then return false, "无效的物品索引" end

    local item = items[index]

    -- 检查是否是丹药（在 pills 数据中存在定义）
    local pillDef = DataItems.FindPillByName(item.name)
    if pillDef then
        -- 将背包中的丹药转移到 pills 列表并服用
        -- 先检查 pills 中是否已有
        local found = false
        for _, pill in ipairs(p.pills or {}) do
            if pill.name == item.name then
                pill.count = (pill.count or 0) + 1
                found = true
                break
            end
        end
        if not found then
            p.pills = p.pills or {}
            p.pills[#p.pills + 1] = {
                name = item.name,
                count = 1,
                quality = pillDef.quality or "common",
                desc = pillDef.effect or "",
                effect = pillDef.effect or "",
            }
        end
        -- 从背包移除 1 个
        GamePlayer.RemoveItem(index, 1)
        -- 执行服用
        return M.DoUsePill(item.name)
    end

    -- 材料类物品不可直接使用
    return false, item.name .. "无法直接使用"
end

return M
