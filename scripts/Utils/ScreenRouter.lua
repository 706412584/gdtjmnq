-- ============================================================================
-- ScreenRouter - 界面切换路由
-- Project Smith / P1-A1
--
-- 管理 Screen 模块的注册、切换和生命周期。
-- 每个 Screen 模块需导出:
--   Create(container, params) -> screen  构建 UI 并返回 screen 控制器
--   screen.Update(dt)                    可选，每帧更新
--   screen.Destroy()                     可选，清理资源
-- ============================================================================

local ScreenRouter = {}

---@type table<string, table> 已注册的 Screen 模块 { name = module }
local screens_ = {}

---@type table|nil 当前 Screen 实例
local currentScreen_ = nil

---@type string 当前 Screen 名称
local currentName_ = ""

---@type table|nil UI 容器（Panel）
local contentContainer_ = nil

---@type table|nil EventBus 引用
local eventBus_ = nil

--- 初始化路由
---@param container table UI.Panel 容器
---@param eventBus table EventBus 模块
function ScreenRouter.Init(container, eventBus)
    contentContainer_ = container
    eventBus_ = eventBus
end

--- 注册一个 Screen 模块
---@param name string 唯一名称
---@param screenModule table { Create, Destroy? }
function ScreenRouter.Register(name, screenModule)
    screens_[name] = screenModule
end

--- 切换到指定 Screen
---@param name string 目标 Screen 名称
---@param params table|nil 传递给 Screen.Create 的参数
function ScreenRouter.GoTo(name, params)
    if name == currentName_ then return end

    -- 销毁当前 Screen
    if currentScreen_ then
        if currentScreen_.Destroy then
            local ok, err = pcall(currentScreen_.Destroy, currentScreen_)
            if not ok then
                print("[ScreenRouter] Error destroying '" .. currentName_ .. "': " .. tostring(err))
            end
        end
        currentScreen_ = nil
    end

    -- 清空容器
    if contentContainer_ then
        contentContainer_:ClearChildren()
    end

    -- 查找目标 Screen 模块
    local screenModule = screens_[name]
    if not screenModule then
        print("[ScreenRouter] Screen not found: " .. name)
        return
    end

    -- 记录导航
    local prevName = currentName_
    currentName_ = name

    -- 创建新 Screen
    local ok, result = pcall(screenModule.Create, contentContainer_, params)
    if not ok then
        print("[ScreenRouter] Error creating '" .. name .. "': " .. tostring(result))
        return
    end
    currentScreen_ = result

    -- 发布导航事件
    if eventBus_ then
        eventBus_.Emit("screen_change", { from = prevName, to = name })
    end

    print("[ScreenRouter] " .. (prevName ~= "" and (prevName .. " -> ") or "") .. name)
end

--- 检查 Screen 是否已注册
---@param name string
---@return boolean
function ScreenRouter.Has(name)
    return screens_[name] ~= nil
end

--- 获取当前 Screen 名称和实例
---@return string name
---@return table|nil screen
function ScreenRouter.GetCurrent()
    return currentName_, currentScreen_
end

--- 每帧更新当前 Screen
---@param dt number
function ScreenRouter.Update(dt)
    if currentScreen_ and currentScreen_.Update then
        currentScreen_.Update(dt)
    end
end

return ScreenRouter
