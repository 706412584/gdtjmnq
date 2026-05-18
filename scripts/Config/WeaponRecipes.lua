-- ============================================================================
-- WeaponRecipes - 武器配方数据接口
-- Project Smith / P1-B5
--
-- 提供武器配方的查询接口，数据来源于 weapon_recipes.json。
-- ============================================================================

local DataLoader = require("Config.DataLoader")

local WeaponRecipes = {}

local DATA_PATH = "Config/data/weapon_recipes.json"

---@type table[]|nil
local recipes_ = nil

--- 确保数据已加载
local function EnsureLoaded()
    if not recipes_ then
        recipes_ = DataLoader.Load(DATA_PATH)
        if not recipes_ then
            recipes_ = {}
            print("[WeaponRecipes] WARNING: Failed to load " .. DATA_PATH)
        end
    end
end

--- 获取全部武器配方
---@return table[]
function WeaponRecipes.GetAll()
    EnsureLoaded()
    return recipes_
end

--- 按 ID 查找配方
---@param id string 武器 ID（如 "WEAPON_001"）
---@return table|nil
function WeaponRecipes.GetById(id)
    EnsureLoaded()
    for i = 1, #recipes_ do
        if recipes_[i].id == id then
            return recipes_[i]
        end
    end
    return nil
end

--- 按武器线查找配方
---@param line string 武器线名称（如 "short_blade"）
---@return table[]
function WeaponRecipes.GetByLine(line)
    EnsureLoaded()
    local result = {}
    for i = 1, #recipes_ do
        if recipes_[i].line == line then
            result[#result + 1] = recipes_[i]
        end
    end
    return result
end

--- 获取已解锁的配方（基于章节）
---@param chapter number 当前章节
---@return table[]
function WeaponRecipes.GetUnlocked(chapter)
    EnsureLoaded()
    local result = {}
    for i = 1, #recipes_ do
        if recipes_[i].unlockChapter <= chapter then
            result[#result + 1] = recipes_[i]
        end
    end
    return result
end

--- 获取配方所需的步骤列表
---@param weaponId string 武器 ID
---@return string[]|nil 步骤类型列表（如 {"ore_select", "forging", "polishing"}）
function WeaponRecipes.GetSteps(weaponId)
    local recipe = WeaponRecipes.GetById(weaponId)
    if recipe then
        return recipe.steps
    end
    return nil
end

--- 获取配方所需的材料
---@param weaponId string 武器 ID
---@return table|nil { materialName = count }
function WeaponRecipes.GetRequiredMaterials(weaponId)
    local recipe = WeaponRecipes.GetById(weaponId)
    if recipe then
        return recipe.requiredMaterials
    end
    return nil
end

return WeaponRecipes
