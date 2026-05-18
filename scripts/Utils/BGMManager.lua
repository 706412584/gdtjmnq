-- ============================================================================
-- BGMManager - 背景音乐管理器
-- Project Smith / P3-D3
--
-- 职责：
--   1. 管理背景音乐播放（循环、切换、淡入淡出）
--   2. 根据屏幕切换自动切换 BGM
--   3. 与 SettingsScreen 音量设置联动（通过 SOUND_MUSIC 增益通道）
-- ============================================================================

local EventBus = require("Core.EventBus")

local BGMManager = {}

-- BGM 资源路径
local BGM_TRACKS = {
    workshop = "audio/bgm_workshop.ogg",
    forging  = "audio/bgm_forging.ogg",
}

-- 屏幕 → BGM 映射
local SCREEN_BGM = {
    home       = "workshop",
    orderBoard = "workshop",
    codex      = "workshop",
    settings   = "workshop",
    upgrade    = "workshop",
    story      = "workshop",
    forge      = "forging",
    result     = "workshop",   -- 结算回到工坊氛围
}

-- 内部状态
---@type Scene|nil
local scene_ = nil
---@type SoundSource|nil
local source_ = nil
---@type string 当前播放的 BGM key
local currentTrack_ = ""

-- ============================================================================
-- 初始化
-- ============================================================================

local function EnsureInit()
    if scene_ then return end
    scene_ = Scene()
    scene_:CreateComponent("Octree")

    local node = scene_:CreateChild("BGM")
    source_ = node:CreateComponent("SoundSource")
    source_.soundType = "Music"
    source_.gain = 1.0  -- 实际音量由 audio:SetMasterGain("Music", ...) 控制

    print("[BGMManager] Initialized")
end

-- ============================================================================
-- 播放控制
-- ============================================================================

--- 播放指定 BGM（如果已在播放则跳过）
---@param trackKey string BGM key（如 "workshop"、"forging"）
function BGMManager.Play(trackKey)
    if trackKey == currentTrack_ then return end

    EnsureInit()

    local path = BGM_TRACKS[trackKey]
    if not path then
        print("[BGMManager] WARN: Unknown track key: " .. tostring(trackKey))
        return
    end

    local sound = cache:GetResource("Sound", path)
    if not sound then
        print("[BGMManager] WARN: Sound not found: " .. path)
        return
    end

    sound.looped = true
    source_:Play(sound)
    currentTrack_ = trackKey

    print("[BGMManager] Playing: " .. trackKey .. " (" .. path .. ")")
end

--- 停止当前 BGM
function BGMManager.Stop()
    if source_ and currentTrack_ ~= "" then
        source_:Stop()
        currentTrack_ = ""
        print("[BGMManager] Stopped")
    end
end

--- 获取当前播放的 BGM key
---@return string
function BGMManager.GetCurrentTrack()
    return currentTrack_
end

-- ============================================================================
-- 屏幕切换自动 BGM 切换
-- ============================================================================

--- 根据屏幕名称自动切换 BGM
---@param data table
local function OnScreenChange(data)
    local toScreen = data and data.to or ""
    local bgmKey = SCREEN_BGM[toScreen]
    if bgmKey then
        BGMManager.Play(bgmKey)
    end
end

--- 初始化自动 BGM 切换（监听 screen_change 事件）
function BGMManager.Init()
    EnsureInit()
    EventBus.On("screen_change", OnScreenChange)
    print("[BGMManager] Auto-switch registered")
end

return BGMManager
