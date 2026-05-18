-- ============================================================================
-- SettingsScreen - 设置界面
-- Project Smith / P3-C3
--
-- 功能: 音效音量、背景音乐音量、关于页面、返回按钮
-- ============================================================================

local UI          = require("urhox-libs/UI")
local GameState   = require("Core.GameState")
local ScreenRouter = require("Utils.ScreenRouter")

local SettingsScreen = {}

-- ============================================================================
-- UI 素材路径（武侠水墨风）
-- ============================================================================

local UI_ASSETS = {
    panel_header     = "image/ui/panel_header.png",
    panel_card       = "image/ui/panel_card.png",
    divider_moon     = "image/ui/divider_moon.png",
}

-- ============================================================================
-- 色板
-- ============================================================================

local C = {
    bgPrimary    = { 26,  26,  46,  255 },
    bgSecondary  = { 22,  33,  62,  255 },
    bgCard       = { 30,  40,  68,  230 },
    accent       = { 233, 69,  96,  255 },
    gold         = { 212, 165, 116, 255 },
    textPrimary  = { 232, 224, 208, 255 },
    textSecondary = { 160, 147, 125, 255 },
    success      = { 78,  205, 196, 255 },
    warning      = { 255, 217, 61,  255 },
    divider      = { 60,  60,  90,  255 },
    btnPrimary   = { 180, 120, 60,  255 },
    btnHover     = { 200, 140, 70,  255 },
    btnPressed   = { 150, 100, 50,  255 },
}

-- ============================================================================
-- Screen 接口
-- ============================================================================

---@param container table UI 容器
---@param params table|nil
---@return table screen
function SettingsScreen.Create(container, params)
    local screen = {}

    -- 加载已有设置
    local settings = GameState.GetSettings()
    local sfxVolume = settings.sfxVolume or 80
    local musicVolume = settings.musicVolume or 60

    -- 应用初始音量
    audio:SetMasterGain(SOUND_EFFECT, sfxVolume / 100)
    audio:SetMasterGain(SOUND_MUSIC, musicVolume / 100)

    -- 前置声明
    local SaveSettings

    -- UI 引用
    local sfxValueLabel_
    local musicValueLabel_

    -- ----------------------------------------------------------------
    -- 标题栏
    -- ----------------------------------------------------------------
    local function CreateHeader()
        return UI.Panel {
            width = "100%",
            flexDirection = "row",
            alignItems = "center",
            paddingHorizontal = 16,
            paddingVertical = 8,
            backgroundImage = UI_ASSETS.panel_header,
            backgroundFit = "cover",
            children = {
                UI.Button {
                    text = "< 返回",
                    fontSize = 14,
                    fontColor = C.gold,
                    backgroundColor = { 0, 0, 0, 0 },
                    paddingHorizontal = 12,
                    paddingVertical = 6,
                    borderRadius = 6,
                    onClick = function(self)
                        ScreenRouter.GoTo("home")
                    end,
                },
                UI.Panel { flexGrow = 1 },
                UI.Label {
                    text = "设置",
                    fontSize = 20,
                    fontColor = C.gold,
                },
                UI.Panel { flexGrow = 1 },
                -- 占位，让标题居中
                UI.Panel { width = 60 },
            }
        }
    end

    -- ----------------------------------------------------------------
    -- 分隔线
    -- ----------------------------------------------------------------
    local function CreateDivider()
        return UI.Panel {
            width = "90%",
            height = 16,
            backgroundImage = UI_ASSETS.divider_moon,
            backgroundFit = "contain",
            alignSelf = "center",
            marginVertical = 8,
        }
    end

    -- ----------------------------------------------------------------
    -- 音量设置区
    -- ----------------------------------------------------------------
    local function CreateVolumeSection()
        sfxValueLabel_ = UI.Label {
            text = tostring(math.floor(sfxVolume)) .. "%",
            fontSize = 13,
            fontColor = C.gold,
            width = 40,
            textAlign = "right",
        }

        musicValueLabel_ = UI.Label {
            text = tostring(math.floor(musicVolume)) .. "%",
            fontSize = 13,
            fontColor = C.gold,
            width = 40,
            textAlign = "right",
        }

        return UI.Panel {
            width = "100%",
            backgroundImage = UI_ASSETS.panel_card,
            backgroundFit = "cover",
            borderRadius = 10,
            padding = 16,
            gap = 16,
            children = {
                -- 区块标题
                UI.Label {
                    text = "音频设置",
                    fontSize = 16,
                    fontColor = C.textPrimary,
                },

                -- 音效音量
                UI.Panel {
                    width = "100%",
                    gap = 6,
                    children = {
                        UI.Panel {
                            width = "100%",
                            flexDirection = "row",
                            justifyContent = "space-between",
                            alignItems = "center",
                            children = {
                                UI.Label {
                                    text = "音效音量",
                                    fontSize = 14,
                                    fontColor = C.textSecondary,
                                },
                                sfxValueLabel_,
                            }
                        },
                        UI.Slider {
                            value = sfxVolume,
                            min = 0,
                            max = 100,
                            step = 5,
                            width = "100%",
                            trackColor = C.divider,
                            activeTrackColor = C.gold,
                            thumbColor = C.gold,
                            onChange = function(self, v)
                                sfxVolume = v
                                sfxValueLabel_.text = tostring(math.floor(v)) .. "%"
                                audio:SetMasterGain(SOUND_EFFECT, v / 100)
                            end,
                            onChangeEnd = function(self, v)
                                sfxVolume = v
                                SaveSettings()
                            end,
                        },
                    }
                },

                CreateDivider(),

                -- 背景音乐音量
                UI.Panel {
                    width = "100%",
                    gap = 6,
                    children = {
                        UI.Panel {
                            width = "100%",
                            flexDirection = "row",
                            justifyContent = "space-between",
                            alignItems = "center",
                            children = {
                                UI.Label {
                                    text = "背景音乐",
                                    fontSize = 14,
                                    fontColor = C.textSecondary,
                                },
                                musicValueLabel_,
                            }
                        },
                        UI.Slider {
                            value = musicVolume,
                            min = 0,
                            max = 100,
                            step = 5,
                            width = "100%",
                            trackColor = C.divider,
                            activeTrackColor = C.success,
                            thumbColor = C.success,
                            onChange = function(self, v)
                                musicVolume = v
                                musicValueLabel_.text = tostring(math.floor(v)) .. "%"
                                audio:SetMasterGain(SOUND_MUSIC, v / 100)
                            end,
                            onChangeEnd = function(self, v)
                                musicVolume = v
                                SaveSettings()
                            end,
                        },
                    }
                },
            }
        }
    end

    -- ----------------------------------------------------------------
    -- 关于区
    -- ----------------------------------------------------------------
    local function CreateAboutSection()
        local aboutItems = {
            { label = "游戏名称", value = "古代铁匠模拟器" },
            { label = "版本", value = "P3" },
            { label = "引擎", value = "UrhoX" },
            { label = "品类", value = "Hybrid-Casual" },
        }

        local rows = {}
        for i = 1, #aboutItems do
            rows[#rows + 1] = UI.Panel {
                width = "100%",
                flexDirection = "row",
                justifyContent = "space-between",
                alignItems = "center",
                paddingVertical = 4,
                children = {
                    UI.Label {
                        text = aboutItems[i].label,
                        fontSize = 13,
                        fontColor = C.textSecondary,
                    },
                    UI.Label {
                        text = aboutItems[i].value,
                        fontSize = 13,
                        fontColor = C.textPrimary,
                    },
                }
            }
            -- 分隔线（最后一项不加）
            if i < #aboutItems then
                rows[#rows + 1] = UI.Panel {
                    width = "100%",
                    height = 1,
                    backgroundColor = { 50, 50, 80, 150 },
                }
            end
        end

        return UI.Panel {
            width = "100%",
            backgroundImage = UI_ASSETS.panel_card,
            backgroundFit = "cover",
            borderRadius = 10,
            padding = 16,
            gap = 8,
            children = {
                UI.Label {
                    text = "关于",
                    fontSize = 16,
                    fontColor = C.textPrimary,
                    marginBottom = 4,
                },
                table.unpack(rows),
            }
        }
    end

    -- ----------------------------------------------------------------
    -- 存档信息区
    -- ----------------------------------------------------------------
    local function CreateSaveInfoSection()
        local totalForged = GameState.GetStat("totalForged")
        local perfectCount = GameState.GetStat("perfectCount")
        local completedOrders = GameState.GetCompletedOrders()
        local codex = GameState.GetCodex()

        local stats = {
            { label = "已完成订单", value = tostring(#completedOrders) },
            { label = "锻造总数", value = tostring(totalForged) },
            { label = "完美锻造", value = tostring(perfectCount) },
            { label = "已解锁图鉴", value = tostring(#codex) },
        }

        local rows = {}
        for i = 1, #stats do
            rows[#rows + 1] = UI.Panel {
                width = "100%",
                flexDirection = "row",
                justifyContent = "space-between",
                alignItems = "center",
                paddingVertical = 3,
                children = {
                    UI.Label {
                        text = stats[i].label,
                        fontSize = 13,
                        fontColor = C.textSecondary,
                    },
                    UI.Label {
                        text = stats[i].value,
                        fontSize = 13,
                        fontColor = C.gold,
                    },
                }
            }
        end

        return UI.Panel {
            width = "100%",
            backgroundImage = UI_ASSETS.panel_card,
            backgroundFit = "cover",
            borderRadius = 10,
            padding = 16,
            gap = 6,
            children = {
                UI.Label {
                    text = "游戏统计",
                    fontSize = 16,
                    fontColor = C.textPrimary,
                    marginBottom = 4,
                },
                table.unpack(rows),
            }
        }
    end

    -- ----------------------------------------------------------------
    -- 危险操作区（删档重来）
    -- ----------------------------------------------------------------
    local function CreateDangerSection()
        return UI.Panel {
            width = "100%",
            backgroundImage = UI_ASSETS.panel_card,
            backgroundFit = "cover",
            borderRadius = 10,
            padding = 16,
            gap = 12,
            children = {
                UI.Label {
                    text = "危险操作",
                    fontSize = 16,
                    fontColor = C.accent,
                },
                UI.Label {
                    text = "删除所有存档数据并重新开始游戏，此操作不可撤销。",
                    fontSize = 12,
                    fontColor = C.textSecondary,
                },
                UI.Button {
                    text = "删档重来",
                    fontSize = 14,
                    fontColor = C.textPrimary,
                    backgroundColor = { 120, 30, 40, 255 },
                    hoverBackgroundColor = { 150, 40, 50, 255 },
                    pressedBackgroundColor = { 90, 20, 30, 255 },
                    paddingHorizontal = 20,
                    paddingVertical = 10,
                    borderRadius = 8,
                    width = "100%",
                    onClick = function(self)
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
                    end,
                },
            }
        }
    end

    -- ----------------------------------------------------------------
    -- 保存设置（本地函数供滑块回调使用）
    -- ----------------------------------------------------------------
    SaveSettings = function()
        GameState.SetSettings({
            sfxVolume = math.floor(sfxVolume),
            musicVolume = math.floor(musicVolume),
        })
    end

    -- ----------------------------------------------------------------
    -- 组装页面
    -- ----------------------------------------------------------------
    local panel = UI.Panel {
        width = "100%",
        height = "100%",
        backgroundColor = C.bgPrimary,
        children = {
            -- 顶部标题
            CreateHeader(),

            -- 可滚动内容区
            UI.ScrollView {
                width = "100%",
                flexGrow = 1,
                flexShrink = 1,
                contentPadding = { top = 8, bottom = 40, left = 16, right = 16 },
                children = {
                    UI.Panel {
                        width = "100%",
                        gap = 16,
                        children = {
                            CreateVolumeSection(),
                            CreateSaveInfoSection(),
                            CreateAboutSection(),
                            CreateDangerSection(),
                        }
                    }
                }
            }
        }
    }

    container:AddChild(panel)
    screen.panel = panel

    -- ----------------------------------------------------------------
    -- 清理
    -- ----------------------------------------------------------------
    function screen.Destroy()
        -- 确保退出时保存最终设置
        SaveSettings()
    end

    return screen
end

return SettingsScreen
