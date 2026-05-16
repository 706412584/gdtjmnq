-- ============================================================================
-- 《问道长生》炼丹系统
-- 职责：材料校验、材料消耗、成功率判定（含气运加成）、丹药产出
-- 设计：Can/Do 模式，所有操作先检查后执行
-- ============================================================================

local GamePlayer = require("game_player")
local DataItems  = require("data_items")
local GameQuest  = require("game_quest")
local Loading    = require("ui_loading")

local M = {}

-- ============================================================================
-- 气运 → 炼丹成功率加成
-- ============================================================================
local FORTUNE_BONUS = {
    ["低迷"] = -5,
    ["普通"] = 0,
    ["小吉"] = 5,
    ["大吉"] = 10,
    ["天命"] = 15,
}

-- ============================================================================
-- 丹方查询
-- ============================================================================

--- 获取全部可炼丹方（通用 + 限制 + 突破）
---@return table[]
function M.GetAllRecipes()
    local recipes = {}
    for _, p in ipairs(DataItems.PILLS_COMMON) do
        recipes[#recipes + 1] = p
    end
    for _, p in ipairs(DataItems.PILLS_LIMITED) do
        recipes[#recipes + 1] = p
    end
    for _, p in ipairs(DataItems.PILLS_BREAKTHROUGH) do
        recipes[#recipes + 1] = p
    end
    return recipes
end

--- 根据 id 查找丹方
---@param recipeId string
---@return table|nil
function M.FindRecipe(recipeId)
    return DataItems.FindPill(recipeId)
end

--- 根据名称查找丹方
---@param name string
---@return table|nil
function M.FindRecipeByName(name)
    return DataItems.FindPillByName(name)
end

-- ============================================================================
-- 材料查询
-- ============================================================================

--- 获取背包中某材料的数量
---@param matName string
---@return number
function M.GetMaterialCount(matName)
    local p = GamePlayer.Get()
    if not p then return 0 end
    for _, item in ipairs(p.bagItems or {}) do
        if item.name == matName then
            return item.count or 0
        end
    end
    return 0
end

--- 检查某丹方各材料的持有情况
---@param recipeId string
---@return table[] { name, need, have, enough }
function M.CheckMaterials(recipeId)
    local recipe = DataItems.FindPill(recipeId)
    if not recipe or not recipe.materials then return {} end
    local result = {}
    for matName, needCount in pairs(recipe.materials) do
        local have = M.GetMaterialCount(matName)
        result[#result + 1] = {
            name   = matName,
            need   = needCount,
            have   = have,
            enough = have >= needCount,
        }
    end
    return result
end

-- ============================================================================
-- 炼丹：Can/Do
-- ============================================================================

--- 检查是否可以炼制某丹药
---@param recipeId string 丹方 id
---@return boolean, string|nil
function M.CanAlchemy(recipeId)
    local p = GamePlayer.Get()
    if not p then return false, "数据未加载" end

    local recipe = DataItems.FindPill(recipeId)
    if not recipe then return false, "未知丹方" end
    if not recipe.materials then return false, "丹方缺少材料配置" end

    -- 检查每种材料是否足够
    for matName, needCount in pairs(recipe.materials) do
        local have = M.GetMaterialCount(matName)
        if have < needCount then
            return false, matName .. "不足"
        end
    end

    return true, nil
end

--- 执行炼丹
---@param recipeId string 丹方 id
---@return boolean success, string message
function M.DoAlchemy(recipeId)
    local ok, reason = M.CanAlchemy(recipeId)
    if not ok then return false, reason or "无法炼制" end

    -- 网络模式：发送到服务端判定（随机数在服务端生成）
    if IsNetworkMode() then
        local Shared    = require("network.shared")
        local ClientNet = require("network.client_net")
        local GameServer = require("game_server")
        ---@diagnostic disable-next-line: undefined-global
        local cjson     = cjson
        local data = VariantMap()
        data["Action"] = Variant("alchemy")
        data["Params"] = Variant(cjson.encode({
            serverId = GameServer.GetCurrentServer().id,
            recipeId = recipeId,
        }))
        ClientNet.SendToServer(Shared.EVENTS.REQ_ALCHEMY_OP, data)
        Loading.Start(nil, 0.5)
        return true
    end

    local p = GamePlayer.Get()
    local recipe = DataItems.FindPill(recipeId)

    -- 1. 消耗材料
    for matName, needCount in pairs(recipe.materials) do
        GamePlayer.RemoveItemByName(matName, needCount)
    end

    -- 2. 计算最终成功率（基础 + 气运加成）
    local baseRate = recipe.rate or 50
    local fortune  = p.fortune or "普通"
    local bonus    = FORTUNE_BONUS[fortune] or 0
    local finalRate = math.max(1, math.min(100, baseRate + bonus))

    -- 3. 投骰
    local roll = math.random(100)

    if roll <= finalRate then
        -- 成功：添加丹药到 pills 列表（堆叠同名）
        local pills = p.pills or {}
        p.pills = pills
        local found = false
        for _, pill in ipairs(pills) do
            if pill.name == recipe.name then
                pill.count = (pill.count or 0) + 1
                found = true
                break
            end
        end
        if not found then
            pills[#pills + 1] = {
                name    = recipe.name,
                count   = 1,
                quality = recipe.quality or "common",
                desc    = recipe.effect or "",
                effect  = recipe.effect or "",
            }
        end

        GamePlayer.MarkDirty()
        -- 任务通知：炼丹成功
        GameQuest.NotifyAction("alchemy_success", 1)
        local msg = "炼丹成功！获得 <c=gold>" .. recipe.name .. " x1</c>"
        GamePlayer.AddLog(msg)
        return true, msg
    else
        -- 失败：材料已消耗
        GamePlayer.MarkDirty()
        GamePlayer.AddLog("炼制" .. recipe.name .. "失败，材料化为灰烬。")
        return false, "炼丹失败，材料已消耗（成功率<c=yellow>" .. finalRate .. "%</c>）"
    end
end

-- ============================================================================
-- 便捷：按名称炼丹
-- ============================================================================

--- 按丹药名称检查是否可炼制
---@param pillName string
---@return boolean, string|nil
function M.CanAlchemyByName(pillName)
    local recipe = DataItems.FindPillByName(pillName)
    if not recipe then return false, "未知丹方: " .. pillName end
    return M.CanAlchemy(recipe.id)
end

--- 按丹药名称执行炼丹
---@param pillName string
---@return boolean, string
function M.DoAlchemyByName(pillName)
    local recipe = DataItems.FindPillByName(pillName)
    if not recipe then return false, "未知丹方: " .. pillName end
    return M.DoAlchemy(recipe.id)
end

-- ============================================================================
-- 服务端回调（网络模式）
-- ============================================================================

--- 处理服务端炼丹/法宝强化回复（由 client_net.lua 中转调用）
---@param eventData any
function M.OnAlchemyResp(eventData)
    Loading.Stop()

    local action  = eventData["Action"]:GetString()
    local success = eventData["Success"]:GetBool()
    local msg     = eventData["Msg"]:GetString()

    local Toast = require("ui_toast")

    if not success then
        Toast.Show(msg, "error")
        return
    end

    ---@diagnostic disable-next-line: undefined-global
    local cjson = cjson
    local dataStr = eventData["Data"]:GetString()
    local ok2, data = pcall(cjson.decode, dataStr)
    if not ok2 then
        Toast.Show("数据解析失败", "error")
        return
    end

    local p = GamePlayer.Get()
    if not p then return end

    if action == "alchemy" then
        -- 同步背包和丹药数据（服务端已扣材料+加丹药）
        if data.bagItems then p.bagItems = data.bagItems end
        if data.pills    then p.pills    = data.pills end
        GamePlayer.MarkDirty()

        if data.success then
            GameQuest.NotifyAction("alchemy_success", 1)
            local pillMsg = "炼丹成功！获得 <c=gold>" .. (data.pillName or "丹药") .. " x1</c>"
            GamePlayer.AddLog(pillMsg)
            Toast.Show("炼丹成功！获得" .. (data.pillName or "丹药"), "success")
        else
            GamePlayer.AddLog("炼制" .. (data.pillName or "丹药") .. "失败，材料化为灰烬。")
            Toast.Show("炼丹失败（成功率" .. (data.rate or "?") .. "%）", "error")
        end

    elseif action == "enhance_artifact" then
        -- 法宝强化回调：转发给 game_artifact 处理
        local GameArtifact = require("game_artifact")
        GameArtifact.OnEnhanceResp(data)
    end
end

return M
