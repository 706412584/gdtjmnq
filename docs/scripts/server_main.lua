-- ============================================================================
-- 《问道长生》服务端入口
-- 职责：连接管理 + serverCloud.list 寄售中转 + serverCloud.message 邮件中转
-- 架构：云变量方案（薄服务端，不管货币）
-- ============================================================================

local Shared           = require("network.shared")
local EVENTS           = Shared.EVENTS
local ServerMarket     = require("network.server_market")
local ServerSocial     = require("network.server_social")
local ServerCloudProxy = require("network.server_cloud_proxy")
local ServerOnline     = require("network.server_online")
local ServerCurrency   = require("network.server_currency")
local ServerCombat     = require("network.server_combat")
local ServerQuest      = require("network.server_quest")
local ServerCultivation = require("network.server_cultivation")
local ServerAlchemy    = require("network.server_alchemy")
local ServerShop       = require("network.server_shop")

require "LuaScripts/Utilities/Sample"

-- ============================================================================
-- Mock graphics（headless 模式）
-- ============================================================================

if GetGraphics() == nil then
    local mg = {
        SetWindowIcon = function() end,
        SetWindowTitleAndIcon = function() end,
        GetWidth  = function() return 1920 end,
        GetHeight = function() return 1080 end,
    }
    function GetGraphics() return mg end
    graphics = mg
    console  = { background = {} }
    function GetConsole() return console end
    debugHud = {}
    function GetDebugHud() return debugHud end
end

-- ============================================================================
-- 状态
-- ============================================================================

---@type table<string, any>   connKey -> Connection
local connections_  = {}
---@type table<string, number> connKey -> userId
local connUserIds_  = {}
---@type table<number, string> userId -> connKey（反查）
local userIdToConn_ = {}

local scene_ = nil

-- ============================================================================
-- 入口
-- ============================================================================

function Start()
    SampleStart()

    scene_ = Scene()
    scene_:CreateComponent("Octree")

    -- 注册远程事件
    Shared.RegisterServerEvents()

    -- 订阅连接事件
    SubscribeToEvent(EVENTS.REQ_MARKET_OP,  "HandleReqMarketOp")
    SubscribeToEvent(EVENTS.REQ_MAIL_FETCH, "HandleReqMailFetch")
    SubscribeToEvent(EVENTS.REQ_MAIL_CLAIM, "HandleReqMailClaim")
    SubscribeToEvent(EVENTS.CLOUD_REQ,      "HandleCloudReq")
    SubscribeToEvent(EVENTS.REQ_SOCIAL_OP,  "HandleReqSocialOp")
    SubscribeToEvent(EVENTS.REQ_SERVER_ONLINE, "HandleReqServerOnline")
    SubscribeToEvent(EVENTS.REQ_GM_SERVER_OP, "HandleReqGMServerOp")
    SubscribeToEvent(EVENTS.REQ_CURRENCY_OP, "HandleReqCurrencyOp")
    SubscribeToEvent(EVENTS.REQ_COMBAT_SETTLE, "HandleReqCombatSettle")
    SubscribeToEvent(EVENTS.REQ_QUEST_CLAIM,   "HandleReqQuestClaim")
    SubscribeToEvent(EVENTS.REQ_CULTIVATION_OP, "HandleReqCultivationOp")
    SubscribeToEvent(EVENTS.REQ_ALCHEMY_OP,     "HandleReqAlchemyOp")
    SubscribeToEvent(EVENTS.REQ_SHOP_BUY,       "HandleReqShopBuy")
    SubscribeToEvent("ClientDisconnected",  "HandleClientDisconnected")

    -- 初始化寄售坊模块
    ServerMarket.Init({
        connections    = connections_,
        connUserIds    = connUserIds_,
        userIdToConn   = userIdToConn_,
        SendToClient   = SendToClient,
    })

    -- 初始化社交模块
    ServerSocial.Init({
        connections    = connections_,
        connUserIds    = connUserIds_,
        userIdToConn   = userIdToConn_,
        SendToClient   = SendToClient,
    })

    -- 初始化云代理模块（clientCloud polyfill 后端）
    ServerCloudProxy.Init({
        SendToClient = SendToClient,
    })

    -- 初始化在线人数追踪模块
    ServerOnline.Init({
        SendToClient = SendToClient,
    })

    -- 初始化货币模块（serverCloud.money 原子操作）
    ServerCurrency.Init({
        SendToClient = SendToClient,
    })

    -- 初始化战斗结算模块（P1: 探索/试炼服务端校验）
    ServerCombat.Init({
        SendToClient = SendToClient,
    })

    -- 初始化任务奖励模块（P1: 任务条件+奖励服务端校验）
    ServerQuest.Init({
        SendToClient = SendToClient,
    })

    -- 初始化修炼/渡劫模块（P2: 渡劫随机数+小境界突破服务端校验）
    ServerCultivation.Init({
        SendToClient = SendToClient,
    })

    -- 初始化炼丹/法宝强化模块（P2: 炼丹随机数+强化随机数服务端判定）
    ServerAlchemy.Init({
        SendToClient = SendToClient,
    })

    -- 初始化NPC商店模块（P2: 价格+库存服务端校验）
    ServerShop.Init({
        SendToClient = SendToClient,
    })

    print("[Server] 《问道长生》服务端已启动（云变量方案 + 云代理 + 货币安全 + P1战斗/任务 + P2修炼/炼丹/商店）")
    print("[Server] serverCloud available: " .. tostring(serverCloud ~= nil))
end

function Stop()
    print("[Server] 服务端关闭")
end

-- ============================================================================
-- 连接管理
-- ============================================================================

--- 从 eventData 提取 userId 和 connKey
---@param eventData any
---@return number|nil userId
---@return string|nil connKey
local function GetSender(eventData)
    local connection = eventData["Connection"]:GetPtr("Connection")
    local connKey = tostring(connection)

    -- 新连接：注册
    if not connUserIds_[connKey] then
        local userId = 10001
        local identityUid = connection.identity["user_id"]
        if identityUid then
            userId = identityUid:GetInt64()
        end

        -- 同一 userId 已有旧连接 → 踢掉旧连接（双设备登录）
        local oldConnKey = userIdToConn_[userId]
        if oldConnKey and oldConnKey ~= connKey then
            local oldConn = connections_[oldConnKey]
            if oldConn then
                -- 先通知旧客户端被踢
                local kickData = VariantMap()
                kickData["Reason"] = Variant("duplicate_login")
                oldConn:SendRemoteEvent(EVENTS.KICKED, true, kickData)
                print("[Server] 踢掉旧连接: userId=" .. tostring(userId) .. " oldKey=" .. oldConnKey)
                -- 延迟断开旧连接（给事件发送留时间）
                oldConn:Disconnect(100)
            end
            -- 清理旧连接数据
            connections_[oldConnKey] = nil
            connUserIds_[oldConnKey] = nil
            ServerMarket.UnloadPlayerListings(userId)
        end

        connections_[connKey]  = connection
        connUserIds_[connKey]  = userId
        userIdToConn_[userId]  = connKey
        print("[Server] 玩家连接: userId=" .. tostring(userId))

        -- 加载玩家寄售到聚合表
        ServerMarket.LoadPlayerListings(userId)
    end

    return connUserIds_[connKey], connKey
end

function HandleClientDisconnected(eventType, eventData)
    local connection = eventData:GetPtr("Connection", "Connection")
    local connKey = tostring(connection)
    local userId = connUserIds_[connKey]

    connections_[connKey]  = nil
    connUserIds_[connKey]  = nil
    if userId then
        userIdToConn_[userId] = nil
        ServerMarket.UnloadPlayerListings(userId)
        ServerOnline.PlayerLeave(userId)
    end

    print("[Server] 玩家断开: userId=" .. tostring(userId))
end

-- ============================================================================
-- 工具函数
-- ============================================================================

--- 向指定玩家发送远程事件
---@param userId number
---@param eventName string
---@param data any VariantMap
function SendToClient(userId, eventName, data)
    local connKey = userIdToConn_[userId]
    if not connKey then return end
    local conn = connections_[connKey]
    if not conn then return end
    conn:SendRemoteEvent(eventName, true, data)
end

-- ============================================================================
-- 请求处理：寄售操作（统一入口）
-- ============================================================================

function HandleReqMarketOp(eventType, eventData)
    local userId = GetSender(eventData)
    if not userId then return end
    ServerMarket.HandleMarketOp(userId, eventData)
end

-- ============================================================================
-- 请求处理：社交操作（统一入口）
-- ============================================================================

function HandleReqSocialOp(eventType, eventData)
    local userId = GetSender(eventData)
    if not userId then return end
    ServerSocial.HandleSocialOp(userId, eventData)
end

-- ============================================================================
-- 请求处理：区服在线人数
-- ============================================================================

function HandleReqServerOnline(eventType, eventData)
    local userId = GetSender(eventData)
    if not userId then return end
    ServerOnline.HandleReqServerOnline(userId, eventData)
end

-- ============================================================================
-- 请求处理：[GM] 区服管理
-- ============================================================================

function HandleReqGMServerOp(eventType, eventData)
    local userId = GetSender(eventData)
    if not userId then return end
    -- TODO: 接入 GM 权限校验（上线前必须添加白名单/权限检查）
    ServerOnline.HandleGMServerOp(userId, eventData)
end

-- ============================================================================
-- 请求处理：货币操作（serverCloud.money 原子操作）
-- ============================================================================

function HandleReqCurrencyOp(eventType, eventData)
    local userId = GetSender(eventData)
    if not userId then return end
    ServerCurrency.HandleCurrencyOp(userId, eventData)
end

-- ============================================================================
-- 请求处理：战斗/探索/试炼结算（P1）
-- ============================================================================

function HandleReqCombatSettle(eventType, eventData)
    local userId = GetSender(eventData)
    if not userId then return end
    ServerCombat.HandleCombatSettle(userId, eventData)
end

-- ============================================================================
-- 请求处理：任务奖励领取（P1）
-- ============================================================================

function HandleReqQuestClaim(eventType, eventData)
    local userId = GetSender(eventData)
    if not userId then return end
    ServerQuest.HandleQuestClaim(userId, eventData)
end

-- ============================================================================
-- 请求处理：修炼/渡劫操作（P2）
-- ============================================================================

function HandleReqCultivationOp(eventType, eventData)
    local userId = GetSender(eventData)
    if not userId then return end
    ServerCultivation.HandleCultivationOp(userId, eventData)
end

-- ============================================================================
-- 请求处理：炼丹/法宝强化操作（P2）
-- ============================================================================

function HandleReqAlchemyOp(eventType, eventData)
    local userId = GetSender(eventData)
    if not userId then return end
    ServerAlchemy.HandleAlchemyOp(userId, eventData)
end

-- ============================================================================
-- 请求处理：NPC商店购买（P2）
-- ============================================================================

function HandleReqShopBuy(eventType, eventData)
    print("[Server] HandleReqShopBuy 被调用")
    local userId = GetSender(eventData)
    if not userId then
        print("[Server] HandleReqShopBuy: GetSender 返回 nil")
        return
    end
    print("[Server] HandleReqShopBuy userId=" .. tostring(userId))
    local ok2, err2 = pcall(ServerShop.HandleShopBuy, userId, eventData)
    if not ok2 then
        print("[Server] HandleReqShopBuy 异常: " .. tostring(err2))
    end
end

-- ============================================================================
-- 请求处理：云代理（clientCloud polyfill 后端）
-- ============================================================================

function HandleCloudReq(eventType, eventData)
    local userId = GetSender(eventData)
    if not userId then return end
    ServerCloudProxy.HandleCloudReq(userId, eventData)
end

-- ============================================================================
-- 请求处理：邮件
-- ============================================================================

--- 拉取未读邮件
function HandleReqMailFetch(eventType, eventData)
    local userId = GetSender(eventData)
    if not userId then return end

    if not serverCloud then
        print("[Server] serverCloud 不可用，无法拉取邮件")
        return
    end

    serverCloud.message:Get(userId, "trade", false, {
        ok = function(messages)
            ---@diagnostic disable-next-line: undefined-global
            local cjson = cjson
            local data = VariantMap()
            data["Data"] = Variant(cjson.encode(messages or {}))
            SendToClient(userId, EVENTS.MAIL_DATA, data)
            print("[Server] 发送 " .. #(messages or {}) .. " 封邮件给 uid=" .. tostring(userId))
        end,
        error = function(code, reason)
            print("[Server] 邮件拉取失败 uid=" .. tostring(userId) .. " " .. tostring(reason))
            local data = VariantMap()
            data["Data"] = Variant("[]")
            SendToClient(userId, EVENTS.MAIL_DATA, data)
        end,
    })
end

--- 领取邮件（标记已读 + 删除）
function HandleReqMailClaim(eventType, eventData)
    local userId = GetSender(eventData)
    if not userId then return end

    local messageIdStr = eventData["MessageId"]:GetString()
    local messageId = tonumber(messageIdStr) or 0

    if not serverCloud or messageId == 0 then
        local data = VariantMap()
        data["Success"]   = Variant(false)
        data["MessageId"] = Variant(messageIdStr)
        data["Msg"]       = Variant("无效的邮件")
        SendToClient(userId, EVENTS.MAIL_CLAIMED, data)
        return
    end

    serverCloud.message:MarkRead(messageId)
    serverCloud.message:Delete(messageId)

    local data = VariantMap()
    data["Success"]   = Variant(true)
    data["MessageId"] = Variant(messageIdStr)
    data["Msg"]       = Variant("领取成功")
    SendToClient(userId, EVENTS.MAIL_CLAIMED, data)

    print("[Server] 邮件领取 uid=" .. tostring(userId) .. " msgId=" .. messageIdStr)
end
