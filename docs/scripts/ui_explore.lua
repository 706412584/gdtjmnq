-- ============================================================================
-- 《问道长生》遭遇与探索页 —— 战斗过程可视化
-- 状态机：idle -> encounter -> battle -> result -> idle
-- ============================================================================

local UI = require("urhox-libs/UI")
local Theme = require("ui_theme")
local Comp = require("ui_components")
local Router = require("ui_router")
local GamePlayer = require("game_player")
local GameExplore = require("game_explore")
local Toast = require("ui_toast")
local NVG = require("nvg_manager")

local M = {}

-- ============================================================================
-- 战斗状态机
-- ============================================================================
local PHASE_IDLE    = "idle"       -- 等待探索
local PHASE_BATTLE  = "battle"     -- 战斗回合播放中
local PHASE_RESULT  = "result"     -- 战斗结束，展示结果

local battleState_ = {
    phase      = PHASE_IDLE,
    encounter  = nil,         -- 当前遭遇
    monsterImg = nil,         -- 怪物图片路径
    rounds     = {},          -- 全部回合数据
    roundIdx   = 0,           -- 当前播放到第几回合
    win        = false,
    summary    = "",
    timer      = 0,           -- 回合播放计时器
    battleLog  = {},          -- 战斗日志文本
    settled    = false,       -- 是否已结算
    resultMsg  = "",          -- 结算消息
}

local ROUND_INTERVAL = 0.6   -- 每回合播放间隔（秒）
local battleUpdateKey_ = "explore_battle"  -- NVG 更新 key

-- ============================================================================
-- 战斗 Update（通过 NVG.Register 驱动回合播放）
-- ============================================================================
local function BattleUpdate(dt)
    local s = battleState_
    if s.phase ~= PHASE_BATTLE then return end

    s.timer = s.timer + dt
    if s.timer < ROUND_INTERVAL then return end
    s.timer = s.timer - ROUND_INTERVAL

    -- 推进一回合
    s.roundIdx = s.roundIdx + 1
    if s.roundIdx > #s.rounds then
        -- 所有回合播放完毕
        s.phase = PHASE_RESULT
        -- 结算
        if not s.settled then
            s.settled = true
            local ok, msg = GameExplore.SettleCombat(s.encounter, s.win, s.summary)
            s.resultMsg = msg
        end
        Router.RebuildUI()
        return
    end

    local round = s.rounds[s.roundIdx]

    -- 生成本回合日志
    local log = s.battleLog
    local pName = "我方"
    local eName = s.encounter.name or "妖"

    -- 玩家行动
    local pa = round.playerAction
    if pa then
        if pa.hit then
            local critTag = pa.crit and "<c=gold>[暴击]</c>" or ""
            log[#log + 1] = "第" .. round.num .. "回合: " .. pName ..
                "攻击" .. eName .. critTag .. "，造成<c=red>" .. pa.damage .. "</c>点伤害"
        else
            log[#log + 1] = "第" .. round.num .. "回合: " .. pName ..
                "攻击" .. eName .. "，<c=gray>未命中</c>"
        end
    end

    -- 敌方行动
    local ea = round.enemyAction
    if ea then
        if ea.hit then
            local critTag = ea.crit and "<c=gold>[暴击]</c>" or ""
            log[#log + 1] = eName .. "反击" .. pName .. critTag ..
                "，造成<c=red>" .. ea.damage .. "</c>点伤害"
        else
            log[#log + 1] = eName .. "攻击" .. pName .. "，<c=gray>未命中</c>"
        end
    end

    -- 回合结束判定
    if round.finished then
        if round.win then
            log[#log + 1] = "<c=gold>--- " .. eName .. "倒下了 ---</c>"
        else
            log[#log + 1] = "<c=red>--- 我方败退 ---</c>"
        end
        s.phase = PHASE_RESULT
        if not s.settled then
            s.settled = true
            local ok, msg = GameExplore.SettleCombat(s.encounter, s.win, s.summary)
            s.resultMsg = msg
        end
    end

    Router.RebuildUI()
end

-- ============================================================================
-- 开始战斗播放
-- ============================================================================
local function StartBattle(enc)
    local s = battleState_
    local win, summary, rounds = GameExplore.DoCombat(enc)
    s.phase = PHASE_BATTLE
    s.encounter = enc
    s.monsterImg = GameExplore.GetMonsterImage(enc)
    s.rounds = rounds
    s.roundIdx = 0
    s.win = win
    s.summary = summary
    s.timer = 0
    s.battleLog = {}
    s.settled = false
    s.resultMsg = ""

    -- 注册更新回调（驱动回合播放）
    NVG.Register(battleUpdateKey_, nil, BattleUpdate)
    Router.RebuildUI()
end

-- ============================================================================
-- 重置战斗状态
-- ============================================================================
local function ResetBattle()
    battleState_.phase = PHASE_IDLE
    battleState_.encounter = nil
    battleState_.rounds = {}
    battleState_.roundIdx = 0
    battleState_.battleLog = {}
    battleState_.settled = false
    NVG.Unregister(battleUpdateKey_)
end

-- ============================================================================
-- HP 条组件
-- ============================================================================
local function BuildHPBar(current, max, label, isEnemy)
    local pct = max > 0 and (current / max) or 0
    if pct < 0 then pct = 0 end
    if pct > 1 then pct = 1 end
    local barColor = isEnemy and Theme.colors.danger or { 80, 180, 80, 255 }
    local hpText = tostring(math.max(0, math.floor(current))) .. "/" .. tostring(math.floor(max))

    return UI.Panel {
        width = "100%",
        gap = 2,
        children = {
            UI.Panel {
                width = "100%",
                flexDirection = "row",
                justifyContent = "space-between",
                children = {
                    UI.Label {
                        text = label,
                        fontSize = 10,
                        fontWeight = "bold",
                        color = isEnemy and Theme.colors.dangerLight or Theme.colors.successLight,
                    },
                    UI.Label {
                        text = hpText,
                        fontSize = 9,
                        color = Theme.colors.textLight,
                    },
                },
            },
            UI.Panel {
                width = "100%",
                height = 8,
                borderRadius = 4,
                backgroundColor = { 40, 35, 30, 200 },
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
        },
    }
end

-- ============================================================================
-- 战斗场景区（带怪物图片、HP 条、当前回合动态）
-- ============================================================================
local function BuildBattleScene(p, s)
    local curRound = s.roundIdx > 0 and s.roundIdx <= #s.rounds and s.rounds[s.roundIdx] or nil
    -- 当前 HP
    local playerHP = curRound and curRound.playerHP or (p.hp or 800)
    local playerHPMax = curRound and curRound.playerHPMax or (p.hpMax or 800)
    local enemyHP = curRound and curRound.enemyHP or (s.encounter and s.encounter.hp or 100)
    local enemyHPMax = s.encounter and s.encounter.hp or 100

    -- 回合提示
    local roundText = ""
    if s.phase == PHASE_BATTLE then
        roundText = "第 " .. tostring(s.roundIdx) .. " / " .. tostring(#s.rounds) .. " 回合"
    elseif s.phase == PHASE_RESULT then
        roundText = s.win and "胜利" or "败退"
    end

    -- 头像路径
    local avatarIdx = p.avatarIndex or 1
    local avatarList = Theme.avatars[p.gender] or Theme.avatars["男"]
    local avatarImg = avatarList[avatarIdx] or avatarList[1]

    return UI.Panel {
        width = "100%",
        borderRadius = Theme.radius.lg,
        backgroundColor = Theme.colors.bgDark,
        borderColor = Theme.colors.borderGold,
        borderWidth = 1,
        padding = 10,
        gap = 8,
        children = {
            -- 回合标题
            UI.Label {
                text = roundText,
                fontSize = 11,
                color = Theme.colors.textGold,
                textAlign = "center",
                width = "100%",
            },
            -- 双方对峙
            UI.Panel {
                width = "100%",
                flexDirection = "row",
                alignItems = "flex-end",
                justifyContent = "space-around",
                children = {
                    -- 玩家侧
                    UI.Panel {
                        width = "40%",
                        alignItems = "center",
                        gap = 4,
                        children = {
                            UI.Panel {
                                width = 60,
                                height = 60,
                                borderRadius = 30,
                                overflow = "hidden",
                                backgroundColor = { 45, 36, 28, 255 },
                                borderColor = { 80, 180, 80, 200 },
                                borderWidth = 2,
                                children = {
                                    UI.Panel {
                                        width = "100%",
                                        height = "100%",
                                        backgroundImage = avatarImg,
                                        backgroundFit = "cover",
                                    },
                                },
                            },
                            UI.Label {
                                text = p.name or "我",
                                fontSize = 11,
                                fontWeight = "bold",
                                color = Theme.colors.successLight,
                            },
                            BuildHPBar(playerHP, playerHPMax, "气血", false),
                        },
                    },
                    -- VS
                    UI.Label {
                        text = "VS",
                        fontSize = 18,
                        fontWeight = "bold",
                        color = Theme.colors.gold,
                        marginBottom = 30,
                    },
                    -- 怪物侧
                    UI.Panel {
                        width = "40%",
                        alignItems = "center",
                        gap = 4,
                        children = {
                            UI.Panel {
                                width = 60,
                                height = 60,
                                borderRadius = 30,
                                overflow = "hidden",
                                backgroundColor = { 50, 25, 25, 255 },
                                borderColor = Theme.colors.dangerLight,
                                borderWidth = 2,
                                children = {
                                    s.monsterImg and UI.Panel {
                                        width = "100%",
                                        height = "100%",
                                        backgroundImage = s.monsterImg,
                                        backgroundFit = "cover",
                                    } or UI.Label {
                                        text = "妖",
                                        fontSize = 20,
                                        fontWeight = "bold",
                                        color = Theme.colors.dangerLight,
                                    },
                                },
                            },
                            UI.Label {
                                text = s.encounter and s.encounter.name or "未知",
                                fontSize = 11,
                                fontWeight = "bold",
                                color = Theme.colors.dangerLight,
                            },
                            BuildHPBar(enemyHP, enemyHPMax, "气血", true),
                        },
                    },
                },
            },
        },
    }
end

-- ============================================================================
-- 战斗日志面板
-- ============================================================================
local function BuildBattleLog(logLines)
    if #logLines == 0 then
        return UI.Panel {
            width = "100%",
            height = 60,
            justifyContent = "center",
            alignItems = "center",
            children = {
                UI.Label {
                    text = "战斗即将开始...",
                    fontSize = Theme.fontSize.small,
                    color = Theme.colors.textSecondary,
                },
            },
        }
    end
    return Comp.BuildLogPanel(logLines, { height = 120 })
end

-- ============================================================================
-- Build 主函数
-- ============================================================================
function M.Build(payload)
    local p = GamePlayer.Get()
    if not p then return UI.Panel { width = "100%", height = "100%" } end

    local s = battleState_
    local contentChildren = {}

    if s.phase == PHASE_IDLE then
        -- ========================
        -- 空闲状态：显示探索入口
        -- ========================
        contentChildren = {
            Comp.BuildSectionTitle("山谷遭遇"),

            -- 静态场景（没有战斗时）
            UI.Panel {
                width = "100%",
                height = 140,
                borderRadius = Theme.radius.lg,
                backgroundColor = Theme.colors.bgDark,
                borderColor = Theme.colors.borderGold,
                borderWidth = 1,
                justifyContent = "center",
                alignItems = "center",
                gap = 8,
                children = {
                    UI.Label {
                        text = "四周灵气浮动，隐约有动静...",
                        fontSize = Theme.fontSize.body,
                        color = Theme.colors.textLight,
                    },
                    UI.Label {
                        text = "点击下方按钮开始探索",
                        fontSize = Theme.fontSize.small,
                        color = Theme.colors.textSecondary,
                    },
                },
            },

            -- 探索日志
            Comp.BuildCardPanel("事件记录", {
                Comp.BuildLogPanel(p.cultivationLogs or {}, { height = 140 }),
            }),

            -- 操作按钮
            Comp.BuildInkButton("继续探索", function()
                -- 生成遭遇
                local enc, reason = GameExplore.GenerateEncounter()
                if not enc then
                    Toast.Show(reason or "无法探索", { variant = "error" })
                    return
                end

                if enc.type == "combat" then
                    -- 战斗类遭遇：启动战斗播放
                    StartBattle(enc)
                else
                    -- 非战斗遭遇：直接走旧逻辑
                    local ok, msg = GameExplore.DoExplore()
                    Toast.Show(msg, { variant = ok and "success" or "error" })
                    Router.HandleNavigate("explore")
                end
            end),
            Comp.BuildSecondaryButton("撤  退", function()
                Router.EnterState(Router.STATE_WORLD_MAP)
            end),
        }

    elseif s.phase == PHASE_BATTLE then
        -- ========================
        -- 战斗播放中
        -- ========================
        contentChildren = {
            Comp.BuildSectionTitle("战斗中"),
            BuildBattleScene(p, s),
            Comp.BuildCardPanel("战斗记录", {
                BuildBattleLog(s.battleLog),
            }),
            -- 跳过按钮（加速看结果）
            Comp.BuildSecondaryButton("跳过战斗", function()
                -- 直接跳到最后
                s.roundIdx = #s.rounds
                -- 生成所有剩余日志
                for i = s.roundIdx, #s.rounds do
                    local round = s.rounds[i]
                    if not round then break end
                    -- 简化：不再逐条写日志，直接跳到结果
                end
                s.phase = PHASE_RESULT
                if not s.settled then
                    s.settled = true
                    local ok, msg = GameExplore.SettleCombat(s.encounter, s.win, s.summary)
                    s.resultMsg = msg
                end
                Router.RebuildUI()
            end),
        }

    elseif s.phase == PHASE_RESULT then
        -- ========================
        -- 战斗结束，展示结果
        -- ========================
        contentChildren = {
            Comp.BuildSectionTitle(s.win and "战斗胜利" or "战斗败退"),
            BuildBattleScene(p, s),
            Comp.BuildCardPanel("战斗记录", {
                BuildBattleLog(s.battleLog),
            }),
            -- 结果信息
            UI.Panel {
                width = "100%",
                padding = Theme.spacing.md,
                borderRadius = Theme.radius.md,
                backgroundColor = s.win and { 30, 50, 30, 200 } or { 50, 25, 25, 200 },
                borderColor = s.win and Theme.colors.successLight or Theme.colors.dangerLight,
                borderWidth = 1,
                alignItems = "center",
                children = {
                    Comp.BuildRichLabel(
                        s.resultMsg or s.summary,
                        Theme.fontSize.body,
                        s.win and Theme.colors.successLight or Theme.colors.dangerLight
                    ),
                },
            },
            -- 继续/撤退按钮
            Comp.BuildInkButton("继续探索", function()
                ResetBattle()
                -- 再来一次
                local enc, reason = GameExplore.GenerateEncounter()
                if not enc then
                    Toast.Show(reason or "无法探索", { variant = "error" })
                    Router.RebuildUI()
                    return
                end
                if enc.type == "combat" then
                    StartBattle(enc)
                else
                    local ok, msg = GameExplore.DoExplore()
                    Toast.Show(msg, { variant = ok and "success" or "error" })
                    Router.HandleNavigate("explore")
                end
            end),
            Comp.BuildSecondaryButton("撤  退", function()
                ResetBattle()
                Router.EnterState(Router.STATE_WORLD_MAP)
            end),
        }
    end

    return Comp.BuildPageShell("explore", p, contentChildren, Router.HandleNavigate)
end

return M
