-- ============================================================================
-- WeeklyGoal - 每周目标系统
-- Project Smith / P3-B4
--
-- 每周从目标池中随机选取 3 个目标，玩家完成后领取奖励。
-- 进度通过 EventBus 事件自动追踪，数据存入 GameState 的 plainData。
--
-- 使用方式:
--   local WeeklyGoal = require("Core.WeeklyGoal")
--   WeeklyGoal.Init()           -- 在 GameState.Load 回调后调用
--   WeeklyGoal.ClaimReward(idx) -- 领取已完成目标的奖励
--   WeeklyGoal.GetGoals()       -- 获取本周 3 个目标的状态
-- ============================================================================

local EventBus   = require("Core.EventBus")
local GameState  = require("Core.GameState")
local DataLoader = require("Config.DataLoader")

local WeeklyGoal = {}

-- ==================== 内部状态 ====================

--- 目标池（从 JSON 加载）
---@type table[]
local goalPool_ = {}

--- 本周选定的 3 个目标
---@type table[] { def, progress, claimed }
local activeGoals_ = {}

--- 本周起始时间戳（周一 00:00 UTC+8）
local weekStartTime_ = 0

--- 是否已初始化
local inited_ = false

-- ==================== 时间工具 ====================

--- 获取当前周一 00:00 的时间戳（UTC+8）
---@return number
local function GetWeekStartTimestamp()
    local now = os.time()
    -- os.date 返回本地时间（引擎运行在 UTC+8）
    local t = os.date("*t", now)
    -- Lua wday: 1=Sunday, 2=Monday, ..., 7=Saturday
    local daysSinceMonday = (t.wday - 2) % 7
    local mondayMidnight = now - daysSinceMonday * 86400 - t.hour * 3600 - t.min * 60 - t.sec
    return mondayMidnight
end

-- ==================== 目标选取 ====================

--- 按权重随机选取 N 个不重复目标
---@param pool table[] 目标池
---@param n number 选取数量
---@return table[] 选中的目标定义
local function WeightedSample(pool, n)
    if #pool <= n then
        local result = {}
        for i = 1, #pool do
            result[i] = pool[i]
        end
        return result
    end

    -- 复制一份避免修改原数组
    local candidates = {}
    for i = 1, #pool do
        candidates[i] = { def = pool[i], weight = pool[i].weight or 1 }
    end

    local result = {}
    for _ = 1, n do
        -- 计算总权重
        local totalWeight = 0
        for i = 1, #candidates do
            totalWeight = totalWeight + candidates[i].weight
        end
        if totalWeight <= 0 then break end

        -- 随机选一个
        local r = math.random() * totalWeight
        local acc = 0
        local chosenIdx = 1
        for i = 1, #candidates do
            acc = acc + candidates[i].weight
            if r <= acc then
                chosenIdx = i
                break
            end
        end

        result[#result + 1] = candidates[chosenIdx].def
        table.remove(candidates, chosenIdx)
    end

    return result
end

-- ==================== 存档读写 ====================

--- 从 GameState plainData 读取每周目标存档
---@return table|nil
local function LoadWeeklyData()
    -- plainData 中查找 weeklyGoals 字段
    -- GameState 没有直接暴露 plainData，我们通过专用接口
    return GameState.GetWeeklyGoals and GameState.GetWeeklyGoals() or nil
end

--- 保存每周目标数据到 GameState
local function SaveWeeklyData()
    local data = {
        weekStart = weekStartTime_,
        goals = {},
    }
    for i = 1, #activeGoals_ do
        local g = activeGoals_[i]
        data.goals[i] = {
            id = g.def.id,
            progress = g.progress,
            claimed = g.claimed,
        }
    end
    if GameState.SetWeeklyGoals then
        GameState.SetWeeklyGoals(data)
    end
end

-- ==================== 公共接口 ====================

--- 初始化每周目标系统（GameState 加载完毕后调用）
function WeeklyGoal.Init()
    if inited_ then return end

    -- 加载目标池
    goalPool_ = DataLoader.Load("Config/data/weekly_goals.json") or {}
    print("[WeeklyGoal] Goal pool loaded: " .. #goalPool_ .. " goals")

    -- 计算本周起始时间
    weekStartTime_ = GetWeekStartTimestamp()

    -- 尝试从存档恢复
    local saved = LoadWeeklyData()
    if saved and saved.weekStart == weekStartTime_ and saved.goals then
        -- 同一周，恢复进度
        activeGoals_ = {}
        for i = 1, #saved.goals do
            local sg = saved.goals[i]
            -- 找到对应的定义
            local def = nil
            for j = 1, #goalPool_ do
                if goalPool_[j].id == sg.id then
                    def = goalPool_[j]
                    break
                end
            end
            if def then
                activeGoals_[#activeGoals_ + 1] = {
                    def = def,
                    progress = sg.progress or 0,
                    claimed = sg.claimed or false,
                }
            end
        end
        print("[WeeklyGoal] Restored " .. #activeGoals_ .. " goals from save")
    else
        -- 新的一周，重新选取
        local selected = WeightedSample(goalPool_, 3)
        activeGoals_ = {}
        for i = 1, #selected do
            activeGoals_[i] = {
                def = selected[i],
                progress = 0,
                claimed = false,
            }
        end
        SaveWeeklyData()
        print("[WeeklyGoal] New week started, selected " .. #activeGoals_ .. " goals")
    end

    -- 注册事件监听
    WeeklyGoal._RegisterEvents()

    inited_ = true
end

--- 获取本周目标列表
---@return table[] { id, title, description, category, progress, target, completed, claimed, reward }
function WeeklyGoal.GetGoals()
    local result = {}
    for i = 1, #activeGoals_ do
        local g = activeGoals_[i]
        local target = g.def.condition.count or 1
        result[i] = {
            id = g.def.id,
            title = g.def.title,
            description = g.def.description,
            category = g.def.category,
            progress = g.progress,
            target = target,
            completed = g.progress >= target,
            claimed = g.claimed,
            reward = {
                coins = g.def.rewardCoins or 0,
                fame = g.def.rewardFame or 0,
                materials = g.def.rewardMaterials or {},
            },
        }
    end
    return result
end

--- 领取已完成目标的奖励
---@param goalIndex number 目标索引（1-based）
---@return boolean success
---@return string|nil errorMsg
function WeeklyGoal.ClaimReward(goalIndex)
    local g = activeGoals_[goalIndex]
    if not g then
        return false, "目标不存在"
    end

    local target = g.def.condition.count or 1
    if g.progress < target then
        return false, "目标尚未完成"
    end

    if g.claimed then
        return false, "奖励已领取"
    end

    -- 发放奖励
    local coins = g.def.rewardCoins or 0
    local fame = g.def.rewardFame or 0
    local materials = g.def.rewardMaterials or {}

    if coins > 0 then GameState.AddCoins(coins) end
    if fame > 0 then GameState.AddFame(fame) end
    for mat, count in pairs(materials) do
        GameState.AddMaterial(mat, count)
    end

    g.claimed = true
    SaveWeeklyData()

    EventBus.Emit("weekly_reward_claimed", {
        goalId = g.def.id,
        goalIndex = goalIndex,
        coins = coins,
        fame = fame,
        materials = materials,
    })

    print("[WeeklyGoal] Reward claimed: " .. g.def.title
        .. " (" .. coins .. " coins, " .. fame .. " fame)")

    return true
end

--- 获取本周剩余时间（秒）
---@return number
function WeeklyGoal.GetTimeRemaining()
    local weekEnd = weekStartTime_ + 7 * 86400
    local remaining = weekEnd - os.time()
    return math.max(0, remaining)
end

--- 格式化剩余时间为可读字符串
---@return string
function WeeklyGoal.GetTimeRemainingText()
    local sec = WeeklyGoal.GetTimeRemaining()
    local days = math.floor(sec / 86400)
    local hours = math.floor((sec % 86400) / 3600)
    if days > 0 then
        return days .. "天" .. hours .. "小时"
    elseif hours > 0 then
        local mins = math.floor((sec % 3600) / 60)
        return hours .. "小时" .. mins .. "分"
    else
        local mins = math.floor(sec / 60)
        return mins .. "分钟"
    end
end

--- 检查是否需要刷新（跨周）
---@return boolean
function WeeklyGoal.CheckRefresh()
    local currentWeekStart = GetWeekStartTimestamp()
    if currentWeekStart ~= weekStartTime_ then
        -- 跨周了，重新初始化
        inited_ = false
        WeeklyGoal.Init()
        return true
    end
    return false
end

-- ==================== 进度追踪（内部） ====================

--- 增加指定条件类型的进度
---@param condType string 条件类型
---@param amount number 增加量
---@param extra table|nil 额外匹配参数
local function IncrementProgress(condType, amount, extra)
    local changed = false
    for i = 1, #activeGoals_ do
        local g = activeGoals_[i]
        if g.claimed then goto continue end

        local cond = g.def.condition
        if cond.type ~= condType then goto continue end

        -- 额外条件匹配
        if extra then
            if cond.line and extra.line and cond.line ~= extra.line then
                goto continue
            end
            if cond.tier and extra.tier and extra.tier < cond.tier then
                goto continue
            end
        end

        local target = cond.count or 1
        if g.progress < target then
            g.progress = math.min(g.progress + amount, target)
            changed = true

            if g.progress >= target then
                EventBus.Emit("weekly_goal_completed", {
                    goalId = g.def.id,
                    goalIndex = i,
                    title = g.def.title,
                })
                print("[WeeklyGoal] Goal completed: " .. g.def.title)
            end
        end

        ::continue::
    end

    if changed then
        SaveWeeklyData()
    end
end

--- 注册 EventBus 事件监听
function WeeklyGoal._RegisterEvents()
    -- 订单完成 → orders_completed / weapon_line / modifier_completed
    EventBus.On("quality_calculated", function(data)
        -- 通用：完成订单计数
        IncrementProgress("orders_completed", 1)

        -- 品质等级目标
        if data.qualityTier and data.qualityTier.tier then
            IncrementProgress("quality_tier_min", 1, { tier = data.qualityTier.tier })
        end
    end)

    -- 奖励领取 → coins_earned / fame_earned / weapon_line
    EventBus.On("reward_collected", function(data)
        if data.coins and data.coins > 0 then
            IncrementProgress("coins_earned", data.coins)
        end
        if data.fame and data.fame > 0 then
            IncrementProgress("fame_earned", data.fame)
        end
        if data.weaponLine then
            IncrementProgress("weapon_line", 1, { line = data.weaponLine })
        end
    end)

    -- 全 Perfect 完成
    EventBus.On("all_steps_complete", function(data)
        if not data.scores then return end
        local allPerfect = true
        for i = 1, #data.scores do
            if data.scores[i].rating ~= "Perfect" then
                allPerfect = false
                break
            end
        end
        if allPerfect then
            IncrementProgress("perfect_count", 1)
        end
    end)

    -- 带修饰符的订单完成追踪
    EventBus.On("order_completed_with_modifier", function(data)
        IncrementProgress("modifier_completed", 1)
    end)
end

return WeeklyGoal
