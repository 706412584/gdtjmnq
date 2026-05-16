-- ============================================================================
-- 《问道长生》灵宠系统
-- 职责：灵宠捕获、喂养升级、出战/召回、战斗加成
-- 设计：Can/Do 模式
-- ============================================================================

local GamePlayer = require("game_player")
local DataWorld  = require("data_world")
local DataItems  = require("data_items")

local M = {}

-- ============================================================================
-- 常量
-- ============================================================================

-- 品质权重（捕获时按权重随机，品质越高越稀有）
local QUALITY_WEIGHTS = {
    common   = 40,
    uncommon = 25,
    rare     = 15,
    epic     = 10,
    legend   = 7,
    mythic   = 3,
}

-- 品质战力乘数
local QUALITY_POWER_MUL = {
    common   = 1.0,
    uncommon = 1.2,
    rare     = 1.5,
    epic     = 2.0,
    legend   = 3.0,
    mythic   = 5.0,
}

-- 等级经验需求表 (level → 升到下一级所需经验)
local LEVEL_EXP = { 0, 100, 300, 600, 1000, 1500, 2200, 3000, 4000, 5500 }
local MAX_LEVEL = #LEVEL_EXP

-- 喂养材料经验值
local FEED_ITEMS = {
    ["灵草"]     = 20,
    ["兽骨"]     = 35,
    ["灵泉水"]   = 60,
    ["天材地宝"] = 150,
}

-- 捕获基础概率 (%)
local CAPTURE_BASE_RATE = 12

-- ============================================================================
-- 内部工具
-- ============================================================================

--- 确保灵宠数据结构
---@return table|nil
local function EnsurePetData()
    local p = GamePlayer.Get()
    if not p then return nil end
    if not p.pets then p.pets = {} end
    if p.activePetId == nil then p.activePetId = 0 end
    return p
end

--- 获取可捕获的灵宠列表（排除神话品质）
---@return table[]
local function GetCapturable()
    local list = {}
    for _, pet in ipairs(DataWorld.PETS) do
        -- 神话灵宠（四神兽）不可捕获
        if pet.quality ~= "mythic" then
            list[#list + 1] = pet
        end
    end
    return list
end

--- 按品质权重随机选择一只灵宠
---@param candidates table[]
---@return table|nil
local function PickByQuality(candidates)
    if #candidates == 0 then return nil end
    local total = 0
    for _, c in ipairs(candidates) do
        total = total + (QUALITY_WEIGHTS[c.quality] or 10)
    end
    local r = math.random(1, total)
    local acc = 0
    for _, c in ipairs(candidates) do
        acc = acc + (QUALITY_WEIGHTS[c.quality] or 10)
        if r <= acc then return c end
    end
    return candidates[#candidates]
end

--- 查找玩家已拥有的灵宠数据（按 id）
---@param p table
---@param petId number
---@return table|nil petData
---@return number|nil idx
local function FindOwnedPet(p, petId)
    for i, pet in ipairs(p.pets) do
        if pet.id == petId then return pet, i end
    end
    return nil, nil
end

--- 获取灵宠当前等级所需总经验
---@param level number
---@return number
local function GetLevelExp(level)
    if level < 1 then return 0 end
    if level > MAX_LEVEL then return LEVEL_EXP[MAX_LEVEL] end
    return LEVEL_EXP[level]
end

-- ============================================================================
-- 公开接口：查询
-- ============================================================================

--- 获取全部灵宠展示数据（含拥有状态、等级）
---@return table[]
function M.GetAllPets()
    local p = EnsurePetData()
    if not p then return {} end

    local result = {}
    for _, def in ipairs(DataWorld.PETS) do
        local owned, _ = FindOwnedPet(p, def.id)
        result[#result + 1] = {
            id       = def.id,
            name     = def.name,
            quality  = def.quality,
            role     = def.role,
            skill    = def.skill,
            image    = def.image,
            desc     = def.desc,
            owned    = owned ~= nil,
            level    = owned and (owned.level or 1) or 0,
            exp      = owned and (owned.exp or 0) or 0,
            expMax   = owned and GetLevelExp(owned.level or 1) or 0,
            isActive = (p.activePetId == def.id),
        }
    end
    return result
end

--- 获取当前出战灵宠信息
---@return table|nil
function M.GetActivePet()
    local p = EnsurePetData()
    if not p or p.activePetId == 0 then return nil end
    local owned = FindOwnedPet(p, p.activePetId)
    if not owned then return nil end
    local def = DataWorld.GetPet(p.activePetId)
    if not def then return nil end
    return {
        id    = def.id,
        name  = def.name,
        quality = def.quality,
        role  = def.role,
        skill = def.skill,
        level = owned.level or 1,
    }
end

--- 获取灵宠战斗加成（给战斗模块用）
---@return table { atkBonus, defBonus, hpBonus, spdBonus }
function M.GetCombatBonus()
    local base = { atkBonus = 0, defBonus = 0, hpBonus = 0, spdBonus = 0 }
    local active = M.GetActivePet()
    if not active then return base end

    local mul = QUALITY_POWER_MUL[active.quality] or 1.0
    local lv = active.level or 1

    if active.role == "攻击" then
        base.atkBonus = math.floor(lv * 2 * mul)
    elseif active.role == "防御" then
        base.defBonus = math.floor(lv * 2 * mul)
        base.hpBonus  = math.floor(lv * 10 * mul)
    elseif active.role == "辅助" then
        base.spdBonus = math.floor(lv * 1 * mul)
        base.atkBonus = math.floor(lv * 1 * mul)
    end
    return base
end

--- 获取拥有的灵宠数量
---@return number
function M.GetOwnedCount()
    local p = EnsurePetData()
    if not p then return 0 end
    return #p.pets
end

-- ============================================================================
-- 公开接口：捕获
-- ============================================================================

--- 探索时尝试捕获灵宠（由 game_explore 调用）
---@return boolean captured, string|nil message
function M.TryCapture()
    local p = EnsurePetData()
    if not p then return false, nil end

    -- 概率判定
    if math.random(100) > CAPTURE_BASE_RATE then
        return false, nil
    end

    -- 筛选可捕获灵宠
    local candidates = GetCapturable()
    if #candidates == 0 then return false, nil end

    local chosen = PickByQuality(candidates)
    if not chosen then return false, nil end

    -- 检查是否已拥有
    local existing = FindOwnedPet(p, chosen.id)
    if existing then
        -- 已有，给经验奖励
        local bonusExp = 50
        existing.exp = (existing.exp or 0) + bonusExp
        -- 检查升级
        M._CheckLevelUp(existing)
        GamePlayer.MarkDirty()
        local msg = "遇到野生<c=gold>" .. chosen.name .. "</c>，但已拥有，获得灵宠经验+<c=yellow>" .. bonusExp .. "</c>"
        return true, msg
    end

    -- 新灵宠入手
    p.pets[#p.pets + 1] = {
        id    = chosen.id,
        level = 1,
        exp   = 0,
    }
    GamePlayer.MarkDirty()
    local qualityLabel = DataItems.GetQualityLabel(chosen.quality)
    local qualityHex   = DataItems.QUALITY[chosen.quality] and DataItems.QUALITY[chosen.quality].hex or "#959595"
    local msg = "捕获了野生<c=gold>" .. chosen.name .. "</c>（<c=" .. qualityHex .. ">" .. qualityLabel .. "</c>）"
    GamePlayer.AddLog(msg)
    return true, msg
end

-- ============================================================================
-- 公开接口：喂养
-- ============================================================================

--- 检查是否可喂养
---@param petId number
---@param itemName string
---@return boolean, string|nil
function M.CanFeed(petId, itemName)
    local p = EnsurePetData()
    if not p then return false, "数据未加载" end

    local owned = FindOwnedPet(p, petId)
    if not owned then return false, "未拥有此灵宠" end

    if (owned.level or 1) >= MAX_LEVEL then
        return false, "已达最高等级"
    end

    local expValue = FEED_ITEMS[itemName]
    if not expValue then return false, "此物品无法喂养灵宠" end

    -- 检查背包中是否有材料
    local found = false
    for _, item in ipairs(p.bagItems or {}) do
        if item.name == itemName and (item.count or 0) >= 1 then
            found = true
            break
        end
    end
    if not found then return false, "背包中没有" .. itemName end

    return true, nil
end

--- 执行喂养
---@param petId number
---@param itemName string
---@return boolean, string
function M.DoFeed(petId, itemName)
    local ok, reason = M.CanFeed(petId, itemName)
    if not ok then return false, reason or "无法喂养" end

    local p = EnsurePetData()
    local owned = FindOwnedPet(p, petId)
    local def = DataWorld.GetPet(petId)
    if not owned or not def then return false, "数据错误" end

    -- 扣除材料
    GamePlayer.RemoveItemByName(itemName, 1)

    -- 增加经验
    local expValue = FEED_ITEMS[itemName]
    owned.exp = (owned.exp or 0) + expValue

    -- 检查升级
    local leveled = M._CheckLevelUp(owned)

    GamePlayer.MarkDirty()
    local msg = "<c=gold>" .. def.name .. "</c>获得经验+<c=yellow>" .. expValue .. "</c>"
    if leveled then
        msg = msg .. "，升到" .. owned.level .. "级"
    end
    GamePlayer.AddLog(msg)
    return true, msg
end

--- 检查并执行升级（内部）
---@param petData table
---@return boolean leveled 是否升级了
function M._CheckLevelUp(petData)
    local leveled = false
    while (petData.level or 1) < MAX_LEVEL do
        local needed = GetLevelExp(petData.level or 1)
        if needed <= 0 or (petData.exp or 0) < needed then break end
        petData.exp = petData.exp - needed
        petData.level = (petData.level or 1) + 1
        leveled = true
    end
    -- 满级后经验清零
    if (petData.level or 1) >= MAX_LEVEL then
        petData.exp = 0
    end
    return leveled
end

-- ============================================================================
-- 公开接口：出战 / 召回
-- ============================================================================

--- 设置出战灵宠
---@param petId number  传0表示召回
---@return boolean, string
function M.DoSetActive(petId)
    local p = EnsurePetData()
    if not p then return false, "数据未加载" end

    if petId == 0 then
        p.activePetId = 0
        GamePlayer.MarkDirty()
        return true, "已召回灵宠"
    end

    local owned = FindOwnedPet(p, petId)
    if not owned then return false, "未拥有此灵宠" end

    local def = DataWorld.GetPet(petId)
    p.activePetId = petId
    GamePlayer.MarkDirty()
    local name = def and def.name or "灵宠"
    GamePlayer.AddLog(name .. "出战")
    return true, name .. "已出战"
end

--- 获取可喂养的材料列表及其经验值
---@return table[] { name, exp }
function M.GetFeedableItems()
    local result = {}
    for name, exp in pairs(FEED_ITEMS) do
        result[#result + 1] = { name = name, exp = exp }
    end
    table.sort(result, function(a, b) return a.exp < b.exp end)
    return result
end

return M
