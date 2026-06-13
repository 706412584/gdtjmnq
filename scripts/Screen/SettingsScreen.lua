-- ============================================================================
-- SettingsScreen - 设置界面 (Layout Migration)
-- Project Smith / P3-C3
--
-- 使用 ui_SettingsScreen_设置.lua 布局 + FindById 绑定数据/事件
-- ============================================================================

local UI          = require("urhox-libs/UI")
local GameState   = require("Core.GameState")
local ScreenRouter = require("Utils.ScreenRouter")
local Layout      = require("ui_SettingsScreen_设置")

local SettingsScreen = {}

-- ============================================================================
-- 侧栏 Tab 定义
-- ============================================================================

local TAB_DEFS = {
    { id = "side_e", bgId = "sr_f", labelId = "tx_g", name = "音画",   sectionTitle = "· 音画 ·  灯火与笛声" },
    { id = "side_h", bgId = "sr_i", labelId = "tx_j", name = "操作",   sectionTitle = "· 操作 ·  手感调校" },
    { id = "side_k", bgId = "sr_l", labelId = "tx_m", name = "账号",   sectionTitle = "· 账号 ·  铁匠身份" },
    { id = "side_n", bgId = "sr_o", labelId = "tx_p", name = "游戏",   sectionTitle = "· 游戏 ·  锻造统计" },
    { id = "side_q", bgId = "sr_r", labelId = "tx_s", name = "帮助",   sectionTitle = "· 帮助 ·  师承指引" },
    { id = "side_t", bgId = "sr_u", labelId = "tx_v", name = "关于",   sectionTitle = "· 关于 ·  工坊铭记" },
}

-- 音量行定义 (id: 轨道背景, 填充条, 滑块圆点, 百分比文字)
local VOLUME_ROWS = {
    { rowId = "row_18", labelId = "tx_1a", trackId = "sr_14", fillId = "sr_15", thumbId = "sc_16", valueId = "tx_17", key = "masterVolume", default = 76 },
    { rowId = "row_1f", labelId = "tx_1h", trackId = "sr_1b", fillId = "sr_1c", thumbId = "sc_1d", valueId = "tx_1e", key = "musicVolume",  default = 64 },
    { rowId = "row_1m", labelId = "tx_1o", trackId = "sr_1i", fillId = "sr_1j", thumbId = "sc_1k", valueId = "tx_1l", key = "ambientVolume", default = 50 },
}

-- 开关行定义
local TOGGLE_ROWS = {
    { rowId = "row_1r", labelId = "tx_1t", bgId = "sr_1p", thumbId = "sc_1q", key = "vibration", default = true },
    { rowId = "row_1w", labelId = "tx_1y", bgId = "sr_1u", thumbId = "sc_1v", key = "lowPower",  default = false },
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

-- 语言选项
local LANG_OPTS = {
    { bgId = "sr_2j", labelId = "tx_2k", value = "zh-CN" },
    { bgId = "sr_2l", labelId = "tx_2m", value = "zh-TW" },
    { bgId = "sr_2n", labelId = "tx_2o", value = "en" },
    { bgId = "sr_2p", labelId = "tx_2q", value = "ja" },
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
    local settings = GameState.GetSettings()
    local state = {
        activeTab     = 1,   -- 当前激活的Tab索引
        masterVolume  = settings.sfxVolume or 76,
        musicVolume   = settings.musicVolume or 64,
        ambientVolume = settings.ambientVolume or 50,
        vibration     = settings.vibration ~= false,  -- 默认开
        lowPower      = settings.lowPower == true,     -- 默认关
        quality       = settings.quality or "standard",
        fontSize      = settings.fontSize or "medium",
        language      = settings.language or "zh-CN",
    }

    -- 应用初始音量
    audio:SetMasterGain(SOUND_EFFECT, state.masterVolume / 100)
    audio:SetMasterGain(SOUND_MUSIC, state.musicVolume / 100)

    -- ----------------------------------------------------------------
    -- 返回按钮
    -- ----------------------------------------------------------------
    local backBtn = root:FindById("plate_3")
    if backBtn then
        backBtn.props.onClick = function()
            ScreenRouter.GoTo("home")
        end
    end

    -- ----------------------------------------------------------------
    -- 侧栏 Tab 交互
    -- ----------------------------------------------------------------
    local sectionTitle = root:FindById("tx_12")

    -- 所有内容行（按Tab显隐）
    -- Tab1=音画: row_18, row_1f, row_1m (音量行)
    -- Tab2=操作: row_1r, row_1w (开关行)
    -- Tab3=账号: (暂无内容行)
    -- Tab4=游戏: row_27, row_2g (画质/字体)
    -- Tab5=帮助: (暂无)
    -- Tab6=关于: row_2r (语言)
    local TAB_ROWS = {
        [1] = { "row_18", "row_1f", "row_1m" },
        [2] = { "row_1r", "row_1w" },
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
                row.display = visibleSet[id] and "flex" or "none"
            end
        end
    end

    -- 绑定Tab点击
    for i, def in ipairs(TAB_DEFS) do
        local tabPanel = root:FindById(def.id)
        if tabPanel then
            tabPanel.props.onClick = function()
                SwitchTab(i)
            end
        end
    end

    -- ----------------------------------------------------------------
    -- 音量滑块交互 (通过点击行调整 ±5)
    -- ----------------------------------------------------------------
    local TRACK_MAX_WIDTH = 843.34

    local function UpdateVolumeVisual(def, value)
        local fill = root:FindById(def.fillId)
        local valLabel = root:FindById(def.valueId)
        local thumb = root:FindById(def.thumbId)
        local ratio = value / 100
        if fill then
            fill.width = math.floor(TRACK_MAX_WIDTH * ratio)
        end
        if valLabel then
            valLabel.text = tostring(math.floor(value)) .. "%"
        end
        if thumb then
            -- 滑块位置用 left 百分比（相对行宽）
            local baseLeft = 26.17 -- 轨道起点百分比
            local trackSpan = 56.08 -- 轨道跨度百分比 (843.34/1503.95*100)
            thumb.left = string.format("%.2f%%", baseLeft + trackSpan * ratio)
        end
    end

    for _, def in ipairs(VOLUME_ROWS) do
        local value = state[def.key] or def.default
        UpdateVolumeVisual(def, value)

        -- 整行可点击 → 叠加一个透明的触控区域
        local row = root:FindById(def.rowId)
        if row then
            row.props.onClick = function()
                -- 简易: 每次点击 +10, 超100循环回0
                ---@diagnostic disable-next-line: assign-type-mismatch
                local v = (state[def.key] or def.default) + 10
                if v > 100 then v = 0 end
                state[def.key] = v
                UpdateVolumeVisual(def, v)
                -- 应用音量
                if def.key == "masterVolume" then
                    audio:SetMasterGain(SOUND_EFFECT, v / 100)
                elseif def.key == "musicVolume" then
                    audio:SetMasterGain(SOUND_MUSIC, v / 100)
                end
            end
        end
    end

    -- ----------------------------------------------------------------
    -- 开关行交互
    -- ----------------------------------------------------------------
    local function UpdateToggleVisual(def, isOn)
        local bg = root:FindById(def.bgId)
        local thumb = root:FindById(def.thumbId)
        if bg then
            bg.backgroundColor = isOn and "#4F7A63" or "rgba(31,26,23,0.3)"
        end
        if thumb then
            -- ON: 右侧, OFF: 左侧
            if isOn then
                thumb.left = "28.97%"
            else
                thumb.left = "26.36%"
            end
        end
    end

    for _, def in ipairs(TOGGLE_ROWS) do
        UpdateToggleVisual(def, state[def.key])
        local row = root:FindById(def.rowId)
        if row then
            row.props.onClick = function()
                state[def.key] = not state[def.key]
                UpdateToggleVisual(def, state[def.key])
            end
        end
    end

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
                state.quality = opt.value
                UpdateOptionVisual(QUALITY_OPTS, opt.value)
            end
        end
    end

    -- 字体
    UpdateOptionVisual(FONT_OPTS, state.fontSize)
    for _, opt in ipairs(FONT_OPTS) do
        local bg = root:FindById(opt.bgId)
        if bg then
            bg.props.onClick = function()
                state.fontSize = opt.value
                UpdateOptionVisual(FONT_OPTS, opt.value)
            end
        end
    end

    -- 语言
    UpdateOptionVisual(LANG_OPTS, state.language)
    for _, opt in ipairs(LANG_OPTS) do
        local bg = root:FindById(opt.bgId)
        if bg then
            bg.props.onClick = function()
                state.language = opt.value
                UpdateOptionVisual(LANG_OPTS, opt.value)
            end
        end
    end

    -- ----------------------------------------------------------------
    -- 底部按钮
    -- ----------------------------------------------------------------
    -- 保存设置
    local saveBtn = root:FindById("plate_2u")
    if saveBtn then
        saveBtn.props.onClick = function()
            GameState.SetSettings({
                sfxVolume     = math.floor(state.masterVolume),
                musicVolume   = math.floor(state.musicVolume),
                ambientVolume = math.floor(state.ambientVolume),
                vibration     = state.vibration,
                lowPower      = state.lowPower,
                quality       = state.quality,
                fontSize      = state.fontSize,
                language      = state.language,
            })
            print("[SettingsScreen] Settings saved")
            -- 简易Toast反馈：临时改按钮文字
            local label = root:FindById("tx_2w")
            if label then
                label.text = "已保存"
            end
        end
    end

    -- 重置默认
    local resetBtn = root:FindById("plate_2x")
    if resetBtn then
        resetBtn.props.onClick = function()
            state.masterVolume = 76
            state.musicVolume = 64
            state.ambientVolume = 50
            state.vibration = true
            state.lowPower = false
            state.quality = "standard"
            state.fontSize = "medium"
            state.language = "zh-CN"
            -- 刷新所有视觉
            for _, def in ipairs(VOLUME_ROWS) do
                UpdateVolumeVisual(def, state[def.key])
            end
            for _, def in ipairs(TOGGLE_ROWS) do
                UpdateToggleVisual(def, state[def.key])
            end
            UpdateOptionVisual(QUALITY_OPTS, state.quality)
            UpdateOptionVisual(FONT_OPTS, state.fontSize)
            UpdateOptionVisual(LANG_OPTS, state.language)
            -- 应用音量
            audio:SetMasterGain(SOUND_EFFECT, state.masterVolume / 100)
            audio:SetMasterGain(SOUND_MUSIC, state.musicVolume / 100)
            print("[SettingsScreen] Settings reset to defaults")
        end
    end

    -- 退出登录 (作为"删档重来"功能)
    local logoutBtn = root:FindById("plate_30")
    if logoutBtn then
        logoutBtn.props.onClick = function()
            UI.Modal.Confirm({
                title = "确认删档",
                message = "确定要删除所有存档数据吗？铜钱、声望、材料、订单进度、图鉴等全部数据将被清空，此操作不可撤销！",
                confirmText = "确认删除",
                cancelText = "取消",
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
        -- 退出时自动保存
        GameState.SetSettings({
            sfxVolume     = math.floor(state.masterVolume),
            musicVolume   = math.floor(state.musicVolume),
            ambientVolume = math.floor(state.ambientVolume),
            vibration     = state.vibration,
            lowPower      = state.lowPower,
            quality       = state.quality,
            fontSize      = state.fontSize,
            language      = state.language,
        })
    end

    return screen
end

return SettingsScreen
