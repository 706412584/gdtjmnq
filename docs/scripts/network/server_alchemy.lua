-- ============================================================================
-- 《问道长生》服务端炼丹/法宝强化模块
-- 职责：炼丹成功率服务端判定 + 法宝强化随机数服务端生成
-- 安全：随机数在服务端生成，客户端无法伪造炼丹/强化结果
-- ============================================================================

local Shared = require("network.shared")
local EVENTS = Shared.EVENTS
local DataItems = require("data_items")
---@diagnostic disable-next-line: undefined-global
local cjson = cjson

local M = {}
local deps_ = nil

-- 气运 → 炼丹成功率加成（与 game_alchemy.lua 保持一致）
local FORTUNE_BONUS = {
    ["低迷"] = -5,
    ["普通"] = 0,
    ["小吉"] = 5,
    ["大吉"] = 10,
    ["天命"] = 15,
}

-- ============================================================================
-- 初始化
-- ============================================================================

---@param deps table { SendToClient }
function M.Init(deps)
    deps_ = deps
    print("[ServerAlchemy] 炼丹/法宝强化模块初始化完成")
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
    deps_.SendToClient(userId, EVENTS.ALCHEMY_RESP, vm)
end

-- ============================================================================
-- 请求分发
-- ============================================================================

---@param userId number
---@param eventData any
function M.HandleAlchemyOp(userId, eventData)
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

    if action == "alchemy" then
        M.DoAlchemy(userId, params)
    elseif action == "enhance_artifact" then
        M.DoEnhanceArtifact(userId, params)
    else
        Reply(userId, action, false, nil, "未知操作: " .. tostring(action))
    end
end

-- ============================================================================
-- 炼丹（服务端判定）
-- ============================================================================

--- 炼丹：服务端校验材料 + 投骰判定 + 写入结果
---@param userId number
---@param params table { serverId, recipeId }
function M.DoAlchemy(userId, params)
    local playerKey = GetPlayerKey(params)
    local recipeId  = params.recipeId

    if not recipeId then
        Reply(userId, "alchemy", false, nil, "缺少丹方 ID")
        return
    end

    local recipe = DataItems.FindPill(recipeId)
    if not recipe then
        Reply(userId, "alchemy", false, nil, "未知丹方")
        return
    end
    if not recipe.materials then
        Reply(userId, "alchemy", false, nil, "丹方缺少材料配置")
        return
    end

    serverCloud:Get(userId, playerKey, {
        ok = function(playerData)
            playerData = playerData or {}

            -- 1. 校验材料是否足够
            local bagItems = playerData.bagItems or {}
            for matName, needCount in pairs(recipe.materials) do
                local have = 0
                for _, item in ipairs(bagItems) do
                    if item.name == matName then
                        have = item.count or 0
                        break
                    end
                end
                if have < needCount then
                    Reply(userId, "alchemy", false, nil, matName .. "不足")
                    return
                end
            end

            -- 2. 消耗材料
            for matName, needCount in pairs(recipe.materials) do
                for _, item in ipairs(bagItems) do
                    if item.name == matName then
                        item.count = (item.count or 0) - needCount
                        break
                    end
                end
            end
            -- 清理 count <= 0 的材料
            local newBag = {}
            for _, item in ipairs(bagItems) do
                if (item.count or 0) > 0 then
                    newBag[#newBag + 1] = item
                end
            end
            playerData.bagItems = newBag

            -- 3. 计算最终成功率（基础 + 气运加成）
            local baseRate = recipe.rate or 50
            local fortune  = playerData.fortune or "普通"
            local bonus    = FORTUNE_BONUS[fortune] or 0
            local finalRate = math.max(1, math.min(100, baseRate + bonus))

            -- 4. 服务端投骰
            local roll = math.random(100)
            local success = roll <= finalRate

            if success then
                -- 成功：添加丹药到 pills 列表（堆叠同名）
                local pills = playerData.pills or {}
                playerData.pills = pills
                local found = false
                for _, pill in ipairs(pills) do
                    if pill.name == recipe.name then
                        pill.count = (pill.count or 0) + 1
                        found = true
                        break
                    end
                end
                if not found then
                    pills[#pills + 1] = {
                        name    = recipe.name,
                        count   = 1,
                        quality = recipe.quality or "common",
                        desc    = recipe.effect or "",
                        effect  = recipe.effect or "",
                    }
                end
            end

            -- 5. 回写 playerData
            serverCloud:Set(userId, playerKey, playerData, {
                ok = function()
                    Reply(userId, "alchemy", true, {
                        success   = success,
                        pillName  = recipe.name,
                        rate      = finalRate,
                        roll      = roll,
                        recipeId  = recipeId,
                        bagItems  = playerData.bagItems,
                        pills     = playerData.pills,
                    })
                end,
                error = function(code, reason)
                    Reply(userId, "alchemy", false, nil,
                        "数据回写失败: " .. tostring(reason))
                end,
            })
        end,
        error = function(code, reason)
            Reply(userId, "alchemy", false, nil,
                "读取数据失败: " .. tostring(reason))
        end,
    })
end

-- ============================================================================
-- 法宝强化（服务端判定）
-- ============================================================================

--- 法宝强化：服务端校验等级+货币 + 投骰判定 + 写入结果
---@param userId number
---@param params table { serverId, artName }
function M.DoEnhanceArtifact(userId, params)
    local playerKey = GetPlayerKey(params)
    local artName   = params.artName

    if not artName then
        Reply(userId, "enhance_artifact", false, nil, "缺少法宝名称")
        return
    end

    serverCloud:Get(userId, playerKey, {
        ok = function(playerData)
            playerData = playerData or {}

            -- 1. 查找法宝
            local art = nil
            for _, a in ipairs(playerData.artifacts or {}) do
                if a.name == artName then
                    art = a
                    break
                end
            end
            if not art then
                Reply(userId, "enhance_artifact", false, nil, "未拥有该法宝")
                return
            end

            local curLevel = art.level or 1
            local maxLevel = art.maxLevel or 10

            if curLevel >= maxLevel then
                Reply(userId, "enhance_artifact", false, nil, "已达最高强化等级")
                return
            end

            -- 2. 获取强化配置
            local enhInfo = DataItems.GetEnhanceInfo(curLevel)
            if not enhInfo then
                Reply(userId, "enhance_artifact", false, nil, "无法获取强化配置")
                return
            end

            -- 3. 扣除货币（通过 serverCloud.money 原子操作）
            local moneyKey = enhInfo.currency == "仙石" and "spiritStone" or "lingStone"
            serverCloud.money:Cost(userId, moneyKey, enhInfo.cost, {
                ok = function()
                    -- 4. 服务端投骰
                    local roll = math.random(1, 100)
                    local success = roll <= enhInfo.rate

                    if success then
                        art.level = curLevel + 1
                    end

                    -- 5. 回写 playerData
                    serverCloud:Set(userId, playerKey, playerData, {
                        ok = function()
                            -- 6. 查询最新余额后回复
                            serverCloud.money:Get(userId, {
                                ok = function(moneys)
                                    Reply(userId, "enhance_artifact", true, {
                                        success   = success,
                                        artName   = artName,
                                        oldLevel  = curLevel,
                                        newLevel  = art.level or curLevel,
                                        rate      = enhInfo.rate,
                                        roll      = roll,
                                        cost      = enhInfo.cost,
                                        currency  = enhInfo.currency,
                                        balance   = moneys[moneyKey] or 0,
                                    })
                                end,
                                error = function()
                                    Reply(userId, "enhance_artifact", true, {
                                        success   = success,
                                        artName   = artName,
                                        oldLevel  = curLevel,
                                        newLevel  = art.level or curLevel,
                                        rate      = enhInfo.rate,
                                        roll      = roll,
                                        cost      = enhInfo.cost,
                                        currency  = enhInfo.currency,
                                        balance   = -1,
                                    })
                                end,
                            })
                        end,
                        error = function(code, reason)
                            -- 数据回写失败，但货币已扣：需退回
                            serverCloud.money:Add(userId, moneyKey, enhInfo.cost, {
                                ok = function() end,
                                error = function() end,
                            })
                            Reply(userId, "enhance_artifact", false, nil,
                                "数据回写失败: " .. tostring(reason))
                        end,
                    })
                end,
                error = function(code, reason)
                    Reply(userId, "enhance_artifact", false, nil,
                        enhInfo.currency .. "不足")
                end,
            })
        end,
        error = function(code, reason)
            Reply(userId, "enhance_artifact", false, nil,
                "读取数据失败: " .. tostring(reason))
        end,
    })
end

return M
