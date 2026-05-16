-- ============================================================================
-- 《问道长生》宗门页
-- ============================================================================

local UI = require("urhox-libs/UI")
local Theme = require("ui_theme")
local Comp = require("ui_components")
local Router = require("ui_router")
local GamePlayer = require("game_player")

local M = {}

-- ============================================================================
-- 宗门数据
-- ============================================================================
local SECT_NAME = "青云门"

local SECT_BUILDINGS = {
    { name = "宗门大殿", desc = "宗门核心，处理门派事务。", unlocked = true },
    { name = "藏经阁",   desc = "收藏功法秘籍之处。", unlocked = true },
    { name = "炼丹房",   desc = "宗门炼丹之所。", unlocked = true },
    { name = "任务阁",   desc = "领取宗门任务。", unlocked = true },
}

local SECT_MESSAGES = {
    "最听：青云门是修真界知名大派。",
    "周近：宗门门宗海为云深临，修为人故。",
    "周近：青云门藏府阁提，带下任为人故。",
}

-- 建筑卡片
local function BuildBuildingCard(building)
    local isLocked = not building.unlocked
    local bg = isLocked and { 40, 35, 28, 180 } or Theme.colors.bgDark

    return UI.Panel {
        width = "47%",
        padding = Theme.spacing.md,
        borderRadius = Theme.radius.md,
        backgroundColor = bg,
        borderColor = isLocked and Theme.colors.border or Theme.colors.borderGold,
        borderWidth = 1,
        gap = 6,
        children = {
            UI.Label {
                text = building.name,
                fontSize = Theme.fontSize.subtitle,
                fontWeight = "bold",
                color = isLocked and Theme.colors.textSecondary or Theme.colors.textGold,
            },
            UI.Label {
                text = building.desc,
                fontSize = Theme.fontSize.tiny,
                color = isLocked and { 100, 90, 75, 120 } or Theme.colors.textLight,
            },
            UI.Panel {
                width = "100%",
                alignItems = "flex-end",
                marginTop = 4,
                children = {
                    Comp.BuildTextButton(isLocked and "未解锁" or "进入", function()
                        if not isLocked then
                            print("[宗门] 进入: " .. building.name)
                        end
                    end, {
                        fontSize = Theme.fontSize.small,
                        color = isLocked and Theme.colors.textSecondary or Theme.colors.gold,
                    }),
                },
            },
        },
    }
end

function M.Build(payload)
    local p = GamePlayer.Get()
    if not p then return UI.Panel { width = "100%", height = "100%" } end

    -- 建筑卡片
    local buildingCards = {}
    for _, b in ipairs(SECT_BUILDINGS) do
        buildingCards[#buildingCards + 1] = BuildBuildingCard(b)
    end

    local contentChildren = {
        -- 宗门标题
        UI.Panel {
            width = "100%",
            alignItems = "center",
            gap = 4,
            paddingVertical = 8,
            children = {
                UI.Label {
                    text = SECT_NAME,
                    fontSize = Theme.fontSize.title,
                    fontWeight = "bold",
                    color = Theme.colors.textGold,
                },
                UI.Label {
                    text = "修仙大派 · 云深不知处",
                    fontSize = Theme.fontSize.small,
                    color = Theme.colors.textLight,
                },
            },
        },

        -- 建筑卡片网格
        Comp.BuildSectionTitle("门派建筑"),
        UI.Panel {
            width = "100%",
            flexDirection = "row",
            flexWrap = "wrap",
            gap = 8,
            justifyContent = "center",
            children = buildingCards,
        },

        -- 宗门消息
        Comp.BuildCardPanel("宗门近讯", {
            Comp.BuildLogPanel(SECT_MESSAGES, { height = 100 }),
        }),
    }

    return Comp.BuildPageShell("sect", p, contentChildren, Router.HandleNavigate)
end

return M
