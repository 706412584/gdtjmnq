-- ============================================================================
-- 《问道长生》悟道模块
-- 职责：悟道参悟（增加进度、悟透奖励）
-- 设计：Can/Do 模式
-- ============================================================================

local GamePlayer = require("game_player")
local GameItems  = require("game_items")
local DataSkills = require("data_skills")

local M = {}

-- 每次参悟增加的进度范围
local PROGRESS_MIN = 5
local PROGRESS_MAX = 15

-- ============================================================================
-- 悟道参悟
-- ============================================================================

--- 检查是否可以参悟
---@param daoName string
---@return boolean, string|nil
function M.CanMeditate(daoName)
    local p = GamePlayer.Get()
    if not p then return false, "数据未加载" end

    local found = nil
    for _, dao in ipairs(p.daoInsights or {}) do
        if dao.name == daoName then
            found = dao
            break
        end
    end
    if not found then return false, "未拥有该悟道" end

    if found.locked then return false, "该悟道尚未解锁" end

    local maxProg = found.maxProgress or 100
    if (found.progress or 0) >= maxProg then
        return false, "已悟透此道"
    end

    return true, nil
end

--- 执行一次参悟
---@param daoName string
---@return boolean, string
function M.DoMeditate(daoName)
    local ok, reason = M.CanMeditate(daoName)
    if not ok then return false, reason or "无法参悟" end

    local p = GamePlayer.Get()
    local dao = nil
    for _, d in ipairs(p.daoInsights or {}) do
        if d.name == daoName then
            dao = d
            break
        end
    end

    -- 增加进度（受悟性影响）
    local wisdomBonus = math.floor((p.wisdom or 0) / 50)
    local gain = math.random(PROGRESS_MIN, PROGRESS_MAX) + wisdomBonus
    local maxProg = dao.maxProgress or 100
    local oldProg = dao.progress or 0
    dao.progress = math.min(maxProg, oldProg + gain)

    GamePlayer.MarkDirty()

    -- 检查是否悟透
    if dao.progress >= maxProg then
        -- 应用悟透奖励
        local def = DataSkills.GetInsight(dao.id)
        local rewardStr = def and def.reward or dao.reward or ""
        local effectMsg = GameItems.ApplyEffect(rewardStr)
        local msg = "<c=gold>" .. dao.name .. "</c> 已悟透! " .. (effectMsg ~= "" and effectMsg or rewardStr)
        GamePlayer.AddLog(msg)
        return true, msg
    end

    local msg = "<c=gold>" .. dao.name .. "</c> 参悟 +<c=yellow>" .. gain .. "</c>（" .. dao.progress .. "/" .. maxProg .. "）"
    GamePlayer.AddLog(msg)
    return true, msg
end

return M
