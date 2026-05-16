-- ============================================================================
-- 《问道长生》客户端社交逻辑
-- 职责：发送社交请求、缓存好友/申请数据、对外暴露状态查询接口
-- ============================================================================

local Shared     = require("network.shared")
local EVENTS     = Shared.EVENTS
local ClientNet  = require("network.client_net")
local DataSocial = require("data_social")
local Toast      = require("ui_toast")
local GamePlayer = require("game_player")
---@diagnostic disable-next-line: undefined-global
local cjson      = cjson

local M = {}

-- ============================================================================
-- 缓存数据
-- ============================================================================

local friends_    = {}    -- 好友列表 { friendUid, friendName, friendRealm, relation, favor, ... }
local pending_    = {}    -- 待处理申请 { fromUid, fromName, fromRealm, messageId, ... }
local onRefresh_  = nil   -- UI 刷新回调 function()

-- ============================================================================
-- 注册 UI 刷新回调
-- ============================================================================

---@param fn fun()
function M.SetRefreshCallback(fn)
    onRefresh_ = fn
end

local function NotifyRefresh()
    if onRefresh_ then
        onRefresh_()
    end
end

-- ============================================================================
-- 数据访问
-- ============================================================================

---@return table[]
function M.GetFriends()
    return friends_
end

---@return table[]
function M.GetPending()
    return pending_
end

---@return number
function M.GetFriendCount()
    return #friends_
end

---@return number
function M.GetPendingCount()
    return #pending_
end

-- ============================================================================
-- 发送请求到服务端（统一通过 ReqSocialOp 事件）
-- ============================================================================

---@param action string
---@param extra table|nil
---@return boolean
local function SendSocialOp(action, extra)
    local data = VariantMap()
    data["Action"] = Variant(action)
    if extra then
        for k, v in pairs(extra) do
            data[k] = Variant(tostring(v))
        end
    end
    return ClientNet.SendToServer(EVENTS.REQ_SOCIAL_OP, data)
end

-- ============================================================================
-- 对外操作接口
-- ============================================================================

--- 请求好友列表
function M.RequestFriends()
    SendSocialOp(DataSocial.ACTION.GET_FRIENDS)
end

--- 请求待处理申请列表
function M.RequestPending()
    SendSocialOp(DataSocial.ACTION.GET_PENDING)
end

--- 发送好友申请
---@param targetUid number|string
function M.AddFriend(targetUid)
    local p = GamePlayer.Get()
    if not p then
        Toast.Show("数据未加载", { variant = "error" })
        return
    end
    SendSocialOp(DataSocial.ACTION.ADD_FRIEND, {
        TargetUid  = targetUid,
        SenderName = p.name or "无名",
        SenderRealm = p.realmName or "凡人",
    })
end

--- 同意好友申请
---@param pendingItem table { messageId, fromUid, fromName, fromRealm }
function M.AcceptFriend(pendingItem)
    local p = GamePlayer.Get()
    if not p then return end
    SendSocialOp(DataSocial.ACTION.ACCEPT_FRIEND, {
        MessageId = pendingItem.messageId or 0,
        FromUid   = pendingItem.fromUid or 0,
        FromName  = pendingItem.fromName or "",
        FromRealm = pendingItem.fromRealm or "",
        MyName    = p.name or "无名",
        MyRealm   = p.realmName or "凡人",
    })
end

--- 拒绝好友申请
---@param pendingItem table { messageId }
function M.RejectFriend(pendingItem)
    SendSocialOp(DataSocial.ACTION.REJECT_FRIEND, {
        MessageId = pendingItem.messageId or 0,
    })
end

--- 一键拒绝全部
function M.RejectAll()
    SendSocialOp(DataSocial.ACTION.REJECT_ALL)
end

--- 解除好友关系
---@param targetUid number|string
function M.RemoveFriend(targetUid)
    SendSocialOp(DataSocial.ACTION.REMOVE_FRIEND, {
        TargetUid = targetUid,
    })
end

--- 赠送礼物
---@param targetUid number|string
---@param giftId string
function M.SendGift(targetUid, giftId)
    SendSocialOp(DataSocial.ACTION.SEND_GIFT, {
        TargetUid = targetUid,
        GiftId    = giftId,
    })
end

-- ============================================================================
-- 服务端回复处理（由 client_net.lua 中转调用）
-- ============================================================================

---@param eventData any
function M.OnSocialData(eventData)
    local action  = eventData:GetString("Action")
    local success = eventData:GetBool("Success")
    local msg     = eventData:GetString("Msg")  -- 可能为空字符串（列表回复没有 Msg 字段）

    -- 好友列表回复
    if action == DataSocial.RESP_ACTION.FRIEND_LIST then
        if success then
            local jsonStr = eventData["Data"]:GetString()
            friends_ = cjson.decode(jsonStr) or {}
            print("[GameSocial] 收到好友列表: " .. #friends_ .. " 人")
        end
        NotifyRefresh()
        return
    end

    -- 待处理申请列表回复
    if action == DataSocial.RESP_ACTION.PENDING_LIST then
        if success then
            local jsonStr = eventData["Data"]:GetString()
            pending_ = cjson.decode(jsonStr) or {}
            print("[GameSocial] 收到待处理申请: " .. #pending_ .. " 条")
        end
        NotifyRefresh()
        return
    end

    -- 操作结果（add_friend / accept_friend / reject_friend / remove_friend / send_gift 等）
    if msg and msg ~= "" then
        Toast.Show(msg, { variant = success and "success" or "error" })
    end

    -- 操作成功后刷新数据
    if success then
        if action == "accept_friend" or action == "remove_friend"
            or action == "friend_accepted" or action == "friend_removed" then
            M.RequestFriends()
        end
        if action == "accept_friend" or action == "reject_friend"
            or action == "reject_all" then
            M.RequestPending()
        end
        -- 收到礼物或好友接受通知 → 刷新列表
        if action == "gift_received" or action == "pending_notify" then
            M.RequestFriends()
            M.RequestPending()
        end
    end
end

return M
