---@diagnostic disable: param-type-mismatch
-- ============================================================================
-- ThemedDialog - 主题化弹窗（古代工坊风格）
-- Project Smith
--
-- 替代内置 UI.Modal.Confirm/Alert，统一弹窗样式与游戏主题一致。
-- ============================================================================

local UI = require("urhox-libs/UI")
local Theme = require("Utils.Theme")
local SFXManager = require("Utils.SFXManager")

local ThemedDialog = {}

local C = Theme.Colors

-- ============================================================================
-- Confirm 确认弹窗
-- options: { title, message, confirmText, cancelText, onConfirm, onCancel, danger }
-- ============================================================================

function ThemedDialog.Confirm(options)
    options = options or {}

    local isDanger = options.danger == true

    local modal = UI.Modal {
        title = options.title or "确认",
        size = "sm",
        showCloseButton = true,
        closeOnOverlay = true,
        borderRadius = 8,
        backgroundColor = "#12100E",
        borderColor = isDanger and "#E94560" or "#D4A574",
        borderWidth = 1.5,
        titleTextColor = isDanger and "#E94560" or "#D4A574",
        titleFontWeight = "bold",
        contentBgColor = { 31, 26, 23, 255 },
        contentPadding = { 20, 24, 20, 24 },
        headerStripeColor = isDanger and { 233, 69, 96, 80 } or { 201, 164, 90, 60 },
        headerStripeHeight = 1,
    }

    -- 消息文本
    local msgLabel = UI.Label {
        text = options.message or "",
        fontSize = 18,
        fontColor = "#E8E0D0",
        width = "100%",
        lineHeight = 1.2,
    }
    modal:AddContent(msgLabel)

    -- 底部按钮行
    local footer = UI.Panel {
        flexDirection = "row",
        justifyContent = "center",
        gap = 16,
        width = "100%",
    }

    -- 取消按钮
    local cancelBtn = UI.Button {
        text = options.cancelText or "取消",
        variant = "secondary",
        height = 38,
        paddingLeft = 20,
        paddingRight = 20,
        onClick = function()
            SFXManager.Play(SFXManager.SFX.UI_TAP, 0.3)
            modal:Close()
            if options.onCancel then options.onCancel() end
        end,
    }
    footer:AddChild(cancelBtn)

    -- 确认按钮
    local confirmBtn = UI.Button {
        text = options.confirmText or "确认",
        variant = "primary",
        height = 38,
        paddingLeft = 20,
        paddingRight = 20,
        backgroundColor = isDanger and "#E94560" or "#D4A574",
        onClick = function()
            SFXManager.Play(SFXManager.SFX.UI_TAP, 0.4)
            modal:Close()
            if options.onConfirm then options.onConfirm() end
        end,
    }
    footer:AddChild(confirmBtn)

    modal:SetFooter(footer)
    modal:Open()

    return modal
end

-- ============================================================================
-- Alert 提示弹窗
-- options: { title, message, buttonText, onClose }
-- ============================================================================

function ThemedDialog.Alert(options)
    options = options or {}

    local modal = UI.Modal {
        title = options.title or "提示",
        size = "sm",
        showCloseButton = true,
        closeOnOverlay = true,
        borderRadius = 8,
        backgroundColor = "#12100E",
        borderColor = "#D4A574",
        borderWidth = 1.5,
        titleTextColor = "#D4A574",
        titleFontWeight = "bold",
        contentBgColor = { 31, 26, 23, 255 },
        contentPadding = { 20, 24, 20, 24 },
        headerStripeColor = { 201, 164, 90, 60 },
        headerStripeHeight = 1,
    }

    local msgLabel = UI.Label {
        text = options.message or "",
        fontSize = 18,
        fontColor = "#E8E0D0",
        width = "100%",
        lineHeight = 1.2,
    }
    modal:AddContent(msgLabel)

    local footer = UI.Panel {
        flexDirection = "row",
        justifyContent = "center",
        width = "100%",
    }

    local okBtn = UI.Button {
        text = options.buttonText or "知道了",
        variant = "primary",
        height = 38,
        paddingLeft = 24,
        paddingRight = 24,
        backgroundColor = "#D4A574",
        onClick = function()
            SFXManager.Play(SFXManager.SFX.UI_TAP, 0.3)
            modal:Close()
            if options.onClose then options.onClose() end
        end,
    }
    footer:AddChild(okBtn)

    modal:SetFooter(footer)
    modal:Open()

    return modal
end

return ThemedDialog
