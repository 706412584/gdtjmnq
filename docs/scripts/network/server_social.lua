-- ============================================================================
-- 《问道长生》服务端社交模块
-- 职责：好友申请/同意/拒绝/解除/赠送好感
-- 存储：serverCloud.list 存好友关系，serverCloud.message 存好友申请
-- ============================================================================

local Shared = require("network.shared")
local EVENTS = Shared.EVENTS
local DataSocial = require("data_social")
---@diagnostic disable-next-line: undefined-global
local cjson = cjson

local M = {}

-- ============================================================================
-- 依赖注入（由 server_main.lua 调用）
-- ============================================================================

---@type table { connections, connUserIds, userIdToConn, SendToClient }
local deps_ = nil

---@param deps table
function M.Init(deps)
    deps_ = deps
    print("[ServerSocial] 社交模块初始化完成")
end

-- ============================================================================
-- 工具函数
-- ============================================================================

--- 统一回复客户端
---@param userId number
---@param action string
---@param success boolean
---@param msg string
---@param extra table|nil
local function Reply(userId, action, success, msg, extra)
    local data = VariantMap()
    data["Action"]  = Variant(action)
    data["Success"] = Variant(success)
    data["Msg"]     = Variant(msg)
    if extra then
        for k, v in pairs(extra) do
            data[k] = v
        end
    end
    deps_.SendToClient(userId, EVENTS.SOCIAL_DATA, data)
end

-- ============================================================================
-- 统一入口
-- ============================================================================

---@param userId number
---@param eventData any
function M.HandleSocialOp(userId, eventData)
    local action = eventData["Action"]:GetString()

    if action == DataSocial.ACTION.ADD_FRIEND then
        M.OnAddFriend(userId, eventData)
    elseif action == DataSocial.ACTION.ACCEPT_FRIEND then
        M.OnAcceptFriend(userId, eventData)
    elseif action == DataSocial.ACTION.REJECT_FRIEND then
        M.OnRejectFriend(userId, eventData)
    elseif action == DataSocial.ACTION.REJECT_ALL then
        M.OnRejectAll(userId)
    elseif action == DataSocial.ACTION.REMOVE_FRIEND then
        M.OnRemoveFriend(userId, eventData)
    elseif action == DataSocial.ACTION.SEND_GIFT then
        M.OnSendGift(userId, eventData)
    elseif action == DataSocial.ACTION.GET_FRIENDS then
        M.OnGetFriends(userId)
    elseif action == DataSocial.ACTION.GET_PENDING then
        M.OnGetPending(userId)
    else
        Reply(userId, action or "unknown", false, "未知社交操作")
    end
end

-- ============================================================================
-- 好友申请：通过 serverCloud.message 发送申请
-- 申请方 → message → 目标方
-- key = "friend_req"
-- value = { fromUid, fromName, fromRealm, relation, timestamp }
-- ============================================================================

function M.OnAddFriend(userId, eventData)
    if not serverCloud then
        Reply(userId, "add_friend", false, "服务端存储不可用")
        return
    end

    local targetUidStr = eventData["TargetUid"]:GetString()
    local targetUid    = tonumber(targetUidStr)
    local senderName   = eventData["SenderName"]:GetString()
    local senderRealm  = eventData["SenderRealm"]:GetString()

    if not targetUid or targetUid == userId then
        Reply(userId, "add_friend", false, "无效的目标玩家")
        return
    end

    -- 检查是否已经是好友（查自己的好友列表）
    serverCloud.list:Get(userId, "friends", {
        ok = function(list)
            for _, item in ipairs(list or {}) do
                local val = item.value or {}
                if val.friendUid == targetUid then
                    Reply(userId, "add_friend", false, "对方已经是你的好友")
                    return
                end
            end

            -- 检查好友上限
            if #(list or {}) >= DataSocial.RELATION_CONFIG.friend.maxCount then
                Reply(userId, "add_friend", false, "好友数量已达上限")
                return
            end

            -- 发送好友申请消息给目标玩家
            local reqValue = {
                fromUid   = userId,
                fromName  = senderName,
                fromRealm = senderRealm,
                relation  = "friend",
                timestamp = os.time(),
            }

            serverCloud.message:Send(userId, "friend_req", targetUid, reqValue, {
                ok = function(errorCode, errorDesc)
                    if errorCode == 0 or errorCode == nil then
                        print("[ServerSocial] 好友申请 " .. tostring(userId) .. " → " .. tostring(targetUid))
                        Reply(userId, "add_friend", true, "好友申请已发送")

                        -- 如果目标在线，通知刷新待处理列表
                        Reply(targetUid, "pending_notify", true, "你收到了一条好友申请")
                    else
                        Reply(userId, "add_friend", false, "申请发送失败: " .. tostring(errorDesc))
                    end
                end,
            })
        end,
        error = function(code, reason)
            Reply(userId, "add_friend", false, "查询好友列表失败")
        end,
    })
end

-- ============================================================================
-- 同意好友申请
-- 1. 读取 message，获取申请者 uid
-- 2. 双方各加一条 friends list item
-- 3. 删除 message
-- ============================================================================

function M.OnAcceptFriend(userId, eventData)
    if not serverCloud then
        Reply(userId, "accept_friend", false, "服务端存储不可用")
        return
    end

    local messageIdStr = eventData["MessageId"]:GetString()
    local messageId    = tonumber(messageIdStr) or 0
    -- 申请者信息由客户端从 pending list 传来
    local fromUid      = tonumber(eventData["FromUid"]:GetString()) or 0
    local fromName     = eventData["FromName"]:GetString()
    local fromRealm    = eventData["FromRealm"]:GetString()
    local myName       = eventData["MyName"]:GetString()
    local myRealm      = eventData["MyRealm"]:GetString()

    if fromUid == 0 then
        Reply(userId, "accept_friend", false, "无效的申请信息")
        return
    end

    -- 先检查自己好友是否已满
    serverCloud.list:Get(userId, "friends", {
        ok = function(myFriends)
            if #(myFriends or {}) >= DataSocial.RELATION_CONFIG.friend.maxCount then
                Reply(userId, "accept_friend", false, "你的好友数量已达上限")
                return
            end

            -- 检查对方好友是否已满
            serverCloud.list:Get(fromUid, "friends", {
                ok = function(otherFriends)
                    if #(otherFriends or {}) >= DataSocial.RELATION_CONFIG.friend.maxCount then
                        Reply(userId, "accept_friend", false, "对方好友数量已达上限")
                        return
                    end

                    -- 检查是否已有好友关系（防重复）
                    for _, item in ipairs(myFriends or {}) do
                        if (item.value or {}).friendUid == fromUid then
                            -- 已有关系，只需删除消息
                            if messageId > 0 then
                                serverCloud.message:MarkRead(messageId)
                                serverCloud.message:Delete(messageId)
                            end
                            Reply(userId, "accept_friend", false, "你们已经是好友了")
                            return
                        end
                    end

                    -- 双方互加好友
                    local now = os.time()

                    -- 我方记录
                    serverCloud.list:Add(userId, "friends", {
                        friendUid   = fromUid,
                        friendName  = fromName,
                        friendRealm = fromRealm,
                        relation    = "friend",
                        favor       = 0,
                        createdAt   = now,
                    })

                    -- 对方记录
                    serverCloud.list:Add(fromUid, "friends", {
                        friendUid   = userId,
                        friendName  = myName,
                        friendRealm = myRealm,
                        relation    = "friend",
                        favor       = 0,
                        createdAt   = now,
                    })

                    -- 删除申请消息
                    if messageId > 0 then
                        serverCloud.message:MarkRead(messageId)
                        serverCloud.message:Delete(messageId)
                    end

                    print("[ServerSocial] 好友建立 " .. tostring(userId) .. " <-> " .. tostring(fromUid))
                    Reply(userId, "accept_friend", true, "已成为好友")
                    Reply(fromUid, "friend_accepted", true, myName .. " 接受了你的好友申请")
                end,
                error = function()
                    Reply(userId, "accept_friend", false, "查询对方好友列表失败")
                end,
            })
        end,
        error = function()
            Reply(userId, "accept_friend", false, "查询好友列表失败")
        end,
    })
end

-- ============================================================================
-- 拒绝好友申请
-- ============================================================================

function M.OnRejectFriend(userId, eventData)
    if not serverCloud then
        Reply(userId, "reject_friend", false, "服务端存储不可用")
        return
    end

    local messageIdStr = eventData["MessageId"]:GetString()
    local messageId = tonumber(messageIdStr) or 0

    if messageId > 0 then
        serverCloud.message:MarkRead(messageId)
        serverCloud.message:Delete(messageId)
    end

    Reply(userId, "reject_friend", true, "已拒绝该申请")
end

-- ============================================================================
-- 一键拒绝全部
-- ============================================================================

function M.OnRejectAll(userId)
    if not serverCloud then
        Reply(userId, "reject_all", false, "服务端存储不可用")
        return
    end

    serverCloud.message:Get(userId, "friend_req", false, {
        ok = function(messages)
            local count = 0
            for _, msg in ipairs(messages or {}) do
                serverCloud.message:MarkRead(msg.message_id)
                serverCloud.message:Delete(msg.message_id)
                count = count + 1
            end
            Reply(userId, "reject_all", true, "已拒绝全部 " .. count .. " 条申请")
        end,
        error = function()
            Reply(userId, "reject_all", false, "获取申请列表失败")
        end,
    })
end

-- ============================================================================
-- 解除好友关系
-- 双向删除 friends list item
-- ============================================================================

function M.OnRemoveFriend(userId, eventData)
    if not serverCloud then
        Reply(userId, "remove_friend", false, "服务端存储不可用")
        return
    end

    local targetUid = tonumber(eventData["TargetUid"]:GetString()) or 0
    if targetUid == 0 then
        Reply(userId, "remove_friend", false, "无效的目标玩家")
        return
    end

    -- 删除我方记录
    serverCloud.list:Get(userId, "friends", {
        ok = function(list)
            for _, item in ipairs(list or {}) do
                if (item.value or {}).friendUid == targetUid then
                    serverCloud.list:Delete(item.list_id)
                    break
                end
            end

            -- 删除对方记录
            serverCloud.list:Get(targetUid, "friends", {
                ok = function(otherList)
                    for _, item in ipairs(otherList or {}) do
                        if (item.value or {}).friendUid == userId then
                            serverCloud.list:Delete(item.list_id)
                            break
                        end
                    end
                    print("[ServerSocial] 解除好友 " .. tostring(userId) .. " <-> " .. tostring(targetUid))
                    Reply(userId, "remove_friend", true, "已解除好友关系")
                    Reply(targetUid, "friend_removed", true, "好友关系已被解除")
                end,
                error = function()
                    -- 对方删除失败不影响主流程
                    Reply(userId, "remove_friend", true, "已解除好友关系")
                end,
            })
        end,
        error = function()
            Reply(userId, "remove_friend", false, "操作失败")
        end,
    })
end

-- ============================================================================
-- 赠送礼物（增加好感度）
-- ============================================================================

function M.OnSendGift(userId, eventData)
    if not serverCloud then
        Reply(userId, "send_gift", false, "服务端存储不可用")
        return
    end

    local targetUid = tonumber(eventData["TargetUid"]:GetString()) or 0
    local giftId    = eventData["GiftId"]:GetString()

    if targetUid == 0 then
        Reply(userId, "send_gift", false, "无效的目标玩家")
        return
    end

    -- 查找礼物配置
    local giftConfig = nil
    for _, g in ipairs(DataSocial.FAVOR_GIFTS) do
        if g.id == giftId then
            giftConfig = g
            break
        end
    end
    if not giftConfig then
        Reply(userId, "send_gift", false, "无效的礼物")
        return
    end

    -- 更新我方好友记录的好感度
    serverCloud.list:Get(userId, "friends", {
        ok = function(list)
            local found = false
            for _, item in ipairs(list or {}) do
                local val = item.value or {}
                if val.friendUid == targetUid then
                    found = true
                    val.favor = (val.favor or 0) + giftConfig.favor
                    serverCloud.list:Modify(item.list_id, val)

                    -- 同步更新对方记录中对我的好感度
                    serverCloud.list:Get(targetUid, "friends", {
                        ok = function(otherList)
                            for _, otherItem in ipairs(otherList or {}) do
                                local otherVal = otherItem.value or {}
                                if otherVal.friendUid == userId then
                                    otherVal.favor = (otherVal.favor or 0) + giftConfig.favor
                                    serverCloud.list:Modify(otherItem.list_id, otherVal)
                                    break
                                end
                            end
                        end,
                    })

                    Reply(userId, "send_gift", true,
                        "赠送" .. giftConfig.name .. "成功，好感+" .. giftConfig.favor, {
                            TargetUid = Variant(tostring(targetUid)),
                            NewFavor  = Variant(val.favor),
                        })
                    Reply(targetUid, "gift_received", true,
                        "收到好友赠送的" .. giftConfig.name .. "，好感+" .. giftConfig.favor)
                    break
                end
            end
            if not found then
                Reply(userId, "send_gift", false, "对方不是你的好友")
            end
        end,
        error = function()
            Reply(userId, "send_gift", false, "操作失败")
        end,
    })
end

-- ============================================================================
-- 获取好友列表
-- ============================================================================

function M.OnGetFriends(userId)
    if not serverCloud then
        Reply(userId, "get_friends", false, "服务端存储不可用")
        return
    end

    serverCloud.list:Get(userId, "friends", {
        ok = function(list)
            local friends = {}
            for _, item in ipairs(list or {}) do
                local val = item.value or {}
                val.listId = item.list_id
                friends[#friends + 1] = val
            end

            local data = VariantMap()
            data["Action"]  = Variant(DataSocial.RESP_ACTION.FRIEND_LIST)
            data["Success"] = Variant(true)
            data["Msg"]     = Variant("")
            data["Data"]    = Variant(cjson.encode(friends))
            deps_.SendToClient(userId, EVENTS.SOCIAL_DATA, data)
        end,
        error = function(code, reason)
            -- 首次查询可能无数据，不视为错误，返回空列表
            print("[ServerSocial] 好友列表查询异常(当作空): " .. tostring(reason))
            local data = VariantMap()
            data["Action"]  = Variant(DataSocial.RESP_ACTION.FRIEND_LIST)
            data["Success"] = Variant(true)
            data["Msg"]     = Variant("")
            data["Data"]    = Variant("[]")
            deps_.SendToClient(userId, EVENTS.SOCIAL_DATA, data)
        end,
    })
end

-- ============================================================================
-- 获取待处理好友申请
-- ============================================================================

function M.OnGetPending(userId)
    if not serverCloud then
        Reply(userId, "get_pending", false, "服务端存储不可用")
        return
    end

    serverCloud.message:Get(userId, "friend_req", false, {
        ok = function(messages)
            local pending = {}
            for _, msg in ipairs(messages or {}) do
                local val = msg.value or {}
                val.messageId = msg.message_id
                pending[#pending + 1] = val
            end

            local data = VariantMap()
            data["Action"]  = Variant(DataSocial.RESP_ACTION.PENDING_LIST)
            data["Success"] = Variant(true)
            data["Msg"]     = Variant("")
            data["Data"]    = Variant(cjson.encode(pending))
            deps_.SendToClient(userId, EVENTS.SOCIAL_DATA, data)
        end,
        error = function(code, reason)
            -- 首次查询可能无消息，不视为错误，返回空列表
            print("[ServerSocial] 申请列表查询异常(当作空): " .. tostring(reason))
            local data = VariantMap()
            data["Action"]  = Variant(DataSocial.RESP_ACTION.PENDING_LIST)
            data["Success"] = Variant(true)
            data["Msg"]     = Variant("")
            data["Data"]    = Variant("[]")
            deps_.SendToClient(userId, EVENTS.SOCIAL_DATA, data)
        end,
    })
end

return M
