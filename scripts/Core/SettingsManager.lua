-- ============================================================================
-- SettingsManager - 全局设置应用器
--
-- 统一负责音量、画质、字体比例、低功耗和语言可用性。
-- Screen 创建后由 ScreenRouter 调用 ApplyToTree，避免各页面重复实现。
-- ============================================================================

local EventBus  = require("Core.EventBus")
local GameState = require("Core.GameState")

local SettingsManager = {}

local DEFAULTS = {
    sfxVolume = 80,
    musicVolume = 60,
    ambientVolume = 50,
    vibration = false,
    lowPower = false,
    quality = "standard",
    fontSize = "medium",
    language = "zh-CN",
}

local QUALITY_PROFILES = {
    smooth = { animationIntensity = 0.0, updateInterval = 1 / 20 },
    standard = { animationIntensity = 0.7, updateInterval = 1 / 30 },
    high = { animationIntensity = 1.0, updateInterval = 0 },
    ultra = { animationIntensity = 1.15, updateInterval = 0 },
}

local FONT_SCALES = {
    small = 0.90,
    medium = 1.00,
    large = 1.15,
}

local SUPPORTED_LANGUAGES = {
    ["zh-CN"] = true,
}

---@type table
local current_ = {}
---@type table<table, number>
local baseFontSizes_ = setmetatable({}, { __mode = "k" })

local function ClampPercent(value, fallback)
    local n = tonumber(value) or fallback
    return math.max(0, math.min(100, math.floor(n + 0.5)))
end

---@param source table|nil
---@return table
function SettingsManager.Normalize(source)
    source = source or {}
    local quality = QUALITY_PROFILES[source.quality] and source.quality or DEFAULTS.quality
    local fontSize = FONT_SCALES[source.fontSize] and source.fontSize or DEFAULTS.fontSize
    local language = SUPPORTED_LANGUAGES[source.language] and source.language or DEFAULTS.language

    return {
        sfxVolume = ClampPercent(source.sfxVolume, DEFAULTS.sfxVolume),
        musicVolume = ClampPercent(source.musicVolume, DEFAULTS.musicVolume),
        ambientVolume = ClampPercent(source.ambientVolume, DEFAULTS.ambientVolume),
        vibration = source.vibration == true,
        lowPower = source.lowPower == true,
        quality = quality,
        fontSize = fontSize,
        language = language,
    }
end

local function CopySettings(source)
    local result = {}
    for key, value in pairs(source) do
        result[key] = value
    end
    return result
end

---@param settings table|nil
function SettingsManager.Apply(settings)
    current_ = SettingsManager.Normalize(settings or GameState.GetSettings())
    audio:SetMasterGain(SOUND_EFFECT, current_.sfxVolume / 100)
    audio:SetMasterGain(SOUND_MUSIC, current_.musicVolume / 100)
    EventBus.Emit("settings_applied", CopySettings(current_))
end

---@param settings table
function SettingsManager.SaveAndApply(settings)
    local normalized = SettingsManager.Normalize(settings)
    GameState.SetSettings(normalized)
    SettingsManager.Apply(normalized)
end

---@return table
function SettingsManager.Get()
    if not current_.quality then
        current_ = SettingsManager.Normalize(GameState.GetSettings())
    end
    return CopySettings(current_)
end

---@return number
function SettingsManager.GetAmbientGain()
    if not current_.quality then SettingsManager.Apply() end
    return current_.ambientVolume / 100
end

---@return number
function SettingsManager.GetFontScale()
    if not current_.quality then SettingsManager.Apply() end
    return FONT_SCALES[current_.fontSize] or 1.0
end

---@return number
function SettingsManager.GetAnimationIntensity()
    if not current_.quality then SettingsManager.Apply() end
    if current_.lowPower then return 0 end
    local profile = QUALITY_PROFILES[current_.quality] or QUALITY_PROFILES.standard
    return profile.animationIntensity
end

---@return number
function SettingsManager.GetDecorativeUpdateInterval()
    if not current_.quality then SettingsManager.Apply() end
    if current_.lowPower then return 1 / 15 end
    local profile = QUALITY_PROFILES[current_.quality] or QUALITY_PROFILES.standard
    return profile.updateInterval
end

---@return boolean
function SettingsManager.ShouldAnimateDecorations()
    return SettingsManager.GetAnimationIntensity() > 0
end

---@param language string
---@return boolean
function SettingsManager.IsLanguageSupported(language)
    return SUPPORTED_LANGUAGES[language] == true
end

---@return string[]
function SettingsManager.GetSupportedLanguages()
    return { "zh-CN" }
end

---@param node table|nil
local function ApplyFontScaleRecursive(node)
    if not node then return end

    local fontSize = node.fontSize
    if type(fontSize) == "number" then
        if not baseFontSizes_[node] then
            baseFontSizes_[node] = fontSize
        end
        node.fontSize = baseFontSizes_[node] * SettingsManager.GetFontScale()
    end

    local children = node.children
    if children then
        for i = 1, #children do
            ApplyFontScaleRecursive(children[i])
        end
    end
end

--- 对当前 UI 树应用字体比例。每个控件缓存原始字号，重复预览不会累乘。
---@param root table|nil
function SettingsManager.ApplyToTree(root)
    ApplyFontScaleRecursive(root)
end

return SettingsManager
