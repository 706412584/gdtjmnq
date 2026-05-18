-- ============================================================================
-- Tween - 补间动画系统
-- Project Smith / P1-A6
--
-- 对 table 字段做数值插值动画，由 main.lua 的 HandleUpdate 驱动。
-- ============================================================================

local Tween = {}

-- ==================== 缓动函数 ====================

local Easing = {}

function Easing.linear(t) return t end

function Easing.easeInQuad(t) return t * t end

function Easing.easeOutQuad(t) return t * (2 - t) end

function Easing.easeInOutQuad(t)
    if t < 0.5 then return 2 * t * t end
    return -1 + (4 - 2 * t) * t
end

function Easing.easeOutCubic(t)
    local t1 = t - 1
    return t1 * t1 * t1 + 1
end

function Easing.easeInOutCubic(t)
    if t < 0.5 then return 4 * t * t * t end
    local t1 = 2 * t - 2
    return 0.5 * t1 * t1 * t1 + 1
end

function Easing.easeOutBack(t)
    local c1 = 1.70158
    local c3 = c1 + 1
    return 1 + c3 * (t - 1) ^ 3 + c1 * (t - 1) ^ 2
end

function Easing.easeOutElastic(t)
    if t == 0 or t == 1 then return t end
    return 2 ^ (-10 * t) * math.sin((t * 10 - 0.75) * (2 * math.pi / 3)) + 1
end

Tween.Easing = Easing

-- ==================== 补间管理 ====================

---@class TweenEntry
---@field target table
---@field props table<string, number>
---@field startValues table<string, number>
---@field duration number
---@field elapsed number
---@field easing function
---@field onComplete function|nil

---@type table<number, TweenEntry>
local tweens_ = {}
local nextId_ = 0

--- 创建补间动画
---@param target table 目标 table（会直接修改其字段）
---@param props table<string, number> 目标属性值 { fieldName = endValue }
---@param duration number 动画时长（秒）
---@param easing function|nil 缓动函数，默认 linear
---@param onComplete function|nil 完成回调
---@return number id 补间 ID，可用于 Cancel
function Tween.To(target, props, duration, easing, onComplete)
    nextId_ = nextId_ + 1
    local startValues = {}
    for k, _ in pairs(props) do
        startValues[k] = target[k] or 0
    end
    tweens_[nextId_] = {
        target = target,
        props = props,
        startValues = startValues,
        duration = duration,
        elapsed = 0,
        easing = easing or Easing.linear,
        onComplete = onComplete,
    }
    return nextId_
end

--- 取消补间
---@param id number
function Tween.Cancel(id)
    tweens_[id] = nil
end

--- 每帧更新（由 main.lua 调用）
---@param dt number
function Tween.Update(dt)
    local toRemove = {}
    for id, tw in pairs(tweens_) do
        tw.elapsed = tw.elapsed + dt
        local t = math.min(tw.elapsed / tw.duration, 1.0)
        local easedT = tw.easing(t)
        for k, endVal in pairs(tw.props) do
            local startVal = tw.startValues[k]
            tw.target[k] = startVal + (endVal - startVal) * easedT
        end
        if t >= 1.0 then
            toRemove[#toRemove + 1] = id
            if tw.onComplete then
                local ok, err = pcall(tw.onComplete)
                if not ok then
                    print("[Tween] Error in onComplete: " .. tostring(err))
                end
            end
        end
    end
    for i = 1, #toRemove do
        tweens_[toRemove[i]] = nil
    end
end

--- 清空所有补间
function Tween.Clear()
    tweens_ = {}
end

return Tween
