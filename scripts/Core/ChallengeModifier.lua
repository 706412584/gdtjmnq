-- ============================================================================
-- ChallengeModifier - 挑战修饰符系统
-- Project Smith / P3-B3
--
-- 为订单附加额外挑战条件，增加可重玩性和奖励深度。
-- 修饰符类型:
--   1. 限时挑战 (time_limit)    - 小游戏总时间缩短
--   2. 连单挑战 (chain_order)   - 连续完成 N 单不失手
--   3. 突发事件 (sudden_event)  - 小游戏中随机触发干扰
--   4. 材料限制 (material_cap)  - 只能用低级材料
--   5. 单手锻造 (one_touch)     - 减少操作次数
--
-- 使用方式:
--   local ChallengeModifier = require("Core.ChallengeModifier")
--   local mod = ChallengeModifier.Roll(chapter, tier)  -- 随机生成修饰符
--   -- mod 可以为 nil（表示无修饰符）
--   -- 在 MiniGameRunner / OrderManager 中应用 mod 的效果
-- ============================================================================

local ChallengeModifier = {}

-- ==================== 修饰符定义 ====================

---@class ModifierDef
---@field id string
---@field name string
---@field description string
---@field icon string      图标提示文本
---@field minChapter number 最低解锁章节
---@field minTier number    最低订单等级
---@field rewardBonus number 奖励加成系数（如 0.3 = +30%）
---@field params table      修饰符参数

local MODIFIER_DEFS = {
    {
        id = "time_limit",
        name = "争分夺秒",
        description = "锻造总时间缩短 30%",
        icon = "[时]",
        minChapter = 2,
        minTier = 2,
        rewardBonus = 0.25,
        params = {
            timeMultiplier = 0.7,  -- 时间乘数（0.7 = 缩短 30%）
        },
    },
    {
        id = "chain_order",
        name = "连炉不歇",
        description = "连续完成订单可叠加奖励加成",
        icon = "[连]",
        minChapter = 2,
        minTier = 2,
        rewardBonus = 0.15,  -- 基础加成，每连一单额外 +10%
        params = {
            chainBonusPerOrder = 0.10,
            maxChainBonus = 0.50,
        },
    },
    {
        id = "sudden_event",
        name = "风雨难阻",
        description = "锻造中随机出现干扰事件",
        icon = "[变]",
        minChapter = 3,
        minTier = 3,
        rewardBonus = 0.30,
        params = {
            eventChance = 0.3,  -- 每步骤触发概率
            eventTypes = { "wind_gust", "ember_burst", "material_shift" },
        },
    },
    {
        id = "material_cap",
        name = "以拙胜巧",
        description = "只能使用低一级的材料",
        icon = "[朴]",
        minChapter = 2,
        minTier = 3,
        rewardBonus = 0.35,
        params = {
            tierReduction = 1,  -- 材料等级降低 1 级
        },
    },
    {
        id = "one_touch",
        name = "一锤定音",
        description = "每个步骤的操作次数减半",
        icon = "[精]",
        minChapter = 3,
        minTier = 4,
        rewardBonus = 0.40,
        params = {
            touchMultiplier = 0.5,
        },
    },
}

-- ==================== 内部状态 ====================

--- 当前连单计数（chain_order 修饰符用）
local chainCount_ = 0

-- ==================== 公共接口 ====================

--- 根据章节和订单等级随机生成一个修饰符
--- 约 40% 概率返回修饰符，60% 概率返回 nil（普通订单）
---@param chapter number 当前章节
---@param tier number 订单等级
---@return table|nil modifier { id, name, description, icon, rewardBonus, params }
function ChallengeModifier.Roll(chapter, tier)
    -- 40% 概率触发修饰符
    if math.random() > 0.40 then
        return nil
    end

    -- 筛选可用修饰符
    local available = {}
    for i = 1, #MODIFIER_DEFS do
        local def = MODIFIER_DEFS[i]
        if chapter >= def.minChapter and tier >= def.minTier then
            available[#available + 1] = def
        end
    end

    if #available == 0 then
        return nil
    end

    -- 随机选一个
    local chosen = available[math.random(1, #available)]

    return {
        id = chosen.id,
        name = chosen.name,
        description = chosen.description,
        icon = chosen.icon,
        rewardBonus = chosen.rewardBonus,
        params = chosen.params,
    }
end

--- 获取所有修饰符定义（UI 展示用）
---@return table[]
function ChallengeModifier.GetAllDefs()
    local result = {}
    for i = 1, #MODIFIER_DEFS do
        local def = MODIFIER_DEFS[i]
        result[#result + 1] = {
            id = def.id,
            name = def.name,
            description = def.description,
            icon = def.icon,
            rewardBonus = def.rewardBonus,
            minChapter = def.minChapter,
            minTier = def.minTier,
        }
    end
    return result
end

--- 计算修饰符带来的奖励加成系数
---@param modifier table|nil 修饰符数据
---@return number bonus 额外奖励倍数（如 0.3 表示 +30%）
function ChallengeModifier.GetRewardBonus(modifier)
    if not modifier then return 0 end

    local bonus = modifier.rewardBonus or 0

    -- 连单修饰符额外加成
    if modifier.id == "chain_order" and modifier.params then
        local chainBonus = chainCount_ * (modifier.params.chainBonusPerOrder or 0.10)
        local maxChain = modifier.params.maxChainBonus or 0.50
        if chainBonus > maxChain then chainBonus = maxChain end
        bonus = bonus + chainBonus
    end

    return bonus
end

--- 记录连单成功（chain_order 修饰符用）
function ChallengeModifier.IncrementChain()
    chainCount_ = chainCount_ + 1
    print("[ChallengeModifier] Chain count: " .. chainCount_)
end

--- 重置连单计数（订单失败或放弃时调用）
function ChallengeModifier.ResetChain()
    chainCount_ = 0
end

--- 获取当前连单计数
---@return number
function ChallengeModifier.GetChainCount()
    return chainCount_
end

--- 判断修饰符是否包含突发事件
---@param modifier table|nil
---@return boolean
function ChallengeModifier.HasSuddenEvent(modifier)
    return modifier ~= nil and modifier.id == "sudden_event"
end

--- 随机检测突发事件是否触发（每步骤调用一次）
---@param modifier table|nil
---@return string|nil eventType 触发的事件类型，nil 表示未触发
function ChallengeModifier.RollSuddenEvent(modifier)
    if not modifier or modifier.id ~= "sudden_event" then
        return nil
    end
    local params = modifier.params
    if not params then return nil end

    local chance = params.eventChance or 0.3
    if math.random() > chance then
        return nil
    end

    local types = params.eventTypes
    if not types or #types == 0 then return nil end

    return types[math.random(1, #types)]
end

return ChallengeModifier
