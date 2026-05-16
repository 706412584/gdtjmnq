-- ============================================================================
-- 《问道长生》灵宠页面
-- 接入 game_pet.lua 真实逻辑：拥有/未拥有、出战/召回、喂养
-- ============================================================================

local UI = require("urhox-libs/UI")
local Theme = require("ui_theme")
local Comp = require("ui_components")
local Router = require("ui_router")
local GamePlayer = require("game_player")
local GamePet = require("game_pet")
local DataItems = require("data_items")
local Toast = require("ui_toast")

local M = {}

-- 当前选中的灵宠 id（nil=未选中）
local selectedPetId_ = nil
-- 喂养面板是否展开
local showFeedPanel_ = false

-- ============================================================================
-- 灵宠卡片
-- ============================================================================
local function BuildPetCard(pet)
    local isSelected = (pet.id == selectedPetId_)
    local qColor = DataItems.GetQualityColor(pet.quality)
    local dimmed = not pet.owned

    return UI.Panel {
        width = "100%",
        flexDirection = "row",
        backgroundColor = isSelected and { 200, 168, 85, 30 }
            or (dimmed and { 30, 25, 20, 200 } or Theme.colors.bgDark),
        borderRadius = Theme.radius.md,
        borderColor = isSelected and Theme.colors.gold or Theme.colors.border,
        borderWidth = isSelected and 2 or 1,
        padding = 10,
        gap = 10,
        cursor = "pointer",
        onClick = function(self)
            selectedPetId_ = (selectedPetId_ == pet.id) and nil or pet.id
            showFeedPanel_ = false
            Router.RebuildUI()
        end,
        children = {
            -- 头像
            UI.Panel {
                width = 64, height = 64,
                borderRadius = 8,
                backgroundColor = { 25, 22, 18, 200 },
                borderColor = dimmed and { 60, 50, 40, 150 } or qColor,
                borderWidth = 1,
                justifyContent = "center",
                alignItems = "center",
                overflow = "hidden",
                children = {
                    UI.Panel {
                        width = 56, height = 56,
                        backgroundImage = pet.image,
                        backgroundFit = "contain",
                        opacity = dimmed and 0.4 or 1.0,
                    },
                },
            },
            -- 信息区
            UI.Panel {
                flexGrow = 1, flexShrink = 1,
                gap = 3,
                children = {
                    -- 名字 + 品质 + 出战标记
                    UI.Panel {
                        flexDirection = "row", gap = 6, alignItems = "center",
                        children = {
                            UI.Label {
                                text = pet.name,
                                fontSize = Theme.fontSize.subtitle,
                                fontWeight = "bold",
                                color = dimmed and Theme.colors.textSecondary or Theme.colors.textLight,
                            },
                            UI.Panel {
                                paddingHorizontal = 6, paddingVertical = 1,
                                borderRadius = 3,
                                backgroundColor = { qColor[1], qColor[2], qColor[3], dimmed and 20 or 40 },
                                borderColor = qColor, borderWidth = 1,
                                children = {
                                    UI.Label {
                                        text = DataItems.GetQualityLabel(pet.quality),
                                        fontSize = 10,
                                        color = dimmed and Theme.colors.textSecondary or qColor,
                                    },
                                },
                            },
                            pet.isActive and UI.Panel {
                                paddingHorizontal = 6, paddingVertical = 1,
                                borderRadius = 3,
                                backgroundColor = { 100, 200, 100, 40 },
                                children = {
                                    UI.Label {
                                        text = "出战中",
                                        fontSize = 10,
                                        color = Theme.colors.success,
                                    },
                                },
                            } or nil,
                        },
                    },
                    -- 技能 / 等级
                    pet.owned and UI.Label {
                        text = "Lv." .. pet.level .. "  技能: " .. pet.skill,
                        fontSize = Theme.fontSize.small,
                        color = Theme.colors.textGold,
                    } or UI.Label {
                        text = "技能: " .. pet.skill,
                        fontSize = Theme.fontSize.small,
                        color = { 100, 90, 75, 150 },
                    },
                    -- 描述
                    UI.Label {
                        text = dimmed and "（未拥有 - 探索时有概率捕获）" or pet.desc,
                        fontSize = Theme.fontSize.tiny,
                        color = Theme.colors.textSecondary,
                        flexShrink = 1,
                    },
                },
            },
        },
    }
end

-- ============================================================================
-- 喂养材料选择面板
-- ============================================================================
local function BuildFeedPanel(petId)
    local p = GamePlayer.Get()
    if not p then return nil end

    local feedItems = GamePet.GetFeedableItems()
    local feedChildren = {}

    for _, fi in ipairs(feedItems) do
        -- 查背包数量
        local bagCount = 0
        for _, item in ipairs(p.bagItems or {}) do
            if item.name == fi.name then bagCount = item.count or 0 end
        end
        local canFeed = bagCount >= 1

        feedChildren[#feedChildren + 1] = UI.Panel {
            flexDirection = "row",
            justifyContent = "space-between",
            alignItems = "center",
            width = "100%",
            paddingVertical = 4,
            children = {
                UI.Panel {
                    flexDirection = "row", gap = 6, alignItems = "center",
                    children = {
                        UI.Label {
                            text = fi.name,
                            fontSize = Theme.fontSize.body,
                            color = canFeed and Theme.colors.textLight or Theme.colors.textSecondary,
                        },
                        UI.Label {
                            text = "(+" .. fi.exp .. "经验)",
                            fontSize = Theme.fontSize.tiny,
                            color = Theme.colors.accent,
                        },
                        UI.Label {
                            text = "x" .. bagCount,
                            fontSize = Theme.fontSize.tiny,
                            color = Theme.colors.textSecondary,
                        },
                    },
                },
                UI.Panel {
                    paddingHorizontal = 12, paddingVertical = 4,
                    borderRadius = Theme.radius.sm,
                    backgroundColor = canFeed and Theme.colors.gold or { 80, 70, 55, 150 },
                    cursor = canFeed and "pointer" or "default",
                    onClick = function(self)
                        if not canFeed then
                            Toast.Show("背包中" .. fi.name .. "不足", { variant = "error" })
                            return
                        end
                        local ok, msg = GamePet.DoFeed(petId, fi.name)
                        Toast.Show(msg, { variant = ok and "success" or "error" })
                        Router.RebuildUI()
                    end,
                    children = {
                        UI.Label {
                            text = canFeed and "喂养" or "不足",
                            fontSize = Theme.fontSize.small,
                            fontWeight = "bold",
                            color = canFeed and Theme.colors.inkBlack or Theme.colors.textSecondary,
                        },
                    },
                },
            },
        }
    end

    return UI.Panel {
        width = "100%",
        backgroundColor = { 35, 30, 25, 200 },
        borderRadius = Theme.radius.sm,
        padding = Theme.spacing.sm,
        gap = 4,
        children = {
            UI.Label {
                text = "选择喂养材料:",
                fontSize = Theme.fontSize.small,
                fontWeight = "bold",
                color = Theme.colors.textGold,
                marginBottom = 4,
            },
            table.unpack(feedChildren),
        },
    }
end

-- ============================================================================
-- 详情面板
-- ============================================================================
local function BuildDetailPanel(pet)
    local qColor = DataItems.GetQualityColor(pet.quality)

    -- 经验条
    local expBar = nil
    if pet.owned and pet.expMax > 0 then
        local pct = pet.expMax > 0 and (pet.exp / pet.expMax) or 0
        if pct > 1 then pct = 1 end
        expBar = UI.Panel {
            width = "100%", gap = 4,
            children = {
                UI.Panel {
                    width = "100%", height = 6,
                    borderRadius = 3,
                    backgroundColor = { 50, 45, 35, 255 },
                    overflow = "hidden",
                    children = {
                        UI.Panel {
                            width = tostring(math.floor(pct * 100)) .. "%",
                            height = "100%",
                            borderRadius = 3,
                            backgroundColor = Theme.colors.accent,
                        },
                    },
                },
                UI.Label {
                    text = "经验: " .. pet.exp .. " / " .. pet.expMax,
                    fontSize = Theme.fontSize.tiny,
                    color = Theme.colors.textSecondary,
                    alignSelf = "flex-end",
                },
            },
        }
    end

    -- 操作按钮
    local actionButtons = {}
    if pet.owned then
        -- 出战/召回
        actionButtons[#actionButtons + 1] = UI.Panel {
            flexGrow = 1,
            children = {
                Comp.BuildInkButton(
                    pet.isActive and "召回" or "出战",
                    function()
                        local newId = pet.isActive and 0 or pet.id
                        local ok, msg = GamePet.DoSetActive(newId)
                        Toast.Show(msg, { variant = ok and "success" or "error" })
                        Router.RebuildUI()
                    end,
                    { width = "100%", fontSize = Theme.fontSize.body }
                ),
            },
        }
        -- 喂养
        actionButtons[#actionButtons + 1] = UI.Panel {
            flexGrow = 1,
            children = {
                Comp.BuildSecondaryButton("喂养", function()
                    showFeedPanel_ = not showFeedPanel_
                    Router.RebuildUI()
                end, { width = "100%" }),
            },
        }
    end

    local detailChildren = {
        -- 头部
        UI.Panel {
            width = "100%", alignItems = "center", gap = 8,
            children = {
                UI.Panel {
                    width = 96, height = 96,
                    borderRadius = 12,
                    backgroundColor = { 25, 22, 18, 200 },
                    borderColor = qColor, borderWidth = 2,
                    justifyContent = "center", alignItems = "center",
                    overflow = "hidden",
                    children = {
                        UI.Panel {
                            width = 80, height = 80,
                            backgroundImage = pet.image,
                            backgroundFit = "contain",
                        },
                    },
                },
                UI.Panel {
                    flexDirection = "row", gap = 8, alignItems = "center",
                    children = {
                        UI.Label {
                            text = pet.name,
                            fontSize = Theme.fontSize.heading,
                            fontWeight = "bold",
                            color = Theme.colors.textLight,
                        },
                        pet.owned and UI.Label {
                            text = "Lv." .. pet.level,
                            fontSize = Theme.fontSize.subtitle,
                            color = Theme.colors.accent,
                        } or nil,
                        UI.Panel {
                            paddingHorizontal = 8, paddingVertical = 2,
                            borderRadius = 4,
                            backgroundColor = { qColor[1], qColor[2], qColor[3], 40 },
                            borderColor = qColor, borderWidth = 1,
                            children = {
                                UI.Label {
                                    text = DataItems.GetQualityLabel(pet.quality),
                                    fontSize = Theme.fontSize.small,
                                    color = qColor,
                                },
                            },
                        },
                    },
                },
            },
        },
        Comp.BuildInkDivider(),
        Comp.BuildStatRow("定位", pet.role, {}),
        Comp.BuildStatRow("技能", pet.skill, { valueColor = Theme.colors.textGold }),
        expBar,
        UI.Label {
            text = pet.desc,
            fontSize = Theme.fontSize.body,
            color = Theme.colors.textLight,
            width = "100%",
        },
    }

    -- 操作按钮行
    if #actionButtons > 0 then
        detailChildren[#detailChildren + 1] = Comp.BuildInkDivider()
        detailChildren[#detailChildren + 1] = UI.Panel {
            width = "100%",
            flexDirection = "row", gap = 8,
            children = actionButtons,
        }
    end

    -- 喂养面板
    if showFeedPanel_ and pet.owned then
        detailChildren[#detailChildren + 1] = BuildFeedPanel(pet.id)
    end

    -- 未拥有提示
    if not pet.owned then
        detailChildren[#detailChildren + 1] = Comp.BuildInkDivider()
        detailChildren[#detailChildren + 1] = UI.Label {
            text = "探索世界时有概率捕获此灵宠",
            fontSize = Theme.fontSize.body,
            color = Theme.colors.textSecondary,
            width = "100%",
            textAlign = "center",
        }
    end

    return UI.Panel {
        width = "100%",
        backgroundColor = Theme.colors.bgDark,
        borderRadius = Theme.radius.md,
        borderColor = Theme.colors.gold,
        borderWidth = 1,
        padding = Theme.spacing.md,
        gap = Theme.spacing.sm,
        children = detailChildren,
    }
end

-- ============================================================================
-- 构建页面
-- ============================================================================
function M.Build(payload)
    local p = GamePlayer.Get()
    if not p then return UI.Panel { width = "100%", height = "100%" } end

    local allPets = GamePet.GetAllPets()
    local ownedCount = GamePet.GetOwnedCount()

    -- 按拥有状态排序：已拥有在前
    local sortedPets = {}
    for _, pet in ipairs(allPets) do sortedPets[#sortedPets + 1] = pet end
    table.sort(sortedPets, function(a, b)
        if a.owned ~= b.owned then return a.owned end
        if a.isActive ~= b.isActive then return a.isActive end
        return a.id < b.id
    end)

    local contentChildren = {
        Comp.BuildSectionTitle("灵宠仙阁"),
        UI.Label {
            text = "已拥有 " .. ownedCount .. "/" .. #allPets .. " 只灵宠，探索时有概率捕获新灵宠",
            fontSize = Theme.fontSize.small,
            color = Theme.colors.textSecondary,
            marginBottom = 4,
        },
    }

    -- 详情面板
    if selectedPetId_ then
        for _, pet in ipairs(allPets) do
            if pet.id == selectedPetId_ then
                contentChildren[#contentChildren + 1] = BuildDetailPanel(pet)
                break
            end
        end
    end

    -- 灵宠列表
    contentChildren[#contentChildren + 1] = Comp.BuildSectionTitle(
        "全部灵宠 (" .. #allPets .. ")"
    )
    for _, pet in ipairs(sortedPets) do
        contentChildren[#contentChildren + 1] = BuildPetCard(pet)
    end

    return Comp.BuildPageShell("pet", p, contentChildren, Router.HandleNavigate)
end

return M
