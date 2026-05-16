-- ============================================================================
-- 《问道长生》网络共享模块
-- 职责：事件常量定义、远程事件注册
-- 架构：云变量方案（clientCloud货币 + serverCloud.list寄售 + serverCloud.message邮件）
-- ============================================================================

local M = {}

-- ============================================================================
-- 远程事件名常量（6个，精简自旧版12个）
-- ============================================================================

M.EVENTS = {
    -- 客户端 → 服务端（5个）
    REQ_MARKET_OP  = "ReqMarketOp",    -- 统一寄售操作（Action: browse/myList/list/delist/buy）
    REQ_MAIL_FETCH = "ReqMailFetch",   -- 拉取未读邮件
    REQ_MAIL_CLAIM = "ReqMailClaim",   -- 领取邮件（MessageId）
    CLOUD_REQ      = "CloudReq",       -- clientCloud 代理请求（Method + Params JSON）
    REQ_SOCIAL_OP  = "ReqSocialOp",    -- 社交操作（Action: add_friend/accept_friend/...）
    REQ_SERVER_ONLINE = "ReqServerOnline", -- 区服在线（Action: query/join）
    REQ_GM_SERVER_OP  = "ReqGMServerOp",   -- [GM] 区服管理操作（Action: get_counts/get_players/force_leave/set_count/...）
    REQ_CURRENCY_OP   = "ReqCurrencyOp",   -- 货币操作（Action: add/cost/get，走 serverCloud.money 原子操作）
    REQ_COMBAT_SETTLE = "ReqCombatSettle", -- P1: 战斗/探索/试炼结算（Action: explore_combat/explore_gather/trial_settle）
    REQ_QUEST_CLAIM   = "ReqQuestClaim",   -- P1: 任务奖励领取（QuestId）
    REQ_CULTIVATION_OP = "ReqCultivationOp", -- P2: 修炼/渡劫操作（Action: tribulation/advance_sub）
    REQ_ALCHEMY_OP     = "ReqAlchemyOp",     -- P2: 炼丹/法宝强化（Action: alchemy/enhance_artifact）
    REQ_SHOP_BUY       = "ReqShopBuy",       -- P2: NPC商店购买（GoodsName + Count）

    -- 服务端 → 客户端
    MARKET_DATA    = "MarketData",     -- 统一寄售回复（Action + Data/Success/Msg）
    MAIL_DATA      = "MailData",       -- 邮件列表（JSON）
    MAIL_CLAIMED   = "MailClaimed",    -- 领取结果（Success + MessageId）
    CLOUD_RESP     = "CloudResp",      -- clientCloud 代理回复（ReqId + Success + Payload JSON）
    SOCIAL_DATA    = "SocialData",     -- 社交数据回复（Action + Data/Success/Msg）
    KICKED         = "Kicked",         -- 被踢下线通知（Reason: duplicate_login 等）
    SERVER_ONLINE_DATA = "ServerOnlineData", -- 各区服在线人数数据（Data JSON）
    GM_SERVER_ONLINE_RESP = "GMServerOnlineResp", -- [GM] 区服管理回复（Action + Data JSON）
    CURRENCY_RESP  = "CurrencyResp",   -- 货币操作回复（Action + Success + Data JSON）
    COMBAT_SETTLE_RESP = "CombatSettleResp", -- P1: 战斗/探索/试炼结算回复
    QUEST_CLAIM_RESP   = "QuestClaimResp",   -- P1: 任务奖励领取回复
    CULTIVATION_RESP   = "CultivationResp",  -- P2: 修炼/渡劫回复
    ALCHEMY_RESP       = "AlchemyResp",      -- P2: 炼丹/法宝强化回复
    SHOP_BUY_RESP      = "ShopBuyResp",      -- P2: NPC商店购买回复
}

-- 服务器需要接收的事件（客户端发送）
M.SERVER_EVENTS = {
    M.EVENTS.REQ_MARKET_OP,
    M.EVENTS.REQ_MAIL_FETCH,
    M.EVENTS.REQ_MAIL_CLAIM,
    M.EVENTS.CLOUD_REQ,
    M.EVENTS.REQ_SOCIAL_OP,
    M.EVENTS.REQ_SERVER_ONLINE,
    M.EVENTS.REQ_GM_SERVER_OP,
    M.EVENTS.REQ_CURRENCY_OP,
    M.EVENTS.REQ_COMBAT_SETTLE,
    M.EVENTS.REQ_QUEST_CLAIM,
    M.EVENTS.REQ_CULTIVATION_OP,
    M.EVENTS.REQ_ALCHEMY_OP,
    M.EVENTS.REQ_SHOP_BUY,
}

-- 客户端需要接收的事件（服务器发送）
M.CLIENT_EVENTS = {
    M.EVENTS.MARKET_DATA,
    M.EVENTS.MAIL_DATA,
    M.EVENTS.MAIL_CLAIMED,
    M.EVENTS.CLOUD_RESP,
    M.EVENTS.SOCIAL_DATA,
    M.EVENTS.KICKED,
    M.EVENTS.SERVER_ONLINE_DATA,
    M.EVENTS.GM_SERVER_ONLINE_RESP,
    M.EVENTS.CURRENCY_RESP,
    M.EVENTS.COMBAT_SETTLE_RESP,
    M.EVENTS.QUEST_CLAIM_RESP,
    M.EVENTS.CULTIVATION_RESP,
    M.EVENTS.ALCHEMY_RESP,
    M.EVENTS.SHOP_BUY_RESP,
}

--- 注册服务器端事件
function M.RegisterServerEvents()
    for _, eventName in ipairs(M.SERVER_EVENTS) do
        network:RegisterRemoteEvent(eventName)
    end
    print("[Shared] 已注册 " .. #M.SERVER_EVENTS .. " 个服务端事件")
end

--- 注册客户端事件
function M.RegisterClientEvents()
    for _, eventName in ipairs(M.CLIENT_EVENTS) do
        network:RegisterRemoteEvent(eventName)
    end
    print("[Shared] 已注册 " .. #M.CLIENT_EVENTS .. " 个客户端事件")
end

return M
