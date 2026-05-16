-- ============================================================================
-- 《问道长生》洞府主页（打坐修炼 + 灵气粒子 + 横向功能栏）
-- ============================================================================

local UI = require("urhox-libs/UI")
local Theme = require("ui_theme")
local Comp = require("ui_components")
local Router = require("ui_router")
local GamePlayer = require("game_player")
local GameCultivation = require("game_cultivation")
local Settings = require("ui_settings")
local Toast = require("ui_toast")

local NVG = require("nvg_manager")
local RedDot = require("ui_red_dot")

local M = {}

-- 新手礼包是否已触发（避免重复）
local newbieGiftShown_ = false

-- ============================================================================
-- 灵气粒子系统（NanoVG）—— 向中心聚拢效果（通过 nvg_manager 调度）
-- ============================================================================
local particles = {}
local MAX_PARTICLES = 30
local particleInited = false
local screenW, screenH = 720, 1280
-- 聚拢目标（打坐角色中心，约屏幕上方 1/3 处）
local targetX, targetY = 360, 340

-- 修炼状态文本轮换
local meditateTexts = { "吐纳灵气中…", "修炼中…", "凝神静修中…", "感悟天道中…" }
local meditateTextIdx = 1
local textTimer = 0

-- 初始化单个粒子
local function CreateParticle()
    local p = {}
    -- 从屏幕边缘随机位置生成
    local side = math.random(1, 4)
    if side == 1 then     -- 上方
        p.x = math.random() * screenW
        p.y = -10
    elseif side == 2 then -- 下方
        p.x = math.random() * screenW
        p.y = screenH * 0.7 + math.random() * (screenH * 0.3)
    elseif side == 3 then -- 左侧
        p.x = -10
        p.y = math.random() * screenH * 0.6
    else                  -- 右侧
        p.x = screenW + 10
        p.y = math.random() * screenH * 0.6
    end
    p.size = math.random() * 2.5 + 1.0              -- 1.0~3.5
    p.alpha = math.random() * 0.3 + 0.1             -- 0.1~0.4
    p.alphaSpeed = (math.random() - 0.5) * 0.2
    p.lifetime = math.random() * 5 + 4              -- 4~9 秒
    p.age = 0
    p.speed = math.random() * 40 + 30               -- 30~70 px/s
    -- 方向指向打坐角色中心（带随机偏移增加自然感）
    local dx = targetX + (math.random() - 0.5) * 60 - p.x
    local dy = targetY + (math.random() - 0.5) * 60 - p.y
    local dist = math.sqrt(dx * dx + dy * dy)
    if dist < 1 then dist = 1 end
    p.vx = dx / dist * p.speed
    p.vy = dy / dist * p.speed
    -- 颜色变体
    local ct = math.random(1, 3)
    if ct == 1 then
        p.r, p.g, p.b = 200, 168, 85    -- 金色灵气
    elseif ct == 2 then
        p.r, p.g, p.b = 120, 180, 220   -- 青蓝灵气
    else
        p.r, p.g, p.b = 220, 215, 200   -- 白色灵气
    end
    return p
end

-- 初始化粒子池
local function InitParticles()
    if particleInited then return end
    particleInited = true
    screenW = graphics:GetWidth() / graphics:GetDPR()
    screenH = graphics:GetHeight() / graphics:GetDPR()
    targetX = screenW * 0.5
    targetY = screenH * 0.28
    for i = 1, MAX_PARTICLES do
        particles[i] = CreateParticle()
        particles[i].age = math.random() * particles[i].lifetime * 0.5
    end
end

-- 更新粒子
local function UpdateParticles(dt)
    for i, p in ipairs(particles) do
        p.age = p.age + dt
        p.x = p.x + p.vx * dt
        p.y = p.y + p.vy * dt
        p.alpha = p.alpha + p.alphaSpeed * dt
        if p.alpha > 0.45 then p.alpha = 0.45; p.alphaSpeed = -math.abs(p.alphaSpeed) end
        if p.alpha < 0.05 then p.alpha = 0.05; p.alphaSpeed = math.abs(p.alphaSpeed) end

        -- 接近中心时加速消散
        local dx = p.x - targetX
        local dy = p.y - targetY
        local dist = math.sqrt(dx * dx + dy * dy)
        if dist < 40 then
            p.alpha = p.alpha * (dist / 40)
        end

        -- 超出生命或到达中心则重置
        if p.age >= p.lifetime or dist < 15 then
            particles[i] = CreateParticle()
        end
    end

    -- 修炼文本轮换
    textTimer = textTimer + dt
    if textTimer >= 4.0 then
        textTimer = 0
        meditateTextIdx = meditateTextIdx % #meditateTexts + 1
    end
end

-- 渲染粒子（ctx 由 nvg_manager 传入）
local function RenderParticles(ctx)
    for _, p in ipairs(particles) do
        local fadeAlpha = p.alpha
        local lifeRatio = p.age / p.lifetime
        if lifeRatio < 0.15 then
            fadeAlpha = fadeAlpha * (lifeRatio / 0.15)
        end
        if lifeRatio > 0.8 then
            fadeAlpha = fadeAlpha * (1.0 - (lifeRatio - 0.8) / 0.2)
        end
        local a = math.floor(fadeAlpha * 255)
        if a < 2 then goto continue end

        local glowSize = p.size * 3.0
        local paint = nvgRadialGradient(ctx,
            p.x, p.y, p.size * 0.3, glowSize,
            nvgRGBA(p.r, p.g, p.b, math.floor(a * 0.35)),
            nvgRGBA(p.r, p.g, p.b, 0))
        nvgBeginPath(ctx)
        nvgCircle(ctx, p.x, p.y, glowSize)
        nvgFillPaint(ctx, paint)
        nvgFill(ctx)

        nvgBeginPath(ctx)
        nvgCircle(ctx, p.x, p.y, p.size * 0.5)
        nvgFillColor(ctx, nvgRGBA(p.r, p.g, p.b, a))
        nvgFill(ctx)

        ::continue::
    end
end

-- ============================================================================
-- 启停粒子系统（通过 nvg_manager）
-- ============================================================================
local homeRegistered = false

function M.StartParticles()
    if homeRegistered then return end
    homeRegistered = true
    NVG.Register("home", RenderParticles, function(dt)
        InitParticles()
        UpdateParticles(dt)
    end)
end

function M.StopParticles()
    if not homeRegistered then return end
    homeRegistered = false
    NVG.Unregister("home")
end

-- ============================================================================
-- 洞府功能按钮数据（角色自身相关）
-- ============================================================================
local homeFeatures = {
    { name = "属性",  icon = Theme.images.iconHome,    desc = "查看角色属性", state = Router.STATE_ATTR,        dotKey = RedDot.KEYS.HOME_ATTR },
    { name = "功法",  icon = Theme.images.iconExplore,  desc = "修炼功法",    state = Router.STATE_SKILL,       dotKey = RedDot.KEYS.HOME_SKILL },
    { name = "法宝",  icon = Theme.images.iconAlchemy,  desc = "法宝炼化",    state = Router.STATE_ARTIFACT,    dotKey = RedDot.KEYS.HOME_ARTIFACT },
    { name = "悟道",  icon = Theme.images.iconSect,     desc = "参悟大道",    state = Router.STATE_DAO,         dotKey = RedDot.KEYS.HOME_DAO },
    { name = "渡劫",  icon = Theme.images.iconTrial,    desc = "突破境界",    state = Router.STATE_TRIBULATION, dotKey = RedDot.KEYS.HOME_TRIBULATION },
    { name = "丹药",  icon = Theme.images.iconBag,      desc = "服用丹药",    state = Router.STATE_PILL,        dotKey = RedDot.KEYS.HOME_PILL },
}

-- ============================================================================
-- 构建单个功能按钮
-- ============================================================================
local function BuildFeatureBtn(feat)
    local btn = UI.Panel {
        width = 72,
        height = 80,
        alignItems = "center",
        justifyContent = "center",
        gap = 4,
        borderRadius = Theme.radius.md,
        backgroundColor = { 35, 30, 25, 160 },
        borderColor = Theme.colors.borderGold,
        borderWidth = 1,
        cursor = "pointer",
        onClick = function(self)
            if feat.state then
                Router.EnterState(feat.state)
            end
        end,
        children = {
            UI.Panel {
                width = 32,
                height = 32,
                backgroundImage = feat.icon,
                backgroundFit = "contain",
                imageTint = Theme.colors.gold,
            },
            UI.Label {
                text = feat.name,
                fontSize = 11,
                fontWeight = "bold",
                color = Theme.colors.textGold,
            },
        },
    }
    -- 红点包装
    if feat.dotKey then
        return Comp.WithRedDot(btn, feat.dotKey)
    end
    return btn
end

-- ============================================================================
-- 构建页面
-- ============================================================================
function M.Build(payload)
    local p = GamePlayer.Get()
    if not p then
        print("[Home] 警告: 玩家数据为空")
        return UI.Panel { width = "100%", height = "100%" }
    end
    payload = payload or {}

    -- 测试红点：属性按钮显示红点
    RedDot.Show(RedDot.KEYS.HOME_ATTR)

    -- 新手礼包 Toast（首次进入主页时触发）
    if payload.newPlayer and not newbieGiftShown_ then
        newbieGiftShown_ = true
        -- 延迟显示新手礼包 Toast 序列
        Toast.ShowSequence({
            "获得大能传承: 灵石 x500",
            "获得大能传承: 仙石 x10",
            "获得大能传承: 基础吐纳功法 x1",
            "获得大能传承: 新手法宝 碎星剑 x1",
            "获得大能传承: 筑基丹 x1",
        }, 0.5)
    end

    -- 启动修炼系统 + 灵气粒子 + 导航栏粒子
    if not GameCultivation.IsRunning() then
        GameCultivation.ApplyOfflineGains()
        GameCultivation.Start()
    end
    M.StartParticles()
    Comp.StartNavParticles()

    -- 修为进度百分比
    local cultPct = math.floor(p.cultivation / p.cultivationMax * 100)

    -- 横向功能按钮列表
    local featureBtns = {}
    for _, feat in ipairs(homeFeatures) do
        featureBtns[#featureBtns + 1] = BuildFeatureBtn(feat)
    end

    return UI.Panel {
        width = "100%",
        height = "100%",
        backgroundImage = Theme.images.bgHome,
        backgroundFit = "cover",
        children = {
            -- 背景遮罩
            UI.Panel {
                position = "absolute",
                top = 0, left = 0, right = 0, bottom = 0,
                backgroundColor = { 15, 12, 10, 120 },
            },

            -- 顶部状态栏
            Comp.BuildTopBar(p),

            -- 中间内容区
            UI.Panel {
                width = "100%",
                flexGrow = 1,
                flexBasis = 0,
                alignItems = "center",
                children = {
                    -- ========== 打坐角色区域 ==========
                    UI.Panel {
                        width = "100%",
                        alignItems = "center",
                        marginTop = 8,
                        children = {
                            -- 打坐图片（根据性别+头像索引选择对应变体）
                            UI.Panel {
                                width = 220,
                                height = 220,
                                backgroundImage = (Theme.meditateChars[p.gender] or Theme.meditateChars["男"])[p.avatarIndex or 1]
                                    or (p.gender == "女" and Theme.images.meditateCharF or Theme.images.meditateChar),
                                backgroundFit = "contain",
                            },
                            -- 修炼状态文字
                            UI.Label {
                                text = meditateTexts[meditateTextIdx],
                                fontSize = Theme.fontSize.body,
                                color = Theme.colors.accent,
                                marginTop = 4,
                            },
                            -- 修为进度条
                            UI.Panel {
                                width = "70%",
                                marginTop = 8,
                                gap = 4,
                                children = {
                                    UI.Panel {
                                        width = "100%",
                                        flexDirection = "row",
                                        justifyContent = "space-between",
                                        children = {
                                            UI.Label {
                                                text = "修为 " .. p.realmName,
                                                fontSize = Theme.fontSize.small,
                                                color = Theme.colors.textGold,
                                            },
                                            UI.Label {
                                                text = p.cultivation .. "/" .. p.cultivationMax .. "  (" .. cultPct .. "%)",
                                                fontSize = Theme.fontSize.small,
                                                color = Theme.colors.textLight,
                                            },
                                        },
                                    },
                                    UI.Panel {
                                        width = "100%",
                                        height = 10,
                                        borderRadius = 5,
                                        backgroundColor = { 50, 45, 35, 255 },
                                        borderColor = Theme.colors.borderGold,
                                        borderWidth = 1,
                                        overflow = "hidden",
                                        children = {
                                            UI.Panel {
                                                width = tostring(cultPct) .. "%",
                                                height = "100%",
                                                borderRadius = 5,
                                                backgroundColor = Theme.colors.gold,
                                            },
                                        },
                                    },
                                },
                            },
                        },
                    },

                    -- ========== 修行日志（紧凑版） ==========
                    UI.Panel {
                        width = "90%",
                        marginTop = 12,
                        backgroundColor = { 25, 22, 18, 180 },
                        borderRadius = Theme.radius.md,
                        borderColor = Theme.colors.border,
                        borderWidth = 1,
                        padding = Theme.spacing.sm,
                        children = {
                            UI.Panel {
                                width = "100%",
                                height = 100,
                                children = {
                                    UI.ScrollView {
                                        width = "100%",
                                        height = "100%",
                                        scrollY = true,
                                        showScrollbar = false,
                                        children = {
                                            UI.Panel {
                                                width = "100%",
                                                gap = 2,
                                                children = (function()
                                                    local logs = {}
                                                    for i, line in ipairs(p.cultivationLogs or {}) do
                                                        logs[i] = Comp.BuildColorText(line, {
                                                            fontSize = Theme.fontSize.tiny,
                                                            color = Theme.colors.textLight,
                                                        })
                                                    end
                                                    return logs
                                                end)(),
                                            },
                                        },
                                    },
                                },
                            },
                        },
                    },

                    -- 弹性留白
                    UI.Panel { flexGrow = 1 },

                    -- ========== 横向功能按钮栏 ==========
                    UI.Panel {
                        width = "100%",
                        paddingHorizontal = 8,
                        marginBottom = 4,
                        children = {
                            UI.ScrollView {
                                width = "100%",
                                height = 90,
                                scrollX = true,
                                scrollY = false,
                                showScrollbar = false,
                                children = {
                                    UI.Panel {
                                        flexDirection = "row",
                                        gap = 8,
                                        paddingHorizontal = 4,
                                        paddingVertical = 4,
                                        children = featureBtns,
                                    },
                                },
                            },
                        },
                    },
                },
            },

            -- 聊天动态框
            Comp.BuildChatTicker(function()
                Router.EnterState(Router.STATE_CHAT)
            end),

            -- 底部导航
            Comp.BuildBottomNav("home", Router.HandleNavigate),

            -- 设置弹窗容器（叠在最上层）
            (function()
                local vis = Settings.IsVisible()
                local overlay = UI.Panel {
                    position = "absolute",
                    top = 0, left = 0, right = 0, bottom = 0,
                    pointerEvents = vis and "auto" or "none",
                    children = vis and {
                        Settings.Build(function() Settings.Hide() end),
                    } or {},
                }
                Settings.BindOverlay(overlay)
                return overlay
            end)(),
        },
    }
end

return M
