-- ============================================================================
-- 《问道长生》游历地图页（地图风格 - 背景图 + 绝对定位功能点）
-- ============================================================================

local UI = require("urhox-libs/UI")
local Theme = require("ui_theme")
local Comp = require("ui_components")
local Router = require("ui_router")
local GamePlayer = require("game_player")

local M = {}

-- 当前选中区域索引（nil 表示未选中）
local selectedIdx = nil

-- ============================================================================
-- 游历地点数据
-- ============================================================================
local LOCATIONS = {
    { name = "云雾山",   levelRange = "1-10",  rewards = { "灵草", "矿石" },         desc = "云雾缭绕的山脉，适合初入修行之人历练。" },
    { name = "天阙遗迹", levelRange = "10-20", rewards = { "功法残页", "灵石" },      desc = "上古遗迹，危机四伏但机缘不少。" },
    { name = "东海海滨", levelRange = "15-25", rewards = { "海珠", "灵贝" },         desc = "东海之滨，海妖出没之地。" },
    { name = "夫山遗迹", levelRange = "20-30", rewards = { "古器碎片", "秘境钥匙" }, desc = "神秘的上古大能洞府遗址。" },
}

-- ============================================================================
-- 地图位置点数据（包含绝对定位坐标 %）
-- ============================================================================
local mapPoints = {
    {
        name = "云雾山",
        icon = Theme.images.iconExplore,
        posX = "18%",  posY = "22%",
        locIdx = 1,
    },
    {
        name = "天阙遗迹",
        icon = Theme.images.iconSect,
        posX = "68%",  posY = "18%",
        locIdx = 2,
    },
    {
        name = "东海海滨",
        icon = Theme.images.iconWorldMap,
        posX = "72%",  posY = "52%",
        locIdx = 3,
    },
    {
        name = "夫山遗迹",
        icon = Theme.images.iconAlchemy,
        posX = "25%",  posY = "58%",
        locIdx = 4,
    },
}

-- ============================================================================
-- 构建地图上的功能点
-- ============================================================================
local function BuildLocationMarker(point, isSelected)
    return UI.Panel {
        position = "absolute",
        left = point.posX,
        top = point.posY,
        width = 90,
        height = 88,
        alignItems = "center",
        gap = 3,
        cursor = "pointer",
        onClick = function(self)
            if selectedIdx == point.locIdx then
                selectedIdx = nil  -- 再次点击取消
            else
                selectedIdx = point.locIdx
            end
            Router.RebuildUI()
        end,
        children = {
            -- 发光底盘（选中时显示）
            UI.Panel {
                width = 52,
                height = 52,
                borderRadius = 26,
                backgroundColor = isSelected and { 200, 168, 85, 60 } or { 30, 25, 20, 100 },
                borderColor = isSelected and Theme.colors.gold or { 200, 168, 85, 80 },
                borderWidth = isSelected and 2 or 1,
                justifyContent = "center",
                alignItems = "center",
                children = {
                    -- 图标
                    UI.Panel {
                        width = 30,
                        height = 30,
                        backgroundImage = point.icon,
                        backgroundFit = "contain",
                        imageTint = isSelected and Theme.colors.gold or { 220, 210, 190, 230 },
                    },
                },
            },
            -- 地名（毛笔刷背景）
            UI.Panel {
                width = 88,
                height = 28,
                backgroundImage = Theme.images.brushLabelBg,
                backgroundFit = "fill",
                justifyContent = "center",
                alignItems = "center",
                children = {
                    UI.Label {
                        text = point.name,
                        fontSize = 12,
                        fontWeight = "bold",
                        color = isSelected and Theme.colors.gold or { 230, 220, 200, 240 },
                        textAlign = "center",
                    },
                },
            },
        },
    }
end

-- ============================================================================
-- 选中区域的详情浮层
-- ============================================================================
local function BuildDetailPopup(loc)
    local rewardText = table.concat(loc.rewards, "、")

    return UI.Panel {
        position = "absolute",
        bottom = 80,
        left = "8%",
        right = "8%",
        backgroundColor = { 25, 22, 18, 230 },
        borderRadius = Theme.radius.lg,
        borderColor = Theme.colors.borderGold,
        borderWidth = 1,
        padding = Theme.spacing.md,
        gap = Theme.spacing.sm,
        children = {
            -- 标题行
            UI.Panel {
                width = "100%",
                flexDirection = "row",
                justifyContent = "space-between",
                alignItems = "center",
                children = {
                    UI.Label {
                        text = loc.name,
                        fontSize = Theme.fontSize.heading,
                        fontWeight = "bold",
                        color = Theme.colors.textGold,
                    },
                    UI.Label {
                        text = "等级 " .. loc.levelRange,
                        fontSize = Theme.fontSize.small,
                        color = Theme.colors.accent,
                    },
                },
            },
            -- 描述
            UI.Label {
                text = loc.desc,
                fontSize = Theme.fontSize.body,
                color = Theme.colors.textLight,
                width = "100%",
            },
            Comp.BuildInkDivider(),
            -- 奖励
            Comp.BuildStatRow("可获奖励", rewardText),
            -- 按钮
            UI.Panel {
                width = "100%",
                flexDirection = "row",
                gap = 8,
                marginTop = 4,
                children = {
                    UI.Panel {
                        flexGrow = 1,
                        children = {
                            Comp.BuildInkButton("开始游历", function()
                                Router.EnterState(Router.STATE_EXPLORE)
                            end, { width = "100%", fontSize = Theme.fontSize.body }),
                        },
                    },
                    UI.Panel {
                        flexGrow = 1,
                        children = {
                            Comp.BuildSecondaryButton("关闭", function()
                                selectedIdx = nil
                                Router.RebuildUI()
                            end, { width = "100%" }),
                        },
                    },
                },
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
    local locs = LOCATIONS

    -- 地图标记
    local markerChildren = {}
    for _, point in ipairs(mapPoints) do
        markerChildren[#markerChildren + 1] = BuildLocationMarker(point, selectedIdx == point.locIdx)
    end

    -- 详情浮层（如果有选中）
    local detailPopup = nil
    if selectedIdx and locs[selectedIdx] then
        detailPopup = BuildDetailPopup(locs[selectedIdx])
    end

    -- 地图标题标签
    markerChildren[#markerChildren + 1] = UI.Panel {
        position = "absolute",
        top = "2%",
        left = "0%",
        right = "0%",
        alignItems = "center",
        children = {
            UI.Label {
                text = "— 天 下 舆 图 —",
                fontSize = Theme.fontSize.subtitle,
                fontWeight = "bold",
                color = { 200, 168, 85, 180 },
                textAlign = "center",
            },
        },
    }

    -- 添加详情浮层
    if detailPopup then
        markerChildren[#markerChildren + 1] = detailPopup
    end

    return UI.Panel {
        width = "100%",
        height = "100%",
        children = {
            -- 顶部状态栏
            Comp.BuildTopBar(p),
            -- 地图区域（中间铺满）
            UI.Panel {
                width = "100%",
                flexGrow = 1,
                flexBasis = 0,
                backgroundImage = Theme.images.bgMap,
                backgroundFit = "cover",
                children = (function()
                    local c = {
                        -- 地图遮罩（轻微压暗以便图标可见）
                        UI.Panel {
                            position = "absolute",
                            top = 0, left = 0, right = 0, bottom = 0,
                            backgroundColor = { 10, 8, 6, 80 },
                        },
                    }
                    -- 地图标记 + 浮层全部绝对定位
                    for _, m in ipairs(markerChildren) do
                        c[#c + 1] = m
                    end
                    return c
                end)(),
            },
            -- 聊天动态框
            Comp.BuildChatTicker(function()
                Router.EnterState(Router.STATE_CHAT)
            end),
            -- 底部导航
            Comp.BuildBottomNav("map", Router.HandleNavigate),
        },
    }
end

return M
