-- ============================================================================
-- Timer - 定时器系统
-- Project Smith / P1-A6
--
-- 支持一次性延迟和循环定时器，由 main.lua 的 HandleUpdate 驱动。
-- ============================================================================

local Timer = {}

---@class TimerEntry
---@field remaining number
---@field interval number|nil
---@field callback function
---@field repeating boolean
---@field count number|nil
---@field fired number

---@type table<number, TimerEntry>
local timers_ = {}
local nextId_ = 0

--- 延迟执行一次
---@param delay number 延迟秒数
---@param callback function 回调函数
---@return number id 定时器 ID，可用于 Cancel
function Timer.After(delay, callback)
    nextId_ = nextId_ + 1
    timers_[nextId_] = {
        remaining = delay,
        callback = callback,
        repeating = false,
    }
    return nextId_
end

--- 循环执行
---@param interval number 间隔秒数
---@param callback function 回调函数
---@param count number|nil 执行次数，nil 表示无限
---@return number id 定时器 ID
function Timer.Every(interval, callback, count)
    nextId_ = nextId_ + 1
    timers_[nextId_] = {
        remaining = interval,
        interval = interval,
        callback = callback,
        repeating = true,
        count = count,
        fired = 0,
    }
    return nextId_
end

--- 取消定时器
---@param id number
function Timer.Cancel(id)
    timers_[id] = nil
end

--- 每帧更新（由 main.lua 调用）
---@param dt number 帧间隔
function Timer.Update(dt)
    local toRemove = {}
    for id, t in pairs(timers_) do
        t.remaining = t.remaining - dt
        if t.remaining <= 0 then
            local ok, err = pcall(t.callback)
            if not ok then
                print("[Timer] Error in timer " .. id .. ": " .. tostring(err))
            end
            if t.repeating then
                t.fired = (t.fired or 0) + 1
                if t.count and t.fired >= t.count then
                    toRemove[#toRemove + 1] = id
                else
                    t.remaining = t.remaining + t.interval
                end
            else
                toRemove[#toRemove + 1] = id
            end
        end
    end
    for i = 1, #toRemove do
        timers_[toRemove[i]] = nil
    end
end

--- 清空所有定时器
function Timer.Clear()
    timers_ = {}
end

return Timer
