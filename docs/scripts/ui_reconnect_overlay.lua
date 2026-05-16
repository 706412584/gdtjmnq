-- ============================================================================
-- 《问道长生》断线重连遮罩
-- NanoVG 绘制全屏遮罩 + 经典圆点旋转加载动画
-- 阻止断线期间误操作 UI
-- ============================================================================

local UI  = require("urhox-libs/UI")
local NVG = require("nvg_manager")
local Theme = require("ui_theme")

local M = {}

-- ============================================================================
-- 状态
-- ============================================================================

local active_     = false   -- 是否激活
local elapsed_    = 0       -- 动画累计时间
local container_  = nil     -- UI 遮罩容器（拦截点击）
local fadeAlpha_  = 0       -- 渐入透明度 0→1

-- 配置
local DOT_COUNT   = 10      -- 圆点数量
local DOT_RADIUS  = 5       -- 单个圆点半径
local RING_RADIUS = 28      -- 环形半径
local FADE_SPEED  = 3.0     -- 渐入速度

-- ============================================================================
-- 开始显示遮罩
-- ============================================================================
function M.Show()
    if active_ then return end
    active_ = true
    elapsed_ = 0
    fadeAlpha_ = 0

    -- 注册 NanoVG 渲染回调
    NVG.Register("reconnect_overlay", M.Render, M.Update)

    -- 重建 UI 容器来拦截点击
    RebuildContainer()
    print("[ReconnectOverlay] 断线遮罩已显示")
end

-- ============================================================================
-- 隐藏遮罩
-- ============================================================================
function M.Hide()
    if not active_ then return end
    active_ = false
    elapsed_ = 0
    fadeAlpha_ = 0

    -- 注销 NanoVG 渲染
    NVG.Unregister("reconnect_overlay")

    -- 清空 UI 容器
    if container_ then
        container_:ClearChildren()
    end
    print("[ReconnectOverlay] 断线遮罩已隐藏")
end

-- ============================================================================
-- 是否激活
-- ============================================================================
function M.IsActive()
    return active_
end

-- ============================================================================
-- NanoVG 渲染：圆点旋转加载动画
-- ============================================================================
function M.Render(ctx)
    if not active_ then return end

    local dpr = graphics:GetDPR()
    local sw = graphics:GetWidth() / dpr
    local sh = graphics:GetHeight() / dpr
    local alpha = math.min(fadeAlpha_, 1.0)

    -- 半透明黑色背景
    nvgBeginPath(ctx)
    nvgRect(ctx, 0, 0, sw, sh)
    nvgFillColor(ctx, nvgRGBA(0, 0, 0, math.floor(160 * alpha)))
    nvgFill(ctx)

    -- 居中偏上的位置
    local cx = sw * 0.5
    local cy = sh * 0.45

    -- 绘制圆点环形
    for i = 0, DOT_COUNT - 1 do
        local angle = (i / DOT_COUNT) * math.pi * 2 - math.pi * 0.5
        -- 旋转偏移
        local rotOffset = elapsed_ * 2.5  -- 旋转速度
        angle = angle + rotOffset

        local dx = cx + math.cos(angle) * RING_RADIUS
        local dy = cy + math.sin(angle) * RING_RADIUS

        -- 每个点的透明度：尾部淡出效果
        local dotAlpha = ((DOT_COUNT - i) / DOT_COUNT)
        dotAlpha = dotAlpha * dotAlpha  -- 二次衰减更自然
        local a = math.floor(255 * dotAlpha * alpha)

        nvgBeginPath(ctx)
        nvgCircle(ctx, dx, dy, DOT_RADIUS * (0.5 + 0.5 * dotAlpha))
        nvgFillColor(ctx, nvgRGBA(200, 170, 80, a))
        nvgFill(ctx)
    end

    -- 文字提示
    nvgFontFace(ctx, "sans")
    nvgFontSize(ctx, 16)
    nvgTextAlign(ctx, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
    nvgFillColor(ctx, nvgRGBA(200, 190, 160, math.floor(200 * alpha)))
    nvgText(ctx, cx, cy + RING_RADIUS + 20, "正在重新连接...")
end

-- ============================================================================
-- 每帧更新
-- ============================================================================
function M.Update(dt)
    if not active_ then return end
    elapsed_ = elapsed_ + dt
    fadeAlpha_ = fadeAlpha_ + dt * FADE_SPEED
    if fadeAlpha_ > 1.0 then fadeAlpha_ = 1.0 end
end

-- ============================================================================
-- UI 遮罩容器（拦截所有点击事件）
-- ============================================================================
function RebuildContainer()
    if not container_ then return end
    container_:ClearChildren()
    if not active_ then return end

    -- 全屏透明面板拦截触摸/点击
    local blocker = UI.Panel {
        position = "absolute",
        left = 0, right = 0, top = 0, bottom = 0,
        pointerEvents = "auto",  -- 拦截所有点击
        backgroundColor = { 0, 0, 0, 1 },  -- 几乎透明但可点击
    }
    container_:AddChild(blocker)
end

-- ============================================================================
-- 获取容器（由 overlay provider 调用）
-- ============================================================================
function M.GetContainer()
    container_ = UI.Panel {
        position = "absolute",
        left = 0, right = 0, top = 0, bottom = 0,
        pointerEvents = "box-none",
    }
    -- 如果已激活，立即添加拦截层
    if active_ then
        RebuildContainer()
    end
    return container_
end

return M
