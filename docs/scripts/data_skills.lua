-- ============================================================================
-- 《问道长生》功法 & 悟道数据配置
-- 数据来源: docs/game-design-values.md §6, §14
-- ============================================================================

local M = {}

-- ============================================================================
-- 6.1 功法列表
-- ============================================================================
-- type: 基础/防御/身法/攻击
-- effect: 主效果描述
-- unlock: 解锁条件描述
-- unlockPrice/unlockCurrency: 坊市购买价格(nil=初始拥有)
-- ============================================================================
M.SKILLS = {
    { id = "tuna",     name = "吐纳术", type = "基础", maxLevel = 10, effect = "修炼速度+15%",      unlock = "初始",   unlockPrice = nil,  unlockCurrency = nil },
    { id = "jingang",  name = "金刚诀", type = "防御", maxLevel = 10, effect = "防御+20",            unlock = "初始",   unlockPrice = nil,  unlockCurrency = nil },
    { id = "yufeng",   name = "御风术", type = "身法", maxLevel = 10, effect = "速度+15, 闪避+2%",   unlock = "初始",   unlockPrice = nil,  unlockCurrency = nil },
    { id = "lieyan",   name = "烈焰掌", type = "攻击", maxLevel = 10, effect = "攻击+30",            unlock = "坊市购买", unlockPrice = 400,  unlockCurrency = "灵石" },
    { id = "bingxin",  name = "冰心诀", type = "基础", maxLevel = 10, effect = "修炼速度+20%",       unlock = "坊市购买", unlockPrice = 800,  unlockCurrency = "灵石" },
}

-- ============================================================================
-- 6.2 功法升级表
-- ============================================================================
-- time: 修炼时间描述
-- timeSec: 修炼时间(秒)
-- wisdomReq: 悟性需求
-- multiplier: 效果倍率
-- ============================================================================
M.SKILL_LEVELS = {
    { level = 1,  timeSec = 0,      wisdomReq = 0,   multiplier = 1.0 },
    { level = 2,  timeSec = 1800,   wisdomReq = 50,  multiplier = 1.2 },
    { level = 3,  timeSec = 1800,   wisdomReq = 50,  multiplier = 1.2 },
    { level = 4,  timeSec = 7200,   wisdomReq = 70,  multiplier = 1.5 },
    { level = 5,  timeSec = 7200,   wisdomReq = 70,  multiplier = 1.5 },
    { level = 6,  timeSec = 7200,   wisdomReq = 70,  multiplier = 1.5 },
    { level = 7,  timeSec = 28800,  wisdomReq = 90,  multiplier = 2.0 },
    { level = 8,  timeSec = 28800,  wisdomReq = 90,  multiplier = 2.0 },
    { level = 9,  timeSec = 28800,  wisdomReq = 90,  multiplier = 2.0 },
    { level = 10, timeSec = 86400,  wisdomReq = 120, multiplier = 3.0 },
}

-- ============================================================================
-- 14. 悟道列表
-- ============================================================================
-- maxProgress: 满进度
-- reward: 奖励描述
-- unlockTier: 需要的最低境界阶数(nil=初始)
-- ============================================================================
M.DAO_INSIGHTS = {
    { id = "tiandao",   name = "天道感悟", maxProgress = 100, reward = "全属性+5",        unlockTier = nil },
    { id = "wuxing",    name = "五行之道", maxProgress = 100, reward = "功法效果+10%",     unlockTier = nil },
    { id = "jianyi",    name = "剑意初悟", maxProgress = 100, reward = "攻击+20, 暴击+5%", unlockTier = 4 },
}

-- ============================================================================
-- 辅助函数
-- ============================================================================

--- 根据id获取功法
---@param id string
---@return table|nil
function M.GetSkill(id)
    for _, s in ipairs(M.SKILLS) do
        if s.id == id then return s end
    end
    return nil
end

--- 根据名称获取功法
---@param name string
---@return table|nil
function M.GetSkillByName(name)
    for _, s in ipairs(M.SKILLS) do
        if s.name == name then return s end
    end
    return nil
end

--- 获取功法等级配置
---@param level number
---@return table|nil
function M.GetSkillLevel(level)
    return M.SKILL_LEVELS[level]
end

--- 获取悟道配置
---@param id string
---@return table|nil
function M.GetInsight(id)
    for _, d in ipairs(M.DAO_INSIGHTS) do
        if d.id == id then return d end
    end
    return nil
end

return M
