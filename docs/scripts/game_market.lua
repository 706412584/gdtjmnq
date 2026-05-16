-- ============================================================================
-- 《问道长生》坊市交易模块
-- 职责：商铺购买、寄售上架/下架/购买
-- 架构：云变量方案（商铺购买纯本地，寄售购买乐观更新+远程事件）
-- ============================================================================

local GamePlayer = require("game_player")
local DataItems  = require("data_items")
local GameQuest  = require("game_quest")
local Toast      = require("ui_toast")
---@diagnostic disable-next-line: undefined-global
local cjson      = cjson  -- 引擎内置全局变量，无需 require

local M = {}

-- ============================================================================
-- 服务端数据缓存
-- ============================================================================

M.serverListings_ = nil   -- 全部寄售列表
M.myListings_     = nil   -- 我的寄售列表

-- ============================================================================
-- 商铺购买（纯本地，不分网络/单机）
-- ============================================================================

---@param item table { name, price, currency, stock, rarity, desc }
---@param count? number
---@return boolean, string|nil
function M.CanBuyGoods(item, count)
    if not item then return false, "无效的商品" end
    local p = GamePlayer.Get()
    if not p then return false, "数据未加载" end

    count = count or 1
    if item.stock ~= nil and item.stock >= 0 and item.stock < count then
        return false, "库存不足"
    end

    local totalCost = item.price * count
    local currKey = item.currency == "仙石" and "spiritStone" or "lingStone"
    if GamePlayer.GetCurrency(currKey) < totalCost then
        return false, item.currency .. "不足"
    end

    return true, nil
end

---@param item table
---@param count? number
---@return boolean, string
function M.DoBuyGoods(item, count)
    count = count or 1
    local ok, reason = M.CanBuyGoods(item, count)
    if not ok then return false, reason or "无法购买" end

    local p = GamePlayer.Get()
    local totalCost = item.price * count
    local currKey = item.currency == "仙石" and "spiritStone" or "lingStone"

    -- 扣币（本地 clientCloud）
    GamePlayer.AddCurrency(currKey, -totalCost)

    -- 扣库存
    if item.stock and item.stock > 0 then
        item.stock = item.stock - count
    end

    -- 添加物品（统一走 bagItems，丹药服用时再转移到 pills）
    GamePlayer.AddItem({
        name   = item.name,
        count  = count,
        rarity = item.rarity or "common",
        desc   = item.desc or "",
    })

    GamePlayer.MarkDirty()
    local msg = "购买<c=gold>" .. item.name .. "x" .. count .. "</c>，花费<c=red>" .. item.currency .. totalCost .. "</c>"
    GamePlayer.AddLog(msg)
    GameQuest.SetMainFlag("purchased", true)
    return true, msg
end

-- ============================================================================
-- 寄售上架
-- ============================================================================

---@param itemIndex number bagItems 中的索引
---@param price number
---@param count number
---@return boolean, string|nil
function M.CanListItem(itemIndex, price, count)
    local p = GamePlayer.Get()
    if not p then return false, "数据未加载" end

    local config = DataItems.TRADING_POST
    local items = p.bagItems or {}
    if itemIndex < 1 or itemIndex > #items then return false, "无效的物品" end

    local item = items[itemIndex]
    if (item.count or 1) < count then return false, "物品数量不足" end
    if price <= 0 then return false, "定价必须大于0" end

    p.tradingListings = p.tradingListings or {}
    local activeCount = 0
    for _, l in ipairs(p.tradingListings) do
        if l.status == "selling" then activeCount = activeCount + 1 end
    end
    if activeCount >= config.maxListings then
        return false, "寄售栏位已满（最多" .. config.maxListings .. "个）"
    end

    return true, nil
end

---@param itemIndex number
---@param price number
---@param count number
---@return boolean, string
function M.DoListItem(itemIndex, price, count)
    local ok, reason = M.CanListItem(itemIndex, price, count)
    if not ok then return false, reason or "无法上架" end

    local p = GamePlayer.Get()
    local item = p.bagItems[itemIndex]

    if IsNetworkMode() then
        -- 网络模式：发远程事件，本地先移除背包
        local Shared = require("network.shared")
        local ClientNet = require("network.client_net")
        local data = VariantMap()
        data["Action"]   = Variant("list")
        data["ItemName"] = Variant(item.name)
        data["Price"]    = Variant(price)
        data["Count"]    = Variant(count)
        data["Rarity"]   = Variant(item.rarity or "common")
        data["Desc"]     = Variant(item.desc or "")
        ClientNet.SendToServer(Shared.EVENTS.REQ_MARKET_OP, data)

        GamePlayer.RemoveItem(itemIndex, count)
        GamePlayer.MarkDirty()
        return true, "上架请求已发送"
    end

    -- 单机模式
    local listingItem = {
        name       = item.name,
        rarity     = item.rarity or "common",
        desc       = item.desc or "",
        stock      = count,
        price      = price,
        refPrice   = price,
        status     = "selling",
        listedTime = "刚刚",
    }
    GamePlayer.RemoveItem(itemIndex, count)

    p.tradingListings = p.tradingListings or {}
    p.tradingListings[#p.tradingListings + 1] = listingItem

    GamePlayer.MarkDirty()
    local msg = "上架<c=gold>" .. item.name .. "x" .. count .. "</c>，单价<c=yellow>" .. price .. "灵石</c>"
    GamePlayer.AddLog(msg)
    return true, msg
end

-- ============================================================================
-- 寄售下架
-- ============================================================================

---@param listingIndex number
---@param listing? table 网络模式下直接传 listing 对象（含 listId）
---@return boolean, string
function M.DoDelistItem(listingIndex, listing)
    if IsNetworkMode() then
        if not listing or not listing.listId then
            return false, "无效的寄售物品"
        end
        local Shared = require("network.shared")
        local ClientNet = require("network.client_net")
        local data = VariantMap()
        data["Action"] = Variant("delist")
        data["ListId"] = Variant(tostring(listing.listId))
        ClientNet.SendToServer(Shared.EVENTS.REQ_MARKET_OP, data)
        return true, "下架请求已发送"
    end

    -- 单机模式
    local p = GamePlayer.Get()
    if not p then return false, "数据未加载" end

    p.tradingListings = p.tradingListings or {}
    if listingIndex < 1 or listingIndex > #p.tradingListings then
        return false, "无效的寄售物品"
    end

    listing = p.tradingListings[listingIndex]
    GamePlayer.AddItem({
        name   = listing.name,
        count  = listing.stock or 1,
        rarity = listing.rarity or "common",
        desc   = listing.desc or "",
    })
    table.remove(p.tradingListings, listingIndex)

    GamePlayer.MarkDirty()
    local msg = "下架<c=gold>" .. listing.name .. "</c>，已退回背包"
    GamePlayer.AddLog(msg)
    return true, msg
end

-- ============================================================================
-- 寄售购买（乐观更新 + 远程事件）
-- ============================================================================

---@param item table { name, price, stock, listId, rarity, desc }
---@return boolean, string
function M.DoBuyListing(item)
    if not item then return false, "无效的物品" end
    local p = GamePlayer.Get()
    if not p then return false, "数据未加载" end

    local config    = DataItems.TRADING_POST
    local totalCost = item.price * (item.stock or 1)
    local fee       = math.floor(totalCost * config.feeRate)
    local finalCost = totalCost + fee

    local balance = GamePlayer.GetCurrency("lingStone")
    if balance < finalCost then
        return false, "灵石不足"
    end

    if IsNetworkMode() then
        if not item.listId then return false, "无效的寄售物品" end

        -- 乐观更新：本地先扣币、加物品
        GamePlayer.AddCurrency("lingStone", -finalCost)
        M.AddItemToPlayer(item)
        GamePlayer.MarkDirty()

        -- 缓存回滚信息
        M.pendingBuy_ = {
            listId    = item.listId,
            finalCost = finalCost,
            itemName  = item.name,
            itemCount = item.stock or 1,
            rarity    = item.rarity or "common",
            desc      = item.desc or "",
        }

        -- 发远程事件
        local Shared = require("network.shared")
        local ClientNet = require("network.client_net")
        local data = VariantMap()
        data["Action"] = Variant("buy")
        data["ListId"] = Variant(tostring(item.listId))
        ClientNet.SendToServer(Shared.EVENTS.REQ_MARKET_OP, data)

        Toast.Show("购买请求已发送...", "info")
        return true, "购买请求已发送"
    end

    -- 单机模式
    GamePlayer.AddCurrency("lingStone", -finalCost)
    M.AddItemToPlayer(item)

    GamePlayer.MarkDirty()
    local msg = "购买<c=gold>" .. item.name .. "x" .. (item.stock or 1) .. "</c>，花费<c=red>灵石" .. finalCost .. "</c>（含手续费" .. fee .. "）"
    GamePlayer.AddLog(msg)
    return true, msg
end

-- ============================================================================
-- 内部工具
-- ============================================================================

--- 将物品添加到玩家背包（统一走 bagItems，丹药服用时再转移到 pills）
function M.AddItemToPlayer(item)
    local p = GamePlayer.Get()
    if not p then return end

    local count = item.stock or item.count or 1
    GamePlayer.AddItem({
        name   = item.name,
        count  = count,
        rarity = item.rarity or "common",
        desc   = item.desc or "",
    })
end

-- ============================================================================
-- 请求服务端数据
-- ============================================================================

function M.RequestBrowseListings()
    if not IsNetworkMode() then return end
    local Shared = require("network.shared")
    local ClientNet = require("network.client_net")
    local data = VariantMap()
    data["Action"] = Variant("browse")
    ClientNet.SendToServer(Shared.EVENTS.REQ_MARKET_OP, data)
end

function M.RequestMyListings()
    if not IsNetworkMode() then return end
    local Shared = require("network.shared")
    local ClientNet = require("network.client_net")
    local data = VariantMap()
    data["Action"] = Variant("myList")
    ClientNet.SendToServer(Shared.EVENTS.REQ_MARKET_OP, data)
end

---@return table|nil
function M.GetServerListings()
    return M.serverListings_
end

---@return table|nil
function M.GetMyListings()
    return M.myListings_
end

-- ============================================================================
-- 服务端回调处理（由 client_net.lua 中转调用）
-- ============================================================================

---@param eventData any
function M.OnMarketData(eventData)
    local action  = eventData["Action"]:GetString()
    local success = false
    local msg     = ""

    -- browse / myList 返回的是 Data 字段（JSON 列表）
    if action == "browse" then
        local json = eventData["Data"]:GetString()
        local ok2, listings = pcall(cjson.decode, json)
        if ok2 and type(listings) == "table" then
            M.serverListings_ = listings
            print("[GameMarket] 寄售列表更新, 共 " .. #listings .. " 条")
        end
        return

    elseif action == "myList" then
        local json = eventData["Data"]:GetString()
        local ok2, listings = pcall(cjson.decode, json)
        if ok2 and type(listings) == "table" then
            M.myListings_ = listings
            print("[GameMarket] 我的寄售更新, 共 " .. #listings .. " 条")
        end
        return
    end

    -- 其他操作返回 Success + Msg
    success = eventData["Success"]:GetBool()
    msg     = eventData["Msg"]:GetString()

    if action == "list" then
        if success then
            Toast.Show("上架成功", "success")
            GamePlayer.AddLog(msg)
        else
            Toast.Show(msg, "error")
        end

    elseif action == "delist" then
        if success then
            -- 退回背包
            local itemName  = eventData["ItemName"]:GetString()
            local itemCount = eventData["ItemCount"]:GetInt()
            local rarity    = eventData["Rarity"]:GetString()
            local desc      = eventData["Desc"]:GetString()
            for _ = 1, itemCount do
                GamePlayer.AddItem({
                    name   = itemName,
                    count  = 1,
                    rarity = rarity,
                    desc   = desc,
                })
            end
            GamePlayer.MarkDirty()
            Toast.Show("下架成功，物品已退回背包", "success")
            GamePlayer.AddLog("下架<c=gold>" .. itemName .. "</c>，已退回背包")
        else
            Toast.Show(msg, "error")
        end

    elseif action == "buy" then
        if success then
            -- 乐观更新已完成，确认成功
            local itemName  = eventData["ItemName"]:GetString()
            local itemCount = eventData["ItemCount"]:GetInt()
            M.pendingBuy_ = nil
            Toast.Show("购买成功: <c=gold>" .. itemName .. " x" .. itemCount .. "</c>", "success")
            GamePlayer.AddLog("购买寄售<c=gold>" .. itemName .. "x" .. itemCount .. "</c>")
            GameQuest.SetMainFlag("purchased", true)
        else
            -- 失败：回滚乐观更新
            M.RollbackPendingBuy()
            Toast.Show(msg, "error")
        end

    elseif action == "soldNotify" then
        Toast.Show(msg, "success")
        GamePlayer.AddLog(msg)

    else
        if success then
            Toast.Show(msg, "success")
        else
            Toast.Show(msg, "error")
        end
    end
end

--- 回滚乐观更新（购买失败时调用）
function M.RollbackPendingBuy()
    local pending = M.pendingBuy_
    if not pending then return end

    -- 退币
    GamePlayer.AddCurrency("lingStone", pending.finalCost)
    -- 移除物品（从背包找同名物品移除）
    local p = GamePlayer.Get()
    if p then
        local pillDef = DataItems.FindPillByName(pending.itemName)
        if pillDef then
            for _, pill in ipairs(p.pills or {}) do
                if pill.name == pending.itemName then
                    pill.count = (pill.count or 0) - pending.itemCount
                    if pill.count <= 0 then pill.count = 0 end
                    break
                end
            end
        else
            -- 移除 bagItems 中最后添加的同名物品
            local removed = 0
            local items = p.bagItems or {}
            for i = #items, 1, -1 do
                if items[i].name == pending.itemName and removed < pending.itemCount then
                    table.remove(items, i)
                    removed = removed + 1
                end
            end
        end
        GamePlayer.MarkDirty()
    end

    M.pendingBuy_ = nil
    print("[GameMarket] 已回滚乐观更新: " .. pending.itemName)
end

return M
