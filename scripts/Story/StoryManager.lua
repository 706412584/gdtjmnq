-- ============================================================================
-- StoryManager - 对话流程引擎
-- Project Smith / P2-B1
--
-- 职责：
--   1. 加载章节对话数据（JSON）
--   2. 驱动对话节点的推进
--   3. 处理分支选择，应用效果（好感度/阵营/标记）
--   4. 与 GameState 协作保存进度
--   5. 提供条件检查，判断节点是否可触发
-- ============================================================================

local DataLoader = require("Config.DataLoader")
local GameState  = require("Core.GameState")
local EventBus   = require("Core.EventBus")

local StoryManager = {}

-- ============================================================================
-- 内部状态
-- ============================================================================

--- 章节数据缓存 { [chapterNum] = nodeArray }
---@type table<number, table[]>
local chapterCache_ = {}

--- 章节节点索引 { [chapterNum] = { [nodeId] = node } }
---@type table<number, table<string, table>>
local nodeIndex_ = {}

--- 角色显示配置
local CHARACTER_CONFIG = {
    keeper     = { name = "老掌柜",   portrait = "image/char_keeper.png",    side = "left" },
    shen       = { name = "沈绫",     portrait = "image/char_shen.png",      side = "left" },
    luchen     = { name = "陆沉",     portrait = "image/char_luchen.png",    side = "left" },
    han        = { name = "韩铸",     portrait = "image/char_han.png",        side = "left" },
    disciple   = { name = "阿晦",     portrait = "image/char_disciple.png",  side = "left" },
    envoy      = { name = "王都使者", portrait = "image/char_envoy.png",     side = "left" },
    hunter     = { name = "猎户",     portrait = "image/char_hunter.png",    side = "left" },
    magistrate = { name = "县衙差役", portrait = "image/char_magistrate.png",side = "left" },
    widow      = { name = "妇人",     portrait = "image/char_widow.png",     side = "left" },
    apprentice = { name = "学徒",     portrait = "image/char_apprentice.png",side = "left" },
    guard      = { name = "官差",     portrait = "image/char_guard.png",     side = "left" },
    player     = { name = "主角",     portrait = "image/char_player.png",    side = "right" },
    narrator   = { name = "",         portrait = nil,                        side = "none" },
}

--- 故事标记（从 GameState 载入并在变更后持久化）
---@type table<string, any>
local storyFlags_ = {}

--- 章节标题（用于进度展示）
local CHAPTER_NAMES = {
    "第一章 · 入门徒",
    "第二章 · 初展锋",
    "第三章 · 名声起",
    "第四章 · 暗潮涌",
    "第五章 · 匠心成",
}

-- GDD 9.14 章节解锁门槛。第一章默认开放；高章节即使存档进度已指向其中，
-- 也必须满足声望后才能触发，防止连续点击一路播放到终章。
local CHAPTER_FAME_REQUIREMENTS = {
    [1] = 0,
    [2] = 40,
    [3] = 120,
    [4] = 260,
    [5] = 480,
}

--- 本次会话中已被玩家手动关闭的待触发节点（避免返回后立即重复自动弹出）
--- 仅会话级，不持久化；剧情推进到新节点后自然失效
---@type string|nil
local dismissedNodeId_ = nil

-- ============================================================================
-- 数据加载
-- ============================================================================

--- 加载指定章节数据
---@param chapter number
---@return boolean success
local function LoadChapter(chapter)
    if chapterCache_[chapter] then return true end

    local path = "Story/data/chapter" .. chapter .. ".json"
    local nodes = DataLoader.Load(path)
    if not nodes then
        print("[StoryManager] WARNING: Failed to load " .. path)
        return false
    end

    chapterCache_[chapter] = nodes
    nodeIndex_[chapter] = {}

    for i = 1, #nodes do
        local node = nodes[i]
        nodeIndex_[chapter][node.id] = node
    end

    print("[StoryManager] Loaded chapter " .. chapter .. " (" .. #nodes .. " nodes)")
    return true
end

--- 获取节点
---@param chapter number
---@param nodeId string
---@return table|nil
local function GetNode(chapter, nodeId)
    if not nodeIndex_[chapter] then
        LoadChapter(chapter)
    end
    return nodeIndex_[chapter] and nodeIndex_[chapter][nodeId] or nil
end

-- ============================================================================
-- 条件判断
-- ============================================================================

--- 检查节点条件是否满足
---@param condition table|nil
---@return boolean
local function CheckCondition(condition)
    if not condition then return true end

    local cType = condition.type

    if cType == "ordersCompleted" then
        local completed = GameState.GetCompletedOrders()
        return #completed >= (condition.min or 1)

    elseif cType == "fameMin" then
        return GameState.GetFame() >= (condition.value or 0)

    elseif cType == "facilityLevel" then
        local fId = condition.facilityId or "furnace"
        return GameState.GetFacilityLevel(fId) >= (condition.level or 2)

    elseif cType == "orderCompleted" then
        local orderId = condition.orderId
        local completed = GameState.GetCompletedOrders()
        for i = 1, #completed do
            if completed[i] == orderId then
                return true
            end
        end
        return false

    elseif cType == "flag" then
        return storyFlags_[condition.flag] == (condition.value or true)

    elseif cType == "relationship" then
        local npcId = condition.npcId or "keeper"
        return GameState.GetRelationship(npcId) >= (condition.min or 0)

    elseif cType == "relationshipMax" then
        local npcId = condition.npcId or "keeper"
        return GameState.GetRelationship(npcId) <= (condition.max or 100)

    elseif cType == "factionMin" then
        local fId = condition.factionId or "court"
        return GameState.GetFaction(fId) >= (condition.min or 0)

    elseif cType == "factionMax" then
        local fId = condition.factionId or "court"
        return GameState.GetFaction(fId) <= (condition.max or 100)

    elseif cType == "and" then
        local subs = condition.conditions or {}
        for i = 1, #subs do
            if not CheckCondition(subs[i]) then return false end
        end
        return true

    elseif cType == "or" then
        local subs = condition.conditions or {}
        for i = 1, #subs do
            if CheckCondition(subs[i]) then return true end
        end
        return #subs == 0
    end

    return true
end

-- ============================================================================
-- 效果应用
-- ============================================================================

--- 应用选择效果
---@param effects table
local function ApplyEffects(effects)
    if not effects then return end

    -- 好感度变化
    if effects.relationships then
        for npcId, delta in pairs(effects.relationships) do
            GameState.AddRelationship(npcId, delta)
            print("[StoryManager] Relationship " .. npcId .. " += " .. delta
                .. " (now " .. GameState.GetRelationship(npcId) .. ")")
        end
    end

    -- 阵营变化
    if effects.factions then
        for factionId, delta in pairs(effects.factions) do
            GameState.AddFaction(factionId, delta)
            print("[StoryManager] Faction " .. factionId .. " += " .. delta
                .. " (now " .. GameState.GetFaction(factionId) .. ")")
        end
    end

    -- 额外阵营字段（JSON 中 factions_2 用于不覆盖 factions 的额外变化）
    if effects.factions_2 then
        for factionId, delta in pairs(effects.factions_2) do
            GameState.AddFaction(factionId, delta)
        end
    end

    -- 标记
    if effects.flags then
        for flag, value in pairs(effects.flags) do
            storyFlags_[flag] = value
            print("[StoryManager] Flag " .. flag .. " = " .. tostring(value))
        end
        GameState.SetStoryFlags(storyFlags_)
    end

    -- 铜钱变化
    if effects.coins then
        GameState.AddCoins(effects.coins)
        print("[StoryManager] Coins += " .. effects.coins)
    end

    -- 声望变化
    if effects.fame then
        GameState.AddFame(effects.fame)
        print("[StoryManager] Fame += " .. effects.fame)
    end
end

-- ============================================================================
-- 公开接口
-- ============================================================================

--- 初始化（游戏启动时调用一次）
function StoryManager.Init()
    storyFlags_ = GameState.GetStoryFlags()
    -- 加载第 1 章数据
    LoadChapter(1)
    print("[StoryManager] Initialized")
end

--- 获取当前剧情进度
---@return number chapter
---@return string nodeId
function StoryManager.GetProgress()
    local progress = GameState.GetStoryProgress()
    return progress.chapter, progress.nodeId
end

--- 获取当前节点数据
---@return table|nil node
function StoryManager.GetCurrentNode()
    local chapter, nodeId = StoryManager.GetProgress()
    return GetNode(chapter, nodeId)
end

--- 返回当前剧情节点尚未满足的解锁条件。
---@return string|nil
function StoryManager.GetCurrentBlockerText()
    local progress = GameState.GetStoryProgress()
    if progress.done then
        return "全部剧情已完成"
    end

    local requiredFame = CHAPTER_FAME_REQUIREMENTS[progress.chapter] or math.huge
    if GameState.GetFame() < requiredFame then
        return "需要声望 " .. requiredFame .. " 才能开启下一章"
    end

    local node = StoryManager.GetCurrentNode()
    local condition = node and node.condition
    if not condition or CheckCondition(condition) then
        return nil
    end
    if condition.type == "orderCompleted" then
        return "完成当前主线委托后继续剧情"
    end
    if condition.type == "fameMin" then
        return "需要声望 " .. (condition.value or 0)
    end
    if condition.type == "facilityLevel" then
        return "需要将设施升级至 Lv" .. (condition.level or 2)
    end
    return "完成当前剧情条件后继续"
end

--- 检查是否有待展示的剧情
---@return boolean
function StoryManager.HasPendingStory()
    -- 全部剧情已完结（持久化标记），不再有待展示内容
    local progress = GameState.GetStoryProgress()
    if progress.done then return false end

    -- 章节级声望门槛优先于节点条件，确保章节解锁节奏符合 GDD。
    local requiredFame = CHAPTER_FAME_REQUIREMENTS[progress.chapter] or math.huge
    if GameState.GetFame() < requiredFame then
        return false
    end

    local node = StoryManager.GetCurrentNode()
    if not node then return false end

    -- 检查条件
    return CheckCondition(node.condition)
end

--- 标记当前待触发剧情为"已关闭"（玩家手动退出时调用）
--- 使其在剧情推进到下一节点前不再自动弹出
function StoryManager.DismissCurrentStory()
    local _, nodeId = StoryManager.GetProgress()
    dismissedNodeId_ = nodeId
end

--- 是否有"新的"待展示剧情（条件满足且未被本会话手动关闭）
--- 用于运行中自动触发，避免玩家退出后立即被再次拉回剧情
---@return boolean
function StoryManager.HasNewPendingStory()
    if not StoryManager.HasPendingStory() then return false end
    local _, nodeId = StoryManager.GetProgress()
    return nodeId ~= dismissedNodeId_
end

--- 全部剧情是否已完结（到达终章终点节点）
---@return boolean
function StoryManager.IsStoryDone()
    local progress = GameState.GetStoryProgress()
    return progress.done == true
end

--- 获取章节标题
---@param chapter number
---@return string
function StoryManager.GetChapterName(chapter)
    return CHAPTER_NAMES[chapter] or ("第" .. chapter .. "章")
end

--- 获取当前章节进度（节点在章节中的序号 / 总节点数）
---@return number chapter 当前章节号
---@return number index 当前节点序号（从 1 开始；找不到为 0）
---@return number total 章节总节点数
function StoryManager.GetChapterProgress()
    local chapter, nodeId = StoryManager.GetProgress()
    if not chapterCache_[chapter] then
        LoadChapter(chapter)
    end
    local nodes = chapterCache_[chapter]
    if not nodes then return chapter, 0, 0 end
    local idx = 0
    for i = 1, #nodes do
        if nodes[i].id == nodeId then
            idx = i
            break
        end
    end
    return chapter, idx, #nodes
end

--- 获取指定节点
---@param nodeId string
---@return table|nil
function StoryManager.GetNodeById(nodeId)
    local chapter = (GameState.GetStoryProgress()).chapter
    return GetNode(chapter, nodeId)
end

--- 获取角色配置
---@param speakerId string
---@return table { name, portrait, side }
function StoryManager.GetCharacterConfig(speakerId)
    return CHARACTER_CONFIG[speakerId] or { name = speakerId, portrait = nil, side = "left" }
end

--- 完成当前对话节点（非选择型），推进到 next
---@param nodeEffects table|nil 节点自带的效果
function StoryManager.CompleteDialogueNode(nodeEffects)
    local chapter, nodeId = StoryManager.GetProgress()
    local node = GetNode(chapter, nodeId)
    if not node then return end

    -- 应用节点效果
    ApplyEffects(nodeEffects or node.effects)

    -- 推进
    local nextId = node.next
    if nextId then
        GameState.SetStoryProgress(chapter, nextId)
        print("[StoryManager] Advanced to " .. nextId)
    elseif node.chapterEnd then
        -- 章节结束，推进到下一章首节点
        local nextChapter = chapter + 1
        local loaded = LoadChapter(nextChapter)
        if loaded and chapterCache_[nextChapter] and #chapterCache_[nextChapter] > 0 then
            local firstNode = chapterCache_[nextChapter][1]
            GameState.SetStoryProgress(nextChapter, firstNode.id)
            print("[StoryManager] Chapter " .. chapter .. " complete. Advanced to chapter " .. nextChapter)
        else
            -- 无后续章节：全部剧情完结，持久化标记，避免被反复拉回
            GameState.MarkStoryDone()
            print("[StoryManager] Chapter " .. chapter .. " complete. Story finished (no next chapter).")
        end
    else
        -- 既无 next 也非 chapterEnd（数据异常兜底）：标记完结，防止死循环
        GameState.MarkStoryDone()
        print("[StoryManager] WARNING: terminal dialogue node without next/chapterEnd: " .. tostring(nodeId))
    end

    EventBus.Emit("story_node_complete", { nodeId = nodeId, chapter = chapter })
end

--- 做出选择并推进
---@param choiceIndex number 选择索引（从 1 开始）
function StoryManager.MakeChoice(choiceIndex)
    local chapter, nodeId = StoryManager.GetProgress()
    local node = GetNode(chapter, nodeId)
    if not node or node.type ~= "choice" then
        print("[StoryManager] ERROR: Current node is not a choice node")
        return
    end

    local choices = node.choices
    if not choices or choiceIndex < 1 or choiceIndex > #choices then
        print("[StoryManager] ERROR: Invalid choice index " .. tostring(choiceIndex))
        return
    end

    local choice = choices[choiceIndex]

    -- 应用效果
    ApplyEffects(choice.effects)
    GameState.AddChoiceHistory({
        nodeId = nodeId,
        chapter = chapter,
        choiceIndex = choiceIndex,
        choiceText = choice.text or "",
    })

    -- 推进到选择的目标节点
    local nextId = choice.next
    if nextId then
        GameState.SetStoryProgress(chapter, nextId)
        print("[StoryManager] Choice " .. choiceIndex .. " -> " .. nextId)
    end

    EventBus.Emit("story_choice_made", {
        nodeId = nodeId,
        chapter = chapter,
        choiceIndex = choiceIndex,
        choiceText = choice.text,
    })
end

--- 强制跳转到指定节点（调试/事件触发用）
---@param chapter number
---@param nodeId string
function StoryManager.JumpTo(chapter, nodeId)
    LoadChapter(chapter)
    GameState.SetStoryProgress(chapter, nodeId)
    print("[StoryManager] Jumped to " .. chapter .. ":" .. nodeId)
end

--- 获取故事标记
---@param flag string
---@return any
function StoryManager.GetFlag(flag)
    return storyFlags_[flag]
end

--- 设置故事标记
---@param flag string
---@param value any
function StoryManager.SetFlag(flag, value)
    storyFlags_[flag] = value
    GameState.SetStoryFlags(storyFlags_)
end

--- 返回当前待完成的主线订单要求。
---@return table|nil
function StoryManager.GetPendingOrderRequirement()
    return GameState.GetPendingStoryOrder()
end

--- 标记指定主线订单已完成，仅匹配当前剧情要求的订单。
---@param orderId string
function StoryManager.MarkStoryOrderCompleted(orderId)
    local pending = GameState.GetPendingStoryOrder()
    if not pending or pending.orderId ~= orderId or pending.completed then
        return false
    end

    pending.completed = true
    GameState.SetPendingStoryOrder(pending)
    EventBus.Emit("story_order_completed", {
        orderId = orderId,
        returnNodeId = pending.returnNodeId,
    })
    print("[StoryManager] Main-story order completed: " .. orderId)
    return true
end

--- 跳过当前章节剩余对话，直接推进到下一章或标记完成
function StoryManager.SkipCurrentChapter()
    local chapter, nodeId = StoryManager.GetProgress()
    print("[StoryManager] Skipping rest of chapter " .. chapter .. " from node " .. (nodeId or "?"))

    -- 查找当前章节的 chapterEnd 节点
    if not chapterCache_[chapter] then
        LoadChapter(chapter)
    end

    local nodes = chapterCache_[chapter]
    if not nodes then return end

    -- 找到最后一个节点（chapterEnd 节点）
    local endNode = nil
    for i = #nodes, 1, -1 do
        if nodes[i].chapterEnd then
            endNode = nodes[i]
            break
        end
    end

    if endNode then
        -- 推进到下一章
        local nextChapter = chapter + 1
        local loaded = LoadChapter(nextChapter)
        if loaded and chapterCache_[nextChapter] and #chapterCache_[nextChapter] > 0 then
            local firstNode = chapterCache_[nextChapter][1]
            GameState.SetStoryProgress(nextChapter, firstNode.id)
            print("[StoryManager] Skipped to chapter " .. nextChapter)
        else
            -- 没有下一章，停在最后节点
            GameState.SetStoryProgress(chapter, endNode.id)
            print("[StoryManager] Skipped to end of chapter " .. chapter)
        end
    else
        -- 没有 chapterEnd 节点，推进到最后节点
        local lastNode = nodes[#nodes]
        if lastNode then
            GameState.SetStoryProgress(chapter, lastNode.id)
        end
    end

    EventBus.Emit("story_chapter_skipped", { chapter = chapter })
end

--- 检查当前节点是否会触发订单。
---@return table|nil
function StoryManager.GetOrderTrigger()
    local node = StoryManager.GetCurrentNode()
    if not node then return nil end
    if type(node.triggerOrder) == "table" then
        return node.triggerOrder
    end
    return nil
end

--- 检查当前节点是否会触发订单。
---@return boolean
function StoryManager.ShouldTriggerOrder()
    return StoryManager.GetOrderTrigger() ~= nil
end

return StoryManager
