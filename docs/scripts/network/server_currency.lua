-- ============================================================================
-- 《问道长生》服务端货币模块
-- 职责：通过 serverCloud.money 原子操作处理灵石/仙石的增减查询
-- 安全：所有货币变动在服务端执行，客户端无法直接篡改余额
-- ============================================================================

local Shared = require("network.shared")
local EVENTS = Shared.EVENTS
---@diagnostic disable-next-line: undefined-global
local cjson  = cjson

local M = {}

-- 依赖注入
local deps_ = nil

-- 合法的货币 key 白名单
local VALID_CURRENCIES = {
    lingStone   = true,   -- 灵石
    spiritStone = true,   -- 仙石
}

-- ============================================================================
-- 初始化
-- ============================================================================

---@param deps table { SendToClient }
function M.Init(deps)
    deps_ = deps
    print("[ServerCurrency] 货币模块初始化完成")
end

-- ============================================================================
-- 工具函数
-- ============================================================================

--- 回复客户端货币操作结果
---@param userId number
---@param action string   "add"|"cost"|"get"
---@param success boolean
---@param data table|nil   附加数据
---@param msg string|nil   错误信息
---@param reqKey string|nil  请求标识（回传给客户端做回调匹配）
local function Reply(userId, action, success, data, msg, reqKey)
    local vm = VariantMap()
    vm["Action"]  = Variant(action)
    vm["Success"] = Variant(success)
    vm["Data"]    = Variant(cjson.encode(data or {}))
    vm["Msg"]     = Variant(msg or "")
    if reqKey then
        vm["ReqKey"] = Variant(reqKey)
    end
    deps_.SendToClient(userId, EVENTS.CURRENCY_RESP, vm)
end

-- ============================================================================
-- 请求分发
-- ============================================================================

---@param userId number
---@param eventData any
function M.HandleCurrencyOp(userId, eventData)
    if not serverCloud then
        Reply(userId, "unknown", false, nil, "serverCloud 不可用")
        return
    end

    local action = eventData["Action"]:GetString()
    local paramsStr = eventData["Params"]:GetString()
    local reqKey = ""
    pcall(function() reqKey = eventData["ReqKey"]:GetString() end)

    local ok, params = pcall(cjson.decode, paramsStr)
    if not ok then
        Reply(userId, action, false, nil, "参数解析失败", reqKey)
        return
    end

    -- get 操作不需要 currency 校验
    if action == "get" then
        M.DoGet(userId, reqKey)
        return
    end

    -- add/cost 操作需要校验货币类型
    local currency = params.currency
    if not currency or not VALID_CURRENCIES[currency] then
        Reply(userId, action, false, nil, "非法货币类型: " .. tostring(currency), reqKey)
        return
    end

    if action == "add" then
        M.DoAdd(userId, params, reqKey)
    elseif action == "cost" then
        M.DoCost(userId, params, reqKey)
    else
        Reply(userId, action, false, nil, "未知操作: " .. tostring(action), reqKey)
    end
end

-- ============================================================================
-- 货币操作实现
-- ============================================================================

--- 增加货币（奖励发放）
---@param userId number
---@param params table { currency, amount, reason? }
---@param reqKey string
function M.DoAdd(userId, params, reqKey)
    local currency = params.currency
    local amount   = tonumber(params.amount) or 0

    if amount <= 0 then
        Reply(userId, "add", false, nil, "增加数量必须大于0", reqKey)
        return
    end

    -- serverCloud.money:Add 不需要回调，始终成功
    serverCloud.money:Add(userId, currency, amount)
    print("[ServerCurrency] Add uid=" .. tostring(userId)
        .. " " .. currency .. "+" .. tostring(amount)
        .. " reason=" .. tostring(params.reason or ""))

    -- 加完后查询最新余额回传给客户端
    serverCloud.money:Get(userId, {
        ok = function(moneys)
            Reply(userId, "add", true, {
                currency = currency,
                amount   = amount,
                balance  = moneys[currency] or 0,
                allBalances = moneys,
            }, nil, reqKey)
        end,
        error = function(code, reason)
            -- Add 本身已成功，但查询余额失败，仍然算成功
            Reply(userId, "add", true, {
                currency = currency,
                amount   = amount,
                balance  = -1,  -- 表示未知
            }, "余额查询失败: " .. tostring(reason), reqKey)
        end,
    })
end

--- 扣除货币（消费、购买）
---@param userId number
---@param params table { currency, amount, reason? }
---@param reqKey string
function M.DoCost(userId, params, reqKey)
    local currency = params.currency
    local amount   = tonumber(params.amount) or 0

    if amount <= 0 then
        Reply(userId, "cost", false, nil, "扣除数量必须大于0", reqKey)
        return
    end

    serverCloud.money:Cost(userId, currency, amount, {
        ok = function()
            print("[ServerCurrency] Cost uid=" .. tostring(userId)
                .. " " .. currency .. "-" .. tostring(amount)
                .. " reason=" .. tostring(params.reason or ""))
            -- 扣除成功后查询最新余额
            serverCloud.money:Get(userId, {
                ok = function(moneys)
                    Reply(userId, "cost", true, {
                        currency = currency,
                        amount   = amount,
                        balance  = moneys[currency] or 0,
                        allBalances = moneys,
                    }, nil, reqKey)
                end,
                error = function(code, reason)
                    Reply(userId, "cost", true, {
                        currency = currency,
                        amount   = amount,
                        balance  = -1,
                    }, "余额查询失败: " .. tostring(reason), reqKey)
                end,
            })
        end,
        error = function(code, reason)
            print("[ServerCurrency] Cost FAILED uid=" .. tostring(userId)
                .. " " .. currency .. "-" .. tostring(amount)
                .. " reason=" .. tostring(reason))
            Reply(userId, "cost", false, nil,
                "余额不足或扣除失败: " .. tostring(reason), reqKey)
        end,
    })
end

--- 查询所有货币余额
---@param userId number
---@param reqKey string
function M.DoGet(userId, reqKey)
    serverCloud.money:Get(userId, {
        ok = function(moneys)
            Reply(userId, "get", true, {
                balances = moneys or {},
            }, nil, reqKey)
        end,
        error = function(code, reason)
            Reply(userId, "get", false, nil,
                "余额查询失败: " .. tostring(reason), reqKey)
        end,
    })
end

return M
