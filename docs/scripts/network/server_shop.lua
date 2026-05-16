-- ============================================================================
-- 《问道长生》服务端NPC商店模块
-- 职责：商品存在性校验 + 货币扣除（原子操作）+ 物品发放
-- 安全：防止客户端伪造价格/库存，所有校验在服务端完成
-- ============================================================================

local Shared = require("network.shared")
local EVENTS = Shared.EVENTS
local DataItems = require("data_items")
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
    print("[ServerShop] NPC商店模块初始化完成")
end

-- ============================================================================
-- 工具函数
-- ============================================================================

local function GetPlayerKey(params)
    local serverId = params.serverId or 1
    return "s" .. serverId .. "_player"
end

local function Reply(userId, success, data, msg)
    local vm = VariantMap()
    vm["Success"] = Variant(success)
    vm["Data"]    = Variant(cjson.encode(data or {}))
    vm["Msg"]     = Variant(msg or "")
    deps_.SendToClient(userId, EVENTS.SHOP_BUY_RESP, vm)
end

--- 在商品表中查找商品
---@param goodsName string
---@return table|nil
local function FindGoods(goodsName)
    for _, g in ipairs(DataItems.MARKET_GOODS) do
        if g.name == goodsName then return g end
    end
    return nil
end

-- ============================================================================
-- 商店购买处理
-- ============================================================================

---@param userId number
---@param eventData any
function M.HandleShopBuy(userId, eventData)
    print("[ServerShop] 收到购买请求 userId=" .. tostring(userId))

    if not serverCloud then
        Reply(userId, false, nil, "serverCloud 不可用")
        return
    end

    local paramsStr = eventData["Params"]:GetString()
    print("[ServerShop] paramsStr=" .. tostring(paramsStr))
    local ok, params = pcall(cjson.decode, paramsStr)
    if not ok then
        Reply(userId, false, nil, "参数解析失败")
        return
    end

    local goodsName = params.goodsName
    local count     = params.count or 1

    if not goodsName then
        Reply(userId, false, nil, "缺少商品名称")
        return
    end
    if count < 1 then
        Reply(userId, false, nil, "购买数量无效")
        return
    end

    -- 1. 查找商品配置（服务端数据表，客户端无法伪造价格）
    local goods = FindGoods(goodsName)
    if not goods then
        Reply(userId, false, nil, "未知商品: " .. goodsName)
        return
    end

    local totalCost = goods.price * count
    local moneyKey  = goods.currency == "仙石" and "spiritStone" or "lingStone"

    -- 2. 原子扣币
    serverCloud.money:Cost(userId, moneyKey, totalCost, {
        ok = function()
            -- 3. 扣币成功 → 读取 playerData 添加物品
            local playerKey = GetPlayerKey(params)
            serverCloud:Get(userId, playerKey, {
                ok = function(playerData)
                    playerData = playerData or {}
                    M.AddGoods(playerData, goods, count)

                    -- 4. 回写
                    serverCloud:Set(userId, playerKey, playerData, {
                        ok = function()
                            -- 5. 查询最新余额后回复
                            serverCloud.money:Get(userId, {
                                ok = function(moneys)
                                    Reply(userId, true, {
                                        goodsName = goodsName,
                                        count     = count,
                                        cost      = totalCost,
                                        currency  = goods.currency,
                                        balance   = moneys[moneyKey] or 0,
                                        bagItems  = playerData.bagItems,
                                        pills     = playerData.pills,
                                        artifacts = playerData.artifacts,
                                        skills    = playerData.skills,
                                    })
                                end,
                                error = function()
                                    -- 余额查询失败也回复成功（物品已发放）
                                    Reply(userId, true, {
                                        goodsName = goodsName,
                                        count     = count,
                                        cost      = totalCost,
                                        currency  = goods.currency,
                                        balance   = -1,
                                        bagItems  = playerData.bagItems,
                                        pills     = playerData.pills,
                                        artifacts = playerData.artifacts,
                                        skills    = playerData.skills,
                                    })
                                end,
                            })
                        end,
                        error = function(code, reason)
                            -- 回写失败，退回货币
                            serverCloud.money:Add(userId, moneyKey, totalCost, {
                                ok = function() end,
                                error = function() end,
                            })
                            Reply(userId, false, nil,
                                "数据回写失败: " .. tostring(reason))
                        end,
                    })
                end,
                error = function(code, reason)
                    -- 读取失败，退回货币
                    serverCloud.money:Add(userId, moneyKey, totalCost, {
                        ok = function() end,
                        error = function() end,
                    })
                    Reply(userId, false, nil,
                        "读取数据失败: " .. tostring(reason))
                end,
            })
        end,
        error = function(code, reason)
            Reply(userId, false, nil, goods.currency .. "不足")
        end,
    })
end

-- ============================================================================
-- 物品添加逻辑（与 game_market.lua DoBuyGoods 保持一致）
-- ============================================================================

--- 将商品添加到玩家数据
---@param playerData table
---@param goods table 商品定义
---@param count number
function M.AddGoods(playerData, goods, count)
    local category = goods.category or ""

    if category == "丹药" then
        -- 丹药堆叠到 pills
        local pills = playerData.pills or {}
        playerData.pills = pills
        local pillDef = DataItems.FindPillByName(goods.name)

        local found = false
        for _, pill in ipairs(pills) do
            if pill.name == goods.name then
                pill.count = (pill.count or 0) + count
                found = true
                break
            end
        end
        if not found then
            pills[#pills + 1] = {
                name    = goods.name,
                count   = count,
                quality = pillDef and pillDef.quality or "common",
                desc    = pillDef and pillDef.effect or "",
                effect  = pillDef and pillDef.effect or "",
            }
        end

    elseif category == "法宝" then
        -- 法宝添加到 artifacts（不堆叠）
        local artifacts = playerData.artifacts or {}
        playerData.artifacts = artifacts
        -- 查法宝定义
        local artDef = nil
        for _, a in ipairs(DataItems.ARTIFACTS) do
            if a.name == goods.name then artDef = a; break end
        end
        for _ = 1, count do
            artifacts[#artifacts + 1] = {
                name     = goods.name,
                quality  = artDef and artDef.quality or "common",
                slot     = artDef and artDef.slot or "weapon",
                effect   = artDef and artDef.effect or "",
                level    = 1,
                maxLevel = 10,
                equipped = false,
            }
        end

    elseif category == "功法" then
        -- 功法添加到 skills
        local skills = playerData.skills or {}
        playerData.skills = skills
        local found = false
        for _, s in ipairs(skills) do
            if s.name == goods.name then
                found = true
                break
            end
        end
        if not found then
            skills[#skills + 1] = {
                name     = goods.name,
                level    = 1,
                equipped = false,
            }
        end

    else
        -- 其他：添加到 bagItems
        local bagItems = playerData.bagItems or {}
        playerData.bagItems = bagItems
        local found = false
        for _, item in ipairs(bagItems) do
            if item.name == goods.name then
                item.count = (item.count or 0) + count
                found = true
                break
            end
        end
        if not found then
            bagItems[#bagItems + 1] = {
                name   = goods.name,
                count  = count,
                rarity = "common",
                desc   = "",
            }
        end
    end
end

return M
