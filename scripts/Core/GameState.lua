-- ============================================================================
-- GameState - 统一数据中枢
-- Project Smith / P1-A5
--
-- 职责：
--   1. Load-Gate：启动时从 clientCloud 异步加载一次，之后全部同步读取
--   2. 内存混淆：敏感数值通过 SecureStore 存储
--   3. 脏标记 + 自动存档：数据变更标 dirty，每 5 秒自动 Save
--   4. 导入导出：Load 时明文->混淆；Save 时混淆->明文->云端
--
-- 使用约束（见 CLAUDE.md §4.3）：
--   - 所有模块通过本接口读写数据，禁止自建数据副本
--   - 读取值只在栈上临时使用，不缓存到模块级/全局变量
-- ============================================================================

local SecureStore = require("Core.SecureStore")
local EventBus    = require("Core.EventBus")

local GameState = {}

-- ==================== 内部状态 ====================

--- 敏感数值（混淆存储）
local secureStore_ = SecureStore.New()

--- 非敏感数据（明文 table）
local plainData_ = {}

--- 状态标记
local dirty_     = false
local loaded_    = false
local saving_    = false
local saveTimer_ = 0
local changeRevision_ = 0
local savingRevision_ = 0
local cloudSaveEnabled_ = false
local loadStatus_ = "loading"

--- 常量
local SAVE_KEY      = "smith_save"
local SAVE_INTERVAL = 5.0
local CURRENT_VERSION = 2

local MATERIAL_IDS = {
    "ore", "charcoal", "grinding_agent", "wood", "leather",
    "iron", "steel", "jade_dust", "pattern_gold", "meteorite",
}
local MATERIAL_MAX_TIER = 5

local function MaterialTierKey(matId, tier)
    return matId .. "_t" .. tier
end

-- ==================== 默认存档 ====================

--- 敏感字段列表（走 SecureStore）
local SECURE_FIELDS = {
    -- 货币
    "coins", "fame", "jade",
    -- 统计
    "stats.totalForged", "stats.perfectCount", "stats.bestQualityTier",
}

--- 敏感字段前缀（带子表的字段，如 materials.ore）
local SECURE_PREFIXES = {
    "materials",
    "facilities",
    "relationships",
    "factions",
}

--- 创建全新存档数据
---@return table
local function CreateDefaultSave()
    return {
        version = CURRENT_VERSION,
        coins = 0,
        fame = 0,
        jade = 0,
        materials = {
            ore = 8,
            charcoal = 5,
            grinding_agent = 3,
            wood = 2,
            leather = 1,
            pattern_gold = 0,
            meteorite = 0,
        },
        facilities = {
            furnace = 1,
            anvil = 1,
            quench_pool = 1,
            grinder = 1,
            display = 1,
        },
        completedOrders = {},
        dailyOrders = { dayKey = "", orders = {} },
        activeOrder = nil,
        tutorial = { stage = "accept_order", completed = false },
        storyFlags = {},
        choiceHistory = {},
        pendingStoryOrder = nil,
        storyHistory = {},
        codex = {},
        achievedEndings = {},
        storyProgress = {
            chapter = 1,
            nodeId = "CH1-001",
        },
        relationships = {
            keeper = 0,
            shen = 0,
            luchen = 0,
            magistrate = 0,
            disciple = 0,
            hanzhu = 0,
            truth = 0,
            folk = 0,
            pragmatic = 0,
        },
        factions = {
            court = 0,
            guild = 0,
            rivers = 0,
            craftsman = 0,
        },
        stats = {
            totalForged = 0,
            perfectCount = 0,
            bestQualityTier = 0,
        },
        timestamp = 0,
    }
end

-- ==================== 版本迁移 ====================

local MIGRATIONS = {
    -- version 1 -> 2: 材料从单一库存迁移为按品质分层库存。
    [1] = function(data)
        data.version = 2
    end,
}

---@param data table
---@return table
local function MigrateData(data)
    local ver = data.version or 1
    while MIGRATIONS[ver] do
        print("[GameState] Migrating save v" .. ver .. " -> v" .. (ver + 1))
        MIGRATIONS[ver](data)
        ver = data.version
    end
    return data
end

-- ==================== 内部工具 ====================

--- 标记数据已修改
local function MarkDirty()
    dirty_ = true
    changeRevision_ = changeRevision_ + 1
end

--- 将完整存档 table 导入到 secureStore_ + plainData_
---@param saveData table
local function ImportSaveData(saveData)
    secureStore_:Clear()
    plainData_ = {}

    -- 导入顶层敏感字段
    for _, field in ipairs(SECURE_FIELDS) do
        -- 处理点分路径，如 "stats.totalForged"
        local parts = {}
        for part in field:gmatch("[^%.]+") do
            parts[#parts + 1] = part
        end
        local val = saveData
        for _, p in ipairs(parts) do
            val = val and val[p]
        end
        if val then
            secureStore_:Set(field, val)
        end
    end

    -- 导入带前缀的敏感子表
    for _, prefix in ipairs(SECURE_PREFIXES) do
        local subTable = saveData[prefix]
        if type(subTable) == "table" then
            for k, v in pairs(subTable) do
                if type(v) == "number" then
                    secureStore_:Set(prefix .. "." .. k, v)
                end
            end
        end
    end

    -- 旧存档中的材料只有单一数量；首次读取时迁移为 1 阶材料库存。
    for i = 1, #MATERIAL_IDS do
        local matId = MATERIAL_IDS[i]
        local legacyKey = "materials." .. matId
        local tierOneKey = "materials." .. MaterialTierKey(matId, 1)
        if not secureStore_:Has(tierOneKey) then
            secureStore_:Set(tierOneKey, secureStore_:Get(legacyKey))
        end
    end

    -- 导入非敏感字段（明文存储）
    plainData_.version = saveData.version or CURRENT_VERSION
    plainData_.completedOrders = saveData.completedOrders or {}
    plainData_.dailyOrders = saveData.dailyOrders or { dayKey = "", orders = {} }
    plainData_.activeOrder = saveData.activeOrder
    plainData_.tutorial = saveData.tutorial or { stage = "accept_order", completed = false }
    plainData_.storyFlags = saveData.storyFlags or {}
    plainData_.choiceHistory = saveData.choiceHistory or {}
    plainData_.pendingStoryOrder = saveData.pendingStoryOrder
    plainData_.storyHistory = saveData.storyHistory or {}
    plainData_.codex = saveData.codex or {}
    plainData_.achievedEndings = saveData.achievedEndings or {}
    plainData_.storyProgress = saveData.storyProgress or { chapter = 1, nodeId = "CH1-001" }
    plainData_.settings = saveData.settings or { sfxVolume = 80, musicVolume = 60 }
    plainData_.weeklyGoals = saveData.weeklyGoals
    plainData_.timestamp = saveData.timestamp or 0
end

--- 将 secureStore_ + plainData_ 导出为完整存档 table
---@return table
local function ExportSaveData()
    local data = {}

    -- 导出版本和非敏感字段
    data.version = plainData_.version or CURRENT_VERSION
    data.completedOrders = plainData_.completedOrders or {}
    data.dailyOrders = plainData_.dailyOrders or { dayKey = "", orders = {} }
    data.activeOrder = plainData_.activeOrder
    data.tutorial = plainData_.tutorial or { stage = "accept_order", completed = false }
    data.storyFlags = plainData_.storyFlags or {}
    data.choiceHistory = plainData_.choiceHistory or {}
    data.pendingStoryOrder = plainData_.pendingStoryOrder
    data.storyHistory = plainData_.storyHistory or {}
    data.codex = plainData_.codex or {}
    data.achievedEndings = plainData_.achievedEndings or {}
    data.storyProgress = plainData_.storyProgress or { chapter = 1, nodeId = "CH1-001" }
    data.settings = plainData_.settings or { sfxVolume = 80, musicVolume = 60 }
    data.weeklyGoals = plainData_.weeklyGoals
    data.timestamp = os.time()

    -- 导出顶层敏感字段
    data.coins = secureStore_:Get("coins")
    data.fame = secureStore_:Get("fame")
    data.jade = secureStore_:Get("jade")

    -- 导出敏感子表
    for _, prefix in ipairs(SECURE_PREFIXES) do
        data[prefix] = {}
        local exported = secureStore_:ExportAll()
        local prefixDot = prefix .. "."
        for field, val in pairs(exported) do
            if field:sub(1, #prefixDot) == prefixDot then
                local subKey = field:sub(#prefixDot + 1)
                data[prefix][subKey] = val
            end
        end
    end

    -- 导出统计
    data.stats = {
        totalForged    = secureStore_:Get("stats.totalForged"),
        perfectCount   = secureStore_:Get("stats.perfectCount"),
        bestQualityTier = secureStore_:Get("stats.bestQualityTier"),
    }

    return data
end

-- ==================== 生命周期 ====================

--- 异步加载存档（仅启动时调用一次）
---@param callback function|nil function(success: boolean)
function GameState.Load(callback)
    if loaded_ then
        if callback then callback(cloudSaveEnabled_) end
        return
    end

    print("[GameState] Loading from cloud...")

    local function FinishLoad(saveData, status, success)
        ImportSaveData(saveData)
        loaded_ = true
        dirty_ = false
        saving_ = false
        saveTimer_ = 0
        changeRevision_ = 0
        savingRevision_ = 0
        loadStatus_ = status
        cloudSaveEnabled_ = success

        EventBus.Emit("gamestate_loaded", { status = status, cloudAvailable = success })
        if callback then callback(success) end
    end

    local function StartTemporaryOffline(reason)
        print("[GameState] Cloud unavailable; using temporary offline state: " .. reason)
        -- 云读取失败时绝不启用写回。避免默认档覆盖仍存在的远端存档。
        FinishLoad(CreateDefaultSave(), "temporary_offline", false)
    end

    clientCloud:Get(SAVE_KEY, {
        ok = function(values, iscores)
            local saveData = values[SAVE_KEY]
            if not saveData then
                print("[GameState] New player, created default save")
                FinishLoad(CreateDefaultSave(), "new", true)
                return
            end

            if type(saveData) == "string" then
                local ok, parsed = pcall(cjson.decode, saveData)
                if not ok or type(parsed) ~= "table" then
                    StartTemporaryOffline("cloud save parse error")
                    return
                end
                saveData = parsed
            end

            if type(saveData) ~= "table" then
                StartTemporaryOffline("cloud save has invalid type")
                return
            end

            saveData = MigrateData(saveData)
            print("[GameState] Cloud save loaded (v" .. (saveData.version or "?") .. ")")
            FinishLoad(saveData, "loaded", true)
        end,
        error = function(code, reason)
            StartTemporaryOffline("error=" .. tostring(reason) .. " (code=" .. tostring(code) .. ")")
        end,
        timeout = function()
            StartTemporaryOffline("timeout")
        end,
    })
end

--- 保存到云端
---@param callback function|nil function(success: boolean)
function GameState.Save(callback)
    if not loaded_ or saving_ or not cloudSaveEnabled_ then
        if callback then callback(false) end
        return
    end

    saving_ = true
    savingRevision_ = changeRevision_
    local saveData = ExportSaveData()
    local jsonStr = cjson.encode(saveData)

    clientCloud:Set(SAVE_KEY, jsonStr, {
        ok = function()
            saving_ = false
            if changeRevision_ == savingRevision_ then
                dirty_ = false
            end
            print("[GameState] Saved to cloud")
            if callback then callback(true) end
            -- 保存期间发生的新修改（例如刚接单）必须紧接着写入，不能等下一个 5 秒周期。
            if dirty_ then
                GameState.Save()
            end
        end,
        error = function(code, reason)
            saving_ = false
            print("[GameState] Save error: " .. tostring(reason))
            if callback then callback(false) end
        end,
        timeout = function()
            saving_ = false
            print("[GameState] Save timeout")
            if callback then callback(false) end
        end,
    })
end

--- 强制立即保存（退出/切后台时调用）
---@param callback function|nil
function GameState.ForceSave(callback)
    dirty_ = true
    GameState.Save(callback)
end

--- 每帧更新（驱动自动存档定时器）
---@param dt number
function GameState.Update(dt)
    if not loaded_ or not dirty_ then return end
    saveTimer_ = saveTimer_ + dt
    if saveTimer_ >= SAVE_INTERVAL then
        saveTimer_ = 0
        GameState.Save()
    end
end

--- 是否已加载完成
---@return boolean
function GameState.IsLoaded()
    return loaded_
end

---@return string "loading"|"loaded"|"new"|"temporary_offline"
function GameState.GetLoadStatus()
    return loadStatus_
end

---@return boolean
function GameState.CanSaveToCloud()
    return cloudSaveEnabled_
end

--- 重置为默认存档（调试用）
function GameState.Reset()
    local saveData = CreateDefaultSave()
    ImportSaveData(saveData)
    dirty_ = true
    print("[GameState] Reset to default")
end

-- ==================== 货币 ====================

function GameState.GetCoins()
    return secureStore_:Get("coins")
end

function GameState.AddCoins(amount)
    secureStore_:Add("coins", amount)
    MarkDirty()
    EventBus.Emit("coins_changed", { coins = secureStore_:Get("coins") })
end

function GameState.CanAffordCoins(cost)
    return secureStore_:CanAfford("coins", cost)
end

function GameState.GetFame()
    return secureStore_:Get("fame")
end

function GameState.AddFame(amount)
    secureStore_:Add("fame", amount)
    MarkDirty()
    EventBus.Emit("fame_changed", { fame = secureStore_:Get("fame") })
end

function GameState.GetJade()
    return secureStore_:Get("jade")
end

function GameState.AddJade(amount)
    secureStore_:Add("jade", amount)
    MarkDirty()
    EventBus.Emit("jade_changed", { jade = secureStore_:Get("jade") })
end

-- ==================== 材料 ====================

---@param matId string 材料 ID（如 "ore", "charcoal"）
---@return number
function GameState.GetMaterial(matId)
    local total = 0
    for tier = 1, MATERIAL_MAX_TIER do
        total = total + GameState.GetMaterialTier(matId, tier)
    end
    return total
end

---@param matId string
---@param tier number
---@return number
function GameState.GetMaterialTier(matId, tier)
    tier = math.max(1, math.min(MATERIAL_MAX_TIER, math.floor(tier or 1)))
    return secureStore_:Get("materials." .. MaterialTierKey(matId, tier))
end

---@param matId string
---@param tier number
---@param n number
function GameState.AddMaterialTier(matId, tier, n)
    tier = math.max(1, math.min(MATERIAL_MAX_TIER, math.floor(tier or 1)))
    local key = "materials." .. MaterialTierKey(matId, tier)
    secureStore_:Add(key, n)
    MarkDirty()
    EventBus.Emit("material_changed", {
        matId = matId,
        tier = tier,
        count = secureStore_:Get(key),
    })
end

---@param matId string
---@param tier number
---@param cost number
---@return boolean
function GameState.CanAffordMaterialTier(matId, tier, cost)
    tier = math.max(1, math.min(MATERIAL_MAX_TIER, math.floor(tier or 1)))
    return secureStore_:CanAfford("materials." .. MaterialTierKey(matId, tier), cost)
end

---@return number[]
function GameState.GetAvailableMaterialTiers(requiredMaterials)
    local result = {}
    for tier = 1, MATERIAL_MAX_TIER do
        local canUse = true
        for matId, count in pairs(requiredMaterials or {}) do
            if not GameState.CanAffordMaterialTier(matId, tier, count) then
                canUse = false
                break
            end
        end
        if canUse then
            result[#result + 1] = tier
        end
    end
    return result
end

---@param matId string
---@param n number
function GameState.AddMaterial(matId, n)
    GameState.AddMaterialTier(matId, 1, n)
end

---@param matId string
---@param cost number
---@return boolean
function GameState.CanAffordMaterial(matId, cost)
    return GameState.GetMaterial(matId) >= math.floor(cost)
end

--- 返回全部材料的明文快照（UI 展示用，不缓存！）
---@return table<string, number>
function GameState.GetAllMaterials()
    local defaultMats = CreateDefaultSave().materials
    local result = {}
    for matId, _ in pairs(defaultMats) do
        result[matId] = secureStore_:Get("materials." .. matId)
    end
    return result
end

-- ==================== 设施 ====================

---@param facId string 设施 ID（如 "furnace", "anvil"）
---@return number
function GameState.GetFacilityLevel(facId)
    return secureStore_:Get("facilities." .. facId)
end

---@param facId string
---@param level number
function GameState.SetFacilityLevel(facId, level)
    secureStore_:Set("facilities." .. facId, level)
    MarkDirty()
    EventBus.Emit("facility_upgraded", { facilityId = facId, newLevel = level })
end

-- ==================== 订单 / 图鉴 ====================

---@return string[]
function GameState.GetCompletedOrders()
    return plainData_.completedOrders or {}
end

---@param orderId string
function GameState.CompleteOrder(orderId)
    local orders = plainData_.completedOrders or {}
    -- 避免重复
    for i = 1, #orders do
        if orders[i] == orderId then return end
    end
    orders[#orders + 1] = orderId
    plainData_.completedOrders = orders
    MarkDirty()
end

---@return string[]
function GameState.GetCodex()
    return plainData_.codex or {}
end

---@param weaponId string
function GameState.UnlockCodex(weaponId)
    local codex = plainData_.codex or {}
    for i = 1, #codex do
        if codex[i] == weaponId then return end
    end
    codex[#codex + 1] = weaponId
    plainData_.codex = codex
    MarkDirty()
end

--- 获取已达成的结局 ID 列表
---@return string[]
function GameState.GetAchievedEndings()
    return plainData_.achievedEndings or {}
end

--- 标记某个结局已达成（去重持久化，供结局图鉴展示）
---@param endingId string
function GameState.MarkEndingAchieved(endingId)
    local list = plainData_.achievedEndings or {}
    for i = 1, #list do
        if list[i] == endingId then return end
    end
    list[#list + 1] = endingId
    plainData_.achievedEndings = list
    MarkDirty()
end

--- 获取进行中订单持久化快照。
---@return table|nil
function GameState.GetActiveOrder()
    return plainData_.activeOrder
end

---@param snapshot table
function GameState.SetActiveOrder(snapshot)
    plainData_.activeOrder = snapshot
    MarkDirty()
end

function GameState.ClearActiveOrder()
    if not plainData_.activeOrder then return end
    plainData_.activeOrder = nil
    MarkDirty()
end

--- 获取首次锻造教程进度。
---@return table { stage: string, completed: boolean }
function GameState.GetTutorial()
    return plainData_.tutorial or { stage = "accept_order", completed = false }
end

---@param data table { stage: string, completed: boolean }
function GameState.SetTutorial(data)
    plainData_.tutorial = data
    MarkDirty()
end

---@return table<string, any>
function GameState.GetStoryFlags()
    return plainData_.storyFlags or {}
end

---@param flags table<string, any>
function GameState.SetStoryFlags(flags)
    plainData_.storyFlags = flags or {}
    MarkDirty()
end

---@return table[]
function GameState.GetChoiceHistory()
    return plainData_.choiceHistory or {}
end

---@param entry table
function GameState.AddChoiceHistory(entry)
    local history = plainData_.choiceHistory or {}
    history[#history + 1] = entry
    plainData_.choiceHistory = history
    MarkDirty()
end

---@return table|nil
function GameState.GetPendingStoryOrder()
    return plainData_.pendingStoryOrder
end

---@param data table|nil
function GameState.SetPendingStoryOrder(data)
    plainData_.pendingStoryOrder = data
    MarkDirty()
end

---@return table[]
function GameState.GetStoryHistory()
    return plainData_.storyHistory or {}
end

---@param entry table { chapter: number, nodeId: string, speaker: string, text: string }
function GameState.AddStoryHistory(entry)
    local history = plainData_.storyHistory or {}
    history[#history + 1] = entry
    while #history > 40 do
        table.remove(history, 1)
    end
    plainData_.storyHistory = history
    MarkDirty()
end

function GameState.CompleteTutorial()
    plainData_.tutorial = { stage = "complete", completed = true }
    MarkDirty()
end

---@return table { dayKey: string, orders: table[] }
function GameState.GetDailyOrders()
    return plainData_.dailyOrders or { dayKey = "", orders = {} }
end

---@param data table { dayKey: string, orders: table[] }
function GameState.SetDailyOrders(data)
    plainData_.dailyOrders = data
    MarkDirty()
end

-- ==================== 剧情 / 关系（P2 扩展）====================

---@return table { chapter: number, nodeId: string }
function GameState.GetStoryProgress()
    return plainData_.storyProgress or { chapter = 1, nodeId = "CH1-001" }
end

---@param chapter number
---@param nodeId string
function GameState.SetStoryProgress(chapter, nodeId)
    plainData_.storyProgress = { chapter = chapter, nodeId = nodeId }
    MarkDirty()
end

--- 标记全部剧情已完结（到达终点节点且无后续章节时调用，持久化到存档）
function GameState.MarkStoryDone()
    local sp = plainData_.storyProgress or { chapter = 1, nodeId = "CH1-001" }
    sp.done = true
    plainData_.storyProgress = sp
    MarkDirty()
end

---@param npcId string
---@return number
function GameState.GetRelationship(npcId)
    return secureStore_:Get("relationships." .. npcId)
end

---@param npcId string
---@param delta number
function GameState.AddRelationship(npcId, delta)
    secureStore_:Add("relationships." .. npcId, delta)
    MarkDirty()
end

---@param factionId string
---@return number
function GameState.GetFaction(factionId)
    return secureStore_:Get("factions." .. factionId)
end

---@param factionId string
---@param delta number
function GameState.AddFaction(factionId, delta)
    secureStore_:Add("factions." .. factionId, delta)
    MarkDirty()
end

-- ==================== 统计 ====================

---@param statName string 如 "totalForged", "perfectCount"
---@return number
function GameState.GetStat(statName)
    return secureStore_:Get("stats." .. statName)
end

---@param statName string
---@param delta number
function GameState.AddStat(statName, delta)
    secureStore_:Add("stats." .. statName, delta)
    MarkDirty()
end

-- ==================== 每周目标 ====================

--- 获取每周目标数据（plainData 存储，非混淆）
---@return table|nil
function GameState.GetWeeklyGoals()
    return plainData_.weeklyGoals
end

--- 设置每周目标数据
---@param data table { weekStart, goals[] }
function GameState.SetWeeklyGoals(data)
    plainData_.weeklyGoals = data
    MarkDirty()
end

-- ==================== 设置（音量等） ====================

--- 获取设置数据
---@return table { sfxVolume: number, musicVolume: number }
function GameState.GetSettings()
    return plainData_.settings or { sfxVolume = 80, musicVolume = 60 }
end

--- 设置数据
---@param data table { sfxVolume: number, musicVolume: number }
function GameState.SetSettings(data)
    plainData_.settings = data
    MarkDirty()
end

-- ==================== 存档元信息 ====================

function GameState.GetSaveVersion()
    return plainData_.version or CURRENT_VERSION
end

return GameState
