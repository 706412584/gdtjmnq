-- ============================================================================
-- BackButton - 统一返回按钮样式工具
-- 将布局中的 plate_3 返回按钮统一改为加大的 "< 返回" 样式
-- 并将页面标题 tx_6 右移避免重叠
-- ============================================================================
---@diagnostic disable: param-type-mismatch

local UI = require("urhox-libs/UI")
local ScreenRouter = require("Utils.ScreenRouter")
local SFXManager   = require("Utils.SFXManager")

local BackButton = {}

--- 初始化页面的返回按钮（统一样式）
---@param root table 页面根节点
---@param targetOrCallback string|function|nil 返回目标页面名(默认"home")或自定义回调函数
function BackButton.Setup(root, targetOrCallback)
    local backBtn = root:FindById("plate_3")
    if not backBtn then return end

    -- 加大按钮尺寸
    backBtn:SetStyle({ width = 110, height = 56, left = "1%", top = "1.5%" })

    -- 隐藏所有旧子元素（布局导出的边框和"返"字）
    local children = backBtn:GetChildren()
    if children then
        for i = 1, #children do
            children[i].visible = false
        end
    end

    -- 新按钮外观
    local btnLabel = UI.Label {
        text = "< 返回",
        fontSize = 23,
        fontColor = "#D4A574",
        textAlign = "center",
    }
    local btnFrame = UI.Panel {
        width = "100%", height = "100%",
        borderRadius = 12,
        borderColor = "#D4A574",
        borderWidth = 1.5,
        justifyContent = "center",
        alignItems = "center",
    }
    btnFrame:AddChild(btnLabel)
    backBtn:AddChild(btnFrame)

    backBtn.props.onClick = function()
        SFXManager.Play(SFXManager.SFX.UI_TAP, 0.4)
        if type(targetOrCallback) == "function" then
            targetOrCallback()
        else
            ScreenRouter.GoTo(targetOrCallback or "home")
        end
    end

    -- 标题右移，避免重叠（按钮 1%+110≈123px，留 ~37px 间距）
    local headerTitle = root:FindById("tx_6")
    if headerTitle then headerTitle:SetStyle({ left = 160 }) end
end

return BackButton
