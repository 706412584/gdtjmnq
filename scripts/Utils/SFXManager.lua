-- ============================================================================
-- SFXManager - 音效管理器
-- Project Smith / P1-E
--
-- 提供简单的音效播放 API。
-- 内部维护一个最小 Scene + 若干 SoundSource 节点，用于 2D 音效播放。
-- ============================================================================

local SFXManager = {}

-- 音效路径定义
SFXManager.SFX = {
    -- 锻造核心（替换旧的 hammer_hit）
    HAMMER_HIT          = "audio/sfx/sfx_hammer_strike_heavy.ogg",
    HAMMER_HEAVY        = "audio/sfx/sfx_hammer_strike_heavy.ogg",
    HAMMER_LIGHT        = "audio/sfx/sfx_hammer_strike_light.ogg",
    HAMMER_PERFECT      = "audio/sfx/sfx_hammer_strike_perfect.ogg",
    ANVIL_RING          = "audio/sfx/sfx_anvil_ring.ogg",
    METAL_FOLD          = "audio/sfx/sfx_metal_fold.ogg",
    BELLOWS_PUMP        = "audio/sfx/sfx_bellows_pump.ogg",
    ORE_DROP            = "audio/sfx/sfx_ore_drop.ogg",
    METAL_SCRAPE        = "audio/sfx/sfx_metal_scrape.ogg",

    -- 原有
    FIRE_CRACKLE        = "audio/sfx/sfx_fire_crackle.ogg",
    GRINDING            = "audio/sfx/sfx_grinding.ogg",
    FORGE_COMPLETE      = "audio/sfx/sfx_forge_complete.ogg",
    QUENCH_SIZZLE       = "audio/sfx/sfx_quench_sizzle.ogg",

    -- UI 反馈
    UI_TAP              = "audio/sfx/sfx_ui_tap.ogg",
    UI_SUCCESS          = "audio/sfx/sfx_ui_success.ogg",
    UI_FAIL             = "audio/sfx/sfx_ui_fail.ogg",
    UI_COIN             = "audio/sfx/sfx_ui_coin.ogg",
    UI_PAGE_TURN        = "audio/sfx/sfx_ui_page_turn.ogg",
    QUALITY_UP          = "audio/sfx/sfx_quality_up.ogg",
    ORDER_ACCEPT        = "audio/sfx/sfx_order_accept.ogg",
    ORDER_COMPLETE      = "audio/sfx/sfx_order_complete.ogg",

    -- 剧情/氛围
    STORY_TENSION       = "audio/sfx/sfx_story_tension.ogg",
    STORY_REVEAL        = "audio/sfx/sfx_story_reveal.ogg",
    STORY_DOOR_KNOCK    = "audio/sfx/sfx_story_door_knock.ogg",
    AMBIENT_WORKSHOP    = "audio/sfx/sfx_ambient_workshop.ogg",
    AMBIENT_RAIN        = "audio/sfx/sfx_ambient_rain.ogg",
    AMBIENT_NIGHT       = "audio/sfx/sfx_ambient_night.ogg",

    -- 人物语气
    CHAR_GREET          = "audio/sfx/sfx_char_greet.ogg",
    CHAR_SURPRISE       = "audio/sfx/sfx_char_surprise.ogg",
    CHAR_APPROVE        = "audio/sfx/sfx_char_approve.ogg",
    CHAR_DISAPPROVE     = "audio/sfx/sfx_char_disapprove.ogg",
    CHAR_LAUGH          = "audio/sfx/sfx_char_laugh.ogg",
    CHAR_THINK          = "audio/sfx/sfx_char_think.ogg",
}

-- 内部状态
---@type Scene|nil
local scene_ = nil
---@type table<string, SoundSource>  -- 循环音效源，按 key 存储
local loopSources_ = {}

-- ============================================================================
-- 初始化（延迟，首次播放时自动调用）
-- ============================================================================

local function EnsureInit()
    if scene_ then return end
    scene_ = Scene()
    scene_:CreateComponent("Octree")
    print("[SFXManager] Initialized audio scene")
end

-- ============================================================================
-- 播放一次性音效
-- ============================================================================

--- 播放一次音效
---@param path string 资源路径
---@param gain number|nil 音量 (0~1, 默认 0.6)
function SFXManager.Play(path, gain)
    EnsureInit()

    local sound = cache:GetResource("Sound", path)
    if not sound then
        print("[SFXManager] WARN: Sound not found: " .. path)
        return
    end

    sound.looped = false

    local node = scene_:CreateChild("SFX")
    local source = node:CreateComponent("SoundSource")
    source.soundType = "Effect"
    source.gain = gain or 0.6
    source.autoRemoveMode = REMOVE_NODE
    source:Play(sound)
end

-- ============================================================================
-- 循环音效（环境音）
-- ============================================================================

--- 开始播放循环音效
---@param key string 唯一标识
---@param path string 资源路径
---@param gain number|nil 音量 (0~1, 默认 0.3)
function SFXManager.PlayLoop(key, path, gain)
    EnsureInit()

    -- 如果已有同 key 的循环，先停掉
    SFXManager.StopLoop(key)

    local sound = cache:GetResource("Sound", path)
    if not sound then
        print("[SFXManager] WARN: Loop sound not found: " .. path)
        return
    end

    sound.looped = true

    local node = scene_:CreateChild("Loop_" .. key)
    local source = node:CreateComponent("SoundSource")
    source.soundType = "Effect"
    source.gain = gain or 0.3
    source:Play(sound)

    loopSources_[key] = { node = node, source = source }
end

--- 停止指定循环音效
---@param key string 唯一标识
function SFXManager.StopLoop(key)
    local entry = loopSources_[key]
    if entry then
        if entry.source then
            entry.source:Stop()
        end
        if entry.node then
            entry.node:Remove()
        end
        loopSources_[key] = nil
    end
end

--- 停止所有循环音效
function SFXManager.StopAllLoops()
    for key, _ in pairs(loopSources_) do
        SFXManager.StopLoop(key)
    end
end

return SFXManager
