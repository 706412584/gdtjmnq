-- ============================================================================
-- ResultScreen_结算界面 - 手写响应式布局
-- Project Smith
--
-- 目标：修复导出稿绝对定位导致的文本溢出、横线穿字、评分条截断、底栏遮挡。
-- ============================================================================
---@diagnostic disable: param-type-mismatch

local UI = require("urhox-libs/UI")

local M = {}

M.Actions = {}

local C = {
    paper = "#E7D8BC",
    header = "#1F1A17",
    ink = "#1F1A17",
    textDark = "#3A322B",
    textMuted = "#6C5A43",
    gold = "#C9A45A",
    goldDim = "rgba(201,164,90,0.35)",
    panel = "rgba(255,255,255,0.54)",
    darkPanel = "rgba(15,12,10,0.86)",
    rewardPanel = "rgba(31,26,23,0.88)",
    green = "#4F7A63",
    orange = "#C96A2B",
}

local function Label(props)
    props.fontColor = props.fontColor or C.textDark
    props.lineHeight = props.lineHeight or 1.12
    return UI.Label(props)
end

local function FramePanel(props)
    props.borderRadius = props.borderRadius or 6
    props.borderWidth = props.borderWidth or 1
    props.borderColor = props.borderColor or C.gold
    props.backgroundColor = props.backgroundColor or C.panel
    props.overflow = props.overflow or "hidden"
    return UI.Panel(props)
end

local function ThinLine(props)
    props = props or {}
    props.height = props.height or 1
    props.backgroundColor = props.backgroundColor or C.goldDim
    return UI.Panel(props)
end

local function ScoreRow(rowId, nameId, barFillId, scoreId, defaultName, color)
    return UI.Panel {
        id = rowId,
        width = "100%",
        height = 34,
        flexDirection = "row",
        alignItems = "center",
        gap = 12,
        children = {
            Label {
                id = nameId,
                text = defaultName,
                width = 130,
                height = "100%",
                fontSize = 20,
                fontWeight = 700,
                fontColor = C.textDark,
                verticalAlign = "middle",
            },
            UI.Panel {
                flexGrow = 1,
                flexShrink = 1,
                height = 20,
                borderRadius = 10,
                borderWidth = 1,
                borderColor = "rgba(58,50,43,0.35)",
                backgroundColor = "rgba(31,26,23,0.48)",
                overflow = "hidden",
                children = {
                    UI.Panel {
                        id = barFillId,
                        width = "0%",
                        height = "100%",
                        backgroundColor = color,
                        borderRadius = 9,
                    },
                },
            },
            Label {
                id = scoreId,
                text = "0 / 100",
                width = 104,
                height = "100%",
                fontSize = 20,
                fontWeight = 700,
                fontColor = color,
                textAlign = "right",
                verticalAlign = "middle",
            },
        },
    }
end

local function Button(id, bgId, textId, text, fillColor, textColor)
    return UI.Panel {
        id = id,
        flexGrow = 1,
        flexShrink = 1,
        height = 58,
        backgroundColor = "#00000000",
        children = {
            UI.Panel {
                id = bgId,
                position = "absolute",
                left = 0,
                right = 0,
                top = 0,
                bottom = 0,
                backgroundColor = fillColor,
                borderRadius = 6,
                borderWidth = 2,
                borderColor = C.gold,
            },
            Label {
                id = textId,
                text = text,
                position = "absolute",
                left = 0,
                right = 0,
                top = 0,
                bottom = 0,
                fontSize = 24,
                fontWeight = 700,
                fontColor = textColor or "#F1E5CC",
                textAlign = "center",
                verticalAlign = "middle",
            },
        },
    }
end

local function RewardCard(id, iconId, labelId, valueId, icon, label, value)
    return FramePanel {
        id = id,
        flexGrow = 1,
        flexShrink = 1,
        height = 58,
        backgroundColor = "rgba(247,232,200,0.06)",
        borderColor = "rgba(201,164,90,0.45)",
        paddingHorizontal = 12,
        flexDirection = "row",
        alignItems = "center",
        gap = 12,
        children = {
            UI.Panel {
                id = iconId,
                width = 28,
                height = 28,
                flexShrink = 0,
                borderRadius = 14,
                backgroundImage = icon,
                backgroundFit = "contain",
            },
            UI.Panel {
                flexGrow = 1,
                flexShrink = 1,
                flexDirection = "column",
                justifyContent = "center",
                children = {
                    Label {
                        id = labelId,
                        text = label,
                        fontSize = 15,
                        fontColor = "rgba(247,232,200,0.72)",
                        width = "100%",
                    },
                    Label {
                        id = valueId,
                        text = value,
                        fontSize = 24,
                        fontWeight = 700,
                        fontColor = C.gold,
                        width = "100%",
                    },
                },
            },
        },
    }
end

function M.Build(payload)
    payload = payload or {}

    return UI.Panel {
        id = "root",
        width = "100%",
        height = "100%",
        flexDirection = "column",
        backgroundColor = C.paper,
        children = {
            -- 顶部标题栏
            UI.Panel {
                id = "header",
                width = "100%",
                height = 76,
                flexDirection = "row",
                alignItems = "center",
                paddingHorizontal = 34,
                gap = 24,
                backgroundColor = C.header,
                children = {
                    Label {
                        id = "tx_2",
                        text = "作 品 · 完 成",
                        width = 520,
                        fontSize = 42,
                        fontWeight = 700,
                        fontColor = C.gold,
                    },
                    ThinLine {
                        id = "sl_3",
                        flexGrow = 1,
                        flexShrink = 1,
                        height = 2,
                        backgroundColor = "rgba(201,164,90,0.28)",
                    },
                },
            },

            -- 主内容区
            UI.Panel {
                id = "main_body",
                width = "100%",
                flexGrow = 1,
                flexShrink = 1,
                flexDirection = "row",
                padding = 22,
                gap = 22,
                children = {
                    -- 左侧武器卡
                    FramePanel {
                        id = "df_4",
                        width = "27%",
                        height = "100%",
                        backgroundColor = C.darkPanel,
                        borderWidth = 2,
                        padding = 18,
                        flexDirection = "column",
                        children = {
                            FramePanel {
                                id = "ph_a",
                                width = "100%",
                                flexGrow = 1,
                                flexShrink = 1,
                                backgroundColor = "rgba(201,164,90,0.12)",
                                borderColor = C.gold,
                                children = {
                                    UI.Panel {
                                        id = "ph_l1_c",
                                        position = "absolute",
                                        left = 0,
                                        right = 0,
                                        top = 0,
                                        bottom = 0,
                                        backgroundColor = "#3D3522",
                                    },
                                    UI.Panel {
                                        id = "ph_l2_d",
                                        position = "absolute",
                                        left = 0,
                                        right = 0,
                                        top = 0,
                                        bottom = 0,
                                        backgroundImage = "image/weapon_001_hunter_knife.png",
                                        backgroundFit = "contain",
                                    },
                                },
                            },
                            UI.Panel {
                                width = "100%",
                                height = 96,
                                flexShrink = 0,
                                paddingTop = 12,
                                flexDirection = "column",
                                justifyContent = "center",
                                children = {
                                    Label {
                                        id = "tx_f",
                                        text = "委托兵器",
                                        width = "100%",
                                        fontSize = 30,
                                        fontWeight = 700,
                                        fontColor = "#F1E5CC",
                                        textAlign = "center",
                                    },
                                    Label {
                                        id = "tx_g",
                                        text = "· 良品 ·",
                                        width = "100%",
                                        fontSize = 22,
                                        fontColor = C.green,
                                        textAlign = "center",
                                        marginTop = 4,
                                    },
                                },
                            },
                        },
                    },

                    -- 右侧信息区
                    UI.Panel {
                        id = "right_area",
                        flexGrow = 1,
                        flexShrink = 1,
                        height = "100%",
                        flexDirection = "column",
                        gap = 12,
                        children = {
                            -- 评分面板
                            FramePanel {
                                id = "df_h",
                                width = "100%",
                                flexGrow = 1,
                                flexShrink = 1,
                                backgroundColor = C.panel,
                                borderColor = C.textDark,
                                padding = 18,
                                flexDirection = "column",
                                children = {
                                    UI.Panel {
                                        width = "100%",
                                        height = 40,
                                        flexDirection = "row",
                                        alignItems = "center",
                                        gap = 16,
                                        children = {
                                            Label {
                                                id = "tx_n",
                                                text = "名匠评议",
                                                width = 148,
                                                fontSize = 26,
                                                fontWeight = 700,
                                                fontColor = C.ink,
                                            },
                                            ThinLine {
                                                id = "sl_o",
                                                flexGrow = 1,
                                                flexShrink = 1,
                                                height = 2,
                                                backgroundColor = "rgba(58,50,43,0.45)",
                                            },
                                        },
                                    },
                                    UI.Panel {
                                        width = "100%",
                                        flexGrow = 1,
                                        flexShrink = 1,
                                        flexDirection = "column",
                                        justifyContent = "center",
                                        gap = 9,
                                        paddingVertical = 4,
                                        children = {
                                            ScoreRow("row_p", "tx_q", "sr_t", "tx_u", "选矿去杂", C.green),
                                            ScoreRow("row_v", "tx_w", "sr_z", "tx_10", "控火熔炼", C.orange),
                                            ScoreRow("row_11", "tx_12", "sr_15", "tx_16", "锻打塑形", C.gold),
                                            ScoreRow("row_17", "tx_18", "sr_1b", "tx_1c", "研磨开刃", C.textDark),
                                        },
                                    },
                                    ThinLine {
                                        id = "sl_1d",
                                        width = "100%",
                                        height = 2,
                                        backgroundColor = "rgba(58,50,43,0.45)",
                                        marginBottom = 10,
                                    },
                                    UI.Panel {
                                        width = "100%",
                                        height = 58,
                                        flexDirection = "row",
                                        alignItems = "center",
                                        gap = 16,
                                        children = {
                                            Label {
                                                id = "tx_1e",
                                                text = "总评级",
                                                width = 136,
                                                fontSize = 25,
                                                fontWeight = 700,
                                                fontColor = C.ink,
                                            },
                                            Label {
                                                id = "tx_1g",
                                                text = "良品 · 156 分",
                                                flexGrow = 1,
                                                flexShrink = 1,
                                                fontSize = 31,
                                                fontWeight = 700,
                                                fontColor = C.textDark,
                                                textAlign = "center",
                                            },
                                            UI.Panel {
                                                id = "sr_1f",
                                                width = 220,
                                                height = 48,
                                                flexShrink = 0,
                                                backgroundColor = C.green,
                                                borderRadius = 22,
                                                borderColor = C.gold,
                                                borderWidth = 2,
                                            },
                                        },
                                    },
                                },
                            },

                            -- 评语面板
                            FramePanel {
                                id = "df_1h",
                                width = "100%",
                                height = 104,
                                flexShrink = 0,
                                backgroundColor = "rgba(79,122,99,0.12)",
                                borderColor = C.green,
                                paddingHorizontal = 18,
                                paddingVertical = 12,
                                flexDirection = "column",
                                children = {
                                    Label {
                                        id = "tx_1n",
                                        text = "委托人 · 评语",
                                        width = "100%",
                                        fontSize = 20,
                                        fontWeight = 700,
                                        fontColor = C.green,
                                    },
                                    Label {
                                        id = "tx_1o",
                                        text = "\"不错的作品。\"",
                                        width = "100%",
                                        flexGrow = 1,
                                        flexShrink = 1,
                                        fontSize = 20,
                                        fontColor = C.textDark,
                                        marginTop = 6,
                                    },
                                },
                            },

                            -- 操作按钮
                            UI.Panel {
                                id = "button_row",
                                width = "100%",
                                height = 62,
                                flexShrink = 0,
                                flexDirection = "row",
                                gap = 18,
                                children = {
                                    Button("plate_1p", "plate_bg_1q", "plate_t_1r", "交付订单", C.green, "#F1E5CC"),
                                    Button("plate_1s", "plate_bg_1t", "plate_t_1u", "广告 · 双倍奖励", C.orange, "#F1E5CC"),
                                    Button("plate_1v", "plate_bg_1w", "plate_t_1x", "入名器图鉴", "rgba(231,216,188,0.18)", C.gold),
                                },
                            },
                        },
                    },
                },
            },

            -- 底部收益栏
            FramePanel {
                id = "sr_1y",
                width = "100%",
                height = 88,
                flexShrink = 0,
                backgroundColor = C.rewardPanel,
                borderColor = C.gold,
                borderRadius = 0,
                borderWidth = 0,
                borderTopWidth = 2,
                paddingHorizontal = 32,
                paddingVertical = 10,
                flexDirection = "row",
                alignItems = "center",
                gap = 16,
                children = {
                    Label {
                        id = "tx_1z",
                        text = "本单收益预览",
                        width = 188,
                        fontSize = 21,
                        fontWeight = 700,
                        fontColor = C.gold,
                    },
                    RewardCard("rew_20", "ri_22", "tx_23", "tx_24", "image/icon_coins.png", "铜钱", "+38"),
                    RewardCard("rew_25", "ri_27", "tx_28", "tx_29", "image/icon_fame.png", "声望", "+12"),
                    RewardCard("rew_2a", "ri_2c", "tx_2d", "tx_2e", "image/icon_skill.png", "熟练度", "+5"),
                    RewardCard("rew_2f", "ri_2h", "tx_2i", "tx_2j", "image/icon_story.png", "额外材料", "× 1"),
                },
            },
        },
    }
end

return M
