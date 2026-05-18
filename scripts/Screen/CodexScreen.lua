-- ============================================================================
-- CodexScreen - 名器图鉴界面
-- Project Smith / P2-C3
--
-- 功能：
--   1. 展示所有武器配方（按武器线分组）
--   2. 已解锁的武器显示详情（图片、名称、描述、工序）
--   3. 未解锁的武器显示剪影/问号占位
--   4. 返回主界面按钮
-- ============================================================================

local UI             = require("urhox-libs/UI")
local GameState      = require("Core.GameState")
local WeaponRecipes  = require("Config.WeaponRecipes")
local ScreenRouter   = require("Utils.ScreenRouter")

local CodexScreen = {}

-- ============================================================================
-- UI 素材路径（武侠水墨风）
-- ============================================================================

local UI_ASSETS = {
    panel_header    = "image/ui/panel_header.png",
    panel_card      = "image/ui/panel_card.png",
    panel_card_blue = "image/ui/panel_card_blue.png",
    btn_secondary   = "image/ui/btn_secondary.png",
    frame_item_md   = "image/ui/frame_item_md.png",
    divider_bamboo  = "image/ui/divider_bamboo.png",
}

-- ============================================================================
-- 色板
-- ============================================================================

local C = {
    bgPrimary     = { 26,  26,  46,  255 },
    bgSecondary   = { 22,  33,  62,  255 },
    bgCard        = { 30,  40,  68,  255 },
    bgCardLocked  = { 20,  25,  40,  200 },
    accent        = { 233, 69,  96,  255 },
    gold          = { 212, 165, 116, 255 },
    textPrimary   = { 232, 224, 208, 255 },
    textSecondary = { 160, 147, 125, 255 },
    textLocked    = { 80,  80,  100, 180 },
    success       = { 78,  205, 196, 255 },
    warning       = { 255, 217, 61,  255 },
    divider       = { 60,  60,  90,  255 },
    btnBack       = { 60,  50,  80,  255 },
    btnBackHover  = { 80,  70,  100, 255 },
    btnBackPress  = { 45,  38,  60,  255 },
}

-- ============================================================================
-- 武器图片映射
-- ============================================================================

local WEAPON_IMAGES = {
    WEAPON_001 = "image/weapon_001_hunter_knife.png",
    WEAPON_002 = "image/weapon_002_guard_blade.png",
    WEAPON_003 = "image/weapon_003_mountain_cleaver.png",
    WEAPON_004 = "image/weapon_004_ranger_sword.png",
    WEAPON_005 = "image/weapon_005_legion_breaker.png",
    WEAPON_006 = "image/weapon_006_azure_sword.png",
    WEAPON_007 = "image/weapon_007_fortress_greatsword.png",
    WEAPON_008 = "image/weapon_008_peak_cleaver.png",
    WEAPON_009 = "image/weapon_009_meteoric_saber.png",
    WEAPON_010 = "image/weapon_010_imperial_decree.png",
    WEAPON_011 = "image/weapon_011_guild_ceremonial.png",
    WEAPON_012 = "image/weapon_012_frostgleam_reforged.png",
}

-- 武器线显示名
local LINE_NAMES = {
    short_blade    = "短刃",
    long_sword     = "长剑",
    heavy_blade    = "重剑",
    ritual         = "礼器",
    heavy_sword    = "重剑",
    ceremony_blade = "礼剑",
}

-- 工序显示名
local STEP_NAMES = {
    ore_select = "选矿",
    smelting   = "熔炼",
    forging    = "锻打",
    quenching  = "淬火",
    polishing  = "研磨",
    assembly   = "组装",
}

-- ============================================================================
-- Screen 接口
-- ============================================================================

---@param container table UI 容器
---@param params table|nil
---@return table screen
function CodexScreen.Create(container, params)
    local screen = {}

    -- 获取已解锁图鉴
    local unlockedSet = {}
    local codexList = GameState.GetCodex()
    for i = 1, #codexList do
        unlockedSet[codexList[i]] = true
    end

    -- 获取所有武器配方
    local allRecipes = WeaponRecipes.GetAll()

    -- 按武器线分组
    local lineGroups = {}
    local lineOrder = {}
    for i = 1, #allRecipes do
        local recipe = allRecipes[i]
        local line = recipe.line
        if not lineGroups[line] then
            lineGroups[line] = {}
            lineOrder[#lineOrder + 1] = line
        end
        lineGroups[line][#lineGroups[line] + 1] = recipe
    end

    -- ----------------------------------------------------------------
    -- 武器卡片
    -- ----------------------------------------------------------------
    local function CreateWeaponCard(recipe, isUnlocked)
        local weaponId = recipe.id

        if isUnlocked then
            -- 已解锁：显示完整信息
            local imgPath = WEAPON_IMAGES[weaponId]

            -- 工序标签
            local stepLabels = {}
            for j = 1, #recipe.steps do
                stepLabels[#stepLabels + 1] = UI.Label {
                    text = STEP_NAMES[recipe.steps[j]] or recipe.steps[j],
                    fontSize = 9,
                    fontColor = C.success,
                    backgroundColor = { 78, 205, 196, 40 },
                    paddingHorizontal = 4,
                    paddingVertical = 1,
                    borderRadius = 3,
                }
            end

            return UI.Panel {
                width = "100%",
                backgroundImage = UI_ASSETS.panel_card,
                backgroundFit = "cover",
                borderRadius = 8,
                padding = 10,
                marginBottom = 8,
                flexDirection = "row",
                gap = 10,
                children = {
                    -- 武器图片（带边框）
                    UI.Panel {
                        width = 76,
                        height = 76,
                        backgroundImage = UI_ASSETS.frame_item_md,
                        backgroundFit = "cover",
                        justifyContent = "center",
                        alignItems = "center",
                        children = {
                            UI.Panel {
                                width = 56,
                                height = 56,
                                backgroundImage = imgPath,
                                backgroundFit = "contain",
                            },
                        },
                    },
                    -- 信息区
                    UI.Panel {
                        flexGrow = 1,
                        flexShrink = 1,
                        gap = 3,
                        children = {
                            UI.Label {
                                text = recipe.name,
                                fontSize = 15,
                                fontColor = C.gold,
                            },
                            UI.Label {
                                text = recipe.description or "",
                                fontSize = 11,
                                fontColor = C.textSecondary,
                            },
                            -- 工序流程
                            UI.Panel {
                                flexDirection = "row",
                                flexWrap = "wrap",
                                gap = 4,
                                marginTop = 3,
                                children = stepLabels,
                            },
                        },
                    },
                },
            }
        else
            -- 未解锁：显示占位
            return UI.Panel {
                width = "100%",
                backgroundImage = UI_ASSETS.panel_card_blue,
                backgroundFit = "cover",
                borderRadius = 8,
                padding = 10,
                marginBottom = 8,
                flexDirection = "row",
                alignItems = "center",
                opacity = 0.6,
                gap = 10,
                children = {
                    -- 问号占位
                    UI.Panel {
                        width = 76,
                        height = 76,
                        backgroundImage = UI_ASSETS.frame_item_md,
                        backgroundFit = "cover",
                        justifyContent = "center",
                        alignItems = "center",
                        children = {
                            UI.Label {
                                text = "?",
                                fontSize = 28,
                                fontColor = C.textLocked,
                                textAlign = "center",
                            },
                        },
                    },
                    -- 锁定提示
                    UI.Panel {
                        flexGrow = 1,
                        flexShrink = 1,
                        children = {
                            UI.Label {
                                text = "???",
                                fontSize = 15,
                                fontColor = C.textLocked,
                            },
                            UI.Label {
                                text = "完成相关订单后解锁",
                                fontSize = 11,
                                fontColor = C.textLocked,
                            },
                        },
                    },
                },
            }
        end
    end

    -- ----------------------------------------------------------------
    -- 武器线分组
    -- ----------------------------------------------------------------
    local function CreateLineSection(lineId, recipes)
        local lineName = LINE_NAMES[lineId] or lineId
        local unlockedCount = 0
        local cards = {}

        for i = 1, #recipes do
            local isUnlocked = unlockedSet[recipes[i].id] == true
            if isUnlocked then unlockedCount = unlockedCount + 1 end
            cards[#cards + 1] = CreateWeaponCard(recipes[i], isUnlocked)
        end

        return UI.Panel {
            width = "100%",
            marginBottom = 12,
            children = {
                -- 分组标题
                UI.Panel {
                    width = "100%",
                    flexDirection = "row",
                    justifyContent = "space-between",
                    alignItems = "center",
                    marginBottom = 6,
                    children = {
                        UI.Label {
                            text = "-- " .. lineName .. "系 --",
                            fontSize = 14,
                            fontColor = C.gold,
                        },
                        UI.Label {
                            text = unlockedCount .. "/" .. #recipes,
                            fontSize = 12,
                            fontColor = C.textSecondary,
                        },
                    },
                },
                -- 卡片列表
                table.unpack(cards),
            },
        }
    end

    -- ----------------------------------------------------------------
    -- 统计
    -- ----------------------------------------------------------------
    local totalWeapons = #allRecipes
    local totalUnlocked = #codexList

    -- ----------------------------------------------------------------
    -- 页面组装
    -- ----------------------------------------------------------------

    -- 内容区域（各武器线）
    local sectionChildren = {}
    for i = 1, #lineOrder do
        sectionChildren[#sectionChildren + 1] = CreateLineSection(lineOrder[i], lineGroups[lineOrder[i]])
    end

    local scrollContent = UI.Panel {
        width = "100%",
        paddingHorizontal = 14,
        paddingTop = 8,
        paddingBottom = 20,
        children = sectionChildren,
    }

    local panel = UI.Panel {
        width = "100%",
        height = "100%",
        flexDirection = "column",
        backgroundColor = C.bgPrimary,
        children = {
            -- 顶部栏
            UI.Panel {
                width = "100%",
                flexDirection = "row",
                alignItems = "center",
                paddingHorizontal = 12,
                paddingTop = 36,
                paddingBottom = 10,
                backgroundImage = UI_ASSETS.panel_header,
                backgroundFit = "cover",
                children = {
                    -- 返回按钮
                    UI.Button {
                        text = "< 返回",
                        width = 70,
                        height = 36,
                        fontSize = 13,
                        backgroundImage = UI_ASSETS.btn_secondary,
                        backgroundFit = "cover",
                        fontColor = C.textPrimary,
                        borderRadius = 6,
                        onClick = function()
                            ScreenRouter.GoTo("home")
                        end,
                    },
                    -- 标题
                    UI.Label {
                        text = "名器图鉴",
                        fontSize = 18,
                        fontColor = C.gold,
                        textAlign = "center",
                        flexGrow = 1,
                    },
                    -- 收集进度
                    UI.Label {
                        text = totalUnlocked .. "/" .. totalWeapons,
                        fontSize = 13,
                        fontColor = C.textSecondary,
                        width = 70,
                        textAlign = "right",
                    },
                },
            },
            -- 分隔线
            UI.Panel {
                width = "100%",
                height = 16,
                backgroundImage = UI_ASSETS.divider_bamboo,
                backgroundFit = "contain",
            },
            -- 可滚动内容区
            UI.ScrollView {
                width = "100%",
                flexGrow = 1,
                flexShrink = 1,
                flexBasis = 0,
                children = {
                    scrollContent,
                },
            },
        },
    }

    container:AddChild(panel)

    function screen.Destroy()
        -- 静态页面，无需清理事件
    end

    return screen
end

return CodexScreen
