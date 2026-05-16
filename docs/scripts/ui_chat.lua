-- ============================================================================
-- 《问道长生》聊天页
-- ============================================================================

local UI = require("urhox-libs/UI")
local Theme = require("ui_theme")
local Comp = require("ui_components")
local Router = require("ui_router")
local GamePlayer = require("game_player")

local M = {}

local activeChannel = "世界"

-- 频道颜色
local channelColors = {
    ["世界"] = { 180, 160, 100, 255 },
    ["仙盟"] = { 100, 180, 100, 255 },
    ["仙界"] = { 100, 140, 200, 255 },
}

-- 聊天消息行
local function BuildChatMessage(msg)
    local chColor = channelColors[msg.channel] or Theme.colors.textSecondary
    local content = msg.content
    if content == "" then content = "..." end

    return UI.Panel {
        width = "100%",
        flexDirection = "row",
        gap = 6,
        paddingVertical = 4,
        paddingHorizontal = 6,
        children = {
            -- 频道标签
            UI.Panel {
                paddingHorizontal = 6,
                paddingVertical = 2,
                borderRadius = 3,
                backgroundColor = { chColor[1], chColor[2], chColor[3], 40 },
                children = {
                    UI.Label {
                        text = msg.channel,
                        fontSize = Theme.fontSize.tiny,
                        color = chColor,
                    },
                },
            },
            -- 发送者
            UI.Label {
                text = msg.sender .. ":",
                fontSize = Theme.fontSize.small,
                fontWeight = "bold",
                color = Theme.colors.textGold,
            },
            -- 内容
            UI.Label {
                text = content,
                fontSize = Theme.fontSize.small,
                color = Theme.colors.textLight,
                flexShrink = 1,
            },
        },
    }
end

function M.Build(payload)
    local p = GamePlayer.Get()
    if not p then return UI.Panel { width = "100%", height = "100%" } end

    local channels = { "世界", "仙盟", "私聊" }

    -- 聊天消息（暂无云端聊天，显示空列表）
    local chatMessages = {}
    local filteredMsgs = {}
    for _, msg in ipairs(chatMessages) do
        if activeChannel == "私聊" or msg.channel == activeChannel then
            filteredMsgs[#filteredMsgs + 1] = msg
        end
    end

    -- 消息列表
    local msgChildren = {}
    if #filteredMsgs == 0 then
        msgChildren[1] = UI.Label {
            text = "暂无消息，聊天功能尚在开发中",
            fontSize = Theme.fontSize.small,
            color = Theme.colors.textSecondary,
            textAlign = "center",
            width = "100%",
            paddingVertical = 40,
        }
    else
        for _, msg in ipairs(filteredMsgs) do
            msgChildren[#msgChildren + 1] = BuildChatMessage(msg)
        end
    end

    -- 频道按钮
    local channelBtns = {}
    for i, ch in ipairs(channels) do
        local isActive = (ch == activeChannel)
        channelBtns[i] = UI.Panel {
            flexGrow = 1,
            height = 36,
            borderRadius = Theme.radius.sm,
            backgroundColor = isActive and Theme.colors.gold or Theme.colors.transparent,
            justifyContent = "center",
            alignItems = "center",
            cursor = "pointer",
            onClick = function(self)
                activeChannel = ch
                Router.RebuildUI()
            end,
            children = {
                UI.Label {
                    text = ch,
                    fontSize = Theme.fontSize.body,
                    fontWeight = isActive and "bold" or "normal",
                    color = isActive and Theme.colors.inkBlack or Theme.colors.textLight,
                },
            },
        }
    end

    return UI.Panel {
        width = "100%",
        height = "100%",
        backgroundImage = Theme.images.bgChat,
        backgroundFit = "cover",
        children = {
            -- 背景遮罩
            UI.Panel {
                position = "absolute",
                top = 0, left = 0, right = 0, bottom = 0,
                backgroundColor = { 15, 12, 10, 160 },
            },
            -- 顶栏
            Comp.BuildTopBar(p),

            -- 频道切换
            UI.Panel {
                width = "100%",
                flexDirection = "row",
                backgroundColor = Theme.colors.inkBlack,
                padding = { 4, 8 },
                gap = 4,
                children = channelBtns,
            },

            -- 消息列表
            UI.ScrollView {
                width = "100%",
                flexGrow = 1,
                flexBasis = 0,
                scrollY = true,
                showScrollbar = true,
                backgroundColor = Theme.colors.bgDark,
                children = {
                    UI.Panel {
                        width = "100%",
                        padding = Theme.spacing.sm,
                        gap = 2,
                        children = msgChildren,
                    },
                },
            },

            -- 输入区域
            UI.Panel {
                width = "100%",
                flexDirection = "row",
                gap = 8,
                padding = { 8, 12 },
                backgroundColor = Theme.colors.inkBlack,
                borderColor = Theme.colors.borderGold,
                borderWidth = { top = 1 },
                alignItems = "center",
                children = {
                    UI.TextField {
                        flexGrow = 1,
                        placeholder = "输入消息...",
                        fontSize = Theme.fontSize.body,
                        onChange = function(self, v)
                            -- 占位
                        end,
                    },
                    UI.Panel {
                        width = 60,
                        height = 36,
                        borderRadius = Theme.radius.sm,
                        backgroundColor = Theme.colors.gold,
                        justifyContent = "center",
                        alignItems = "center",
                        cursor = "pointer",
                        onClick = function(self)
                            print("[聊天] 发送消息 - 占位")
                        end,
                        children = {
                            UI.Label {
                                text = "发送",
                                fontSize = Theme.fontSize.body,
                                fontWeight = "bold",
                                color = Theme.colors.inkBlack,
                            },
                        },
                    },
                },
            },

            -- 底部导航
            Comp.BuildBottomNav("chat", Router.HandleNavigate),
        },
    }
end

return M
