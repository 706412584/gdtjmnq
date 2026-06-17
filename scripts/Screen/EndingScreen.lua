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
local ScreenRouter    = require("Utils.ScreenRouter")
local SFXManager      = require("Utils.SFXManager")

local EndingScreen = {}

-- 结局主题色（与各路线呼应）
local ENDING_COLORS = {
    craftsman_way  = "#C9A45A",  -- 鎏金（匠道）
    imperial_smith = "#E94560",  -- 炉火红（朝廷）
    jianghu_forge  = "#4ECDC4",  -- 青铜绿（江湖）
    guild_foundry  = "#D4A574",  -- 暖金（商会）
    broken_forge   = "#A0937D",  -- 烟灰（失败）
}

---@param container table UI 容器
---@param params table|nil
---@return table screen
function EndingScreen.Create(container, params)
    local screen = {}

    -- 评估当前数据，得到结局
    local result = EndingEvaluator.Evaluate()
    local accent = ENDING_COLORS[result.endingId] or "#C9A45A"

    -- 决定性数值（从 details 中挑出已通过的条目展示）
    local statChildren = {}
    if result.details then
        for i = 1, #result.details do
            local d = result.details[i]
            statChildren[#statChildren + 1] = UI.Label {
                text = (d.pass and "● " or "○ ") .. d.label .. "  (" .. tostring(d.value) .. ")",
                fontSize = 15,
                fontColor = d.pass and "#E8E0D0" or "#A0937D",
                marginBottom = 6,
            }
        end
    end

    local backBtn = UI.Button {
        text = "回到工坊",
        variant = "primary",
        width = 220,
        height = 56,
        onClick = function()
            SFXManager.Play(SFXManager.SFX.UI_TAP, 0.4)
            ScreenRouter.GoTo((params and params.returnTo) or "home")
        end,
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
                fontSize = 16,
                fontColor = "#A0937D",
                marginBottom = 18,
            },
            -- 结局名称
            UI.Label {
                text = result.endingName,
                fontSize = 40,
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
                fontSize = 18,
                fontColor = "#E8E0D0",
                lineHeight = 1.7,
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
                borderColor = "#3A322B",
                borderWidth = 1,
                marginBottom = 36,
                children = (function()
                    local list = {
                        UI.Label {
                            text = "结局缘由",
                            fontSize = 14,
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
            backBtn,
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
