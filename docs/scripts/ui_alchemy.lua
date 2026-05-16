-- ============================================================================
-- 《问道长生》炼丹页
-- ============================================================================

local UI = require("urhox-libs/UI")
local Theme = require("ui_theme")
local Comp = require("ui_components")
local Router = require("ui_router")
local GamePlayer = require("game_player")
local GameAlchemy = require("game_alchemy")
local DataItems = require("data_items")
local Toast = require("ui_toast")

local M = {}

local selectedRecipe = 1

-- ============================================================================
-- 材料槽（显示某丹方所需材料的持有情况）
-- ============================================================================
local function BuildMaterialSlot(matInfo)
    if not matInfo then
        -- 空槽
        return UI.Panel {
            width = 72,
            height = 72,
            borderRadius = Theme.radius.sm,
            backgroundColor = { 40, 35, 28, 120 },
            borderColor = Theme.colors.border,
            borderWidth = 1,
            justifyContent = "center",
            alignItems = "center",
        }
    end

    local enough = matInfo.enough
    return UI.Panel {
        width = 72,
        height = 72,
        borderRadius = Theme.radius.sm,
        backgroundColor = enough and Theme.colors.bgDark or { 60, 30, 30, 150 },
        borderColor = enough and Theme.colors.borderGold or Theme.colors.danger,
        borderWidth = 1,
        justifyContent = "center",
        alignItems = "center",
        gap = 2,
        children = {
            UI.Label {
                text = matInfo.name,
                fontSize = Theme.fontSize.small,
                color = enough and Theme.colors.textLight or Theme.colors.dangerLight,
                textAlign = "center",
            },
            UI.Label {
                text = matInfo.have .. "/" .. matInfo.need,
                fontSize = Theme.fontSize.tiny,
                fontWeight = "bold",
                color = enough and Theme.colors.successLight or Theme.colors.dangerLight,
            },
        },
    }
end

-- ============================================================================
-- 丹方列表项
-- ============================================================================
local function BuildRecipeItem(recipe, idx, isSelected)
    local bg = isSelected and Theme.colors.gold or Theme.colors.bgDark
    local txtColor = isSelected and Theme.colors.inkBlack or Theme.colors.textLight
    local qualityColor = DataItems.GetQualityColor(
        DataItems.QUALITY[recipe.quality] and DataItems.QUALITY[recipe.quality].label or "普通"
    )
    local qualityLabel = DataItems.QUALITY[recipe.quality]
        and DataItems.QUALITY[recipe.quality].label or "普通"

    return UI.Panel {
        width = "100%",
        flexDirection = "row",
        justifyContent = "space-between",
        alignItems = "center",
        padding = { 10, 12 },
        borderRadius = Theme.radius.sm,
        backgroundColor = bg,
        borderColor = isSelected and Theme.colors.goldDark or Theme.colors.border,
        borderWidth = 1,
        cursor = "pointer",
        onClick = function(self)
            selectedRecipe = idx
            Router.RebuildUI()
        end,
        children = {
            UI.Panel {
                flexShrink = 1,
                gap = 2,
                children = {
                    UI.Panel {
                        flexDirection = "row",
                        gap = 6,
                        alignItems = "center",
                        children = {
                            UI.Label {
                                text = recipe.name,
                                fontSize = Theme.fontSize.body,
                                fontWeight = "bold",
                                color = isSelected and Theme.colors.inkBlack or qualityColor,
                            },
                            UI.Label {
                                text = "[" .. qualityLabel .. "]",
                                fontSize = Theme.fontSize.tiny,
                                color = isSelected and { 80, 70, 50, 200 } or qualityColor,
                            },
                        },
                    },
                    UI.Label {
                        text = "成功率 " .. (recipe.rate or 0) .. "% | " .. (recipe.time or 0) .. "秒",
                        fontSize = Theme.fontSize.tiny,
                        color = isSelected and { 60, 50, 40, 200 } or Theme.colors.textSecondary,
                    },
                },
            },
            UI.Label {
                text = isSelected and "已选" or "选择",
                fontSize = Theme.fontSize.small,
                color = isSelected and { 60, 50, 40, 200 } or Theme.colors.gold,
            },
        },
    }
end

-- ============================================================================
-- 页面构建
-- ============================================================================
function M.Build(payload)
    local p = GamePlayer.Get()
    if not p then return UI.Panel { width = "100%", height = "100%" } end

    local recipes = GameAlchemy.GetAllRecipes()
    if #recipes == 0 then
        return Comp.BuildPageShell("alchemy", p, {
            UI.Label {
                text = "暂无可用丹方",
                fontSize = Theme.fontSize.body,
                color = Theme.colors.textSecondary,
            },
        }, Router.HandleNavigate)
    end
    if selectedRecipe > #recipes then selectedRecipe = 1 end
    local sel = recipes[selectedRecipe]

    -- 材料持有情况
    local matInfos = GameAlchemy.CheckMaterials(sel.id)
    local matSlots = {}
    for _, mi in ipairs(matInfos) do
        matSlots[#matSlots + 1] = BuildMaterialSlot(mi)
    end

    -- 检查能否炼制
    local canDo, cantReason = GameAlchemy.CanAlchemy(sel.id)

    -- 气运加成提示
    local fortune = p.fortune or "普通"
    local fortuneText = "无"
    if fortune == "小吉" then fortuneText = "+5%"
    elseif fortune == "大吉" then fortuneText = "+10%"
    elseif fortune == "天命" then fortuneText = "+15%"
    elseif fortune == "低迷" then fortuneText = "-5%"
    end

    -- 丹方列表
    local recipeItems = {}
    for i, r in ipairs(recipes) do
        recipeItems[#recipeItems + 1] = BuildRecipeItem(r, i, i == selectedRecipe)
    end

    local contentChildren = {
        -- 炼丹炉区域
        UI.Panel {
            width = "100%",
            height = 120,
            borderRadius = Theme.radius.lg,
            backgroundColor = Theme.colors.bgDark,
            borderColor = Theme.colors.borderGold,
            borderWidth = 1,
            justifyContent = "center",
            alignItems = "center",
            gap = 6,
            children = {
                UI.Panel {
                    width = 48,
                    height = 48,
                    backgroundImage = Theme.images.iconAlchemy,
                    backgroundFit = "contain",
                },
                UI.Label {
                    text = "炼 丹 炉",
                    fontSize = Theme.fontSize.heading,
                    fontWeight = "bold",
                    color = Theme.colors.textGold,
                },
                UI.Label {
                    text = "当前: " .. sel.name .. "  成功率 " .. (sel.rate or 0) .. "%",
                    fontSize = Theme.fontSize.small,
                    color = Theme.colors.textLight,
                },
            },
        },

        -- 材料需求
        Comp.BuildSectionTitle("所需材料"),
        UI.Panel {
            width = "100%",
            flexDirection = "row",
            flexWrap = "wrap",
            gap = 8,
            children = matSlots,
        },

        -- 丹方详情
        Comp.BuildCardPanel(sel.name, {
            UI.Label {
                text = sel.effect or "",
                fontSize = Theme.fontSize.body,
                color = Theme.colors.successLight,
                width = "100%",
            },
            Comp.BuildStatRow("品质", DataItems.QUALITY[sel.quality]
                and DataItems.QUALITY[sel.quality].label or "普通"),
            Comp.BuildStatRow("基础成功率", (sel.rate or 0) .. "%"),
            Comp.BuildStatRow("气运加成", fortuneText, {
                valueColor = fortune == "低迷" and Theme.colors.dangerLight or Theme.colors.successLight
            }),
            Comp.BuildStatRow("炼制时间", (sel.time or 0) .. "秒"),
        }),

        -- 开始炼制按钮
        Comp.BuildInkButton(canDo and "开始炼制" or (cantReason or "材料不足"), function()
            if not canDo then
                Toast.Show(cantReason or "无法炼制", { variant = "error" })
                return
            end
            local ok, msg = GameAlchemy.DoAlchemy(sel.id)
            if msg then Toast.Show(msg, { variant = ok and "success" or "error" }) end
            Router.RebuildUI()
        end, { disabled = not canDo }),

        -- 丹方列表
        Comp.BuildSectionTitle("全部丹方"),
        UI.Panel {
            width = "100%",
            gap = 6,
            children = recipeItems,
        },
    }

    return Comp.BuildPageShell("alchemy", p, contentChildren, Router.HandleNavigate)
end

return M
