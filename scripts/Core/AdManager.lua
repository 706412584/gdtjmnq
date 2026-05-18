-- ============================================================================
-- AdManager - 广告管理器
-- Project Smith / P3-C1
--
-- 封装激励视频广告接口，提供统一的展示/回调/冷却管理。
-- 广告场景:
--   1. 双倍奖励（结算界面看广告翻倍铜钱/声望）
--   2. 额外材料（看广告获得稀有材料）
--   3. 复活机会（小游戏失败后看广告重试）
--
-- 使用方式:
--   local AdManager = require("Core.AdManager")
--   AdManager.ShowRewardAd("double_reward", function(success) ... end)
-- ============================================================================

local EventBus = require("Core.EventBus")

local AdManager = {}

-- ==================== 配置 ====================

--- 广告场景定义
local AD_SCENES = {
    double_reward = {
        name = "双倍奖励",
        cooldownSec = 0,         -- 无冷却（每单最多看一次，由业务层控制）
        description = "观看广告获得双倍铜钱和声望",
    },
    extra_material = {
        name = "额外材料",
        cooldownSec = 300,       -- 5 分钟冷却
        description = "观看广告获得稀有材料",
    },
    retry_chance = {
        name = "重试机会",
        cooldownSec = 0,         -- 无冷却
        description = "观看广告重新挑战当前步骤",
    },
}

--- 各场景上次展示时间
local lastShowTime_ = {}

--- 是否正在展示广告
local showing_ = false

-- ==================== 公共接口 ====================

--- 检查广告是否可用
---@param sceneId string 广告场景 ID
---@return boolean available
---@return string|nil reason 不可用原因
function AdManager.IsAvailable(sceneId)
    if showing_ then
        return false, "广告正在播放中"
    end

    local scene = AD_SCENES[sceneId]
    if not scene then
        return false, "未知的广告场景"
    end

    -- 冷却检查
    if scene.cooldownSec > 0 then
        local last = lastShowTime_[sceneId] or 0
        local elapsed = os.time() - last
        if elapsed < scene.cooldownSec then
            local remaining = scene.cooldownSec - elapsed
            return false, "冷却中（" .. remaining .. "秒）"
        end
    end

    return true
end

--- 展示激励视频广告
---@param sceneId string 广告场景 ID
---@param callback function(success:boolean, msg:string) 回调
function AdManager.ShowRewardAd(sceneId, callback)
    local available, reason = AdManager.IsAvailable(sceneId)
    if not available then
        print("[AdManager] Ad not available: " .. (reason or "unknown"))
        if callback then
            callback(false, reason or "广告不可用")
        end
        return
    end

    showing_ = true
    local scene = AD_SCENES[sceneId] or {}

    print("[AdManager] Showing reward ad: " .. sceneId .. " (" .. (scene.name or "") .. ")")

    EventBus.Emit("ad_show_start", { sceneId = sceneId })

    ---@diagnostic disable-next-line: undefined-global
    sdk:ShowRewardVideoAd(function(result)
        showing_ = false

        local success = result and result.success == true
        local msg = result and result.msg or "unknown"

        if success then
            lastShowTime_[sceneId] = os.time()
            print("[AdManager] Ad completed successfully: " .. sceneId)

            EventBus.Emit("ad_reward_granted", {
                sceneId = sceneId,
                sceneName = scene.name,
            })
        else
            print("[AdManager] Ad failed or cancelled: " .. sceneId .. " (" .. msg .. ")")

            EventBus.Emit("ad_show_failed", {
                sceneId = sceneId,
                msg = msg,
            })
        end

        if callback then
            callback(success, msg)
        end
    end)
end

--- 获取广告场景信息
---@param sceneId string
---@return table|nil
function AdManager.GetSceneInfo(sceneId)
    return AD_SCENES[sceneId]
end

--- 获取冷却剩余时间（秒）
---@param sceneId string
---@return number 0 表示已就绪
function AdManager.GetCooldownRemaining(sceneId)
    local scene = AD_SCENES[sceneId]
    if not scene or scene.cooldownSec <= 0 then return 0 end

    local last = lastShowTime_[sceneId] or 0
    local elapsed = os.time() - last
    local remaining = scene.cooldownSec - elapsed
    return math.max(0, remaining)
end

return AdManager
