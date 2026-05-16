-- ============================================================================
-- 《问道长生》功法修炼模块
-- 职责：功法升级检查与执行
-- 设计：Can/Do 模式
-- ============================================================================

local GamePlayer = require("game_player")
local DataSkills = require("data_skills")

local M = {}

-- ============================================================================
-- 功法修炼
-- ============================================================================

--- 检查是否可以修炼（升级）功法
---@param skillName string
---@return boolean, string|nil
function M.CanTrainSkill(skillName)
    local p = GamePlayer.Get()
    if not p then return false, "数据未加载" end

    -- 在玩家拥有的功法中查找
    local found = nil
    for _, sk in ipairs(p.skills or {}) do
        if sk.name == skillName then
            found = sk
            break
        end
    end
    if not found then return false, "未拥有该功法" end

    -- 等级上限
    if found.level >= (found.maxLevel or 10) then
        return false, "功法已达最高等级"
    end

    -- 查询下一级所需悟性
    local nextLv = DataSkills.GetSkillLevel(found.level + 1)
    if not nextLv then return false, "无法获取升级配置" end

    if (p.wisdom or 0) < nextLv.wisdomReq then
        return false, "悟性不足"
    end

    return true, nil
end

--- 执行功法修炼（立即升级，不等时间）
---@param skillName string
---@return boolean, string
function M.DoTrainSkill(skillName)
    local ok, reason = M.CanTrainSkill(skillName)
    if not ok then return false, reason or "无法修炼" end

    local p = GamePlayer.Get()
    local skill = nil
    for _, sk in ipairs(p.skills or {}) do
        if sk.name == skillName then
            skill = sk
            break
        end
    end

    local oldLv = skill.level
    skill.level = skill.level + 1

    -- 刷新派生属性（功法效果变更）
    GamePlayer.RefreshDerived()
    GamePlayer.MarkDirty()

    local msg = "<c=gold>" .. skill.name .. "</c> 升级至 <c=yellow>Lv." .. skill.level .. "</c>"
    GamePlayer.AddLog(msg)
    return true, msg
end

return M
