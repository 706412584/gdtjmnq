-- ============================================================================
-- 《问道长生》境界体系数据配置
-- 数据来源: docs/game-design-values.md §1
-- ============================================================================

local M = {}

-- ============================================================================
-- 1.1 小境界名称
-- ============================================================================
M.SUB_REALMS = { "初期", "中期", "大成" }

-- ============================================================================
-- 1.2 大境界定义
-- ============================================================================
-- tier:  阶数(1~10)
-- name:  境界名称
-- cultivation: { 初期, 中期, 大成 } 修为需求
-- lifespan: 寿命上限(年)
-- breakRate: 突破成功率(%)
-- breakCond: 突破条件描述
-- desc:  境界描述文案
-- ============================================================================
M.REALMS = {
    {
        tier = 1, name = "炼气",
        cultivation = { 0, 500, 1500 },
        lifespan = 100,
        breakRate = 100,
        breakCond = "无",
        desc = "感应天地元气，接引入体，全身内气转化为真气",
    },
    {
        tier = 2, name = "聚灵",
        cultivation = { 3000, 8000, 15000 },
        lifespan = 150,
        breakRate = 70,
        breakCond = "气血>=300",
        desc = "凝聚天地灵气，真气日益精纯，初窥修真门径",
    },
    {
        tier = 3, name = "筑基",
        cultivation = { 25000, 50000, 80000 },
        lifespan = 300,
        breakRate = 55,
        breakCond = "筑基丹, 道心稳固",
        desc = "神念与灵魂合一成为神魂，真气压缩为真元，筑修炼之基",
    },
    {
        tier = 4, name = "金丹",
        cultivation = { 120000, 200000, 350000 },
        lifespan = 500,
        breakRate = 40,
        breakCond = "功法>=3",
        desc = "真元凝聚成丹，丹田中结金丹一枚，自此脱胎换骨",
    },
    {
        tier = 5, name = "元婴",
        cultivation = { 500000, 800000, 1200000 },
        lifespan = 1000,
        breakRate = 30,
        breakCond = "凝婴丹",
        desc = "斩去虚妄成元婴，元婴自动吐纳，记录修士全部信息",
    },
    {
        tier = 6, name = "化神",
        cultivation = { 2000000, 4000000, 8000000 },
        lifespan = 2000,
        breakRate = 20,
        breakCond = "天劫渡过",
        desc = "领悟法则改造其身，修出元神，一丝元神不毁则可重生，长生不老",
    },
    -- v2 仙人期
    {
        tier = 7, name = "返虚",
        cultivation = { 15000000, 30000000, 60000000 },
        lifespan = 3000,
        breakRate = 15,
        breakCond = "待定(v2)",
        desc = "法则圆融，得窥大道，有四九天劫",
    },
    {
        tier = 8, name = "合道",
        cultivation = { 100000000, 200000000, 400000000 },
        lifespan = 5000,
        breakRate = 10,
        breakCond = "待定(v2)",
        desc = "万世灵光现，择适而合，虚空造物，人称陆地神仙",
    },
    {
        tier = 9, name = "大乘",
        cultivation = { 800000000, 1600000000, 3200000000 },
        lifespan = 8000,
        breakRate = 7,
        breakCond = "待定(v2)",
        desc = "知行合一，能唯心开境，言出法随，有九九天劫",
    },
    {
        tier = 10, name = "渡劫",
        cultivation = { 6400000000, 12800000000, 25600000000 },
        lifespan = -1, -- 不死
        breakRate = 5,
        breakCond = "待定(v2)",
        desc = "喜游于尘世间却不为凡尘所扰，清净自然，飞升在即",
    },
}

-- ============================================================================
-- 1.3 突破增幅表
-- ============================================================================
-- 索引 = 从第i个境界突破到第i+1个 (1=炼气→聚灵, 2=聚灵→筑基, ...)
-- atk/def/hp/spd: 基础属性增幅
-- crit: 暴击增幅(百分点)
-- sense: 神识容量增幅
-- ============================================================================
M.BREAK_BONUS = {
    { atk = 10,  def = 5,   hp = 50,   spd = 2,  crit = 0, sense = 20 },   -- 炼气→聚灵
    { atk = 15,  def = 8,   hp = 80,   spd = 3,  crit = 0, sense = 20 },   -- 聚灵→筑基
    { atk = 25,  def = 12,  hp = 150,  spd = 5,  crit = 1, sense = 50 },   -- 筑基→金丹
    { atk = 40,  def = 18,  hp = 300,  spd = 7,  crit = 1, sense = 50 },   -- 金丹→元婴
    { atk = 65,  def = 28,  hp = 500,  spd = 10, crit = 2, sense = 100 },  -- 元婴→化神
    { atk = 100, def = 45,  hp = 800,  spd = 15, crit = 2, sense = 100 },  -- 化神→返虚
    { atk = 150, def = 65,  hp = 1200, spd = 18, crit = 3, sense = 0 },    -- 返虚→合道
    { atk = 220, def = 90,  hp = 1800, spd = 22, crit = 3, sense = 0 },    -- 合道→大乘
    { atk = 300, def = 120, hp = 2500, spd = 25, crit = 5, sense = 0 },    -- 大乘→渡劫
}

-- ============================================================================
-- 1.4 渡劫配置
-- ============================================================================
-- targetTier: 目标境界阶数
-- ============================================================================
M.TRIBULATIONS = {
    { name = "雷劫一重", targetTier = 3, baseRate = 55, pillBonus = 20 },
    { name = "雷劫二重", targetTier = 4, baseRate = 40, pillBonus = 15 },
    { name = "雷劫三重", targetTier = 5, baseRate = 30, pillBonus = 10 },
    { name = "天劫",     targetTier = 6, baseRate = 20, pillBonus = 5 },
    { name = "四九天劫", targetTier = 7, baseRate = 15, pillBonus = 3 },
    { name = "六九天劫", targetTier = 8, baseRate = 10, pillBonus = 2 },
    { name = "九九天劫", targetTier = 9, baseRate = 7,  pillBonus = 1 },
    { name = "飞升劫",   targetTier = 10, baseRate = 5, pillBonus = 1 },
}

-- 突破失败消耗当前修为的百分比
M.BREAK_FAIL_COST_PCT = 20

-- 凡人期最大阶数(v1)
M.MAX_TIER_V1 = 6

-- ============================================================================
-- 1.5 仙界境界储备 (后续版本)
-- ============================================================================
M.IMMORTAL_REALMS = {
    { tier = 11, name = "散仙",     desc = "若不遇大劫，则长生久视" },
    { tier = 12, name = "金仙",     desc = "参悟天道法则，举手抬足间天地异变" },
    { tier = 13, name = "大罗金仙", desc = "体内凝练仙胎之力，已拥有创造世界之能" },
    { tier = 14, name = "混元金仙", desc = "触摸圣人境界门槛" },
    { tier = 15, name = "鸿蒙金仙", desc = "突破天地人桎梏，以身合道，可争夺圣人果位" },
    { tier = 16, name = "太乙金仙", desc = "解锁鸿蒙紫气" },
    { tier = 17, name = "无极金仙", desc = "挣脱天道束缚位锁链，但仍受束缚" },
    { tier = 18, name = "仙王",     desc = "纵横寰宇，一方天地王者" },
    { tier = 19, name = "仙君",     desc = "纵横寰宇，一方天地之君" },
    { tier = 20, name = "仙尊",     desc = "化身一方天地之尊" },
    { tier = 21, name = "仙帝",     desc = "化身一方天地帝王" },
    { tier = 22, name = "道尊",     desc = "掌握星辰源力，可随意改变天地规则" },
    { tier = 23, name = "道帝",     desc = "可掌握盘古之力" },
    { tier = 24, name = "准圣",     desc = "感悟天道圣人之道，获得成圣契机" },
    { tier = 25, name = "天道圣人", desc = "天道之上，万道归宗" },
}

-- ============================================================================
-- 辅助函数
-- ============================================================================

--- 根据阶数获取境界配置
---@param tier number 阶数1~10
---@return table|nil
function M.GetRealm(tier)
    return M.REALMS[tier]
end

--- 根据境界名获取配置
---@param name string 境界名(如"筑基")
---@return table|nil
function M.GetRealmByName(name)
    for _, r in ipairs(M.REALMS) do
        if r.name == name then return r end
    end
    return nil
end

--- 获取完整境界名(如"筑基初期")
---@param tier number 阶数
---@param sub number 小境界索引(1=初期,2=中期,3=大成)
---@return string
function M.GetFullName(tier, sub)
    local r = M.REALMS[tier]
    if not r then return "未知" end
    return r.name .. (M.SUB_REALMS[sub] or "")
end

--- 解析完整境界名为 tier, sub
---@param fullName string 如"筑基初期"
---@return number|nil tier, number|nil sub
function M.ParseFullName(fullName)
    for _, r in ipairs(M.REALMS) do
        for si, sn in ipairs(M.SUB_REALMS) do
            if fullName == r.name .. sn then
                return r.tier, si
            end
        end
    end
    return nil, nil
end

--- 获取指定境界小境界的修为需求
---@param tier number
---@param sub number
---@return number
function M.GetCultivationReq(tier, sub)
    local r = M.REALMS[tier]
    if not r then return 0 end
    return r.cultivation[sub] or 0
end

--- 获取突破到下一个大境界的增幅
---@param fromTier number 当前大境界阶数
---@return table|nil
function M.GetBreakBonus(fromTier)
    return M.BREAK_BONUS[fromTier]
end

--- 获取渡劫信息
---@param targetTier number 目标境界阶数
---@return table|nil
function M.GetTribulation(targetTier)
    for _, t in ipairs(M.TRIBULATIONS) do
        if t.targetTier == targetTier then return t end
    end
    return nil
end

return M
