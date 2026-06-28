---@diagnostic disable: param-type-mismatch
-- ============================================================================
-- EndingScreen - 结局展示界面
-- Project Smith
--
-- 第五章终章完成后展示：根据 EndingEvaluator 评估结果显示对应结局的
-- 名称、尾声文本、决定性数值，并提供"回到工坊"。
-- 竖屏 9:16，暖色调。
-- ============================================================================

local UI              = require("urhox-libs/UI")
local EndingEvaluator = require("Story.EndingEvaluator")
local GameState       = require("Core.GameState")
local ScreenRouter    = require("Utils.ScreenRouter")
local SFXManager      = require("Utils.SFXManager")

local EndingScreen = {}

-- 结局主题色（与各路线呼应）
local ENDING_COLORS = {
    craftsman_way  = "#FFD93D",  -- 像素黄（匠道）
    imperial_smith = "#E94560",  -- 像素红（朝廷）
    jianghu_forge  = "#D4A574",  -- 像素青（江湖）
    guild_foundry  = "#6C5CE7",  -- 像素紫（商会）
    folk_forge     = "#E8E0D0",  -- 像素白（市井平凡）
    broken_forge   = "#505070",  -- 像素灰（失败）
}

---@param container table UI 容器
---@param params table|nil
---@return table screen
function EndingScreen.Create(container, params)
    local screen = {}

    -- 评估当前数据，得到结局
    local result = EndingEvaluator.Evaluate()
    local accent = ENDING_COLORS[result.endingId] or "#D4A574"

    -- 持久化记录：本次达成的结局写入存档，供图鉴「结局回顾」展示
    GameState.MarkEndingAchieved(result.endingId)

    -- 决定性数值（从 details 中挑出已通过的条目展示）
    local statChildren = {}
    if result.details then
        for i = 1, #result.details do
            local d = result.details[i]
            statChildren[#statChildren + 1] = UI.Label {
                text = (d.pass and "● " or "○ ") .. d.label .. "  (" .. tostring(d.value) .. ")",
                fontSize = 20,
                fontColor = d.pass and "#E8E0D0" or "#A0A0C0",
                marginBottom = 6,
            }
        end
    end

    local backBtn = UI.Button {
        text = "回到工坊",
        variant = "primary",
        width = 200,
        height = 56,
        onClick = function()
            SFXManager.Play(SFXManager.SFX.UI_TAP, 0.4)
            ScreenRouter.GoTo((params and params.returnTo) or "home")
        end,
    }

    local codexBtn = UI.Button {
        text = "结局图鉴",
        variant = "secondary",
        width = 160,
        height = 56,
        onClick = function()
            SFXManager.Play(SFXManager.SFX.UI_TAP, 0.4)
            ScreenRouter.GoTo("codex")
        end,
    }

    local btnRow = UI.Panel {
        flexDirection = "row",
        alignItems = "center",
        justifyContent = "center",
        children = {
            codexBtn,
            UI.Panel { width = 16, height = 1 },
            backBtn,
        },
    }

    local root = UI.Panel {
        width = "100%", height = "100%",
        flexDirection = "column",
        alignItems = "center",
        justifyContent = "center",
        backgroundColor = "#1A1613",
        paddingLeft = 40, paddingRight = 40,
        children = {
            -- 顶部小标
            UI.Label {
                text = "— 终 章 —",
                fontSize = 21,
                fontColor = "#A0A0C0",
                marginBottom = 18,
            },
            -- 结局名称
            UI.Label {
                text = result.endingName,
                fontSize = 52,
                fontWeight = 700,
                fontColor = accent,
                marginBottom = 8,
            },
            -- 分隔线
            UI.Panel {
                width = 120, height = 2,
                backgroundColor = accent,
                marginBottom = 24,
            },
            -- 尾声文本
            UI.Label {
                text = result.epilogue or "",
                fontSize = 23,
                fontColor = "#E8E0D0",
                lineHeight = 1.2,
                textAlign = "center",
                width = "100%",
                marginBottom = 32,
            },
            -- 决定性数值面板
            UI.Panel {
                width = "100%",
                flexDirection = "column",
                alignItems = "flex-start",
                paddingLeft = 24, paddingRight = 24,
                paddingTop = 18, paddingBottom = 18,
                borderRadius = 12,
                backgroundColor = "rgba(38,31,26,0.9)",
                borderColor = "#3D2B1F",
                borderWidth = 1,
                marginBottom = 36,
                children = (function()
                    local list = {
                        UI.Label {
                            text = "结局缘由",
                            fontSize = 18,
                            fontColor = accent,
                            marginBottom = 10,
                        },
                    }
                    for i = 1, #statChildren do
                        list[#list + 1] = statChildren[i]
                    end
                    return list
                end)(),
            },
            btnRow,
        },
    }
    container:AddChild(root)

    -- 音效：结局揭示
    SFXManager.StopAllLoops()
    if result.endingId == "broken_forge" then
        SFXManager.Play(SFXManager.SFX.UI_FAIL, 0.5)
    else
        SFXManager.Play(SFXManager.SFX.QUALITY_UP, 0.6)
    end

    print("[EndingScreen] Ending = " .. result.endingId .. " (" .. result.endingName .. ")")

    function screen.Destroy() end

    return screen
end

return EndingScreen
