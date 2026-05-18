-- ============================================================================
-- ResultScreen - 结算界面
-- Project Smith / P1-D4
--
-- 展示锻造结果:
--   - 武器名称 + 品质等级
--   - 最终分数
--   - 各步骤评分明细
--   - 获得奖励（铜钱、声望、材料）
--   - 首次锻造标记
--   - 返回工坊按钮
-- ============================================================================

local UI = require("urhox-libs/UI")
local ScreenRouter = require("Utils.ScreenRouter")
local SFXManager = require("Utils.SFXManager")

local ResultScreen = {}

-- ============================================================================
-- UI 素材路径（武侠水墨风）
-- ============================================================================

local UI_ASSETS = {
    panel_card       = "image/ui/panel_card.png",
    panel_card_green = "image/ui/panel_card_green.png",
    panel_header2    = "image/ui/panel_header2.png",
    btn_gold         = "image/ui/btn_gold.png",
    frame_item_lg    = "image/ui/frame_item_lg.png",
}

-- ============================================================================
-- 资源路径
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

local ICONS = {
    coins = "image/icon_coins.png",
    fame  = "image/icon_fame.png",
}

-- ============================================================================
-- 色板
-- ============================================================================

local C = {
    bgPrimary     = { 26,  26,  46,  255 },
    bgSecondary   = { 22,  33,  62,  255 },
    bgCard        = { 30,  40,  68,  255 },
    gold          = { 212, 165, 116, 255 },
    textPrimary   = { 232, 224, 208, 255 },
    textSecondary = { 160, 147, 125, 255 },
    accent        = { 233, 69,  96,  255 },
    success       = { 78,  205, 196, 255 },
    warning       = { 255, 217, 61,  255 },
}

-- 品质颜色映射
local TIER_COLORS = {
    [0] = { 128, 128, 128, 255 },  -- 凡品 - 灰
    [1] = { 160, 200, 160, 255 },  -- 良品 - 浅绿
    [2] = { 100, 180, 220, 255 },  -- 上品 - 蓝
    [3] = { 180, 120, 220, 255 },  -- 珍品 - 紫
    [4] = { 255, 200, 60,  255 },  -- 名器 - 金
    [5] = { 255, 100, 100, 255 },  -- 传世 - 红金
}

-- 步骤名称映射
local STEP_NAMES = {
    ore_select = "选矿去杂",
    forging    = "锻打塑形",
    polishing  = "研磨开刃",
    smelting   = "控火熔炼",
    quenching  = "淬火时机",
    assembly   = "组装装饰",
}

-- ============================================================================
-- Screen 接口
-- ============================================================================

--- 创建结算界面
---@param container table UI 容器
---@param params table { result }
---@return table screen
function ResultScreen.Create(container, params)
    local screen = {}

    local result = params and params.result
    if not result then
        -- 无结算数据
        container:AddChild(UI.Panel {
            width = "100%", height = "100%",
            justifyContent = "center", alignItems = "center",
            children = {
                UI.Label { text = "结算数据异常", fontSize = 16, fontColor = C.accent },
                UI.Button {
                    text = "返回工坊",
                    onClick = function() ScreenRouter.GoTo("home") end,
                },
            },
        })
        return screen
    end

    -- ----------------------------------------------------------------
    -- 解析数据
    -- ----------------------------------------------------------------

    local tierInfo  = result.qualityTier or { name = "?", tier = 0 }
    local tierColor = TIER_COLORS[tierInfo.tier] or C.textPrimary
    local finalScore = result.finalScore or 0

    -- ----------------------------------------------------------------
    -- UI 构建
    -- ----------------------------------------------------------------

    -- 武器图片
    local weaponImgPath = result.weaponId and WEAPON_IMAGES[result.weaponId] or nil

    -- 武器名 + 品质大标题
    local titleChildren = {}

    -- 武器成品图（带武侠风边框）
    if weaponImgPath then
        titleChildren[#titleChildren + 1] = UI.Panel {
            width = 140, height = 140,
            backgroundImage = UI_ASSETS.frame_item_lg,
            backgroundFit = "cover",
            justifyContent = "center",
            alignItems = "center",
            marginBottom = 4,
            children = {
                UI.Panel {
                    width = 100, height = 100,
                    backgroundImage = weaponImgPath,
                    backgroundFit = "contain",
                },
            },
        }
    end

    titleChildren[#titleChildren + 1] = UI.Label {
        text = result.weaponName or "未知武器",
        fontSize = 22,
        fontColor = C.gold,
    }
    titleChildren[#titleChildren + 1] = UI.Label {
        text = "[ " .. tierInfo.name .. " ]",
        fontSize = 28,
        fontColor = tierColor,
    }
    titleChildren[#titleChildren + 1] = UI.Label {
        text = "评分: " .. tostring(math.floor(finalScore + 0.5)),
        fontSize = 16,
        fontColor = C.textSecondary,
    }

    local titleSection = UI.Panel {
        width = "100%",
        alignItems = "center",
        gap = 4,
        paddingTop = 24,
        paddingBottom = 12,
        children = titleChildren,
    }

    -- 首次锻造标记
    local firstForgeLabel = nil
    if result.isFirstForge then
        firstForgeLabel = UI.Panel {
            width = "90%",
            paddingVertical = 8,
            borderRadius = 6,
            backgroundImage = UI_ASSETS.panel_header2,
            backgroundFit = "cover",
            alignItems = "center",
            children = {
                UI.Label {
                    text = "[首次锻造] 已收录至名器图鉴",
                    fontSize = 12,
                    fontColor = C.warning,
                },
            },
        }
    end

    -- 步骤评分明细
    local stepChildren = {}
    local stepScores = result.stepScores or {}
    for i = 1, #stepScores do
        local s = stepScores[i]
        local stepName = STEP_NAMES[s.stepType] or s.stepType or ("步骤 " .. i)
        local ratingColor = C.textPrimary
        if s.rating == "Perfect" then
            ratingColor = C.warning
        elseif s.rating == "Great" then
            ratingColor = C.success
        elseif s.rating == "Poor" then
            ratingColor = C.accent
        end

        stepChildren[#stepChildren + 1] = UI.Panel {
            width = "100%",
            flexDirection = "row",
            justifyContent = "space-between",
            paddingHorizontal = 12,
            paddingVertical = 4,
            children = {
                UI.Label {
                    text = stepName,
                    fontSize = 13,
                    fontColor = C.textSecondary,
                },
                UI.Label {
                    text = s.rating .. " (" .. string.format("%.0f", (s.score or 0) * 100) .. ")",
                    fontSize = 13,
                    fontColor = ratingColor,
                },
            },
        }
    end

    local stepsCard = UI.Panel {
        width = "90%",
        backgroundImage = UI_ASSETS.panel_card,
        backgroundFit = "cover",
        borderRadius = 8,
        paddingVertical = 8,
        gap = 2,
        children = {
            UI.Label {
                text = "工序评价",
                fontSize = 14,
                fontColor = C.gold,
                paddingHorizontal = 12,
                paddingBottom = 4,
            },
            table.unpack(stepChildren),
        },
    }

    -- 奖励卡片
    local rewardItems = {
        UI.Label {
            text = "获得奖励",
            fontSize = 14,
            fontColor = C.gold,
            paddingHorizontal = 12,
            paddingBottom = 4,
        },
    }

    -- 铜钱
    rewardItems[#rewardItems + 1] = UI.Panel {
        width = "100%",
        flexDirection = "row",
        justifyContent = "space-between",
        alignItems = "center",
        paddingHorizontal = 12,
        paddingVertical = 3,
        children = {
            UI.Panel {
                flexDirection = "row", alignItems = "center", gap = 4,
                children = {
                    UI.Panel {
                        width = 16, height = 16,
                        backgroundImage = ICONS.coins,
                        backgroundFit = "contain",
                    },
                    UI.Label { text = "铜钱", fontSize = 13, fontColor = C.textSecondary },
                },
            },
            UI.Label {
                text = "+" .. tostring(result.rewardCoins or 0),
                fontSize = 13,
                fontColor = C.warning,
            },
        },
    }

    -- 声望
    rewardItems[#rewardItems + 1] = UI.Panel {
        width = "100%",
        flexDirection = "row",
        justifyContent = "space-between",
        alignItems = "center",
        paddingHorizontal = 12,
        paddingVertical = 3,
        children = {
            UI.Panel {
                flexDirection = "row", alignItems = "center", gap = 4,
                children = {
                    UI.Panel {
                        width = 16, height = 16,
                        backgroundImage = ICONS.fame,
                        backgroundFit = "contain",
                    },
                    UI.Label { text = "声望", fontSize = 13, fontColor = C.textSecondary },
                },
            },
            UI.Label {
                text = "+" .. tostring(result.rewardFame or 0),
                fontSize = 13,
                fontColor = C.success,
            },
        },
    }

    -- 额外材料
    local bonusMats = result.bonusMaterials or {}
    for mat, count in pairs(bonusMats) do
        rewardItems[#rewardItems + 1] = UI.Panel {
            width = "100%",
            flexDirection = "row",
            justifyContent = "space-between",
            paddingHorizontal = 12,
            paddingVertical = 3,
            children = {
                UI.Label { text = mat, fontSize = 13, fontColor = C.textSecondary },
                UI.Label {
                    text = "+" .. tostring(count),
                    fontSize = 13,
                    fontColor = C.gold,
                },
            },
        }
    end

    local rewardCard = UI.Panel {
        width = "90%",
        backgroundImage = UI_ASSETS.panel_card_green,
        backgroundFit = "cover",
        borderRadius = 8,
        paddingVertical = 8,
        gap = 2,
        children = rewardItems,
    }

    -- 返回按钮
    local backButton = UI.Button {
        text = "返回工坊",
        width = "80%",
        height = 52,
        fontSize = 18,
        backgroundImage = UI_ASSETS.btn_gold,
        backgroundFit = "cover",
        fontColor = C.bgPrimary,
        borderRadius = 10,
        onClick = function()
            ScreenRouter.GoTo("home")
        end,
    }

    -- 组装主面板
    local scrollContent = {
        titleSection,
    }
    if firstForgeLabel then
        scrollContent[#scrollContent + 1] = firstForgeLabel
    end
    scrollContent[#scrollContent + 1] = stepsCard
    scrollContent[#scrollContent + 1] = rewardCard
    scrollContent[#scrollContent + 1] = UI.Panel { height = 16 }  -- 间距
    scrollContent[#scrollContent + 1] = backButton
    scrollContent[#scrollContent + 1] = UI.Panel { height = 24 }  -- 底部空间

    local scrollView = UI.ScrollView {
        width = "100%",
        flexGrow = 1,
        flexBasis = 0,
        flexShrink = 1,
        children = {
            UI.Panel {
                width = "100%",
                flexDirection = "column",
                alignItems = "center",
                gap = 10,
                children = scrollContent,
            },
        },
    }

    local mainPanel = UI.Panel {
        width = "100%",
        height = "100%",
        flexDirection = "column",
        children = {
            scrollView,
        },
    }

    container:AddChild(mainPanel)

    -- 停止所有循环音效（防止小游戏残留），然后播放完成音效
    SFXManager.StopAllLoops()
    SFXManager.Play(SFXManager.SFX.FORGE_COMPLETE, 0.8)

    -- 品质达到珍品(3)及以上播放品质提升音效
    if tierInfo.tier >= 3 then
        SFXManager.Play(SFXManager.SFX.QUALITY_UP, 0.5)
    end

    -- 首次锻造播放成功音效
    if result.isFirstForge then
        SFXManager.Play(SFXManager.SFX.UI_SUCCESS, 0.4)
    end

    print("[ResultScreen] Displayed: " .. (result.weaponName or "?")
        .. " | " .. tierInfo.name
        .. " | Score=" .. tostring(math.floor(finalScore + 0.5)))

    return screen
end

return ResultScreen
