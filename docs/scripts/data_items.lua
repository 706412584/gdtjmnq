-- ============================================================================
-- 《问道长生》物品体系数据配置
-- 数据来源: docs/game-design-values.md §4, §5, §7, §8, §12
-- ============================================================================

local M = {}

-- ============================================================================
-- 4.1 品质等级 & 颜色
-- ============================================================================
M.QUALITY_ORDER = { "common", "uncommon", "rare", "epic", "legend", "mythic" }

M.QUALITY = {
    common   = { label = "普通", color = { 149, 149, 149, 255 }, hex = "#959595", weight = 50 },
    uncommon = { label = "良品", color = { 174, 213, 129, 255 }, hex = "#AED581", weight = 30 },
    rare     = { label = "珍稀", color = { 41,  182, 246, 255 }, hex = "#29B6F6", weight = 15 },
    epic     = { label = "史诗", color = { 234, 128, 252, 255 }, hex = "#EA80FC", weight = 4 },
    legend   = { label = "传说", color = { 255, 112, 67,  255 }, hex = "#FF7043", weight = 1 },
    mythic   = { label = "神话", color = { 244, 81,  30,  255 }, hex = "#F4511E", weight = 0 },
}

-- 中文名 → key 映射
M.QUALITY_NAME_MAP = {}
for k, v in pairs(M.QUALITY) do
    M.QUALITY_NAME_MAP[v.label] = k
end

-- ============================================================================
-- 5.1 通用丹药 (不限次数)
-- ============================================================================
M.PILLS_COMMON = {
    { id = "peiyuan",     name = "培元丹",     quality = "common",   effect = "修为+200",          materials = { ["灵草"] = 1, ["矿石"] = 2 },         time = 30,  rate = 80 },
    { id = "huiqi",       name = "回气丹",     quality = "common",   effect = "灵力恢复100",        materials = { ["灵草"] = 1, ["灵泉水"] = 1 },       time = 30,  rate = 80 },
    { id = "ningshen",    name = "凝神丹",     quality = "uncommon", effect = "神识+20",            materials = { ["灵草"] = 2, ["兽骨"] = 1 },         time = 60,  rate = 60 },
    { id = "tongmai",     name = "通脉丹",     quality = "rare",     effect = "修炼速度+20%(1小时)", materials = { ["灵草"] = 3, ["灵泉水"] = 1 },       time = 90,  rate = 40 },
    { id = "peiyuan_up",  name = "上品培元丹", quality = "uncommon", effect = "修为+1000",          materials = { ["灵草"] = 3, ["矿石"] = 5 },         time = 60,  rate = 50 },
    { id = "peiyuan_top", name = "极品培元丹", quality = "rare",     effect = "修为+5000",          materials = { ["灵草"] = 5, ["天材地宝"] = 1 },     time = 120, rate = 30 },
}

-- ============================================================================
-- 5.2 限制丹药 (每境界限次)
-- ============================================================================
-- perRealm: 每个大境界可服用次数上限
-- ============================================================================
M.PILLS_LIMITED = {
    { id = "hongyun",  name = "鸿运丹", quality = "rare",     effect = "气运+1级",       perRealm = 1, materials = { ["灵草"] = 5, ["天材地宝"] = 1 }, rate = 25 },
    { id = "qiangshen", name = "强身丹", quality = "uncommon", effect = "气血+50(永久)",   perRealm = 5, materials = { ["灵草"] = 2, ["兽骨"] = 2 },    rate = 50 },
    { id = "linggong", name = "灵攻丹", quality = "uncommon", effect = "攻击+10(永久)",   perRealm = 5, materials = { ["灵草"] = 2, ["矿石"] = 3 },    rate = 50 },
    { id = "guyuan",   name = "固元丹", quality = "uncommon", effect = "防御+8(永久)",    perRealm = 5, materials = { ["兽骨"] = 3, ["矿石"] = 2 },    rate = 50 },
    { id = "jifeng",   name = "疾风丹", quality = "rare",     effect = "速度+3(永久)",    perRealm = 3, materials = { ["灵草"] = 3, ["灵泉水"] = 2 },  rate = 35 },
    { id = "xisui",    name = "洗髓丹", quality = "rare",     effect = "悟性+5(永久)",    perRealm = 3, materials = { ["灵草"] = 3, ["天材地宝"] = 1 }, rate = 30 },
}

-- ============================================================================
-- 5.3 突破辅助丹药
-- ============================================================================
M.PILLS_BREAKTHROUGH = {
    { id = "zhuji",    name = "筑基丹", quality = "rare", effect = "渡劫成功率+20%",     perBreak = 1, materials = { ["灵草"] = 5, ["天材地宝"] = 1 }, rate = 20 },
    { id = "qingxin",  name = "清心丹", quality = "rare", effect = "渡劫失败不降道心",    perBreak = 1, materials = { ["灵草"] = 5, ["灵泉水"] = 3 },  rate = 25 },
    { id = "pojie",    name = "破劫丹", quality = "epic", effect = "渡劫成功率+30%",     perBreak = 1, materials = { ["天材地宝"] = 3 },              rate = 10 },
}

-- ============================================================================
-- 5.4 炼丹材料
-- ============================================================================
M.MATERIALS = {
    { id = "lingcao",     name = "灵草",     quality = "common",   price = 20,  currency = "灵石", source = "探索采集" },
    { id = "kuangshi",    name = "矿石",     quality = "common",   price = 15,  currency = "灵石", source = "探索采矿" },
    { id = "shougu",      name = "兽骨",     quality = "common",   price = 30,  currency = "灵石", source = "击杀灵兽" },
    { id = "lingquanshui", name = "灵泉水",   quality = "uncommon", price = 80,  currency = "灵石", source = "稀有采集点" },
    { id = "tiancaidibao", name = "天材地宝", quality = "rare",     price = 50,  currency = "仙石", source = "Boss掉落/秘境" },
}

-- ============================================================================
-- 6.1 物品分类枚举
-- ============================================================================
M.ITEM_CATEGORIES = {
    { key = "fabao",    label = "法宝",  subTabs = { "头戴", "身穿", "手持", "饰品", "鞋子" } },
    { key = "material", label = "材料",  subTabs = nil },
    { key = "item",     label = "物品",  subTabs = { "丹药", "丹方", "宝箱", "其他" } },
    { key = "pet",      label = "灵宠",  subTabs = nil },
}

--- 根据 category key 获取分类定义
---@param key string
---@return table|nil
function M.GetCategory(key)
    for _, cat in ipairs(M.ITEM_CATEGORIES) do
        if cat.key == key then return cat end
    end
    return nil
end

--- 根据物品推断 category + subType
---@param itemName string
---@return string category, string|nil subType
function M.InferCategory(itemName)
    -- 丹药检查
    if M.FindPillByName(itemName) then
        return "item", "丹药"
    end
    -- 材料检查
    for _, mat in ipairs(M.MATERIALS) do
        if mat.name == itemName then return "material", nil end
    end
    -- 法宝检查
    for _, art in ipairs(M.ARTIFACTS) do
        if art.name == itemName then
            local slotDef = M.GetSlotByKey(art.slot)
            return "fabao", slotDef and slotDef.label or "手持"
        end
    end
    -- 默认归到"物品-其他"
    return "item", "其他"
end

-- ============================================================================
-- 6.2 背包容量配置
-- ============================================================================
M.BAG_EXPAND = {
    initialCapacity = 50,   -- 初始容量
    perExpand       = 10,   -- 每次扩容增加格数
    maxCapacity     = 120,  -- 容量上限
    costPerSlot     = 20,   -- 每格灵石成本（基础）
    -- 扩容费用 = 当前容量 * costPerSlot
}

-- ============================================================================
-- 7.1 装备槽位（5个部位，对齐旧游戏）
-- ============================================================================
M.EQUIP_SLOTS = {
    { slot = "head",      label = "头戴", mainStat = "defense" },
    { slot = "body",      label = "身穿", mainStat = "defense" },
    { slot = "weapon",    label = "手持", mainStat = "attack" },
    { slot = "accessory", label = "饰品", mainStat = "crit" },
    { slot = "shoes",     label = "鞋子", mainStat = "speed" },
}

--- 根据 slot key 获取槽位定义
---@param slotKey string
---@return table|nil
function M.GetSlotByKey(slotKey)
    for _, s in ipairs(M.EQUIP_SLOTS) do
        if s.slot == slotKey then return s end
    end
    return nil
end

-- ============================================================================
-- 7.2 法宝定义
-- ============================================================================
M.ARTIFACTS = {
    { id = "biyu_zan",   name = "碧玉灵簪", quality = "uncommon", slot = "accessory", effect = "灵力上限+50",           price = nil,  currency = nil },
    { id = "zhenmo_ling", name = "镇魔铃",   quality = "rare",     slot = "weapon",    effect = "攻击+15, 暴击+3%",      price = nil,  currency = nil },
    { id = "xuantie_dun", name = "玄铁盾",   quality = "common",   slot = "body",      effect = "防御+25",               price = 300,  currency = "灵石" },
    { id = "zijin_ling",  name = "紫金铃",   quality = "rare",     slot = "weapon",    effect = "攻击+25, 暴击+2%",      price = 500,  currency = "灵石" },
    { id = "xianling_shan", name = "仙灵扇",  quality = "epic",     slot = "weapon",    effect = "攻击+35, 速度+40",      price = 80,   currency = "仙石" },
}

-- ============================================================================
-- 7.3 法宝强化表
-- ============================================================================
-- pct: 属性增幅百分比
-- ============================================================================
M.ENHANCE_TABLE = {
    { level = 1,  cost = 100,  currency = "灵石", pct = 5,  rate = 100 },
    { level = 2,  cost = 100,  currency = "灵石", pct = 5,  rate = 100 },
    { level = 3,  cost = 100,  currency = "灵石", pct = 5,  rate = 100 },
    { level = 4,  cost = 300,  currency = "灵石", pct = 8,  rate = 80 },
    { level = 5,  cost = 300,  currency = "灵石", pct = 8,  rate = 80 },
    { level = 6,  cost = 300,  currency = "灵石", pct = 8,  rate = 80 },
    { level = 7,  cost = 800,  currency = "灵石", pct = 12, rate = 50 },
    { level = 8,  cost = 800,  currency = "灵石", pct = 12, rate = 50 },
    { level = 9,  cost = 800,  currency = "灵石", pct = 12, rate = 50 },
    { level = 10, cost = 2000, currency = "灵石", pct = 20, rate = 30 },
}

-- ============================================================================
-- 8 称号体系
-- ============================================================================
M.TITLE_RARITIES = {
    { level = 1, label = "普通", color = { 149, 149, 149, 255 }, hex = "#959595", bonus = 0 },
    { level = 2, label = "优秀", color = { 174, 213, 129, 255 }, hex = "#AED581", bonus = 1 },
    { level = 3, label = "精良", color = { 41,  182, 246, 255 }, hex = "#29B6F6", bonus = 3 },
    { level = 4, label = "史诗", color = { 234, 128, 252, 255 }, hex = "#EA80FC", bonus = 5 },
    { level = 5, label = "传说", color = { 255, 112, 67,  255 }, hex = "#FF7043", bonus = 8 },
    { level = 6, label = "神话", color = { 244, 81,  30,  255 }, hex = "#F4511E", bonus = 12 },
}

-- ============================================================================
-- 12.1 坊市商品定价
-- ============================================================================
M.MARKET_GOODS = {
    -- 丹药
    { name = "培元丹",   category = "丹药", price = 50,   currency = "灵石", stock = 10 },
    { name = "洗髓丹",   category = "丹药", price = 200,  currency = "灵石", stock = 5 },
    { name = "筑基丹",   category = "丹药", price = 30,   currency = "仙石", stock = 1 },
    { name = "凝神丹",   category = "丹药", price = 120,  currency = "灵石", stock = 3 },
    { name = "强身丹",   category = "丹药", price = 100,  currency = "灵石", stock = 5 },
    { name = "灵攻丹",   category = "丹药", price = 150,  currency = "灵石", stock = 5 },
    { name = "鸿运丹",   category = "丹药", price = 50,   currency = "仙石", stock = 1 },
    -- 法宝
    { name = "紫金铃",   category = "法宝", price = 500,  currency = "灵石", stock = 2 },
    { name = "玄铁盾",   category = "法宝", price = 300,  currency = "灵石", stock = 3 },
    { name = "仙灵扇",   category = "法宝", price = 80,   currency = "仙石", stock = 1 },
    -- 功法
    { name = "冰心诀",   category = "功法", price = 800,  currency = "灵石", stock = 1 },
    { name = "烈焰掌",   category = "功法", price = 400,  currency = "灵石", stock = 2 },
    -- 材料
    { name = "灵草",     category = "材料", price = 20,   currency = "灵石", stock = 99 },
    { name = "兽骨",     category = "材料", price = 30,   currency = "灵石", stock = 50 },
    { name = "灵泉水",   category = "材料", price = 80,   currency = "灵石", stock = 10 },
    { name = "天材地宝", category = "材料", price = 50,   currency = "仙石", stock = 2 },
}

-- 12.2 寄售坊配置
M.TRADING_POST = {
    feeRate     = 0.05,
    maxListings = 5,
    currency    = "灵石",
}

-- ============================================================================
-- 辅助函数
-- ============================================================================

--- 获取品质颜色(RGBA)，兼容中文label和英文key
---@param quality string 中文品质名(如"珍稀")或英文key(如"rare")
---@return table {r,g,b,a}
function M.GetQualityColor(quality)
    -- 先尝试直接作为英文 key 查
    if M.QUALITY[quality] then
        return M.QUALITY[quality].color
    end
    -- 再尝试作为中文 label 查
    local key = M.QUALITY_NAME_MAP[quality]
    if key and M.QUALITY[key] then
        return M.QUALITY[key].color
    end
    return M.QUALITY.common.color
end

--- 获取品质中文显示名，兼容中文label和英文key
---@param quality string 中文品质名或英文key
---@return string
function M.GetQualityLabel(quality)
    -- 英文 key → 返回中文 label
    if M.QUALITY[quality] then
        return M.QUALITY[quality].label
    end
    -- 已经是中文 label → 直接返回
    if M.QUALITY_NAME_MAP[quality] then
        return quality
    end
    return "普通"
end

--- 获取品质key
---@param qualityLabel string
---@return string
function M.GetQualityKey(qualityLabel)
    return M.QUALITY_NAME_MAP[qualityLabel] or "common"
end

--- 根据id查找丹药(所有类别)
---@param id string
---@return table|nil
function M.FindPill(id)
    for _, p in ipairs(M.PILLS_COMMON) do
        if p.id == id then return p end
    end
    for _, p in ipairs(M.PILLS_LIMITED) do
        if p.id == id then return p end
    end
    for _, p in ipairs(M.PILLS_BREAKTHROUGH) do
        if p.id == id then return p end
    end
    return nil
end

--- 根据名称查找丹药
---@param name string
---@return table|nil
function M.FindPillByName(name)
    for _, p in ipairs(M.PILLS_COMMON) do
        if p.name == name then return p end
    end
    for _, p in ipairs(M.PILLS_LIMITED) do
        if p.name == name then return p end
    end
    for _, p in ipairs(M.PILLS_BREAKTHROUGH) do
        if p.name == name then return p end
    end
    return nil
end

--- 获取法宝强化配置
---@param level number
---@return table|nil
function M.GetEnhanceInfo(level)
    return M.ENHANCE_TABLE[level]
end

return M
