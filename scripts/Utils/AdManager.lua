-- ============================================================================
-- AdManager - 激励视频广告封装
-- Project Smith
--
-- 统一封装 sdk:ShowRewardVideoAd，处理各种结果分支，只有完整观看
-- (result.success == true) 才回调发奖。
--
-- 注意：广告需在 TapTap 开发者后台开通"广告变现"后才能真正播放，
--       未开通/非嵌入环境会走失败分支并给出友好提示。
-- ============================================================================

local UI = require("urhox-libs/UI")

local AdManager = {}

--- 观看激励视频广告
---@param onReward fun() 完整观看后的发奖回调（仅 success 时触发）
---@param onFail fun(msg: string)|nil 失败回调（可选）
function AdManager.WatchAd(onReward, onFail)
    -- sdk 为引擎运行时全局，LSP 类型未声明，通过 _G 访问；非嵌入环境可能不存在
    local sdk_ = rawget(_G, "sdk")
    if not sdk_ or not sdk_.ShowRewardVideoAd then
        UI.Toast.Show("当前环境暂不支持广告", { type = "warning", duration = 2 })
        if onFail then onFail("no sdk") end
        return
    end

    sdk_:ShowRewardVideoAd(function(result)
        if result and result.success then
            if onReward then onReward() end
        else
            local msg = (result and result.msg) or "未知错误"
            if msg == "embed manual close" then
                UI.Toast.Show("需完整观看广告才能获得奖励", { type = "warning", duration = 2.5 })
            elseif msg == "unsupported platform" then
                UI.Toast.Show("当前环境暂不支持广告", { type = "warning", duration = 2 })
            else
                UI.Toast.Show("广告暂时无法播放，请稍后再试", { type = "warning", duration = 2 })
            end
            if onFail then onFail(msg) end
        end
    end)
end

return AdManager
