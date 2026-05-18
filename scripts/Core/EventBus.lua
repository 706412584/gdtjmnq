-- ============================================================================
-- EventBus - 发布-订阅事件总线
-- Project Smith / P1-A2
-- ============================================================================

local EventBus = {}

---@type table<string, function[]>
local listeners_ = {}

--- 订阅事件
---@param event string 事件名
---@param callback function 回调函数(data)
---@return function unsubscribe 取消订阅函数
function EventBus.On(event, callback)
    if not listeners_[event] then
        listeners_[event] = {}
    end
    table.insert(listeners_[event], callback)
    -- 返回取消订阅函数
    return function()
        EventBus.Off(event, callback)
    end
end

--- 取消订阅
---@param event string
---@param callback function
function EventBus.Off(event, callback)
    local list = listeners_[event]
    if not list then return end
    for i = #list, 1, -1 do
        if list[i] == callback then
            table.remove(list, i)
            break
        end
    end
end

--- 发布事件
---@param event string
---@param data any 事件数据
function EventBus.Emit(event, data)
    local list = listeners_[event]
    if not list then return end
    -- 复制列表，防止回调中修改列表导致迭代异常
    local copy = {}
    for i = 1, #list do
        copy[i] = list[i]
    end
    for i = 1, #copy do
        local ok, err = pcall(copy[i], data)
        if not ok then
            print("[EventBus] Error in '" .. event .. "' handler: " .. tostring(err))
        end
    end
end

--- 清空所有监听器
function EventBus.Clear()
    listeners_ = {}
end

--- 获取某事件的监听器数量（调试用）
---@param event string
---@return number
function EventBus.ListenerCount(event)
    local list = listeners_[event]
    return list and #list or 0
end

return EventBus
