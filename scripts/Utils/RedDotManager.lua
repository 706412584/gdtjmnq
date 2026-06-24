-- ============================================================================
-- RedDotManager - 集中式红点状态管理
-- Project Smith
--
-- 职责:
--   1. 定义各红点 key 的判定函数（纯计算，无副作用）
--   2. 事件驱动：监听 GameState/Story 事件 → 自动重判 → 通知 UI 刷新
--   3. 消除逻辑：进入对应界面时 Dismiss(key) 清除一次性红点
--   4. 对外接口：Check(key)→bool, OnChange(cb)→unsub, Dismiss(key)
--
-- 红点 Key 定义:
--   "story"        — 有待展示的剧情
--   "upgrade"      — 至少一处设施可升级（铜钱+声望均足）
--   "specialOrder" — 有好感解锁的专属订单可接（已达门槛且未完成）
--   "codex"        — 有未查看的新解锁图鉴（武器 / 结局）
--   "shop"         — 商店折扣已生效（本会话首次提示）
--   "relationship" — 有角色达到新解锁等级（本会话首次提示）
-- ============================================================================

local EventBus            = require("Core.EventBus")
local GameState           = require("Core.GameState")
local FacilityConfig      = require("Config.FacilityConfig")
local OrderConfig         = require("Config.OrderConfig")
local StoryManager        = require("Story.StoryManager")
local RelationshipTracker = require("Story.RelationshipTracker")

local RedDotManager = {}

-- ============================================================================
-- 内部状态
-- ============================================================================

--- 上一次各 key 的状态快照（用于判定变化、发出通知）
---@type table<string, boolean>
local lastState_ = {}

--- 已消除的 key 集合（会话级，不持久化）
---@type table<string, boolean>
local dismissed_ = {}

--- 变化回调列表
---@type function[]
local listeners_ = {}

--- 已初始化标记
local inited_ = false

--- 上次图鉴查看时的武器+结局数量（会话级）
local lastCodexCount_ = -1  -- -1 表示尚未记录（首次进 codex 前，有新解锁就提示）

-- ============================================================================
-- 判定函数（每个红点 key 的条件）
-- ============================================================================

local CHECKERS = {}

--- story: 有待展示的剧情节点
CHECKERS.story = function()
    return StoryManager.HasPendingStory()
end

--- upgrade: 至少一处设施可用当前铜钱+声望升级
CHECKERS.upgrade = function()
    local coins = GameState.GetCoins()
    local fame = GameState.GetFame()
    local allIds = FacilityConfig.GetAllIds()
    for i = 1, #allIds do
        local fId = allIds[i]
        local lv = GameState.GetFacilityLevel(fId)
        if not FacilityConfig.IsMaxLevel(fId, lv) then
            local cost = FacilityConfig.GetUpgradeCost(fId, lv)
            if cost and coins >= cost.coins and fame >= cost.fame then
                return true
            end
        end
    end
    return false
end

--- specialOrder: 有好感解锁的专属订单可接（已达门槛、在当前章节可见、未完成）
CHECKERS.specialOrder = function()
    local progress = GameState.GetStoryProgress()
    local chapter = progress and progress.chapter or 1
    local completed = GameState.GetCompletedOrders()
    local completedSet = {}
    for i = 1, #completed do completedSet[completed[i]] = true end

    -- 遍历 OrderConfig 中带 favorRequirement 的订单
    local all = OrderConfig.GetAvailable(chapter, completed)
    for i = 1, #all do
        local order = all[i]
        if order.favorRequirement and not completedSet[order.id] then
            return true
        end
    end
    return false
end

--- codex: 当前武器图鉴+结局图鉴数量 > 上次查看时记录的数量
CHECKERS.codex = function()
    if lastCodexCount_ < 0 then
        -- 首次：如果已有解锁内容，不算"新"（避免新存档一进来全红）
        return false
    end
    local currentCount = #GameState.GetCodex() + #GameState.GetAchievedEndings()
    return currentCount > lastCodexCount_
end

--- shop: 商店折扣已生效（沈绫好感达到阈值）
CHECKERS.shop = function()
    return RelationshipTracker.GetShopDiscountRate() > 0
end

--- relationship: 任一角色有已解锁等级 > 0（意味着有新故事细节可查看）
CHECKERS.relationship = function()
    local display = RelationshipTracker.CHARACTER_DISPLAY
    for i = 1, #display do
        if RelationshipTracker.GetUnlockedLevel(display[i].npcId) > 0 then
            return true
        end
    end
    return false
end

-- ============================================================================
-- 核心逻辑
-- ============================================================================

--- 重新计算所有红点状态，状态有变化时通知监听者
local function Recompute()
    local changed = false
    for key, checker in pairs(CHECKERS) do
        local val = false
        if not dismissed_[key] then
            local ok, result = pcall(checker)
            val = ok and (result == true) or false
        end
        if val ~= (lastState_[key] or false) then
            lastState_[key] = val
            changed = true
        end
    end
    if changed then
        for i = 1, #listeners_ do
            local ok, err = pcall(listeners_[i])
            if not ok then
                print("[RedDotManager] Listener error: " .. tostring(err))
            end
        end
    end
end

-- ============================================================================
-- 公开接口
-- ============================================================================

--- 初始化（在 GameState 加载完成后调用一次）
function RedDotManager.Init()
    if inited_ then return end
    inited_ = true

    -- 初始计算
    Recompute()

    -- 订阅所有可能改变红点状态的事件
    local events = {
        "coins_changed", "fame_changed", "jade_changed",
        "facility_upgraded", "material_changed",
        "story_node_complete", "story_choice_made", "story_chapter_skipped",
        "reward_collected", "order_completed_with_modifier",
        "gamestate_loaded",
    }
    for i = 1, #events do
        EventBus.On(events[i], function()
            Recompute()
        end)
    end

    print("[RedDotManager] Initialized, tracking " .. 6 .. " keys")
end

--- 查询某个 key 当前是否应显示红点
---@param key string
---@return boolean
function RedDotManager.Check(key)
    if dismissed_[key] then return false end
    if lastState_[key] ~= nil then return lastState_[key] end
    -- 未缓存时实时计算
    local checker = CHECKERS[key]
    if not checker then return false end
    local ok, val = pcall(checker)
    return ok and (val == true) or false
end

--- 消除一个红点（进入对应界面时调用，会话级，不持久化）
---@param key string
function RedDotManager.Dismiss(key)
    if not dismissed_[key] then
        dismissed_[key] = true
        -- 图鉴消除时记录当前数量
        if key == "codex" then
            lastCodexCount_ = #GameState.GetCodex() + #GameState.GetAchievedEndings()
        end
        Recompute()
    end
end

--- 重新激活一个已消除的红点（条件再次满足时自动显示）
--- 通常不需要手动调用——当条件从 false→true 时自动恢复
---@param key string
function RedDotManager.Undismiss(key)
    if dismissed_[key] then
        dismissed_[key] = nil
        Recompute()
    end
end

--- 注册状态变化监听（任何红点状态变化时触发）
---@param callback function
---@return function unsub 取消订阅函数
function RedDotManager.OnChange(callback)
    listeners_[#listeners_ + 1] = callback
    return function()
        for i = #listeners_, 1, -1 do
            if listeners_[i] == callback then
                table.remove(listeners_, i)
                break
            end
        end
    end
end

--- 获取所有红点状态快照（调试用）
---@return table<string, boolean>
function RedDotManager.GetAll()
    local snapshot = {}
    for key, _ in pairs(CHECKERS) do
        snapshot[key] = RedDotManager.Check(key)
    end
    return snapshot
end

return RedDotManager
