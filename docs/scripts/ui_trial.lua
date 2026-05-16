-- ============================================================================
-- 《问道长生》试炼场页 —— 战斗过程可视化
-- 状态机：list -> battle -> fight_result -> (下一场 or final) -> list
-- ============================================================================

local UI = require("urhox-libs/UI")
local Theme = require("ui_theme")
local Comp = require("ui_components")
local Router = require("ui_router")
local GamePlayer = require("game_player")
local GameTrial = require("game_trial")
local Toast = require("ui_toast")
local NVG = require("nvg_manager")

local M = {}

-- ============================================================================
-- 状态常量
-- ============================================================================
local PHASE_LIST         = "list"
local PHASE_BATTLE       = "battle"
local PHASE_FIGHT_RESULT = "fight_result"
local PHASE_FINAL        = "final"

-- ============================================================================
-- 模块状态
-- ============================================================================
local state_ = {
    phase        = PHASE_LIST,
    -- PrepareChallenge 返回的完整结果
    challengeResult = nil,
    -- 当前场次索引
    fightIdx     = 0,
    -- 当前场次回合播放索引
    roundIdx     = 0,
    timer        = 0,
    battleLog    = {},
    -- 结算后的信息
    settled      = false,
    settleMsg    = "",
}

local ROUND_INTERVAL = 0.5
local FIGHT_PAUSE    = 1.0   -- 场次间停顿
local UPDATE_KEY     = "trial_battle"

-- ============================================================================
-- 辅助：获取当前场次数据
-- ============================================================================
local function CurFight()
    local r = state_.challengeResult
    if not r then return nil end
    return r.fights[state_.fightIdx]
end

-- ============================================================================
-- 辅助：场次标签文本
-- ============================================================================
local function FightLabel()
    local r = state_.challengeResult
    if not r then return "" end
    local f = CurFight()
    if not f then return "" end
    if r.type == "闯关" then
        return "第" .. f.floor .. "层"
    elseif r.type == "生存" then
        return "第" .. f.floor .. "波"
    elseif r.type == "限时" then
        return "第" .. state_.fightIdx .. "只"
    end
    return ""
end

-- ============================================================================
-- 战斗 Update 回调
-- ============================================================================
local function BattleUpdate(dt)
    local s = state_
    if s.phase ~= PHASE_BATTLE then return end

    s.timer = s.timer + dt
    if s.timer < ROUND_INTERVAL then return end
    s.timer = s.timer - ROUND_INTERVAL

    local fight = CurFight()
    if not fight then
        s.phase = PHASE_FIGHT_RESULT
        Router.RebuildUI()
        return
    end

    s.roundIdx = s.roundIdx + 1
    if s.roundIdx > #fight.rounds then
        s.phase = PHASE_FIGHT_RESULT
        Router.RebuildUI()
        return
    end

    local round = fight.rounds[s.roundIdx]
    local pName = "我方"
    local eName = fight.enemy.name or "妖"

    -- 玩家行动日志
    local pa = round.playerAction
    if pa then
        if pa.hit then
            local critTag = pa.crit and "<c=gold>[暴击]</c>" or ""
            s.battleLog[#s.battleLog + 1] = "R" .. round.num .. ": " .. pName ..
                "击" .. eName .. critTag .. " <c=red>-" .. pa.damage .. "</c>"
        else
            s.battleLog[#s.battleLog + 1] = "R" .. round.num .. ": " .. pName ..
                "击" .. eName .. " <c=gray>未中</c>"
        end
    end

    -- 敌方行动日志
    local ea = round.enemyAction
    if ea then
        if ea.hit then
            local critTag = ea.crit and "<c=gold>[暴击]</c>" or ""
            s.battleLog[#s.battleLog + 1] = eName .. "反击" .. critTag ..
                " <c=red>-" .. ea.damage .. "</c>"
        else
            s.battleLog[#s.battleLog + 1] = eName .. "攻击 <c=gray>未中</c>"
        end
    end

    -- 回合结束
    if round.finished then
        if round.win then
            s.battleLog[#s.battleLog + 1] = "<c=gold>--- " .. eName .. " 倒下 ---</c>"
        else
            s.battleLog[#s.battleLog + 1] = "<c=red>--- 我方败退 ---</c>"
        end
        s.phase = PHASE_FIGHT_RESULT
    end

    Router.RebuildUI()
end

-- ============================================================================
-- 开始挑战
-- ============================================================================
local function StartChallenge(trialId)
    local result, err = GameTrial.PrepareChallenge(trialId)
    if not result then
        Toast.Show(err or "挑战失败", { variant = "error" })
        return
    end

    state_.phase = PHASE_BATTLE
    state_.challengeResult = result
    state_.fightIdx = 1
    state_.roundIdx = 0
    state_.timer = 0
    state_.battleLog = { "<c=gold>--- " .. result.trialName .. " 开始 ---</c>" }
    state_.settled = false
    state_.settleMsg = ""

    -- 添加首场提示
    local firstFight = result.fights[1]
    if firstFight then
        state_.battleLog[#state_.battleLog + 1] = "<c=yellow>" .. FightLabel() ..
            ": VS " .. firstFight.enemy.name .. "</c>"
    end

    NVG.Register(UPDATE_KEY, nil, BattleUpdate)
    Router.RebuildUI()
end

-- ============================================================================
-- 推进到下一场或最终结算
-- ============================================================================
local function AdvanceOrSettle()
    local s = state_
    local r = s.challengeResult
    if not r then return end

    local curFight = CurFight()
    -- 如果当前场失败，直接结算
    if curFight and not curFight.win then
        s.phase = PHASE_FINAL
        if not s.settled then
            s.settled = true
            local ok, msg = GameTrial.SettleChallenge(r)
            s.settleMsg = msg
        end
        Router.RebuildUI()
        return
    end

    -- 还有下一场？
    if s.fightIdx < #r.fights then
        s.fightIdx = s.fightIdx + 1
        s.roundIdx = 0
        s.timer = 0
        s.phase = PHASE_BATTLE
        local fight = CurFight()
        if fight then
            s.battleLog[#s.battleLog + 1] = "<c=yellow>" .. FightLabel() ..
                ": VS " .. fight.enemy.name .. "</c>"
        end
        Router.RebuildUI()
    else
        -- 所有场次完成
        s.phase = PHASE_FINAL
        if not s.settled then
            s.settled = true
            local ok, msg = GameTrial.SettleChallenge(r)
            s.settleMsg = msg
        end
        Router.RebuildUI()
    end
end

-- ============================================================================
-- 跳过全部战斗
-- ============================================================================
local function SkipAll()
    local s = state_
    local r = s.challengeResult
    if not r then return end

    -- 生成所有剩余日志
    for fi = s.fightIdx, #r.fights do
        local fight = r.fights[fi]
        if fi > s.fightIdx or s.roundIdx == 0 then
            s.battleLog[#s.battleLog + 1] = "<c=yellow>" ..
                (r.type == "闯关" and ("第" .. fight.floor .. "层") or
                 r.type == "生存" and ("第" .. fight.floor .. "波") or
                 ("第" .. fi .. "只")) ..
                ": VS " .. fight.enemy.name .. "</c>"
        end
        if fight.win then
            s.battleLog[#s.battleLog + 1] = "<c=gold>击败 " .. fight.enemy.name .. "</c>"
        else
            s.battleLog[#s.battleLog + 1] = "<c=red>败于 " .. fight.enemy.name .. "</c>"
        end
    end

    s.fightIdx = #r.fights
    s.roundIdx = r.fights[s.fightIdx] and #r.fights[s.fightIdx].rounds or 0
    s.phase = PHASE_FINAL
    if not s.settled then
        s.settled = true
        local ok, msg = GameTrial.SettleChallenge(r)
        s.settleMsg = msg
    end
    Router.RebuildUI()
end

-- ============================================================================
-- 重置状态
-- ============================================================================
local function ResetState()
    state_.phase = PHASE_LIST
    state_.challengeResult = nil
    state_.fightIdx = 0
    state_.roundIdx = 0
    state_.battleLog = {}
    state_.settled = false
    state_.settleMsg = ""
    NVG.Unregister(UPDATE_KEY)
end

-- ============================================================================
-- UI 组件：HP 条
-- ============================================================================
local function BuildHPBar(current, max, label, isEnemy)
    local pct = max > 0 and (current / max) or 0
    if pct < 0 then pct = 0 end
    if pct > 1 then pct = 1 end
    local barColor = isEnemy and Theme.colors.danger or { 80, 180, 80, 255 }
    local hpText = tostring(math.max(0, math.floor(current))) .. "/" .. tostring(math.floor(max))

    return UI.Panel {
        width = "100%", gap = 2,
        children = {
            UI.Panel {
                width = "100%", flexDirection = "row", justifyContent = "space-between",
                children = {
                    UI.Label {
                        text = label, fontSize = 10, fontWeight = "bold",
                        color = isEnemy and Theme.colors.dangerLight or Theme.colors.successLight,
                    },
                    UI.Label {
                        text = hpText, fontSize = 9,
                        color = Theme.colors.textLight,
                    },
                },
            },
            UI.Panel {
                width = "100%", height = 8, borderRadius = 4,
                backgroundColor = { 40, 35, 30, 200 }, overflow = "hidden",
                children = {
                    UI.Panel {
                        width = tostring(math.floor(pct * 100)) .. "%",
                        height = "100%", borderRadius = 4,
                        backgroundColor = barColor,
                    },
                },
            },
        },
    }
end

-- ============================================================================
-- UI 组件：战斗场景（双方对峙）
-- ============================================================================
local function BuildBattleScene(p)
    local s = state_
    local fight = CurFight()
    if not fight then return UI.Panel { width = "100%" } end

    local curRound = s.roundIdx > 0 and s.roundIdx <= #fight.rounds and fight.rounds[s.roundIdx] or nil
    local playerHP = curRound and curRound.playerHP or (p.hp or 800)
    local playerHPMax = curRound and curRound.playerHPMax or (p.hpMax or 800)
    local enemyHP = curRound and curRound.enemyHP or fight.enemy.hp
    local enemyHPMax = fight.enemy.hp

    local roundText = ""
    if s.phase == PHASE_BATTLE then
        roundText = FightLabel() .. "  回合 " .. tostring(s.roundIdx) .. "/" .. tostring(#fight.rounds)
    elseif s.phase == PHASE_FIGHT_RESULT then
        roundText = FightLabel() .. (fight.win and "  胜利" or "  败退")
    elseif s.phase == PHASE_FINAL then
        roundText = FightLabel() .. (fight.win and "  胜利" or "  败退")
    end

    local avatarIdx = p.avatarIndex or 1
    local avatarList = Theme.avatars[p.gender] or Theme.avatars["男"]
    local avatarImg = avatarList[avatarIdx] or avatarList[1]

    return UI.Panel {
        width = "100%",
        borderRadius = Theme.radius.lg,
        backgroundColor = Theme.colors.bgDark,
        borderColor = Theme.colors.borderGold,
        borderWidth = 1,
        padding = 10, gap = 6,
        children = {
            UI.Label {
                text = roundText, fontSize = 11,
                color = Theme.colors.textGold,
                textAlign = "center", width = "100%",
            },
            UI.Panel {
                width = "100%", flexDirection = "row",
                alignItems = "flex-end", justifyContent = "space-around",
                children = {
                    -- 玩家
                    UI.Panel {
                        width = "40%", alignItems = "center", gap = 4,
                        children = {
                            UI.Panel {
                                width = 56, height = 56, borderRadius = 28, overflow = "hidden",
                                backgroundColor = { 45, 36, 28, 255 },
                                borderColor = { 80, 180, 80, 200 }, borderWidth = 2,
                                children = {
                                    UI.Panel {
                                        width = "100%", height = "100%",
                                        backgroundImage = avatarImg, backgroundFit = "cover",
                                    },
                                },
                            },
                            UI.Label {
                                text = p.name or "我", fontSize = 10, fontWeight = "bold",
                                color = Theme.colors.successLight,
                            },
                            BuildHPBar(playerHP, playerHPMax, "气血", false),
                        },
                    },
                    UI.Label {
                        text = "VS", fontSize = 16, fontWeight = "bold",
                        color = Theme.colors.gold, marginBottom = 24,
                    },
                    -- 怪物
                    UI.Panel {
                        width = "40%", alignItems = "center", gap = 4,
                        children = {
                            UI.Panel {
                                width = 56, height = 56, borderRadius = 28, overflow = "hidden",
                                backgroundColor = { 50, 25, 25, 255 },
                                borderColor = Theme.colors.dangerLight, borderWidth = 2,
                                children = {
                                    fight.monsterImg and UI.Panel {
                                        width = "100%", height = "100%",
                                        backgroundImage = fight.monsterImg, backgroundFit = "cover",
                                    } or UI.Label {
                                        text = "妖", fontSize = 18, fontWeight = "bold",
                                        color = Theme.colors.dangerLight,
                                    },
                                },
                            },
                            UI.Label {
                                text = fight.enemy.name, fontSize = 10, fontWeight = "bold",
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
-- UI 组件：进度条（几场/共几场）
-- ============================================================================
local function BuildProgressBar()
    local s = state_
    local r = s.challengeResult
    if not r then return UI.Panel { width = "100%" } end

    local total = #r.fights
    local current = s.fightIdx

    local dots = {}
    for i = 1, total do
        local fight = r.fights[i]
        local dotColor
        if i < current then
            dotColor = fight.win and Theme.colors.success or Theme.colors.danger
        elseif i == current then
            dotColor = Theme.colors.gold
        else
            dotColor = { 60, 55, 45, 150 }
        end
        dots[#dots + 1] = UI.Panel {
            width = 10, height = 10, borderRadius = 5,
            backgroundColor = dotColor,
        }
    end

    -- 如果场次过多，只显示文字
    if total > 15 then
        return UI.Panel {
            width = "100%", alignItems = "center",
            children = {
                UI.Label {
                    text = "进度: " .. current .. " / " .. total,
                    fontSize = Theme.fontSize.small,
                    color = Theme.colors.textGold,
                },
            },
        }
    end

    return UI.Panel {
        width = "100%", flexDirection = "row",
        justifyContent = "center", gap = 4,
        flexWrap = "wrap", paddingVertical = 4,
        children = dots,
    }
end

-- ============================================================================
-- 难度星级
-- ============================================================================
local TRIAL_DIFFICULTY = {
    wanyao  = 2,
    mijing  = 3,
    shengsi = 4,
    xianmo  = 5,
}

local function BuildDifficultyStars(trialId)
    local level = TRIAL_DIFFICULTY[trialId] or 2
    local stars = {}
    for i = 1, 5 do
        stars[#stars + 1] = UI.Label {
            text = i <= level and "*" or "-",
            fontSize = Theme.fontSize.small,
            color = i <= level and Theme.colors.gold or { 80, 70, 55, 120 },
        }
    end
    return UI.Panel { flexDirection = "row", gap = 2, children = stars }
end

-- ============================================================================
-- 试炼卡片（列表用）
-- ============================================================================
local function BuildTrialCard(trial)
    local isLocked = not trial.unlocked

    local typeColors = {
        ["闯关"] = Theme.colors.accent,
        ["限时"] = Theme.colors.warning,
        ["生存"] = Theme.colors.danger,
    }

    local rewardText = ""
    if trial.rewards then
        rewardText = table.concat(trial.rewards, "  ")
    end

    local requirementText = ""
    if trial.unlockTier then
        local DataRealms = require("data_realms")
        local realm = DataRealms.GetRealm(trial.unlockTier)
        requirementText = realm and realm.name or ("境界" .. trial.unlockTier)
    end

    return Comp.BuildCardPanel(nil, {
        -- 标题行
        UI.Panel {
            width = "100%", flexDirection = "row",
            justifyContent = "space-between", alignItems = "center",
            children = {
                UI.Panel {
                    flexDirection = "row", gap = 8, alignItems = "center",
                    children = {
                        UI.Label {
                            text = trial.name,
                            fontSize = Theme.fontSize.subtitle, fontWeight = "bold",
                            color = isLocked and Theme.colors.textSecondary or Theme.colors.textGold,
                        },
                        UI.Panel {
                            paddingHorizontal = 8, paddingVertical = 2,
                            borderRadius = Theme.radius.sm,
                            backgroundColor = { 50, 42, 35, 200 },
                            children = {
                                UI.Label {
                                    text = trial.type, fontSize = Theme.fontSize.tiny,
                                    color = typeColors[trial.type] or Theme.colors.textLight,
                                },
                            },
                        },
                    },
                },
                BuildDifficultyStars(trial.id),
            },
        },
        -- 描述
        UI.Label {
            text = trial.desc, fontSize = Theme.fontSize.small,
            color = isLocked and { 100, 90, 75, 150 } or Theme.colors.textLight,
            width = "100%",
        },
        -- 进度/解锁
        isLocked and UI.Panel {
            width = "100%", flexDirection = "row", gap = 4, alignItems = "center",
            children = {
                UI.Label {
                    text = "解锁条件:", fontSize = Theme.fontSize.small,
                    color = Theme.colors.textSecondary,
                },
                UI.Label {
                    text = requirementText, fontSize = Theme.fontSize.small,
                    fontWeight = "bold", color = Theme.colors.danger,
                },
            },
        } or UI.Label {
            text = trial.progressText, fontSize = Theme.fontSize.small,
            color = Theme.colors.accent, width = "100%",
        },
        -- 奖励 + 挑战按钮
        UI.Panel {
            width = "100%", flexDirection = "row",
            justifyContent = "space-between", alignItems = "center",
            marginTop = 4,
            children = {
                UI.Panel {
                    flexShrink = 1,
                    children = {
                        UI.Label {
                            text = "奖励: " .. rewardText,
                            fontSize = Theme.fontSize.tiny,
                            color = Theme.colors.goldLight,
                        },
                    },
                },
                UI.Panel {
                    paddingHorizontal = 16, paddingVertical = 6,
                    borderRadius = Theme.radius.sm,
                    backgroundColor = isLocked and { 80, 70, 55, 150 } or Theme.colors.gold,
                    cursor = isLocked and "default" or "pointer",
                    onClick = function(self)
                        if isLocked then
                            Toast.Show("试炼未解锁，需要达到" .. requirementText, { variant = "error" })
                            return
                        end
                        StartChallenge(trial.id)
                    end,
                    children = {
                        UI.Label {
                            text = isLocked and "未解锁" or "挑战",
                            fontSize = Theme.fontSize.body, fontWeight = "bold",
                            color = isLocked and Theme.colors.textSecondary or Theme.colors.inkBlack,
                        },
                    },
                },
            },
        },
    })
end

-- ============================================================================
-- 返回行
-- ============================================================================
local function BuildBackRow(backTarget, backLabel)
    return UI.Panel {
        width = "100%", flexDirection = "row",
        alignItems = "center", gap = 8,
        children = {
            UI.Panel {
                paddingHorizontal = 8, paddingVertical = 4,
                cursor = "pointer",
                onClick = function(self)
                    if backTarget == "list" then
                        ResetState()
                        Router.RebuildUI()
                    else
                        Router.EnterState(Router.STATE_MORE)
                    end
                end,
                children = {
                    UI.Label {
                        text = "< " .. (backLabel or "返回"),
                        fontSize = Theme.fontSize.body,
                        color = Theme.colors.gold,
                    },
                },
            },
            UI.Label {
                text = "试炼场",
                fontSize = Theme.fontSize.heading, fontWeight = "bold",
                color = Theme.colors.textGold,
            },
        },
    }
end

-- ============================================================================
-- Build 主函数
-- ============================================================================
function M.Build(payload)
    local p = GamePlayer.Get()
    if not p then return UI.Panel { width = "100%", height = "100%" } end

    local s = state_
    local contentChildren = {}

    -- ==================================================================
    -- PHASE_LIST
    -- ==================================================================
    if s.phase == PHASE_LIST then
        local trials = GameTrial.GetAllTrials()
        contentChildren[#contentChildren + 1] = BuildBackRow("more", "返回")
        contentChildren[#contentChildren + 1] = Comp.BuildSectionTitle("试炼列表")
        for _, trial in ipairs(trials) do
            contentChildren[#contentChildren + 1] = BuildTrialCard(trial)
        end

    -- ==================================================================
    -- PHASE_BATTLE
    -- ==================================================================
    elseif s.phase == PHASE_BATTLE then
        local r = s.challengeResult
        contentChildren[#contentChildren + 1] = BuildBackRow("list", "放弃")
        contentChildren[#contentChildren + 1] = Comp.BuildSectionTitle(
            r and (r.trialName .. " - 战斗中") or "战斗中"
        )
        contentChildren[#contentChildren + 1] = BuildProgressBar()
        contentChildren[#contentChildren + 1] = BuildBattleScene(p)
        contentChildren[#contentChildren + 1] = Comp.BuildCardPanel("战斗记录", {
            (#s.battleLog > 0) and Comp.BuildLogPanel(s.battleLog, { height = 120 })
            or UI.Label {
                text = "战斗即将开始...",
                fontSize = Theme.fontSize.small,
                color = Theme.colors.textSecondary,
            },
        })
        contentChildren[#contentChildren + 1] = Comp.BuildSecondaryButton("跳过全部", function()
            SkipAll()
        end)

    -- ==================================================================
    -- PHASE_FIGHT_RESULT
    -- ==================================================================
    elseif s.phase == PHASE_FIGHT_RESULT then
        local r = s.challengeResult
        local fight = CurFight()
        contentChildren[#contentChildren + 1] = BuildBackRow("list", "放弃")
        contentChildren[#contentChildren + 1] = Comp.BuildSectionTitle(
            r and (r.trialName .. " - " .. FightLabel()) or "战斗结果"
        )
        contentChildren[#contentChildren + 1] = BuildProgressBar()
        contentChildren[#contentChildren + 1] = BuildBattleScene(p)

        -- 本场结果提示
        if fight then
            contentChildren[#contentChildren + 1] = UI.Panel {
                width = "100%", padding = 8,
                borderRadius = Theme.radius.md,
                backgroundColor = fight.win and { 30, 50, 30, 200 } or { 50, 25, 25, 200 },
                borderColor = fight.win and Theme.colors.successLight or Theme.colors.dangerLight,
                borderWidth = 1, alignItems = "center",
                children = {
                    UI.Label {
                        text = fight.win and (FightLabel() .. " 通过") or (FightLabel() .. " 失败"),
                        fontSize = Theme.fontSize.body, fontWeight = "bold",
                        color = fight.win and Theme.colors.successLight or Theme.colors.dangerLight,
                    },
                },
            }
        end

        -- 按钮：下一场 or 查看结算
        local hasNext = fight and fight.win and s.fightIdx < #r.fights
        if hasNext then
            contentChildren[#contentChildren + 1] = Comp.BuildInkButton("下一场", function()
                AdvanceOrSettle()
            end)
            contentChildren[#contentChildren + 1] = Comp.BuildSecondaryButton("跳过全部", function()
                SkipAll()
            end)
        else
            contentChildren[#contentChildren + 1] = Comp.BuildInkButton("查看结算", function()
                AdvanceOrSettle()
            end)
        end

    -- ==================================================================
    -- PHASE_FINAL
    -- ==================================================================
    elseif s.phase == PHASE_FINAL then
        local r = s.challengeResult
        contentChildren[#contentChildren + 1] = BuildBackRow("list", "返回列表")
        contentChildren[#contentChildren + 1] = Comp.BuildSectionTitle(
            r and (r.trialName .. " - 结算") or "试炼结算"
        )
        contentChildren[#contentChildren + 1] = BuildProgressBar()

        -- 战斗日志
        contentChildren[#contentChildren + 1] = Comp.BuildCardPanel("战斗记录", {
            Comp.BuildLogPanel(s.battleLog, { height = 140 }),
        })

        -- 总结信息
        contentChildren[#contentChildren + 1] = UI.Panel {
            width = "100%", padding = Theme.spacing.md,
            borderRadius = Theme.radius.md,
            backgroundColor = (r and r.cleared > 0) and { 30, 50, 30, 200 } or { 50, 25, 25, 200 },
            borderColor = (r and r.cleared > 0) and Theme.colors.successLight or Theme.colors.dangerLight,
            borderWidth = 1, alignItems = "center", gap = 6,
            children = {
                Comp.BuildRichLabel(
                    s.settleMsg ~= "" and s.settleMsg or "挑战结束",
                    Theme.fontSize.body,
                    (r and r.cleared > 0) and Theme.colors.successLight or Theme.colors.dangerLight
                ),
                r and UI.Label {
                    text = "通过: " .. r.cleared .. " 场  |  灵石: +" .. r.reward,
                    fontSize = Theme.fontSize.small,
                    color = Theme.colors.goldLight,
                } or nil,
            },
        }

        contentChildren[#contentChildren + 1] = Comp.BuildInkButton("返回试炼列表", function()
            ResetState()
            Router.RebuildUI()
        end)
    end

    return Comp.BuildPageShell("more", p, contentChildren, Router.HandleNavigate)
end

return M
