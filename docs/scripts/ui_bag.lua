-- ============================================================================
-- 《问道长生》储物页（重构版）
-- 功能：分类标签 + 子标签 + 容量显示 + 物品锁定 + 回收面板
-- ============================================================================

local UI = require("urhox-libs/UI")
local Theme = require("ui_theme")
local Comp = require("ui_components")
local Router = require("ui_router")
local GamePlayer = require("game_player")
local GameItems = require("game_items")
local DataItems = require("data_items")
local Toast = require("ui_toast")

local M = {}

-- ============================================================================
-- 页面状态
-- ============================================================================
local activeCategory_ = "fabao"    -- 当前主分类
local activeSubTab_   = nil        -- 当前子分类（nil=全部）
local selectedItem_   = 1          -- 当前选中物品索引（分类列表内）
local showRecycle_    = false       -- 回收面板
local showExpand_     = false       -- 扩容确认
local showBatchSell_  = false       -- 批量出售确认
local batchSellCount_ = 0
local batchSellPrice_ = 0

-- 回收品质勾选状态
local recycleQualities_ = {
    common   = true,
    uncommon = true,
    rare     = false,
    epic     = false,
    legend   = false,
    mythic   = false,
}

-- ============================================================================
-- 构建分类主标签栏
-- ============================================================================
local function BuildCategoryTabs()
    local cats = DataItems.ITEM_CATEGORIES
    local counts = GameItems.GetCategoryCounts()
    local children = {}
    for _, cat in ipairs(cats) do
        local isActive = (cat.key == activeCategory_)
        local cnt = counts[cat.key] or 0
        local label = cat.label
        if cnt > 0 then label = label .. "(" .. cnt .. ")" end

        children[#children + 1] = UI.Panel {
            flexGrow = 1,
            height = 36,
            justifyContent = "center",
            alignItems = "center",
            backgroundColor = isActive and { 60, 50, 35, 255 } or { 0, 0, 0, 0 },
            borderColor = isActive and Theme.colors.gold or { 0, 0, 0, 0 },
            borderWidth = { bottom = isActive and 2 or 0 },
            cursor = "pointer",
            onClick = function(self)
                activeCategory_ = cat.key
                activeSubTab_ = nil
                selectedItem_ = 1
                Router.RebuildUI()
            end,
            children = {
                UI.Label {
                    text = label,
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
        backgroundColor = { 30, 25, 20, 200 },
        borderColor = Theme.colors.border,
        borderWidth = { bottom = 1 },
        children = children,
    }
end

-- ============================================================================
-- 构建子标签栏（仅法宝/物品有子分类）
-- ============================================================================
local function BuildSubTabs()
    local catDef = DataItems.GetCategory(activeCategory_)
    if not catDef or not catDef.subTabs then return nil end

    local children = {}
    -- "全部"按钮
    local allActive = (activeSubTab_ == nil)
    children[#children + 1] = UI.Panel {
        paddingHorizontal = 10,
        paddingVertical = 4,
        borderRadius = Theme.radius.sm,
        backgroundColor = allActive and Theme.colors.gold or { 45, 38, 30, 200 },
        cursor = "pointer",
        onClick = function(self)
            activeSubTab_ = nil
            selectedItem_ = 1
            Router.RebuildUI()
        end,
        children = {
            UI.Label {
                text = "全部",
                fontSize = Theme.fontSize.small,
                fontWeight = allActive and "bold" or "normal",
                color = allActive and Theme.colors.inkBlack or Theme.colors.textLight,
            },
        },
    }
    for _, sub in ipairs(catDef.subTabs) do
        local isActive = (activeSubTab_ == sub)
        children[#children + 1] = UI.Panel {
            paddingHorizontal = 10,
            paddingVertical = 4,
            borderRadius = Theme.radius.sm,
            backgroundColor = isActive and Theme.colors.gold or { 45, 38, 30, 200 },
            cursor = "pointer",
            onClick = function(self)
                activeSubTab_ = sub
                selectedItem_ = 1
                Router.RebuildUI()
            end,
            children = {
                UI.Label {
                    text = sub,
                    fontSize = Theme.fontSize.small,
                    fontWeight = isActive and "bold" or "normal",
                    color = isActive and Theme.colors.inkBlack or Theme.colors.textLight,
                },
            },
        }
    end

    return UI.Panel {
        width = "100%",
        flexDirection = "row",
        flexWrap = "wrap",
        gap = 6,
        paddingVertical = 6,
        paddingHorizontal = 4,
        children = children,
    }
end

-- ============================================================================
-- 构建容量栏
-- ============================================================================
local function BuildCapacityBar()
    local used = GameItems.GetBagUsed()
    local cap = GameItems.GetBagCapacity()
    local pct = used / math.max(cap, 1)
    local barColor = pct > 0.9 and Theme.colors.danger
        or pct > 0.7 and { 220, 180, 60, 255 }
        or Theme.colors.gold

    return UI.Panel {
        width = "100%",
        flexDirection = "row",
        alignItems = "center",
        gap = 8,
        paddingHorizontal = 4,
        children = {
            UI.Label {
                text = "储物戒",
                fontSize = Theme.fontSize.body,
                fontWeight = "bold",
                color = Theme.colors.textGold,
            },
            -- 进度条
            UI.Panel {
                flexGrow = 1,
                height = 8,
                borderRadius = 4,
                backgroundColor = { 50, 45, 35, 255 },
                overflow = "hidden",
                children = {
                    UI.Panel {
                        width = tostring(math.floor(pct * 100)) .. "%",
                        height = "100%",
                        borderRadius = 4,
                        backgroundColor = barColor,
                    },
                },
            },
            UI.Label {
                text = used .. "/" .. cap,
                fontSize = Theme.fontSize.small,
                color = pct > 0.9 and Theme.colors.danger or Theme.colors.textLight,
            },
        },
    }
end

-- ============================================================================
-- 构建物品格子
-- ============================================================================
local function BuildItemCell(item, idx, isSelected)
    local rarityColor = Comp.GetRarityColor(item.rarity)
    local bg = isSelected and { 60, 55, 40, 255 } or Theme.colors.bgDark
    local borderC = isSelected and Theme.colors.gold or rarityColor
    local locked = item.locked or false

    return UI.Panel {
        width = "18%",
        aspectRatio = 1,
        borderRadius = Theme.radius.sm,
        backgroundColor = bg,
        borderColor = borderC,
        borderWidth = isSelected and 2 or 1,
        justifyContent = "center",
        alignItems = "center",
        gap = 1,
        cursor = "pointer",
        onClick = function(self)
            selectedItem_ = idx
            Router.RebuildUI()
        end,
        children = (function()
            local c = {}
            if locked then
                c[#c + 1] = UI.Panel {
                    position = "absolute",
                    top = 1, right = 1,
                    children = {
                        UI.Label {
                            text = "[锁]",
                            fontSize = 7,
                            color = Theme.colors.gold,
                        },
                    },
                }
            end
            c[#c + 1] = UI.Label {
                text = item.name,
                fontSize = 9,
                color = Theme.colors.textLight,
                textAlign = "center",
            }
            c[#c + 1] = UI.Label {
                text = "x" .. (item.count or 1),
                fontSize = 8,
                color = Theme.colors.textSecondary,
            }
            return c
        end)(),
    }
end

-- ============================================================================
-- 构建选中物品详情面板
-- ============================================================================
local function BuildItemDetail(item, globalIndex)
    if not item then return nil end
    local rarityLabel = DataItems.GetQualityLabel(item.rarity or "common")
    local rarityColor = Comp.GetRarityColor(item.rarity)
    local locked = item.locked or false

    local detailChildren = {
        UI.Panel {
            flexDirection = "row",
            justifyContent = "space-between",
            alignItems = "center",
            width = "100%",
            children = (function()
                local c = {
                    UI.Panel {
                        flexDirection = "row",
                        gap = 8,
                        alignItems = "center",
                        children = (function()
                            local cc = {
                                UI.Label {
                                    text = "数量: " .. (item.count or 1),
                                    fontSize = Theme.fontSize.body,
                                    color = Theme.colors.textLight,
                                },
                            }
                            if locked then
                                cc[#cc + 1] = UI.Label {
                                    text = "[已锁定]",
                                    fontSize = Theme.fontSize.small,
                                    color = Theme.colors.gold,
                                }
                            end
                            return cc
                        end)(),
                    },
                    UI.Label {
                        text = rarityLabel,
                        fontSize = Theme.fontSize.small,
                        fontWeight = "bold",
                        color = rarityColor,
                    },
                }
                return c
            end)(),
        },
    }
    -- 描述（有内容才添加）
    if item.desc and item.desc ~= "" then
        detailChildren[#detailChildren + 1] = UI.Label {
            text = item.desc,
            fontSize = Theme.fontSize.small,
            color = Theme.colors.textSecondary,
            width = "100%",
        }
    end
    -- 操作按钮行
    detailChildren[#detailChildren + 1] = UI.Panel {
            width = "100%",
            flexDirection = "row",
            gap = 6,
            marginTop = 4,
            children = {
                -- 使用按钮
                UI.Panel {
                    flexGrow = 1,
                    children = {
                        Comp.BuildInkButton("使用", function()
                            local ok, msg = GameItems.DoUseItem(globalIndex)
                            Toast.Show(msg, { variant = ok and "success" or "error" })
                            if ok then
                                selectedItem_ = math.max(1, selectedItem_)
                                Router.RebuildUI()
                            end
                        end, { width = "100%", fontSize = Theme.fontSize.body }),
                    },
                },
                -- 锁定/解锁按钮
                UI.Panel {
                    flexGrow = 1,
                    children = {
                        Comp.BuildSecondaryButton(locked and "解锁" or "锁定", function()
                            local ok, msg = GameItems.ToggleLock(globalIndex)
                            Toast.Show(msg, { variant = ok and "success" or "info" })
                            if ok then Router.RebuildUI() end
                        end, { width = "100%" }),
                    },
                },
                -- 出售按钮
                UI.Panel {
                    flexGrow = 1,
                    children = {
                        Comp.BuildSecondaryButton("出售", function()
                            if locked then
                                Toast.Show("已锁定的物品无法出售", { variant = "error" })
                                return
                            end
                            local ok, msg = GameItems.DoSellItem(globalIndex)
                            Toast.Show(msg, { variant = ok and "success" or "error" })
                            if ok then
                                selectedItem_ = math.max(1, selectedItem_)
                                Router.RebuildUI()
                            end
                        end, { width = "100%" }),
                    },
                },
            },
        }

    return Comp.BuildCardPanel(item.name, detailChildren)
end

-- ============================================================================
-- 构建回收面板弹窗
-- ============================================================================
local function BuildRecyclePanel()
    local qualityOrder = DataItems.QUALITY_ORDER
    -- 品质勾选列表
    local checkChildren = {}
    for _, qKey in ipairs(qualityOrder) do
        local qDef = DataItems.QUALITY[qKey]
        if not qDef then goto cont end
        local checked = recycleQualities_[qKey] or false
        checkChildren[#checkChildren + 1] = UI.Panel {
            flexDirection = "row",
            alignItems = "center",
            gap = 6,
            cursor = "pointer",
            onClick = function(self)
                recycleQualities_[qKey] = not recycleQualities_[qKey]
                Router.RebuildUI()
            end,
            children = {
                UI.Panel {
                    width = 18, height = 18,
                    borderRadius = 3,
                    borderColor = qDef.color,
                    borderWidth = 1,
                    backgroundColor = checked and qDef.color or { 40, 35, 30, 200 },
                    justifyContent = "center",
                    alignItems = "center",
                    children = checked and {
                        UI.Label {
                            text = "V",
                            fontSize = 11,
                            fontWeight = "bold",
                            color = Theme.colors.inkBlack,
                        },
                    } or {},
                },
                UI.Label {
                    text = qDef.label,
                    fontSize = Theme.fontSize.body,
                    color = qDef.color,
                },
            },
        }
        ::cont::
    end

    -- 预览结果
    local recyclable, totalPrice = GameItems.GetRecyclableItems(recycleQualities_)
    local cnt = 0
    for _, r in ipairs(recyclable) do cnt = cnt + (r.item.count or 1) end

    return UI.Panel {
        position = "absolute",
        top = 0, left = 0, right = 0, bottom = 0,
        backgroundColor = { 0, 0, 0, 160 },
        justifyContent = "center",
        alignItems = "center",
        onClick = function(self)
            showRecycle_ = false
            Router.RebuildUI()
        end,
        children = {
            UI.Panel {
                width = "80%",
                backgroundColor = Theme.colors.bgDarkSolid,
                borderRadius = Theme.radius.lg,
                borderColor = Theme.colors.borderGold,
                borderWidth = 1,
                padding = Theme.spacing.lg,
                gap = Theme.spacing.md,
                onClick = function(self) end,  -- 阻止穿透
                children = {
                    UI.Label {
                        text = "回收站",
                        fontSize = Theme.fontSize.heading,
                        fontWeight = "bold",
                        color = Theme.colors.textGold,
                        alignSelf = "center",
                    },
                    UI.Divider {
                        orientation = "horizontal",
                        thickness = 1,
                        color = Theme.colors.divider,
                        spacing = 4,
                    },
                    UI.Label {
                        text = "选择回收品质(锁定物品不参与回收):",
                        fontSize = Theme.fontSize.body,
                        color = Theme.colors.textLight,
                    },
                    -- 品质勾选网格
                    UI.Panel {
                        width = "100%",
                        flexDirection = "row",
                        flexWrap = "wrap",
                        gap = 10,
                        children = checkChildren,
                    },
                    UI.Divider {
                        orientation = "horizontal",
                        thickness = 1,
                        color = Theme.colors.divider,
                        spacing = 4,
                    },
                    -- 预览统计
                    Comp.BuildStatRow("符合条件物品",
                        tostring(cnt) .. " 件",
                        { valueColor = Theme.colors.textLight }),
                    Comp.BuildStatRow("预计获得",
                        "灵石 " .. tostring(totalPrice),
                        { valueColor = { 240, 220, 100, 255 } }),
                    -- 按钮行
                    UI.Panel {
                        width = "100%",
                        flexDirection = "row",
                        gap = 10,
                        marginTop = 4,
                        children = {
                            UI.Panel {
                                flexGrow = 1,
                                children = {
                                    Comp.BuildSecondaryButton("取消", function()
                                        showRecycle_ = false
                                        Router.RebuildUI()
                                    end, { width = "100%" }),
                                },
                            },
                            UI.Panel {
                                flexGrow = 1,
                                children = {
                                    Comp.BuildInkButton("全部回收", function()
                                        showRecycle_ = false
                                        local ok, msg = GameItems.DoRecycle(recycleQualities_)
                                        Toast.Show(msg, { variant = ok and "success" or "error" })
                                        if ok then
                                            selectedItem_ = 1
                                        end
                                        Router.RebuildUI()
                                    end, {
                                        width = "100%",
                                        fontSize = Theme.fontSize.body,
                                        disabled = cnt == 0,
                                    }),
                                },
                            },
                        },
                    },
                },
            },
        },
    }
end

-- ============================================================================
-- 构建扩容确认弹窗
-- ============================================================================
local function BuildExpandConfirm()
    local cost, currency = GameItems.GetExpandCost()
    local cap = GameItems.GetBagCapacity()
    local newCap = cap + DataItems.BAG_EXPAND.perExpand
    local canExpand, reason = GameItems.CanExpandBag()

    return UI.Panel {
        position = "absolute",
        top = 0, left = 0, right = 0, bottom = 0,
        backgroundColor = { 0, 0, 0, 160 },
        justifyContent = "center",
        alignItems = "center",
        onClick = function(self)
            showExpand_ = false
            Router.RebuildUI()
        end,
        children = {
            UI.Panel {
                width = "75%",
                backgroundColor = Theme.colors.bgDarkSolid,
                borderRadius = Theme.radius.lg,
                borderColor = Theme.colors.borderGold,
                borderWidth = 1,
                padding = Theme.spacing.lg,
                gap = Theme.spacing.md,
                alignItems = "center",
                onClick = function(self) end,
                children = {
                    UI.Label {
                        text = "储物扩容",
                        fontSize = Theme.fontSize.heading,
                        fontWeight = "bold",
                        color = Theme.colors.textGold,
                    },
                    UI.Divider {
                        orientation = "horizontal",
                        thickness = 1,
                        color = Theme.colors.divider,
                        spacing = 4,
                    },
                    Comp.BuildStatRow("当前容量",
                        tostring(cap) .. " 格",
                        { valueColor = Theme.colors.textLight }),
                    Comp.BuildStatRow("扩容后",
                        tostring(newCap) .. " 格",
                        { valueColor = Theme.colors.gold }),
                    Comp.BuildStatRow("消耗",
                        currency .. " " .. tostring(cost),
                        { valueColor = { 240, 220, 100, 255 } }),
                    not canExpand and reason and UI.Label {
                        text = reason,
                        fontSize = Theme.fontSize.small,
                        color = Theme.colors.danger,
                        textAlign = "center",
                    } or nil,
                    UI.Panel {
                        width = "100%",
                        flexDirection = "row",
                        gap = 10,
                        marginTop = 4,
                        children = {
                            UI.Panel {
                                flexGrow = 1,
                                children = {
                                    Comp.BuildSecondaryButton("取消", function()
                                        showExpand_ = false
                                        Router.RebuildUI()
                                    end, { width = "100%" }),
                                },
                            },
                            UI.Panel {
                                flexGrow = 1,
                                children = {
                                    Comp.BuildInkButton("确认扩容", function()
                                        showExpand_ = false
                                        local ok, msg = GameItems.DoExpandBag()
                                        Toast.Show(msg, { variant = ok and "success" or "error" })
                                        Router.RebuildUI()
                                    end, {
                                        width = "100%",
                                        fontSize = Theme.fontSize.body,
                                        disabled = not canExpand,
                                    }),
                                },
                            },
                        },
                    },
                },
            },
        },
    }
end

-- ============================================================================
-- 构建批量出售确认弹窗
-- ============================================================================
local function BuildBatchSellConfirm()
    return UI.Panel {
        position = "absolute",
        top = 0, left = 0, right = 0, bottom = 0,
        backgroundColor = { 0, 0, 0, 160 },
        justifyContent = "center",
        alignItems = "center",
        onClick = function(self)
            showBatchSell_ = false
            Router.RebuildUI()
        end,
        children = {
            UI.Panel {
                width = "75%",
                backgroundColor = Theme.colors.bgDarkSolid,
                borderRadius = Theme.radius.lg,
                borderColor = Theme.colors.borderGold,
                borderWidth = 1,
                padding = Theme.spacing.lg,
                gap = Theme.spacing.md,
                alignItems = "center",
                onClick = function(self) end,
                children = {
                    UI.Label {
                        text = "批量出售确认",
                        fontSize = Theme.fontSize.heading,
                        fontWeight = "bold",
                        color = Theme.colors.textGold,
                    },
                    UI.Divider {
                        orientation = "horizontal",
                        thickness = 1,
                        color = Theme.colors.divider,
                        spacing = 4,
                    },
                    UI.Label {
                        text = "将出售优良品质及以下的所有物品",
                        fontSize = Theme.fontSize.body,
                        color = Theme.colors.textLight,
                        textAlign = "center",
                    },
                    UI.Label {
                        text = "(已锁定物品不会被出售)",
                        fontSize = Theme.fontSize.small,
                        color = Theme.colors.textSecondary,
                        textAlign = "center",
                    },
                    Comp.BuildStatRow("出售数量",
                        tostring(batchSellCount_) .. " 件",
                        { valueColor = Theme.colors.gold }),
                    Comp.BuildStatRow("预计获得",
                        "灵石 " .. tostring(batchSellPrice_),
                        { valueColor = { 240, 220, 100, 255 } }),
                    UI.Panel {
                        width = "100%",
                        flexDirection = "row",
                        gap = 10,
                        marginTop = 4,
                        children = {
                            UI.Panel {
                                flexGrow = 1,
                                children = {
                                    Comp.BuildSecondaryButton("取消", function()
                                        showBatchSell_ = false
                                        Router.RebuildUI()
                                    end, { width = "100%" }),
                                },
                            },
                            UI.Panel {
                                flexGrow = 1,
                                children = {
                                    Comp.BuildInkButton("确认出售", function()
                                        showBatchSell_ = false
                                        local ok, msg = GameItems.DoBatchSell("uncommon")
                                        Toast.Show(msg, { variant = ok and "success" or "error" })
                                        if ok then
                                            selectedItem_ = 1
                                            Router.RebuildUI()
                                        end
                                    end, { width = "100%", fontSize = Theme.fontSize.body }),
                                },
                            },
                        },
                    },
                },
            },
        },
    }
end

-- ============================================================================
-- 主页面构建
-- ============================================================================
function M.Build(payload)
    local p = GamePlayer.Get()
    if not p then return UI.Panel { width = "100%", height = "100%" } end

    -- 旧数据迁移：确保所有物品有分类字段
    GameItems.MigrateBagCategories()

    local allItems = p.bagItems or {}

    -- 筛选当前分类的物品
    local filteredItems = GameItems.GetItemsByCategory(activeCategory_, activeSubTab_)
    if selectedItem_ > #filteredItems then selectedItem_ = 1 end

    -- 空状态
    if #allItems == 0 then
        return Comp.BuildPageShell("bag", p, {
            BuildCapacityBar(),
            BuildCategoryTabs(),
            Comp.BuildCardPanel("储物袋", {
                UI.Label {
                    text = "背包空空如也，去探索获取物品吧",
                    fontSize = Theme.fontSize.body,
                    color = Theme.colors.textSecondary,
                    textAlign = "center",
                    width = "100%",
                    paddingVertical = 40,
                },
            }),
        }, Router.HandleNavigate)
    end

    -- 当前分类无物品
    local hasItems = #filteredItems > 0
    local sel = hasItems and filteredItems[selectedItem_] or nil

    -- 需要找到选中物品在全局 bagItems 中的索引（操作用）
    local globalIndex = 0
    if sel then
        for i, item in ipairs(allItems) do
            if item == sel then
                globalIndex = i
                break
            end
        end
    end

    -- 物品网格
    local itemCells = {}
    for i, item in ipairs(filteredItems) do
        itemCells[#itemCells + 1] = BuildItemCell(item, i, i == selectedItem_)
    end

    -- 子标签
    local subTabs = BuildSubTabs()

    local contentChildren = {
        -- 容量栏
        BuildCapacityBar(),
        -- 分类标签
        BuildCategoryTabs(),
    }
    -- 子标签（仅法宝/物品有，材料/灵宠没有）
    if subTabs then
        contentChildren[#contentChildren + 1] = subTabs
    end
    -- 选中物品详情
    contentChildren[#contentChildren + 1] = hasItems and BuildItemDetail(sel, globalIndex) or Comp.BuildCardPanel(nil, {
        UI.Label {
            text = "当前分类暂无物品",
            fontSize = Theme.fontSize.body,
            color = Theme.colors.textSecondary,
            textAlign = "center",
            width = "100%",
            paddingVertical = 20,
        },
    })
    -- 物品网格
    if hasItems then
        contentChildren[#contentChildren + 1] = UI.Panel {
            width = "100%",
            flexDirection = "row",
            flexWrap = "wrap",
            gap = 4,
            children = itemCells,
        }
    end
    -- 底部操作按钮
    contentChildren[#contentChildren + 1] = UI.Panel {
            width = "100%",
            flexDirection = "row",
            gap = 6,
            marginTop = 8,
            children = {
                UI.Panel {
                    flexGrow = 1,
                    children = {
                        Comp.BuildSecondaryButton("整理", function()
                            local msg = GameItems.SortBag()
                            Toast.Show(msg, { variant = "success" })
                            Router.RebuildUI()
                        end, { width = "100%" }),
                    },
                },
                UI.Panel {
                    flexGrow = 1,
                    children = {
                        Comp.BuildSecondaryButton("回收", function()
                            showRecycle_ = true
                            Router.RebuildUI()
                        end, { width = "100%" }),
                    },
                },
                UI.Panel {
                    flexGrow = 1,
                    children = {
                        Comp.BuildSecondaryButton("批量出售", function()
                            local cnt, price = GameItems.PreviewBatchSell("uncommon")
                            if cnt == 0 then
                                Toast.Show("没有可出售的物品", { variant = "error" })
                                return
                            end
                            batchSellCount_ = cnt
                            batchSellPrice_ = price
                            showBatchSell_ = true
                            Router.RebuildUI()
                        end, { width = "100%" }),
                    },
                },
                UI.Panel {
                    flexGrow = 1,
                    children = {
                        Comp.BuildSecondaryButton("扩容", function()
                            showExpand_ = true
                            Router.RebuildUI()
                        end, { width = "100%" }),
                    },
                },
            },
        }

    local pageShell = Comp.BuildPageShell("bag", p, contentChildren, Router.HandleNavigate)

    -- 叠加弹窗层
    if showRecycle_ or showExpand_ or showBatchSell_ then
        local overlay = nil
        if showRecycle_ then
            overlay = BuildRecyclePanel()
        elseif showExpand_ then
            overlay = BuildExpandConfirm()
        elseif showBatchSell_ then
            overlay = BuildBatchSellConfirm()
        end

        return UI.Panel {
            width = "100%",
            height = "100%",
            children = {
                pageShell,
                overlay,
            },
        }
    end

    return pageShell
end

return M
