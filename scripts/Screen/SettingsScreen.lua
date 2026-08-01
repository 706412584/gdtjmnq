-- ============================================================================
-- SettingsScreen - 设置界面 (Layout Migration)
-- Project Smith / P3-C3
--
-- 使用 ui_SettingsScreen_设置.lua 布局 + FindById 绑定数据/事件
-- 隐藏暂未实现的功能Tab（操作、账号），保留可用功能
-- ============================================================================

local UI           = require("urhox-libs/UI")
local GameState    = require("Core.GameState")
local SettingsManager = require("Core.SettingsManager")
local ScreenRouter   = require("Utils.ScreenRouter")
local SFXManager   = require("Utils.SFXManager")
local ThemedDialog = require("Utils.ThemedDialog")
local BackButton   = require("Utils.BackButton")
local Layout       = require("ui_SettingsScreen_设置")

local SettingsScreen = {}

-- ============================================================================
-- 侧栏 Tab 定义（仅保留可用功能）
-- ============================================================================

local TAB_DEFS = {
    { id = "side_e", bgId = "sr_f", labelId = "tx_g", name = "音画",   sectionTitle = "· 音画 ·  灯火与笛声" },
    { id = "side_h", bgId = "sr_i", labelId = "tx_j", name = "性能",   sectionTitle = "· 性能 ·  动效与功耗" },
    { id = "side_k", bgId = "sr_l", labelId = "tx_m", name = "账号",   sectionTitle = "· 账号 ·  铁匠身份", hidden = true },
    { id = "side_n", bgId = "sr_o", labelId = "tx_p", name = "游戏",   sectionTitle = "· 游戏 ·  画质偏好" },
    { id = "side_q", bgId = "sr_r", labelId = "tx_s", name = "帮助",   sectionTitle = "· 帮助 ·  师承指引", hidden = true },
    { id = "side_t", bgId = "sr_u", labelId = "tx_v", name = "关于",   sectionTitle = "· 关于 ·  工坊铭记" },
}

-- 音量行定义 (id: 轨道背景, 填充条, 滑块圆点, 百分比文字)
local VOLUME_ROWS = {
    { rowId = "row_18", labelId = "tx_1a", trackId = "sr_14", fillId = "sr_15", thumbId = "sc_16", valueId = "tx_17", key = "masterVolume", default = 80 },
    { rowId = "row_1f", labelId = "tx_1h", trackId = "sr_1b", fillId = "sr_1c", thumbId = "sc_1d", valueId = "tx_1e", key = "musicVolume",  default = 80 },
    { rowId = "row_1m", labelId = "tx_1o", trackId = "sr_1i", fillId = "sr_1j", thumbId = "sc_1k", valueId = "tx_1l", key = "ambientVolume", default = 50 },
}

-- 性能开关：当前仅开放已真实接入的低功耗模式。
local TOGGLE_ROWS = {
    { rowId = "row_1w", labelId = "tx_1y", bgId = "sr_1u", thumbId = "sc_1v", key = "lowPower", default = false },
}

-- 选项行颜色
local SELECTED_BG     = "#C96A2B"
local SELECTED_TEXT   = "#f1e5cc"
local UNSELECTED_TEXT = "#c9a45a"

-- 画质选项
local QUALITY_OPTS = {
    { bgId = "sr_1z", labelId = "tx_20", value = "smooth" },
    { bgId = "sr_21", labelId = "tx_22", value = "standard" },
    { bgId = "sr_23", labelId = "tx_24", value = "high" },
    { bgId = "sr_25", labelId = "tx_26", value = "ultra" },
}

-- 字体大小选项
local FONT_OPTS = {
    { bgId = "sr_2a", labelId = "tx_2b", value = "small" },
    { bgId = "sr_2c", labelId = "tx_2d", value = "medium" },
    { bgId = "sr_2e", labelId = "tx_2f", value = "large" },
}

-- 当前仅简体中文已完成本地化，其他语言不作为可选项展示。
local LANG_OPTS = {
    { bgId = "sr_2j", labelId = "tx_2k", value = "zh-CN" },
}

-- ============================================================================
-- Screen 接口
-- ============================================================================

---@param container table UI 容器
---@param params table|nil
---@return table screen
function SettingsScreen.Create(container, params)
    local screen = {}

    -- 构建布局
    local root = Layout.Build()
    container:AddChild(root)

    -- ----------------------------------------------------------------
    -- 加载设置
    -- ----------------------------------------------------------------
    local settings = SettingsManager.Normalize(GameState.GetSettings())
    local state = {
        activeTab     = 1,
        masterVolume  = settings.sfxVolume,
        musicVolume   = settings.musicVolume,
        ambientVolume = settings.ambientVolume,
        vibration     = false,
        lowPower      = settings.lowPower,
        quality       = settings.quality,
        fontSize      = settings.fontSize,
        language      = settings.language,
    }

    -- 当前设置打包与即时应用。所有可见设置都必须产生可观察效果。
    local function BuildSettings()
        return {
            sfxVolume = math.floor(state.masterVolume),
            musicVolume = math.floor(state.musicVolume),
            ambientVolume = math.floor(state.ambientVolume),
            vibration = false,
            lowPower = state.lowPower,
            quality = state.quality,
            fontSize = state.fontSize,
            language = "zh-CN",
        }
    end

    local function ApplyState(applyFonts)
        SettingsManager.SaveAndApply(BuildSettings())
        SFXManager.RefreshLoopGains()
        if applyFonts then
            SettingsManager.ApplyToTree(root)
        end
    end

    -- 应用初始音量和环境循环增益
    SettingsManager.Apply(settings)
    SFXManager.RefreshLoopGains()

    -- 同步侧栏显示文本
    local performanceTabLabel = root:FindById("tx_j")
    if performanceTabLabel then performanceTabLabel.text = "性能" end

    -- ----------------------------------------------------------------
    -- 隐藏未实现的 Tab（visible=false 跳过布局，不占空间）
    -- ----------------------------------------------------------------
    for _, def in ipairs(TAB_DEFS) do
        if def.hidden then
            local tabPanel = root:FindById(def.id)
            if tabPanel then tabPanel.visible = false end
        end
    end

    -- ----------------------------------------------------------------
    -- 左上角返回按钮（统一样式）
    -- ----------------------------------------------------------------
    BackButton.Setup(root, "home")

    -- ----------------------------------------------------------------
    -- 重新定位可见 Tab（隐藏的 Tab 留下空位，需手动重排）
    -- ----------------------------------------------------------------
    local visibleTabIds = {}
    for _, def in ipairs(TAB_DEFS) do
        if not def.hidden then
            visibleTabIds[#visibleTabIds + 1] = def.id
        end
    end
    local TAB_START_TOP = 12.50   -- 第一个 Tab 的 top%
    local TAB_INTERVAL  = 8.33   -- 每个 Tab 间距%
    for i, tabId in ipairs(visibleTabIds) do
        local tabPanel = root:FindById(tabId)
        if tabPanel then
            tabPanel.top = string.format("%.2f%%", TAB_START_TOP + (i - 1) * TAB_INTERVAL)
        end
    end

    -- ----------------------------------------------------------------
    -- 侧栏 Tab 交互
    -- ----------------------------------------------------------------
    local sectionTitle = root:FindById("tx_12")

    -- 所有内容行（按Tab显隐）
    -- Tab1=音画: row_18, row_1f, row_1m (音量行)
    -- Tab2=操作: row_1r, row_1w (开关行) -- 已隐藏
    -- Tab3=账号: (暂无内容行) -- 已隐藏
    -- Tab4=游戏: row_27, row_2g (画质/字体)
    -- Tab5=帮助: (暂无) -- 已隐藏
    -- Tab6=关于: row_2r (语言)
    local TAB_ROWS = {
        [1] = { "row_18", "row_1f", "row_1m" },
        [2] = { "row_1w" },
        [3] = {},
        [4] = { "row_27", "row_2g" },
        [5] = {},
        [6] = { "row_2r" },
    }

    -- 收集所有内容行ID
    local ALL_ROW_IDS = {}
    for _, ids in pairs(TAB_ROWS) do
        for _, id in ipairs(ids) do
            ALL_ROW_IDS[id] = true
        end
    end

    local function SwitchTab(tabIdx)
        state.activeTab = tabIdx
        -- 更新侧栏高亮
        for i, def in ipairs(TAB_DEFS) do
            if not def.hidden then
                local bg = root:FindById(def.bgId)
                local label = root:FindById(def.labelId)
                if i == tabIdx then
                    if bg then bg.backgroundColor = "#C96A2B" end
                    if label then label.fontColor = "#f1e5cc" end
                else
                    if bg then bg.backgroundColor = "#00000000" end
                    if label then label.fontColor = "#1f1a17" end
                end
            end
        end
        -- 更新标题
        if sectionTitle then
            sectionTitle.text = TAB_DEFS[tabIdx].sectionTitle
        end
        -- 显隐行
        local visibleIds = TAB_ROWS[tabIdx] or {}
        local visibleSet = {}
        for _, id in ipairs(visibleIds) do visibleSet[id] = true end
        for id, _ in pairs(ALL_ROW_IDS) do
            local row = root:FindById(id)
            if row then
                row.visible = visibleSet[id] == true
            end
        end
    end

    -- 绑定Tab点击（仅可用Tab）
    for i, def in ipairs(TAB_DEFS) do
        if not def.hidden then
            local tabPanel = root:FindById(def.id)
            if tabPanel then
                tabPanel.props.onClick = function()
                    SFXManager.Play(SFXManager.SFX.UI_TAP, 0.4)
                    SwitchTab(i)
                end
            end
        end
    end

    -- ----------------------------------------------------------------
    -- 音量滑块 - 用真正的 UI.Slider 替换布局中的假进度条
    -- ----------------------------------------------------------------
    local volumeSliders = {}

    for _, def in ipairs(VOLUME_ROWS) do
        local value = state[def.key] or def.default
        local row = root:FindById(def.rowId)
        if row then
            -- 隐藏布局中的假轨道/填充/滑块圆点
            local track = root:FindById(def.trackId)
            local fill = root:FindById(def.fillId)
            local thumb = root:FindById(def.thumbId)
            if track then track.visible = false end
            if fill then fill.visible = false end
            if thumb then thumb.visible = false end

            -- 更新百分比文字颜色统一为金色
            local valLabel = root:FindById(def.valueId)
            if valLabel then
                valLabel.text = tostring(math.floor(value)) .. "%"
                valLabel.fontColor = "#C9A45A"
            end

            -- 创建真正的 Slider 控件，绝对定位在文字下方
            local slider = UI.Slider {
                value = value / 100,
                min = 0,
                max = 1,
                step = 0.01,
                position = "absolute",
                left = "26%",
                top = "55%",
                width = "55%",
                height = 32,
                trackHeight = 6,
                thumbSize = 20,
                trackColor = "rgba(60,50,40,0.5)",
                trackFillColor = "#C9A45A",
                thumbColor = "#D4A574",
                onChange = function(self, v)
                    local vol = math.floor(v * 100 + 0.5)
                    state[def.key] = vol
                    if valLabel then
                        valLabel.text = tostring(vol) .. "%"
                    end
                    if def.key == "masterVolume" then
                        audio:SetMasterGain(SOUND_EFFECT, v)
                    elseif def.key == "musicVolume" then
                        audio:SetMasterGain(SOUND_MUSIC, v)
                    elseif def.key == "ambientVolume" then
                        ApplyState(false)
                    end
                end,
            }
            row:AddChild(slider)
            volumeSliders[def.key] = slider
        end
    end

    -- ----------------------------------------------------------------
    -- 性能开关：低功耗模式会关闭装饰动画并降低装饰更新频率。
    -- ----------------------------------------------------------------
    local function UpdateToggleVisual(def)
        local bg = root:FindById(def.bgId)
        local thumb = root:FindById(def.thumbId)
        local enabled = state[def.key] == true
        if bg then
            bg.backgroundColor = enabled and "#4ECDC4" or "rgba(31,26,23,0.3)"
        end
        if thumb then
            thumb.left = enabled and "29.0%" or "26.4%"
            thumb.backgroundColor = enabled and "#E8E0D0" or "#5A4A3A"
        end
    end

    for _, def in ipairs(TOGGLE_ROWS) do
        UpdateToggleVisual(def)
        local row = root:FindById(def.rowId)
        if row then
            row.props.onClick = function()
                state[def.key] = not state[def.key]
                UpdateToggleVisual(def)
                ApplyState(false)
                SFXManager.Play(SFXManager.SFX.UI_TAP, 0.4)
            end
        end
    end

    -- 振动没有稳定的平台接口，隐藏对应行，避免形成伪设置。
    local vibrationRow = root:FindById("row_1r")
    if vibrationRow then vibrationRow.visible = false end

    -- ----------------------------------------------------------------
    -- 选项行交互 (画质/字体/语言)
    -- ----------------------------------------------------------------
    local function UpdateOptionVisual(opts, selectedValue)
        for _, opt in ipairs(opts) do
            local bg = root:FindById(opt.bgId)
            local label = root:FindById(opt.labelId)
            if opt.value == selectedValue then
                if bg then
                    bg.backgroundColor = SELECTED_BG
                    bg.borderWidth = 0
                end
                if label then label.fontColor = SELECTED_TEXT end
            else
                if bg then
                    bg.backgroundColor = "#00000000"
                    bg.borderWidth = 2
                    bg.borderColor = "#C9A45A"
                end
                if label then label.fontColor = UNSELECTED_TEXT end
            end
        end
    end

    -- 画质
    UpdateOptionVisual(QUALITY_OPTS, state.quality)
    for _, opt in ipairs(QUALITY_OPTS) do
        local bg = root:FindById(opt.bgId)
        if bg then
            bg.props.onClick = function()
                SFXManager.Play(SFXManager.SFX.UI_TAP, 0.4)
                state.quality = opt.value
                UpdateOptionVisual(QUALITY_OPTS, opt.value)
                ApplyState(false)
            end
        end
    end

    -- 字体
    UpdateOptionVisual(FONT_OPTS, state.fontSize)
    for _, opt in ipairs(FONT_OPTS) do
        local bg = root:FindById(opt.bgId)
        if bg then
            bg.props.onClick = function()
                SFXManager.Play(SFXManager.SFX.UI_TAP, 0.4)
                state.fontSize = opt.value
                UpdateOptionVisual(FONT_OPTS, opt.value)
                ApplyState(true)
            end
        end
    end

    -- 语言
    UpdateOptionVisual(LANG_OPTS, state.language)
    for _, opt in ipairs(LANG_OPTS) do
        local bg = root:FindById(opt.bgId)
        if bg then
            bg.props.onClick = function()
                SFXManager.Play(SFXManager.SFX.UI_TAP, 0.4)
                state.language = opt.value
                UpdateOptionVisual(LANG_OPTS, opt.value)
                ApplyState(false)
            end
        end
    end

    -- 未完成翻译的语言选项整体隐藏，不让玩家选择无效语言。
    local unsupportedLanguageIds = { "sr_2l", "tx_2m", "sr_2n", "tx_2o", "sr_2p", "tx_2q" }
    for i = 1, #unsupportedLanguageIds do
        local item = root:FindById(unsupportedLanguageIds[i])
        if item then item.visible = false end
    end

    -- ----------------------------------------------------------------
    -- 底部按钮
    -- ----------------------------------------------------------------
    -- 保存设置
    local saveBtn = root:FindById("plate_2u")
    if saveBtn then
        saveBtn.props.onClick = function()
            SFXManager.Play(SFXManager.SFX.UI_TAP, 0.4)
            ApplyState(true)
            UI.Toast.Show("设置已保存")
            print("[SettingsScreen] Settings saved")
        end
    end

    -- 重置默认
    local resetBtn = root:FindById("plate_2x")
    if resetBtn then
        resetBtn.props.onClick = function()
            SFXManager.Play(SFXManager.SFX.UI_TAP, 0.4)
            state.masterVolume = 80
            state.musicVolume = 60
            state.ambientVolume = 50
            state.vibration = false
            state.lowPower = false
            state.quality = "standard"
            state.fontSize = "medium"
            state.language = "zh-CN"
            -- 刷新所有滑块
            for _, def in ipairs(VOLUME_ROWS) do
                local sl = volumeSliders[def.key]
                if sl then sl.value = state[def.key] / 100 end
                local valLabel = root:FindById(def.valueId)
                if valLabel then valLabel.text = tostring(state[def.key]) .. "%" end
            end
            UpdateOptionVisual(QUALITY_OPTS, state.quality)
            UpdateOptionVisual(FONT_OPTS, state.fontSize)
            UpdateOptionVisual(LANG_OPTS, state.language)
            for _, def in ipairs(TOGGLE_ROWS) do UpdateToggleVisual(def) end
            ApplyState(true)
            UI.Toast.Show("已恢复默认设置")
            print("[SettingsScreen] Settings reset to defaults")
        end
    end

    -- 删档重来（原"退出登录"按钮）
    local logoutBtn = root:FindById("plate_30")
    if logoutBtn then
        -- 更新按钮文字为"删档重来"
        local logoutLabel = root:FindById("tx_32")
        if logoutLabel then
            logoutLabel.text = "删档重来"
            logoutLabel.fontColor = "#E94560"
        end
        logoutBtn.props.onClick = function()
            SFXManager.Play(SFXManager.SFX.UI_TAP, 0.4)
            ThemedDialog.Confirm({
                title = "确认删档",
                message = "确定要删除所有存档数据吗？铜钱、声望、材料、订单进度、图鉴等全部数据将被清空，此操作不可撤销！",
                confirmText = "确认删除",
                cancelText = "取消",
                danger = true,
                onConfirm = function()
                    GameState.Reset()
                    GameState.ForceSave(function()
                        print("[SettingsScreen] Save wiped, navigating to home")
                        ScreenRouter.GoTo("home")
                    end)
                end,
            })
        end
    end

    -- ----------------------------------------------------------------
    -- 初始化显示
    -- ----------------------------------------------------------------
    SwitchTab(1) -- 默认显示"音画"Tab

    -- ----------------------------------------------------------------
    -- 清理
    -- ----------------------------------------------------------------
    function screen.Destroy()
        ApplyState(false)
    end

    return screen
end

return SettingsScreen
