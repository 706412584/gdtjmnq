---@diagnostic disable: param-type-mismatch
-- ============================================================================
-- RelationshipScreen - 人物关系 / 阵营倾向 展示界面
-- Project Smith
--
-- 展示玩家当前的阵营倾向（朝廷/商会/江湖/匠道）与关键人物好感度，
-- 让剧情抉择带来的关系变化对玩家可见。竖屏 9:16，暖色调。
-- 入口：主界面顶部"友"按钮。
-- ============================================================================

local UI                  = require("urhox-libs/UI")
local GameState           = require("Core.GameState")
local RelationshipTracker = require("Story.RelationshipTracker")
local ScreenRouter        = require("Utils.ScreenRouter")
local SFXManager          = require("Utils.SFXManager")

local RelationshipScreen = {}

-- 阵营展示顺序与主题色
local FACTION_ORDER = {
    { id = "court",     color = "#E94560" },  -- 朝廷 · 炉火红
    { id = "guild",     color = "#D4A574" },  -- 商会 · 暖金
    { id = "rivers",    color = "#4ECDC4" },  -- 江湖 · 青铜绿
    { id = "craftsman", color = "#C9A45A" },  -- 匠道 · 鎏金
}

-- 阵营条最大参考值（用于进度条归一化，匠道可达 ~99）
local FACTION_BAR_MAX = 100

---@param container table UI 容器
---@param params table|nil
---@return table screen
function RelationshipScreen.Create(container, params)
    local screen = {}

    -- ----------------------------------------------------------------
    -- 顶栏
    -- ----------------------------------------------------------------
    local backBtn = UI.Panel {
        width = 110, height = 56,
        borderRadius = 12,
        borderColor = "#C9A45A",
        borderWidth = 1.5,
        justifyContent = "center",
        alignItems = "center",
        onClick = function()
            SFXManager.Play(SFXManager.SFX.UI_TAP, 0.4)
            ScreenRouter.GoTo((params and params.returnTo) or "home")
        end,
        children = {
            UI.Label { text = "< 返回", fontSize = 18, fontColor = "#C9A45A", textAlign = "center" },
        },
    }
    local header = UI.Panel {
        width = "100%", height = 72,
        flexDirection = "row",
        alignItems = "center",
        paddingLeft = 24, paddingRight = 24,
        backgroundColor = "rgba(31,26,23,0.85)",
        children = {
            backBtn,
            UI.Label {
                text = "人物关系 · 江湖往来",
                fontSize = 24, fontWeight = 700,
                fontColor = "#E4B982",
                verticalAlign = "middle",
                marginLeft = 18,
                flexGrow = 1,
            },
        },
    }

    -- ----------------------------------------------------------------
    -- 阵营倾向条
    -- ----------------------------------------------------------------
    ---@param fid string
    ---@param color string
    ---@return table
    local function BuildFactionRow(fid, color)
        local val = RelationshipTracker.GetFaction(fid)
        local name = RelationshipTracker.GetFactionName(fid)
        local pct = math.max(0, math.min(100, val))  -- 负值显示为空条

        return UI.Panel {
            width = "100%",
            marginBottom = 14,
            flexDirection = "column",
            children = {
                UI.Panel {
                    width = "100%",
                    flexDirection = "row",
                    justifyContent = "space-between",
                    marginBottom = 6,
                    children = {
                        UI.Label { text = name, fontSize = 17, fontColor = "#E8E0D0" },
                        UI.Label { text = tostring(val), fontSize = 17, fontWeight = 700, fontColor = color },
                    },
                },
                -- 进度条轨道
                UI.Panel {
                    width = "100%", height = 12,
                    borderRadius = 6,
                    backgroundColor = "rgba(58,50,43,0.8)",
                    children = {
                        UI.Panel {
                            width = pct .. "%", height = "100%",
                            borderRadius = 6,
                            backgroundColor = color,
                        },
                    },
                },
            },
        }
    end

    local factionRows = {}
    for i = 1, #FACTION_ORDER do
        factionRows[i] = BuildFactionRow(FACTION_ORDER[i].id, FACTION_ORDER[i].color)
    end

    -- ----------------------------------------------------------------
    -- 人物好感条目
    -- ----------------------------------------------------------------
    ---@param npcId string
    ---@param name string
    ---@return table
    local function BuildCharacterRow(npcId, name)
        local favor = RelationshipTracker.GetFavor(npcId)
        local desc = RelationshipTracker.GetUnlockedDesc(npcId)
        -- 好感正绿负红
        local favorColor = favor > 0 and "#4ECDC4" or (favor < 0 and "#E94560" or "#A0937D")

        local rightChildren = {
            UI.Label {
                text = (favor >= 0 and "+" or "") .. tostring(favor),
                fontSize = 18, fontWeight = 700,
                fontColor = favorColor,
                verticalAlign = "middle",
            },
        }
        if desc then
            rightChildren[#rightChildren + 1] = UI.Label {
                text = "已解锁 · " .. desc,
                fontSize = 12,
                fontColor = "#C9A45A",
                marginTop = 2,
            }
        end

        return UI.Panel {
            width = "100%",
            marginBottom = 10,
            paddingLeft = 16, paddingRight = 16,
            paddingTop = 12, paddingBottom = 12,
            flexDirection = "row",
            alignItems = "center",
            justifyContent = "space-between",
            borderRadius = 10,
            backgroundColor = "rgba(247,232,200,0.06)",
            borderColor = "#3A322B",
            borderWidth = 1,
            children = {
                UI.Label { text = name, fontSize = 18, fontColor = "#E8E0D0", verticalAlign = "middle" },
                UI.Panel {
                    flexDirection = "column",
                    alignItems = "flex-end",
                    children = rightChildren,
                },
            },
        }
    end

    local charRows = {}
    local disp = RelationshipTracker.CHARACTER_DISPLAY
    for i = 1, #disp do
        charRows[i] = BuildCharacterRow(disp[i].npcId, disp[i].name)
    end

    -- 真相揭露度
    local truthVal = GameState.GetRelationship("truth")
    local truthRow = UI.Panel {
        width = "100%",
        marginTop = 6,
        paddingLeft = 16, paddingRight = 16,
        paddingTop = 12, paddingBottom = 12,
        flexDirection = "row",
        alignItems = "center",
        justifyContent = "space-between",
        borderRadius = 10,
        backgroundColor = "rgba(201,164,90,0.10)",
        borderColor = "#C9A45A",
        borderWidth = 1,
        children = {
            UI.Label { text = "真相揭露度", fontSize = 18, fontColor = "#E4B982", verticalAlign = "middle" },
            UI.Label { text = tostring(truthVal), fontSize = 18, fontWeight = 700, fontColor = "#E4B982", verticalAlign = "middle" },
        },
    }

    -- ----------------------------------------------------------------
    -- 组装滚动内容
    -- ----------------------------------------------------------------
    local function SectionTitle(text)
        return UI.Label {
            text = text,
            fontSize = 16, fontWeight = 700,
            fontColor = "#C9A45A",
            marginTop = 8, marginBottom = 14,
        }
    end

    local content = { SectionTitle("阵营倾向") }
    for i = 1, #factionRows do content[#content + 1] = factionRows[i] end
    content[#content + 1] = SectionTitle("人物好感")
    for i = 1, #charRows do content[#content + 1] = charRows[i] end
    content[#content + 1] = truthRow

    local scroll = UI.ScrollView {
        width = "100%",
        flexGrow = 1,
        flexBasis = 0,
        scrollY = true,
        paddingLeft = 24, paddingRight = 24, paddingTop = 18, paddingBottom = 24,
        children = {
            UI.Panel { width = "100%", flexDirection = "column", children = content },
        },
    }

    local root = UI.Panel {
        width = "100%", height = "100%",
        flexDirection = "column",
        backgroundColor = "#1F1A17",
        children = { header, scroll },
    }
    container:AddChild(root)

    print("[RelationshipScreen] Created")
    function screen.Destroy() end
    return screen
end

return RelationshipScreen
