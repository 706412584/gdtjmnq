-- ============================================================================
-- 《问道长生》角色创建页
-- ============================================================================

local UI = require("urhox-libs/UI")
local Theme = require("ui_theme")
local Comp = require("ui_components")
local Router = require("ui_router")

local M = {}

-- 角色创建临时数据
local roleData = {
    gender = "男",
    avatarIndex = 1,
    rootBone = "中品灵根",
    fortune = "普通机缘",
    name = "",
}

local rootBones = { "上品灵根", "中品灵根", "下品灵根", "天灵根", "变异灵根" }
local fortunes = { "普通机缘", "稀有机缘", "传说机缘", "无机缘" }

-- 随机道号素材
local NAME_PREFIXES = {
    "清", "玄", "紫", "青", "云", "风", "明", "星", "天", "灵",
    "无", "凌", "逸", "幽", "苍", "墨", "白", "素", "尘", "寒",
    "静", "虚", "道", "真", "玉", "鹤", "松", "竹", "兰", "梅",
}
local NAME_SUFFIXES = {
    "尘", "风", "云", "鹤", "阳", "虚", "玄", "真", "一", "然",
    "道", "心", "明", "远", "空", "逸", "默", "幽", "澜", "霄",
    "微", "渺", "朴", "素", "清", "宁", "安", "止", "觉", "悟",
}

local function RandomDaoName()
    local p = NAME_PREFIXES[math.random(1, #NAME_PREFIXES)]
    local s = NAME_SUFFIXES[math.random(1, #NAME_SUFFIXES)]
    -- 避免前后相同
    while s == p do
        s = NAME_SUFFIXES[math.random(1, #NAME_SUFFIXES)]
    end
    return p .. s
end

-- 构建选择行
local function BuildSelectRow(label, value, onTap)
    return UI.Panel {
        width = "100%",
        flexDirection = "row",
        justifyContent = "space-between",
        alignItems = "center",
        padding = { 12, 16 },
        backgroundColor = Theme.colors.bgDark,
        borderRadius = Theme.radius.md,
        borderColor = Theme.colors.borderGold,
        borderWidth = 1,
        cursor = "pointer",
        onClick = function(self)
            if onTap then onTap() end
        end,
        children = {
            UI.Label {
                text = label,
                fontSize = Theme.fontSize.body,
                color = Theme.colors.textSecondary,
            },
            UI.Label {
                text = value,
                fontSize = Theme.fontSize.body,
                fontWeight = "bold",
                color = Theme.colors.textGold,
            },
        },
    }
end

function M.Build(payload)
    local root = UI.Panel {
        width = "100%",
        height = "100%",
        backgroundImage = Theme.images.bgCreateRole,
        backgroundFit = "cover",
        children = {
            -- 半透明遮罩
            UI.Panel {
                position = "absolute",
                top = 0, left = 0, right = 0, bottom = 0,
                backgroundColor = { 20, 18, 15, 120 },
            },
            UI.ScrollView {
                width = "100%",
                flexGrow = 1,
                flexBasis = 0,
                scrollY = true,
                showScrollbar = false,
                children = {
                    UI.Panel {
                        width = "100%",
                        padding = { 40, 24, 24, 24 },
                        gap = 16,
                        alignItems = "center",
                        children = {
                            -- 页面标题
                            UI.Label {
                                text = "开 辟 道 途",
                                fontSize = 28,
                                fontWeight = "bold",
                                color = Theme.colors.textGold,
                                textAlign = "center",
                            },
                            UI.Label {
                                text = "选定根基，踏入修行之路",
                                fontSize = Theme.fontSize.small,
                                color = Theme.colors.textLight,
                                textAlign = "center",
                                marginBottom = 8,
                            },

                            -- 当前选中的头像（大图预览）
                            UI.Panel {
                                width = 120,
                                height = 120,
                                borderRadius = 60,
                                backgroundColor = { 35, 30, 25, 180 },
                                borderColor = Theme.colors.gold,
                                borderWidth = 2,
                                justifyContent = "center",
                                alignItems = "center",
                                overflow = "hidden",
                                children = {
                                    UI.Panel {
                                        width = 100,
                                        height = 100,
                                        backgroundImage = Theme.avatars[roleData.gender][roleData.avatarIndex],
                                        backgroundFit = "contain",
                                    },
                                },
                            },

                            -- 头像选择网格（5个头像一排）
                            UI.Panel {
                                width = "100%",
                                flexDirection = "row",
                                justifyContent = "center",
                                gap = 8,
                                marginBottom = 8,
                                children = (function()
                                    local items = {}
                                    local avatarList = Theme.avatars[roleData.gender]
                                    for i = 1, #avatarList do
                                        local selected = (i == roleData.avatarIndex)
                                        items[#items + 1] = UI.Panel {
                                            width = 52,
                                            height = 52,
                                            borderRadius = 26,
                                            backgroundColor = selected and { 200, 168, 85, 60 } or { 35, 30, 25, 150 },
                                            borderColor = selected and Theme.colors.gold or Theme.colors.border,
                                            borderWidth = selected and 2 or 1,
                                            justifyContent = "center",
                                            alignItems = "center",
                                            overflow = "hidden",
                                            cursor = "pointer",
                                            onClick = function(self)
                                                roleData.avatarIndex = i
                                                Router.RebuildUI()
                                            end,
                                            children = {
                                                UI.Panel {
                                                    width = 44,
                                                    height = 44,
                                                    backgroundImage = avatarList[i],
                                                    backgroundFit = "contain",
                                                },
                                            },
                                        }
                                    end
                                    return items
                                end)(),
                            },

                            -- 性别选择（分段按钮）
                            UI.Panel {
                                width = "100%",
                                gap = 4,
                                children = {
                                    UI.Label {
                                        text = "性别",
                                        fontSize = Theme.fontSize.small,
                                        color = Theme.colors.textSecondary,
                                        marginBottom = 4,
                                    },
                                    UI.Panel {
                                        width = "100%",
                                        flexDirection = "row",
                                        gap = 8,
                                        children = {
                                            -- 男
                                            UI.Panel {
                                                flexGrow = 1,
                                                height = 40,
                                                borderRadius = Theme.radius.md,
                                                backgroundColor = roleData.gender == "男" and Theme.colors.gold or Theme.colors.bgDark,
                                                borderColor = Theme.colors.borderGold,
                                                borderWidth = 1,
                                                justifyContent = "center",
                                                alignItems = "center",
                                                cursor = "pointer",
                                                onClick = function(self)
                                                    roleData.gender = "男"
                                                    roleData.avatarIndex = 1
                                                    Router.RebuildUI()
                                                end,
                                                children = {
                                                    UI.Label {
                                                        text = "男",
                                                        fontSize = Theme.fontSize.body,
                                                        fontWeight = "bold",
                                                        color = roleData.gender == "男" and Theme.colors.inkBlack or Theme.colors.textLight,
                                                    },
                                                },
                                            },
                                            -- 女
                                            UI.Panel {
                                                flexGrow = 1,
                                                height = 40,
                                                borderRadius = Theme.radius.md,
                                                backgroundColor = roleData.gender == "女" and Theme.colors.gold or Theme.colors.bgDark,
                                                borderColor = Theme.colors.borderGold,
                                                borderWidth = 1,
                                                justifyContent = "center",
                                                alignItems = "center",
                                                cursor = "pointer",
                                                onClick = function(self)
                                                    roleData.gender = "女"
                                                    roleData.avatarIndex = 1
                                                    Router.RebuildUI()
                                                end,
                                                children = {
                                                    UI.Label {
                                                        text = "女",
                                                        fontSize = Theme.fontSize.body,
                                                        fontWeight = "bold",
                                                        color = roleData.gender == "女" and Theme.colors.inkBlack or Theme.colors.textLight,
                                                    },
                                                },
                                            },
                                        },
                                    },
                                },
                            },

                            -- 根骨
                            BuildSelectRow("根  骨", roleData.rootBone, function()
                                local idx = math.random(1, #rootBones)
                                roleData.rootBone = rootBones[idx]
                                Router.RebuildUI()
                            end),

                            -- 机缘
                            BuildSelectRow("机  缘", roleData.fortune, function()
                                local idx = math.random(1, #fortunes)
                                roleData.fortune = fortunes[idx]
                                Router.RebuildUI()
                            end),

                            -- 道号输入
                            UI.Panel {
                                width = "100%",
                                gap = 4,
                                marginTop = 8,
                                children = {
                                    UI.Panel {
                                        width = "100%",
                                        flexDirection = "row",
                                        justifyContent = "space-between",
                                        alignItems = "center",
                                        children = {
                                            UI.Label {
                                                text = "道号",
                                                fontSize = Theme.fontSize.small,
                                                color = Theme.colors.textSecondary,
                                            },
                                            UI.Panel {
                                                paddingLeft = 10,
                                                paddingRight = 10,
                                                paddingTop = 4,
                                                paddingBottom = 4,
                                                borderRadius = Theme.radius.sm,
                                                backgroundColor = { 35, 30, 25, 180 },
                                                borderColor = Theme.colors.borderGold,
                                                borderWidth = 1,
                                                cursor = "pointer",
                                                onClick = function(self)
                                                    roleData.name = RandomDaoName()
                                                    Router.RebuildUI()
                                                end,
                                                children = {
                                                    UI.Label {
                                                        text = "随机道号",
                                                        fontSize = Theme.fontSize.tiny,
                                                        color = Theme.colors.textGold,
                                                    },
                                                },
                                            },
                                        },
                                    },
                                    UI.TextField {
                                        value = roleData.name,
                                        placeholder = "请输入道号...",
                                        maxLength = 12,
                                        fontSize = Theme.fontSize.body,
                                        onChange = function(self, v)
                                            roleData.name = v
                                        end,
                                    },
                                },
                            },

                            -- 间距
                            UI.Panel { height = 16 },

                            -- 确认创建
                            Comp.BuildInkButton("确认创建", function()
                                print("[角色创建] 创建角色: " .. roleData.name)
                                Router.EnterState(Router.STATE_HOME)
                            end),

                            -- 返回
                            Comp.BuildTextButton("返回标题", function()
                                Router.EnterState(Router.STATE_TITLE)
                            end, { color = Theme.colors.textSecondary }),
                        },
                    },
                },
            },
        },
    }

    -- 入场淡入效果（从故事页过渡而来）
    root:SetStyle({ opacity = 0 })
    root:Animate({
        keyframes = {
            [0] = { opacity = 0 },
            [1] = { opacity = 1 },
        },
        duration = 1.0,
        easing = "easeOut",
        fillMode = "forwards",
    })

    return root
end

return M
