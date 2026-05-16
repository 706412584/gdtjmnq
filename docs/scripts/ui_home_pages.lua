-- ============================================================================
-- 《问道长生》洞府子页面（属性/功法/法宝/悟道/渡劫/丹药）
-- ============================================================================

local UI = require("urhox-libs/UI")
local Theme = require("ui_theme")
local Comp = require("ui_components")
local Router = require("ui_router")
local GamePlayer = require("game_player")
local GameCultivation = require("game_cultivation")
local GameItems = require("game_items")
local Toast = require("ui_toast")
local DataItems = require("data_items")
local DataRealms = require("data_realms")
local GameSkill = require("game_skill")
local GameArtifact = require("game_artifact")
local GameDao = require("game_dao")

local M = {}

-- ============================================================================
-- 通用：返回按钮
-- ============================================================================
local function BuildBackRow(title)
    return UI.Panel {
        width = "100%",
        flexDirection = "row",
        alignItems = "center",
        gap = 8,
        children = {
            UI.Panel {
                paddingHorizontal = 8,
                paddingVertical = 4,
                cursor = "pointer",
                onClick = function(self)
                    Router.EnterState(Router.STATE_HOME)
                end,
                children = {
                    UI.Label {
                        text = "< 返回",
                        fontSize = Theme.fontSize.body,
                        color = Theme.colors.gold,
                    },
                },
            },
            UI.Label {
                text = title,
                fontSize = Theme.fontSize.heading,
                fontWeight = "bold",
                color = Theme.colors.textGold,
            },
        },
    }
end

-- ============================================================================
-- 通用：品质颜色
-- ============================================================================
local function GetQualityColor(q)
    return DataItems.GetQualityColor(q)
end

-- ============================================================================
-- 页面1：属性
-- ============================================================================
function M.BuildAttr(payload)
    local p = GamePlayer.Get()
    if not p then return UI.Panel { width = "100%", height = "100%" } end

    -- 从玩家数据动态构建属性列表
    local basicDefs = {
        { label = "气血",   value = (p.hp or 0) .. " / " .. (p.hpMax or 0), color = "danger" },
        { label = "灵力",   value = (p.mp or 0) .. " / " .. (p.mpMax or 0), color = "accent" },
        { label = "攻击",   value = tostring(p.attack or 0) },
        { label = "防御",   value = tostring(p.defense or 0) },
        { label = "速度",   value = tostring(p.speed or 0) },
        { label = "暴击",   value = (p.crit or 0) .. "%" },
        { label = "闪避",   value = (p.dodge or 0) .. "%" },
        { label = "命中",   value = (p.hit or 0) .. "%" },
    }
    local basicRows = {}
    for _, a in ipairs(basicDefs) do
        local valColor = Theme.colors.textLight
        if a.color == "danger" then valColor = Theme.colors.dangerLight
        elseif a.color == "accent" then valColor = Theme.colors.accent
        end
        basicRows[#basicRows + 1] = Comp.BuildStatRow(a.label, a.value, { valueColor = valColor })
    end

    local specialDefs = {
        { label = "灵根",   value = p.rootBone or "未知" },
        { label = "悟性",   value = tostring(p.wisdom or 0) },
        { label = "气运",   value = p.fortune or "未知" },
        { label = "道心",   value = p.daoHeart or "未知" },
        { label = "神识",   value = tostring(p.sense or 0) },
    }
    local specialRows = {}
    for _, a in ipairs(specialDefs) do
        specialRows[#specialRows + 1] = Comp.BuildStatRow(a.label, a.value, { valueColor = Theme.colors.gold })
    end

    local contentChildren = {
        BuildBackRow("角色属性"),

        -- 角色信息
        Comp.BuildCardPanel("基本信息", {
            Comp.BuildStatRow("道号", p.name or "无名", { valueColor = Theme.colors.textGold }),
            Comp.BuildStatRow("境界", p.realmName or "练气初期", { valueColor = Theme.colors.gold }),
            Comp.BuildStatRow("灵根", p.rootBone or "未知"),
            Comp.BuildStatRow("气运", p.fortune or "未知"),
        }),

        -- 基础属性
        Comp.BuildCardPanel("战斗属性", basicRows),

        -- 特殊属性
        Comp.BuildCardPanel("修真属性", specialRows),
    }

    return Comp.BuildPageShell("home", p, contentChildren, Router.HandleNavigate)
end

-- ============================================================================
-- 页面2：功法
-- ============================================================================
local function BuildSkillCard(skill)
    local isLocked = skill.locked
    local lvText = isLocked and "未学" or ("Lv." .. skill.level .. "/" .. skill.maxLevel)
    local pct = isLocked and 0 or math.floor(skill.level / skill.maxLevel * 100)

    return Comp.BuildCardPanel(nil, {
        -- 标题行
        UI.Panel {
            width = "100%",
            flexDirection = "row",
            justifyContent = "space-between",
            alignItems = "center",
            children = {
                UI.Panel {
                    flexDirection = "row",
                    gap = 8,
                    alignItems = "center",
                    children = {
                        UI.Label {
                            text = skill.name,
                            fontSize = Theme.fontSize.subtitle,
                            fontWeight = "bold",
                            color = isLocked and Theme.colors.textSecondary or Theme.colors.textGold,
                        },
                        UI.Label {
                            text = "[" .. skill.type .. "]",
                            fontSize = Theme.fontSize.tiny,
                            color = Theme.colors.accent,
                        },
                    },
                },
                UI.Label {
                    text = lvText,
                    fontSize = Theme.fontSize.small,
                    fontWeight = "bold",
                    color = isLocked and Theme.colors.textSecondary or Theme.colors.gold,
                },
            },
        },
        -- 描述
        UI.Label {
            text = skill.desc,
            fontSize = Theme.fontSize.small,
            color = isLocked and { 100, 90, 75, 150 } or Theme.colors.textLight,
        },
        -- 效果
        UI.Label {
            text = "效果: " .. skill.effect,
            fontSize = Theme.fontSize.small,
            color = isLocked and { 100, 90, 75, 150 } or Theme.colors.successLight,
        },
        -- 等级进度条（非锁定时显示）
        not isLocked and UI.Panel {
            width = "100%",
            height = 6,
            borderRadius = 3,
            backgroundColor = { 50, 45, 35, 255 },
            overflow = "hidden",
            children = {
                UI.Panel {
                    width = tostring(pct) .. "%",
                    height = "100%",
                    borderRadius = 3,
                    backgroundColor = Theme.colors.gold,
                },
            },
        } or nil,
        -- 操作按钮
        UI.Panel {
            width = "100%",
            flexDirection = "row",
            justifyContent = "flex-end",
            marginTop = 4,
            children = {
                isLocked
                    and UI.Label {
                        text = "条件不足",
                        fontSize = Theme.fontSize.small,
                        color = Theme.colors.textSecondary,
                    }
                    or Comp.BuildSecondaryButton("修炼", function()
                        local ok, msg = GameSkill.DoTrainSkill(skill.name)
                        Toast.Show(msg, { variant = ok and "success" or "error" })
                        if ok then Router.HandleNavigate("home_skill") end
                    end, { width = 80, fontSize = Theme.fontSize.small }),
            },
        },
    })
end

function M.BuildSkill(payload)
    local p = GamePlayer.Get()
    if not p then return UI.Panel { width = "100%", height = "100%" } end
    local skills = p.skills or {}

    local cardList = { BuildBackRow("功法修炼") }
    for _, sk in ipairs(skills) do
        cardList[#cardList + 1] = BuildSkillCard(sk)
    end

    return Comp.BuildPageShell("home", p, cardList, Router.HandleNavigate)
end

-- ============================================================================
-- 页面3：法宝
-- ============================================================================
local function BuildArtifactCard(art)
    local pct = math.floor(art.level / art.maxLevel * 100)

    return Comp.BuildCardPanel(nil, {
        -- 标题行
        UI.Panel {
            width = "100%",
            flexDirection = "row",
            justifyContent = "space-between",
            alignItems = "center",
            children = {
                UI.Panel {
                    flexDirection = "row",
                    gap = 6,
                    alignItems = "center",
                    children = {
                        UI.Label {
                            text = art.name,
                            fontSize = Theme.fontSize.subtitle,
                            fontWeight = "bold",
                            color = GetQualityColor(art.quality),
                        },
                        UI.Label {
                            text = "[" .. art.quality .. "]",
                            fontSize = Theme.fontSize.tiny,
                            color = GetQualityColor(art.quality),
                        },
                    },
                },
                art.equipped and UI.Panel {
                    paddingHorizontal = 8,
                    paddingVertical = 2,
                    borderRadius = Theme.radius.sm,
                    backgroundColor = { 80, 160, 80, 60 },
                    borderColor = Theme.colors.successLight,
                    borderWidth = 1,
                    children = {
                        UI.Label {
                            text = "装备中",
                            fontSize = Theme.fontSize.tiny,
                            color = Theme.colors.successLight,
                        },
                    },
                } or UI.Label {
                    text = "Lv." .. art.level,
                    fontSize = Theme.fontSize.small,
                    color = Theme.colors.gold,
                },
            },
        },
        -- 描述
        UI.Label {
            text = art.desc,
            fontSize = Theme.fontSize.small,
            color = Theme.colors.textLight,
        },
        -- 效果
        UI.Label {
            text = "效果: " .. art.effect,
            fontSize = Theme.fontSize.small,
            color = Theme.colors.successLight,
        },
        -- 等级条
        UI.Panel {
            width = "100%",
            flexDirection = "row",
            gap = 8,
            alignItems = "center",
            children = {
                UI.Label {
                    text = "Lv." .. art.level .. "/" .. art.maxLevel,
                    fontSize = Theme.fontSize.tiny,
                    color = Theme.colors.textSecondary,
                },
                UI.Panel {
                    flexGrow = 1,
                    height = 6,
                    borderRadius = 3,
                    backgroundColor = { 50, 45, 35, 255 },
                    overflow = "hidden",
                    children = {
                        UI.Panel {
                            width = tostring(pct) .. "%",
                            height = "100%",
                            borderRadius = 3,
                            backgroundColor = Theme.colors.accent,
                        },
                    },
                },
            },
        },
        -- 操作
        UI.Panel {
            width = "100%",
            flexDirection = "row",
            justifyContent = "flex-end",
            gap = 8,
            marginTop = 4,
            children = {
                Comp.BuildSecondaryButton(art.equipped and "卸下" or "装备", function()
                    local ok, msg
                    if art.equipped then
                        ok, msg = GameArtifact.DoUnequip(art.name)
                    else
                        ok, msg = GameArtifact.DoEquip(art.name)
                    end
                    Toast.Show(msg, { variant = ok and "success" or "error" })
                    if ok then Router.HandleNavigate("home_artifact") end
                end, { width = 70, fontSize = Theme.fontSize.small }),
                Comp.BuildSecondaryButton("炼化", function()
                    local ok, msg = GameArtifact.DoEnhance(art.name)
                    if msg then Toast.Show(msg, { variant = ok and "success" or "error" }) end
                    if ok then Router.HandleNavigate("home_artifact") end
                end, { width = 70, fontSize = Theme.fontSize.small }),
            },
        },
    })
end

function M.BuildArtifact(payload)
    local p = GamePlayer.Get()
    if not p then return UI.Panel { width = "100%", height = "100%" } end
    local arts = p.artifacts or {}

    local cardList = { BuildBackRow("法宝") }
    if #arts == 0 then
        cardList[#cardList + 1] = Comp.BuildCardPanel(nil, {
            UI.Label {
                text = "暂无法宝，可前往坊市购买或游历获取。",
                fontSize = Theme.fontSize.body,
                color = Theme.colors.textSecondary,
            },
        })
    else
        for _, art in ipairs(arts) do
            cardList[#cardList + 1] = BuildArtifactCard(art)
        end
    end

    return Comp.BuildPageShell("home", p, cardList, Router.HandleNavigate)
end

-- ============================================================================
-- 页面4：悟道
-- ============================================================================
local function BuildDaoCard(dao)
    local isLocked = dao.locked
    local pct = math.floor(dao.progress / dao.maxProgress * 100)

    return Comp.BuildCardPanel(nil, {
        -- 标题行
        UI.Panel {
            width = "100%",
            flexDirection = "row",
            justifyContent = "space-between",
            alignItems = "center",
            children = {
                UI.Label {
                    text = dao.name,
                    fontSize = Theme.fontSize.subtitle,
                    fontWeight = "bold",
                    color = isLocked and Theme.colors.textSecondary or Theme.colors.textGold,
                },
                UI.Label {
                    text = isLocked and "未解锁" or (pct .. "%"),
                    fontSize = Theme.fontSize.small,
                    color = isLocked and Theme.colors.textSecondary or Theme.colors.gold,
                },
            },
        },
        -- 描述
        UI.Label {
            text = dao.desc,
            fontSize = Theme.fontSize.small,
            color = isLocked and { 100, 90, 75, 150 } or Theme.colors.textLight,
        },
        -- 奖励
        UI.Label {
            text = "悟透奖励: " .. dao.reward,
            fontSize = Theme.fontSize.small,
            color = isLocked and { 100, 90, 75, 150 } or Theme.colors.successLight,
        },
        -- 进度条
        not isLocked and UI.Panel {
            width = "100%",
            height = 8,
            borderRadius = 4,
            backgroundColor = { 50, 45, 35, 255 },
            borderColor = Theme.colors.borderGold,
            borderWidth = 1,
            overflow = "hidden",
            children = {
                UI.Panel {
                    width = tostring(pct) .. "%",
                    height = "100%",
                    borderRadius = 4,
                    backgroundColor = Theme.colors.gold,
                },
            },
        } or nil,
        -- 操作
        not isLocked and UI.Panel {
            width = "100%",
            flexDirection = "row",
            justifyContent = "flex-end",
            marginTop = 4,
            children = {
                Comp.BuildSecondaryButton("参悟", function()
                    local ok, msg = GameDao.DoMeditate(dao.name)
                    Toast.Show(msg, { variant = ok and "success" or "error" })
                    if ok then Router.HandleNavigate("home_dao") end
                end, { width = 80, fontSize = Theme.fontSize.small }),
            },
        } or nil,
    })
end

function M.BuildDao(payload)
    local p = GamePlayer.Get()
    if not p then return UI.Panel { width = "100%", height = "100%" } end
    local insights = p.daoInsights or {}

    local cardList = { BuildBackRow("悟道") }
    if #insights == 0 then
        cardList[#cardList + 1] = Comp.BuildCardPanel(nil, {
            UI.Label {
                text = "尚未开始参悟大道，修为提升后可解锁悟道。",
                fontSize = Theme.fontSize.body,
                color = Theme.colors.textSecondary,
            },
        })
    else
        for _, dao in ipairs(insights) do
            cardList[#cardList + 1] = BuildDaoCard(dao)
        end
    end

    return Comp.BuildPageShell("home", p, cardList, Router.HandleNavigate)
end

-- ============================================================================
-- 页面5：渡劫
-- ============================================================================
function M.BuildTribulation(payload)
    local p = GamePlayer.Get()
    if not p then return UI.Panel { width = "100%", height = "100%" } end

    local tier = p.tier or 1
    local sub  = p.sub or 1
    local canSub, subReason = GameCultivation.CanAdvanceSub()
    local canTrib, tribReason = GameCultivation.CanTribulation()

    -- 判断当前阶段：小境界突破 or 渡劫
    local isSubBreak = (sub < 3)  -- 非大成期 → 小境界突破
    local currentRealm = DataRealms.GetFullName(tier, sub)
    local nextRealm
    if isSubBreak then
        nextRealm = DataRealms.GetFullName(tier, sub + 1)
    elseif tier < 10 then
        nextRealm = DataRealms.GetFullName(tier + 1, 1)
    else
        nextRealm = "已至巅峰"
    end

    -- 渡劫条件
    local cultMet = (p.cultivation or 0) >= (p.cultivationMax or 0)
    local reqs = {
        { label = "修为", current = p.cultivation or 0, need = p.cultivationMax or 0, met = cultMet },
    }
    if not isSubBreak then
        reqs[#reqs + 1] = { label = "境界", current = DataRealms.GetFullName(tier, sub), need = DataRealms.GetFullName(tier, 3), met = (sub >= 3) }
    end

    local reqRows = {}
    for _, req in ipairs(reqs) do
        local valText
        if type(req.current) == "number" then
            valText = req.current .. " / " .. req.need
        else
            valText = tostring(req.current) .. " (" .. tostring(req.need) .. ")"
        end
        reqRows[#reqRows + 1] = UI.Panel {
            width = "100%",
            flexDirection = "row",
            justifyContent = "space-between",
            alignItems = "center",
            paddingVertical = 2,
            children = {
                UI.Label {
                    text = req.label,
                    fontSize = Theme.fontSize.body,
                    color = Theme.colors.textSecondary,
                },
                UI.Label {
                    text = valText,
                    fontSize = Theme.fontSize.body,
                    fontWeight = "bold",
                    color = req.met and Theme.colors.successLight or Theme.colors.dangerLight,
                },
            },
        }
    end

    -- 天劫信息（仅渡劫时显示）
    local tribInfoCard = nil
    local tribInfo = GameCultivation.GetTribulationInfo()
    if not isSubBreak and tribInfo then
        tribInfoCard = Comp.BuildCardPanel("天劫信息", {
            Comp.BuildStatRow("劫难类型", tribInfo.name, { valueColor = Theme.colors.dangerLight }),
            Comp.BuildStatRow("成功率", tribInfo.successRate .. "%", {
                valueColor = tribInfo.successRate >= 70 and Theme.colors.successLight or Theme.colors.warning,
            }),
            Comp.BuildStatRow("突破奖励", "全属性大幅提升", { valueColor = Theme.colors.gold }),
        })
    end

    -- 突破辅助丹药选择（仅渡劫时显示）
    local breakPills = {}
    local pillSelectCard = nil
    if not isSubBreak then
        breakPills = GameCultivation.GetBreakthroughPills()
    end
    -- 用模块级表记录选中状态（按丹药名 → bool）
    M._selectedPills = M._selectedPills or {}

    if not isSubBreak and #breakPills > 0 then
        local pillRows = {}
        local totalBonus = 0
        for _, bp in ipairs(breakPills) do
            local isOn = M._selectedPills[bp.name] or false
            if isOn then
                if bp.name == "筑基丹" then totalBonus = totalBonus + 20
                elseif bp.name == "破劫丹" then totalBonus = totalBonus + 30
                end
            end
            pillRows[#pillRows + 1] = UI.Panel {
                width = "100%",
                flexDirection = "row",
                justifyContent = "space-between",
                alignItems = "center",
                paddingVertical = 4,
                children = {
                    UI.Panel {
                        flexShrink = 1,
                        gap = 2,
                        children = {
                            UI.Label {
                                text = bp.name .. " x" .. bp.count,
                                fontSize = Theme.fontSize.body,
                                fontWeight = "bold",
                                color = Theme.colors.textLight,
                            },
                            UI.Label {
                                text = bp.effect,
                                fontSize = Theme.fontSize.tiny,
                                color = Theme.colors.successLight,
                            },
                        },
                    },
                    Comp.BuildSecondaryButton(isOn and "已选用" or "使用", function()
                        M._selectedPills[bp.name] = not M._selectedPills[bp.name]
                        Router.EnterState(Router.STATE_TRIBULATION)
                    end, {
                        width = 70,
                        fontSize = Theme.fontSize.small,
                        bg = isOn and Theme.colors.gold or nil,
                        textColor = isOn and Theme.colors.inkBlack or nil,
                    }),
                },
            }
        end
        if totalBonus > 0 and tribInfo then
            pillRows[#pillRows + 1] = UI.Panel {
                width = "100%",
                paddingTop = 4,
                borderTopWidth = 1,
                borderColor = Theme.colors.border,
                children = {
                    UI.Label {
                        text = "丹药加成后成功率: " .. math.min(100, tribInfo.successRate + totalBonus) .. "%",
                        fontSize = Theme.fontSize.small,
                        fontWeight = "bold",
                        color = Theme.colors.gold,
                    },
                },
            }
        end
        pillSelectCard = Comp.BuildCardPanel("突破辅助丹药", pillRows)
    end

    local allMet = isSubBreak and canSub or canTrib
    local btnText = isSubBreak and "突破" or "开始渡劫"
    if not allMet then btnText = "条件不足" end

    local contentChildren = {
        BuildBackRow(isSubBreak and "突破" or "渡劫"),

        -- 当前境界
        Comp.BuildCardPanel("境界突破", {
            UI.Panel {
                width = "100%",
                alignItems = "center",
                gap = 8,
                paddingVertical = 8,
                children = {
                    UI.Label {
                        text = currentRealm,
                        fontSize = Theme.fontSize.title,
                        fontWeight = "bold",
                        color = Theme.colors.textGold,
                    },
                    UI.Label {
                        text = "▼",
                        fontSize = Theme.fontSize.heading,
                        color = Theme.colors.gold,
                    },
                    UI.Label {
                        text = nextRealm,
                        fontSize = Theme.fontSize.title,
                        fontWeight = "bold",
                        color = Theme.colors.gold,
                    },
                },
            },
        }),

        -- 突破/渡劫条件
        Comp.BuildCardPanel(isSubBreak and "突破条件" or "渡劫条件", reqRows),

        -- 天劫信息
        tribInfoCard,

        -- 突破丹药选择
        pillSelectCard,

        -- 操作按钮
        UI.Panel {
            width = "100%",
            alignItems = "center",
            marginTop = 8,
            children = {
                Comp.BuildInkButton(btnText, function()
                    if isSubBreak then
                        if canSub then
                            local ok, msg = GameCultivation.AdvanceSub()
                            if msg then Toast.Show(msg, { variant = ok and "success" or "error" }) end
                            M._selectedPills = {}
                            Router.EnterState(Router.STATE_TRIBULATION)
                        else
                            Toast.Show(subReason or "突破条件不足", { variant = "error" })
                        end
                    else
                        if canTrib then
                            -- 收集选中的丹药名称列表
                            local pillNames = {}
                            for name, on in pairs(M._selectedPills or {}) do
                                if on then pillNames[#pillNames + 1] = name end
                            end
                            local ok, msg = GameCultivation.DoTribulation(
                                #pillNames > 0 and pillNames or nil
                            )
                            if msg then Toast.Show(msg, { variant = ok and "success" or "error" }) end
                            M._selectedPills = {}
                            Router.EnterState(Router.STATE_TRIBULATION)
                        else
                            Toast.Show(tribReason or "渡劫条件不足", { variant = "error" })
                        end
                    end
                end, { disabled = not allMet }),
            },
        },
    }

    return Comp.BuildPageShell("home", p, contentChildren, Router.HandleNavigate)
end

-- ============================================================================
-- 页面6：丹药
-- ============================================================================
local function BuildPillCard(pill)
    local isLocked = pill.locked
    local isEmpty = (pill.count <= 0) and not isLocked

    return Comp.BuildCardPanel(nil, {
        -- 标题行
        UI.Panel {
            width = "100%",
            flexDirection = "row",
            justifyContent = "space-between",
            alignItems = "center",
            children = {
                UI.Panel {
                    flexDirection = "row",
                    gap = 6,
                    alignItems = "center",
                    children = {
                        UI.Label {
                            text = pill.name,
                            fontSize = Theme.fontSize.subtitle,
                            fontWeight = "bold",
                            color = isLocked and Theme.colors.textSecondary or GetQualityColor(pill.quality),
                        },
                        UI.Label {
                            text = "[" .. pill.quality .. "]",
                            fontSize = Theme.fontSize.tiny,
                            color = GetQualityColor(pill.quality),
                        },
                    },
                },
                UI.Label {
                    text = isLocked and "未拥有" or ("x" .. pill.count),
                    fontSize = Theme.fontSize.subtitle,
                    fontWeight = "bold",
                    color = isLocked and Theme.colors.textSecondary
                        or (isEmpty and Theme.colors.dangerLight or Theme.colors.gold),
                },
            },
        },
        -- 描述
        UI.Label {
            text = pill.desc,
            fontSize = Theme.fontSize.small,
            color = isLocked and { 100, 90, 75, 150 } or Theme.colors.textLight,
        },
        -- 效果
        UI.Label {
            text = "效果: " .. pill.effect,
            fontSize = Theme.fontSize.small,
            color = isLocked and { 100, 90, 75, 150 } or Theme.colors.successLight,
        },
        -- 操作
        UI.Panel {
            width = "100%",
            flexDirection = "row",
            justifyContent = "flex-end",
            marginTop = 4,
            children = {
                (not isLocked and not isEmpty)
                    and Comp.BuildSecondaryButton("服用", function()
                        local ok, msg = GameItems.DoUsePill(pill.name)
                        Toast.Show(msg, { variant = ok and "success" or "error" })
                        if ok then Router.RebuildUI() end
                    end, { width = 80, fontSize = Theme.fontSize.small })
                    or UI.Label {
                        text = isLocked and "暂无来源" or "数量不足",
                        fontSize = Theme.fontSize.small,
                        color = Theme.colors.textSecondary,
                    },
            },
        },
    })
end

function M.BuildPill(payload)
    local p = GamePlayer.Get()
    if not p then return UI.Panel { width = "100%", height = "100%" } end
    local pills = p.pills or {}

    local cardList = { BuildBackRow("丹药") }
    if #pills == 0 then
        cardList[#cardList + 1] = Comp.BuildCardPanel(nil, {
            UI.Label {
                text = "暂无丹药，可前往坊市购买或炼丹获取。",
                fontSize = Theme.fontSize.body,
                color = Theme.colors.textSecondary,
            },
        })
    else
        for _, pill in ipairs(pills) do
            cardList[#cardList + 1] = BuildPillCard(pill)
        end
    end

    return Comp.BuildPageShell("home", p, cardList, Router.HandleNavigate)
end

return M
