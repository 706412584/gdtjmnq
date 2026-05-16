-- ============================================================================
-- 《问道长生》社交页面
-- 好友列表 / 待处理申请 / 添加好友 / 赠送礼物
-- ============================================================================

local UI         = require("urhox-libs/UI")
local Theme      = require("ui_theme")
local Comp       = require("ui_components")
local Router     = require("ui_router")
local GamePlayer = require("game_player")
local GameSocial = require("game_social")
local DataSocial = require("data_social")
local Toast      = require("ui_toast")

local M = {}

-- 当前子标签：friends / pending
local currentTab_ = "friends"

-- 弹窗状态
local showAddDialog_  = false   -- 添加好友弹窗
local addInputText_   = ""      -- 输入的ID文本
local showGiftDialog_ = false   -- 赠送礼物弹窗
local giftTarget_     = nil     -- 赠送目标好友对象
local dataRequested_  = false   -- 是否已经请求过数据（防止 Build→请求→回调→RebuildUI→Build 死循环）

-- ============================================================================
-- 初始化：进入页面时请求数据
-- ============================================================================
local function RequestData()
    GameSocial.RequestFriends()
    GameSocial.RequestPending()
end

-- ============================================================================
-- 返回行
-- ============================================================================
local function BuildBackRow()
    local pendingCount = GameSocial.GetPendingCount()
    local pendingHint = ""
    if pendingCount > 0 then
        pendingHint = " (" .. pendingCount .. ")"
    end

    return UI.Panel {
        width = "100%",
        flexDirection = "row",
        alignItems = "center",
        justifyContent = "space-between",
        children = {
            UI.Panel {
                flexDirection = "row", alignItems = "center", gap = 8,
                children = {
                    UI.Panel {
                        paddingHorizontal = 8, paddingVertical = 4, cursor = "pointer",
                        onClick = function(self)
                            Router.EnterState(Router.STATE_MORE)
                        end,
                        children = {
                            UI.Label { text = "< 返回", fontSize = Theme.fontSize.body, color = Theme.colors.gold },
                        },
                    },
                    UI.Label {
                        text = "游戏关系",
                        fontSize = Theme.fontSize.heading, fontWeight = "bold", color = Theme.colors.textGold,
                    },
                },
            },
            -- 好友数量
            UI.Label {
                text = "好友: " .. GameSocial.GetFriendCount() .. "/" .. DataSocial.RELATION_CONFIG.friend.maxCount,
                fontSize = Theme.fontSize.small, color = Theme.colors.textSecondary,
            },
        },
    }
end

-- ============================================================================
-- 子标签栏
-- ============================================================================
local function BuildTabBar()
    local pendingCount = GameSocial.GetPendingCount()

    local function TabBtn(label, key, badge)
        local isActive = currentTab_ == key
        local text = label
        if badge and badge > 0 then
            text = label .. "(" .. badge .. ")"
        end
        return UI.Panel {
            flex = 1,
            paddingVertical = 8,
            alignItems = "center",
            cursor = "pointer",
            borderBottomWidth = isActive and 2 or 0,
            borderColor = Theme.colors.gold,
            onClick = function(self)
                if currentTab_ ~= key then
                    currentTab_ = key
                    Router.RebuildUI()
                end
            end,
            children = {
                UI.Label {
                    text = text,
                    fontSize = Theme.fontSize.body,
                    fontWeight = isActive and "bold" or "normal",
                    color = isActive and Theme.colors.textGold or Theme.colors.textSecondary,
                },
            },
        }
    end

    return UI.Panel {
        width = "100%",
        flexDirection = "row",
        backgroundColor = Theme.colors.bgDark,
        borderRadius = Theme.radius.sm,
        children = {
            TabBtn("好友列表", "friends"),
            TabBtn("关系邀请", "pending", pendingCount),
        },
    }
end

-- ============================================================================
-- 操作按钮行：添加好友 / 一键拒绝
-- ============================================================================
local function BuildActionBar()
    local children = {}

    -- 添加好友按钮
    children[#children + 1] = Comp.BuildInkButton("添加好友", function()
        showAddDialog_ = true
        addInputText_ = ""
        Router.RebuildUI()
    end, { flex = 1 })

    if currentTab_ == "pending" and GameSocial.GetPendingCount() > 0 then
        children[#children + 1] = Comp.BuildSecondaryButton("一键拒绝", function()
            GameSocial.RejectAll()
        end, { flex = 1 })
    end

    return UI.Panel {
        width = "100%",
        flexDirection = "row",
        gap = 10,
        children = children,
    }
end

-- ============================================================================
-- 好友卡片
-- ============================================================================
local function BuildFriendCard(friend)
    local favorLv = DataSocial.GetFavorLevel(friend.favor or 0)

    -- 关系标签
    local relationLabel = "好友"
    local relationColor = DataSocial.RELATION_CONFIG.friend.color
    local cfg = DataSocial.RELATION_CONFIG[friend.relation]
    if cfg then
        relationLabel = cfg.label
        relationColor = cfg.color
    end

    return Comp.BuildCardPanel(nil, {
        -- 主信息行
        UI.Panel {
            width = "100%",
            flexDirection = "row",
            justifyContent = "space-between",
            alignItems = "center",
            children = {
                -- 左侧：名字 + 境界
                UI.Panel {
                    flexDirection = "row", alignItems = "center", gap = 8, flexShrink = 1,
                    children = {
                        UI.Label {
                            text = friend.friendName or "未知",
                            fontSize = Theme.fontSize.subtitle,
                            fontWeight = "bold",
                            color = Theme.colors.textGold,
                        },
                        UI.Label {
                            text = friend.friendRealm or "",
                            fontSize = Theme.fontSize.small,
                            color = Theme.colors.textSecondary,
                        },
                    },
                },
                -- 右侧：关系标签
                UI.Panel {
                    paddingHorizontal = 8, paddingVertical = 2,
                    borderRadius = 4,
                    backgroundColor = { relationColor[1], relationColor[2], relationColor[3], 40 },
                    borderColor = relationColor, borderWidth = 1,
                    children = {
                        UI.Label {
                            text = relationLabel,
                            fontSize = Theme.fontSize.tiny,
                            color = relationColor,
                        },
                    },
                },
            },
        },
        -- 好感度行
        UI.Panel {
            width = "100%",
            flexDirection = "row",
            alignItems = "center",
            gap = 12,
            children = {
                UI.Label {
                    text = "好感: " .. tostring(friend.favor or 0),
                    fontSize = Theme.fontSize.small,
                    color = Theme.colors.textLight,
                },
                UI.Label {
                    text = favorLv.label,
                    fontSize = Theme.fontSize.small,
                    color = favorLv.color,
                },
            },
        },
        -- 操作行
        UI.Panel {
            width = "100%",
            flexDirection = "row",
            gap = 8,
            marginTop = 4,
            children = {
                Comp.BuildSecondaryButton("送礼", function()
                    giftTarget_ = friend
                    showGiftDialog_ = true
                    Router.RebuildUI()
                end, { flex = 1, height = 28 }),
                Comp.BuildSecondaryButton("解除", function()
                    GameSocial.RemoveFriend(friend.friendUid)
                end, { flex = 1, height = 28 }),
            },
        },
    }, { gap = 6 })
end

-- ============================================================================
-- 待处理申请卡片
-- ============================================================================
local function BuildPendingCard(item)
    return Comp.BuildCardPanel(nil, {
        -- 申请者信息
        UI.Panel {
            width = "100%",
            flexDirection = "row",
            justifyContent = "space-between",
            alignItems = "center",
            children = {
                UI.Panel {
                    flexDirection = "row", alignItems = "center", gap = 8, flexShrink = 1,
                    children = {
                        UI.Label {
                            text = item.fromName or "未知",
                            fontSize = Theme.fontSize.subtitle, fontWeight = "bold",
                            color = Theme.colors.textGold,
                        },
                        UI.Label {
                            text = item.fromRealm or "",
                            fontSize = Theme.fontSize.small,
                            color = Theme.colors.textSecondary,
                        },
                    },
                },
                UI.Label {
                    text = "请求加为好友",
                    fontSize = Theme.fontSize.small, color = Theme.colors.textSecondary,
                },
            },
        },
        -- 操作行
        UI.Panel {
            width = "100%",
            flexDirection = "row",
            gap = 8,
            marginTop = 4,
            children = {
                Comp.BuildInkButton("同意", function()
                    GameSocial.AcceptFriend(item)
                end, { flex = 1, height = 30 }),
                Comp.BuildSecondaryButton("拒绝", function()
                    GameSocial.RejectFriend(item)
                end, { flex = 1, height = 30 }),
            },
        },
    }, { gap = 6 })
end

-- ============================================================================
-- 列表内容
-- ============================================================================
local function BuildListContent()
    local children = {}

    if currentTab_ == "friends" then
        local friends = GameSocial.GetFriends()
        if #friends == 0 then
            children[#children + 1] = UI.Panel {
                width = "100%", paddingVertical = 40, alignItems = "center",
                children = {
                    UI.Label {
                        text = "暂无好友",
                        fontSize = Theme.fontSize.body,
                        color = Theme.colors.textSecondary,
                    },
                    UI.Label {
                        text = "点击「添加好友」输入对方ID申请",
                        fontSize = Theme.fontSize.small,
                        color = { 100, 90, 75, 150 },
                        marginTop = 8,
                    },
                },
            }
        else
            for _, friend in ipairs(friends) do
                children[#children + 1] = BuildFriendCard(friend)
            end
        end
    else
        -- pending
        local pending = GameSocial.GetPending()
        if #pending == 0 then
            children[#children + 1] = UI.Panel {
                width = "100%", paddingVertical = 40, alignItems = "center",
                children = {
                    UI.Label {
                        text = "暂无好友申请",
                        fontSize = Theme.fontSize.body,
                        color = Theme.colors.textSecondary,
                    },
                },
            }
        else
            for _, item in ipairs(pending) do
                children[#children + 1] = BuildPendingCard(item)
            end
        end
    end

    return UI.Panel {
        width = "100%",
        gap = 8,
        paddingBottom = 40,
        children = children,
    }
end

-- ============================================================================
-- 添加好友弹窗（使用通用 Dialog）
-- ============================================================================
local addInputField_ = nil  -- TextField 引用

local function CloseAddDialog()
    showAddDialog_ = false
    Router.RebuildUI()
end

local function DoAddFriend()
    local text = addInputField_ and addInputField_:GetValue() or ""
    local targetUid = tonumber(text)
    if not targetUid or targetUid <= 0 then
        Toast.Show("请输入有效的玩家ID", { variant = "error" })
        return
    end
    showAddDialog_ = false
    GameSocial.AddFriend(targetUid)
    Router.RebuildUI()
end

local function BuildAddFriendModal()
    if not showAddDialog_ then return nil end

    addInputField_ = UI.TextField {
        width = "100%",
        height = 36,
        placeholder = "输入玩家ID",
        fontSize = Theme.fontSize.body,
        onSubmit = function(field, text) DoAddFriend() end,
    }

    -- content 为自定义控件：提示文字 + 输入框
    local contentWidget = UI.Panel {
        width = "100%", gap = 10,
        children = {
            UI.Label {
                text = "请输入对方玩家ID",
                fontSize = Theme.fontSize.small,
                color = Theme.colors.textSecondary,
                textAlign = "center",
                width = "100%",
            },
            addInputField_,
        },
    }

    return Comp.Dialog("添加好友", contentWidget, {
        { text = "取消", onClick = CloseAddDialog },
        { text = "申请", onClick = DoAddFriend, primary = true },
    }, { onClose = CloseAddDialog })
end

-- ============================================================================
-- 赠送礼物弹窗（使用通用 Dialog）
-- ============================================================================
local function CloseGiftDialog()
    showGiftDialog_ = false
    giftTarget_ = nil
    Router.RebuildUI()
end

local function BuildGiftModal()
    if not showGiftDialog_ or not giftTarget_ then return nil end

    local giftRows = {}
    for _, gift in ipairs(DataSocial.FAVOR_GIFTS) do
        giftRows[#giftRows + 1] = UI.Panel {
            width = "100%",
            flexDirection = "row",
            justifyContent = "space-between",
            alignItems = "center",
            paddingVertical = 6,
            paddingHorizontal = 8,
            borderRadius = Theme.radius.sm,
            backgroundColor = Theme.colors.bgDark,
            cursor = "pointer",
            onClick = function(self)
                local uid = giftTarget_.friendUid
                showGiftDialog_ = false
                giftTarget_ = nil
                GameSocial.SendGift(uid, gift.id)
                Router.RebuildUI()
            end,
            children = {
                UI.Panel {
                    gap = 2, flexShrink = 1,
                    children = {
                        UI.Label {
                            text = gift.name .. " (好感+" .. gift.favor .. ")",
                            fontSize = Theme.fontSize.body,
                            color = Theme.colors.textGold,
                        },
                        UI.Label {
                            text = gift.desc,
                            fontSize = Theme.fontSize.tiny,
                            color = Theme.colors.textSecondary,
                        },
                    },
                },
                UI.Label {
                    text = gift.price .. "灵石",
                    fontSize = Theme.fontSize.small,
                    color = Theme.colors.warning,
                },
            },
        }
    end

    local giftList = UI.Panel { width = "100%", gap = 6, children = giftRows }

    return Comp.Dialog(
        "赠送给 " .. (giftTarget_.friendName or "好友"),
        giftList,
        { { text = "取消", onClick = CloseGiftDialog } },
        { onClose = CloseGiftDialog }
    )
end

-- ============================================================================
-- 构建页面
-- ============================================================================
function M.Build(payload)
    local p = GamePlayer.Get()
    if not p then return UI.Panel { width = "100%", height = "100%" } end

    -- 注册刷新回调
    GameSocial.SetRefreshCallback(function()
        Router.RebuildUI()
    end)

    -- 仅首次进入时请求数据（防止 Build→请求→回调→RebuildUI→Build 死循环）
    if not dataRequested_ then
        dataRequested_ = true
        RequestData()
    end

    local contentChildren = {
        BuildBackRow(),
        BuildTabBar(),
        BuildActionBar(),
        BuildListContent(),
    }

    local page = Comp.BuildPageShell("more", p, contentChildren, Router.HandleNavigate)

    -- 弹窗叠加层
    local modal = BuildAddFriendModal() or BuildGiftModal()
    if modal then
        page:AddChild(modal)
    end

    return page
end

--- 离开页面时清理状态
function M.Cleanup()
    dataRequested_ = false
    showAddDialog_ = false
    showGiftDialog_ = false
    giftTarget_ = nil
    GameSocial.SetRefreshCallback(nil)
end

return M
