-- ============================================================================
-- ForgeScreen_锻造界面 - 手写响应式布局
-- Project Smith
--
-- 目标：去掉布局编辑器导出的零散绝对定位稿，改为清晰的三层结构：
--   1. 顶部：返回、标题、步骤进度
--   2. 中部：工坊背景 + 中央小游戏工作台 + 订单/客户对话
--   3. 底部：品质评分与容错状态
-- ============================================================================
---@diagnostic disable: param-type-mismatch

local UI = require("urhox-libs/UI")

local M = {}

M.Actions = {}

local C = {
    bg = "#12100E",
    panel = "rgba(15,12,10,0.78)",
    panelSoft = "rgba(15,12,10,0.58)",
    panelInk = "rgba(24,20,18,0.72)",
    border = "#8A6A3F",
    borderDim = "#4D3928",
    gold = "#D4A574",
    goldSoft = "rgba(212,165,116,0.24)",
    text = "#E8E0D0",
    textDim = "#A0937D",
    success = "#4ECDC4",
    warning = "#FFD93D",
    error = "#E94560",
    fire = "#C96A2B",
}

local function Label(props)
    props.fontColor = props.fontColor or C.text
    props.lineHeight = props.lineHeight or 1.15
    return UI.Label(props)
end

local function FineLine(props)
    props = props or {}
    props.height = props.height or 1
    props.backgroundColor = props.backgroundColor or "rgba(212,165,116,0.45)"
    return UI.Panel(props)
end

local function Dot(id, text)
    return UI.Panel {
        id = id,
        width = 28,
        height = 28,
        borderRadius = 14,
        backgroundColor = "#5a4a3a",
        borderWidth = 1,
        borderColor = "rgba(212,165,116,0.45)",
        justifyContent = "center",
        alignItems = "center",
        children = {
            Label {
                text = text,
                fontSize = 13,
                fontWeight = 700,
                fontColor = "#E8E0D0",
                textAlign = "center",
            },
        },
    }
end

local function FramePanel(props)
    props.backgroundColor = props.backgroundColor or C.panel
    props.borderWidth = props.borderWidth or 1
    props.borderColor = props.borderColor or C.border
    props.borderRadius = props.borderRadius or 8
    props.overflow = props.overflow or "hidden"
    return UI.Panel(props)
end

local function ProgressBar(fillId, textId, text)
    return UI.Panel {
        width = "100%",
        height = 28,
        backgroundColor = "rgba(31,26,23,0.70)",
        borderRadius = 14,
        borderWidth = 1,
        borderColor = C.borderDim,
        overflow = "hidden",
        children = {
            UI.Panel {
                id = fillId,
                position = "absolute",
                left = 3,
                top = 3,
                bottom = 3,
                width = "0%",
                backgroundColor = C.gold,
                borderRadius = 11,
            },
            Label {
                id = textId,
                text = text,
                position = "absolute",
                left = 0,
                top = 0,
                width = "100%",
                height = "100%",
                fontSize = 16,
                fontWeight = 700,
                textAlign = "center",
                verticalAlign = "middle",
                fontColor = C.text,
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
        backgroundColor = C.bg,
        children = {
            -- 顶部标题栏
            UI.Panel {
                id = "top_bar",
                width = "100%",
                height = 82,
                flexDirection = "row",
                alignItems = "center",
                paddingHorizontal = 18,
                gap = 18,
                backgroundColor = "rgba(15,12,10,0.96)",
                borderBottomWidth = 2,
                borderColor = C.gold,
                children = {
                    UI.Panel {
                        id = "plate_3",
                        width = 112,
                        height = 48,
                        borderRadius = 12,
                        borderWidth = 1,
                        borderColor = C.gold,
                        backgroundColor = "rgba(10,8,7,0.40)",
                        justifyContent = "center",
                        alignItems = "center",
                        children = {
                            Label {
                                id = "plate_t_5",
                                text = "< 返回",
                                fontSize = 22,
                                fontWeight = 700,
                                fontColor = C.gold,
                                textAlign = "center",
                            },
                        },
                    },
                    UI.Panel {
                        flexGrow = 1,
                        flexShrink = 1,
                        flexDirection = "column",
                        justifyContent = "center",
                        children = {
                            Label {
                                id = "tx_6",
                                text = "锻造 · 准备开炉",
                                fontSize = 30,
                                fontWeight = 700,
                                fontColor = C.gold,
                                width = "100%",
                            },
                            Label {
                                id = "step_hint_label",
                                text = "按委托工序完成锻造，品质会随每一步累积。",
                                fontSize = 14,
                                fontColor = C.textDim,
                                width = "100%",
                                marginTop = 2,
                            },
                        },
                    },
                    UI.Panel {
                        id = "stage_dots_wrap",
                        width = 260,
                        flexDirection = "row",
                        justifyContent = "flex-end",
                        alignItems = "center",
                        gap = 9,
                        children = {
                            Dot("stage_7", "1"),
                            Dot("stage_8", "2"),
                            Dot("stage_9", "3"),
                            Dot("stage_a", "4"),
                            Dot("stage_b", "5"),
                            Dot("stage_c", "6"),
                        },
                    },
                },
            },

            -- 工坊主体
            UI.Panel {
                id = "stage_outer",
                width = "100%",
                flexGrow = 1,
                flexShrink = 1,
                paddingHorizontal = 22,
                paddingTop = 12,
                paddingBottom = 10,
                children = {
                    FramePanel {
                        id = "stage_frame",
                        width = "100%",
                        height = "100%",
                        backgroundImage = "image/bg_forge_20260612201542.png",
                        backgroundFit = "cover",
                        backgroundColor = "#0f0c0a",
                        borderWidth = 2,
                        children = {
                            UI.Panel {
                                id = "stage_dim",
                                position = "absolute",
                                left = 0,
                                right = 0,
                                top = 0,
                                bottom = 0,
                                backgroundColor = "rgba(8,6,5,0.26)",
                            },

                            -- 中央小游戏工作台，只给小游戏占用，不再铺满整张背景
                            FramePanel {
                                id = "ph_i",
                                position = "absolute",
                                left = "16%",
                                right = "16%",
                                top = 72,
                                bottom = 178,
                                backgroundColor = "rgba(15,12,10,0.36)",
                                borderColor = "rgba(212,165,116,0.55)",
                                borderWidth = 1,
                                borderRadius = 10,
                            },

                            -- 左下订单信息
                            FramePanel {
                                id = "order_card",
                                position = "absolute",
                                left = 22,
                                bottom = 22,
                                width = "34%",
                                height = 138,
                                backgroundColor = C.panel,
                                padding = 14,
                                flexDirection = "row",
                                alignItems = "center",
                                gap = 14,
                                children = {
                                    UI.Panel {
                                        id = "ph_t",
                                        width = 86,
                                        height = 86,
                                        flexShrink = 0,
                                        borderRadius = 6,
                                        borderWidth = 1,
                                        borderColor = C.gold,
                                        backgroundColor = C.goldSoft,
                                        justifyContent = "center",
                                        alignItems = "center",
                                        children = {
                                            Label {
                                                id = "ph_t_x",
                                                text = "兵器",
                                                fontSize = 22,
                                                fontWeight = 700,
                                                fontColor = C.gold,
                                                textAlign = "center",
                                            },
                                        },
                                    },
                                    UI.Panel {
                                        flexGrow = 1,
                                        flexShrink = 1,
                                        flexDirection = "column",
                                        justifyContent = "center",
                                        children = {
                                            Label {
                                                id = "tx_y",
                                                text = "委托兵器",
                                                fontSize = 24,
                                                fontWeight = 700,
                                                fontColor = C.text,
                                                width = "100%",
                                            },
                                            Label {
                                                id = "tx_z",
                                                text = "材料 · 待确认",
                                                fontSize = 15,
                                                fontColor = C.textDim,
                                                width = "100%",
                                                marginTop = 5,
                                            },
                                            Label {
                                                id = "tx_10",
                                                text = "客户期望 · 良品",
                                                fontSize = 15,
                                                fontColor = C.success,
                                                width = "100%",
                                                marginTop = 3,
                                            },
                                            UI.Panel {
                                                width = "100%",
                                                marginTop = 7,
                                                children = {
                                                    ProgressBar("sr_13", "tx_14", "完成度 0%"),
                                                },
                                            },
                                        },
                                    },
                                },
                            },

                            -- 右下客户对话
                            FramePanel {
                                id = "dialogue_card",
                                position = "absolute",
                                right = 22,
                                bottom = 22,
                                width = "38%",
                                height = 138,
                                backgroundColor = "rgba(12,10,9,0.80)",
                                padding = 16,
                                flexDirection = "column",
                                children = {
                                    UI.Panel {
                                        width = "100%",
                                        flexDirection = "row",
                                        alignItems = "center",
                                        justifyContent = "space-between",
                                        children = {
                                            Label {
                                                id = "customer_name_label",
                                                text = "委托人",
                                                fontSize = 20,
                                                fontWeight = 700,
                                                fontColor = C.gold,
                                            },
                                            Label {
                                                id = "order_tier_label",
                                                text = "寻常委托",
                                                fontSize = 14,
                                                fontColor = C.textDim,
                                            },
                                        },
                                    },
                                    FineLine { width = "100%", marginTop = 9, marginBottom = 9 },
                                    Label {
                                        id = "customer_dialogue_label",
                                        text = "「请按委托要求完成锻造。」",
                                        width = "100%",
                                        flexGrow = 1,
                                        flexShrink = 1,
                                        fontSize = 17,
                                        fontColor = C.text,
                                    },
                                },
                            },
                        },
                    },
                },
            },

            -- 底部品质栏
            UI.Panel {
                id = "quality_bar",
                width = "100%",
                height = 96,
                flexDirection = "row",
                alignItems = "center",
                paddingHorizontal = 22,
                gap = 18,
                backgroundColor = "rgba(15,12,10,0.96)",
                borderTopWidth = 1,
                borderColor = C.borderDim,
                children = {
                    UI.Panel {
                        flexGrow = 1,
                        flexShrink = 1,
                        flexDirection = "column",
                        justifyContent = "center",
                        children = {
                            Label {
                                id = "tx_1n",
                                text = "品质 · 评估中",
                                fontSize = 20,
                                fontWeight = 700,
                                fontColor = C.gold,
                                marginBottom = 8,
                            },
                            ProgressBar("sr_1q", "tx_1r", "品质评分 0 / 100"),
                        },
                    },
                    FramePanel {
                        id = "error_panel",
                        width = 230,
                        height = 66,
                        backgroundColor = "rgba(20,14,14,0.72)",
                        borderColor = "rgba(233,69,96,0.45)",
                        paddingHorizontal = 14,
                        justifyContent = "center",
                        children = {
                            UI.Panel {
                                flexDirection = "row",
                                justifyContent = "center",
                                alignItems = "center",
                                gap = 12,
                                children = {
                                    UI.Panel { id = "heart_1s", width = 28, height = 22, borderRadius = 4, backgroundColor = "#8b3a3a" },
                                    UI.Panel { id = "heart_1t", width = 28, height = 22, borderRadius = 4, backgroundColor = "#8b3a3a" },
                                    UI.Panel { id = "heart_1u", width = 28, height = 22, borderRadius = 4, backgroundColor = "#8b3a3a" },
                                },
                            },
                            Label {
                                id = "tx_1v",
                                text = "失误容错 · 0/3",
                                fontSize = 15,
                                fontColor = C.error,
                                textAlign = "center",
                                width = "100%",
                                marginTop = 7,
                            },
                        },
                    },
                },
            },
        },
    }
end

return M
