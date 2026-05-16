-- ============================================================================
-- 《问道长生》更多功能页
-- 将次要功能集中展示在网格布局中
-- ============================================================================

local UI = require("urhox-libs/UI")
local Theme = require("ui_theme")
local Comp = require("ui_components")
local Router = require("ui_router")
local GamePlayer = require("game_player")
local Settings = require("ui_settings")

local M = {}

-- ============================================================================
-- 功能入口数据
-- ============================================================================
local features = {
    {
        name = "炼丹",
        icon = Theme.images.iconAlchemy,
        desc = "炼制丹药",
        state = Router.STATE_ALCHEMY,
    },
    {
        name = "宗门",
        icon = Theme.images.iconSect,
        desc = "门派事务",
        state = Router.STATE_SECT,
    },
    {
        name = "机缘",
        icon = Theme.images.iconExplore,
        desc = "奇遇探索",
        state = Router.STATE_EXPLORE,
    },
    {
        name = "聊天",
        icon = Theme.images.iconChat,
        desc = "仙友交流",
        state = Router.STATE_CHAT,
    },
    {
        name = "坊市",
        icon = Theme.images.iconMarket,
        desc = "灵材交易",
        state = Router.STATE_MARKET,
    },
    {
        name = "仙信",
        icon = Theme.images.iconMarket,  -- 暂用坊市图标
        desc = "交易邮件",
        state = Router.STATE_MAIL,
    },
    {
        name = "排行",
        icon = Theme.images.iconRanking,
        desc = "仙道排名",
        state = Router.STATE_RANKING,
    },
    {
        name = "试炼",
        icon = Theme.images.iconTrial,
        desc = "试炼闯关",
        state = Router.STATE_TRIAL,
    },
    {
        name = "任务",
        icon = Theme.images.iconQuest,
        desc = "修仙任务",
        state = Router.STATE_QUEST,
    },
    {
        name = "社交",
        icon = Theme.images.iconChat,
        desc = "仙友关系",
        state = Router.STATE_SOCIAL,
    },
    {
        name = "设置",
        icon = Theme.images.iconSettings,
        desc = "游戏设置",
        state = nil,
        action = "settings",  -- 特殊处理：弹出设置弹窗
    },
}

-- ============================================================================
-- 单个功能卡片
-- ============================================================================
local function BuildFeatureCard(feat)
    local hasAction = (feat.state ~= nil or feat.action ~= nil)
    local isLocked = not hasAction

    return UI.Panel {
        width = "45%",
        padding = Theme.spacing.md,
        borderRadius = Theme.radius.md,
        backgroundColor = isLocked and { 40, 35, 30, 120 } or Theme.colors.bgDark,
        borderColor = isLocked and Theme.colors.border or Theme.colors.borderGold,
        borderWidth = 1,
        gap = 6,
        alignItems = "center",
        cursor = isLocked and "default" or "pointer",
        hitSlop = 0,           -- 精确触控区域，减少误触
        onClick = function(self)
            if isLocked then return end
            if feat.action == "settings" then
                Settings.Show()
            elseif feat.state then
                Router.EnterState(feat.state)
            end
        end,
        children = {
            -- 图标
            UI.Panel {
                width = 40,
                height = 40,
                backgroundImage = feat.icon,
                backgroundFit = "contain",
                imageTint = isLocked and { 120, 110, 100, 150 } or Theme.colors.gold,
            },
            -- 名称
            UI.Label {
                text = feat.name,
                fontSize = Theme.fontSize.subtitle,
                fontWeight = "bold",
                color = isLocked and Theme.colors.textSecondary or Theme.colors.textGold,
            },
            -- 描述
            UI.Label {
                text = isLocked and "敬请期待" or feat.desc,
                fontSize = Theme.fontSize.tiny,
                color = isLocked and { 100, 90, 75, 150 } or Theme.colors.textSecondary,
            },
        },
    }
end

-- ============================================================================
-- 构建页面
-- ============================================================================
function M.Build(payload)
    local p = GamePlayer.Get()
    if not p then return UI.Panel { width = "100%", height = "100%" } end

    -- 功能网格
    local cardChildren = {}
    for _, feat in ipairs(features) do
        cardChildren[#cardChildren + 1] = BuildFeatureCard(feat)
    end

    local contentChildren = {
        Comp.BuildSectionTitle("更多功能"),

        -- 功能网格（2列）
        UI.Panel {
            width = "100%",
            flexDirection = "row",
            flexWrap = "wrap",
            gap = 10,
            justifyContent = "center",
            paddingBottom = 40,  -- 底部留白，确保有滚动空间以减少误触
            children = cardChildren,
        },
    }

    return Comp.BuildPageShell("more", p, contentChildren, Router.HandleNavigate)
end

return M
