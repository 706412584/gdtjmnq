-- ============================================================================
-- 《问道长生》玩家数据中心
-- 职责：云端存取、内存缓存、自动存档、派生字段计算
-- 设计：Load-Gate 模式 —— 标题页异步加载一次，之后 UI 全部同步读取
-- ============================================================================

local GameServer = require("game_server")
local DataRealms = require("data_realms")
local DataAttr   = require("data_attributes")
local CloudPolyfill = require("network.cloud_polyfill")

local Debug = require("ui_debug")
local Loading = require("ui_loading")

local M = {}

-- ============================================================================
-- 云变量 Key 常量
-- ============================================================================
local PLAYER_KEY      = "player"       -- 主数据（values）
local REALM_RANK_KEY  = "realm"        -- 境界排行（iscores）
local POWER_RANK_KEY  = "power"        -- 战力排行（iscores）
local WEALTH_RANK_KEY = "wealth"       -- 财富排行（iscores）

local SAVE_INTERVAL   = 5.0           -- 自动存档间隔（秒）
local MAX_LOGS        = 50            -- 修炼日志条数上限

-- 派生字段名单（Save 时需排除）
local DERIVED_FIELDS = {
    realmName = true, cultivationMax = true,
    lifespanMax = true, power = true,
}

-- 货币字段（Save 时排除，已迁移到 serverCloud.money）
local CURRENCY_FIELDS = {
    lingStone = true, spiritStone = true,
}

-- ============================================================================
-- 模块状态
-- ============================================================================
local playerData_ = nil    ---@type table|nil 缓存的玩家数据
local dirty_      = false  -- 有未保存的变更
local saveTimer_  = 0
local loaded_     = false  -- 加载已完成（不论成功/失败）
local loading_    = false
local saving_     = false
local saveFailCount_ = 0   -- 连续保存失败次数
local SAVE_FAIL_THRESHOLD = 10  -- 连续失败 N 次后提醒用户

-- 服务端货币缓存（从 serverCloud.money 同步）
local currencyCache_ = {
    lingStone   = 0,
    spiritStone = 0,
}
local currencyLoaded_ = false  -- 是否已从服务端拉取货币余额

-- Load 自动重试
local LOAD_RETRY_INTERVAL = 1.0  -- 重试间隔（秒）- 缩短以加速 clientCloud 检测
local LOAD_RETRY_MAX      = 30   -- 最大重试次数（超过后停止轮询并报错）
local loadRetryTimer_  = 0
local loadRetrying_    = false   -- 是否在重试等待中
local loadCallback_    = nil     -- 缓存的原始回调
local loadRetryCount_  = 0       -- 已重试次数



-- ============================================================================
-- 内部工具
-- ============================================================================

--- 获取下一小境界的修为需求
---@param tier number
---@param sub number
---@return number
local function GetNextCultivationReq(tier, sub)
    if sub < 3 then
        return DataRealms.GetCultivationReq(tier, sub + 1)
    elseif tier < 10 then
        return DataRealms.GetCultivationReq(tier + 1, 1)
    else
        return DataRealms.GetCultivationReq(10, 3)
    end
end

--- 计算战力值（排行榜用）
---@param data table
---@return number
local function CalcPower(data)
    return math.floor(
        (data.attack or 0)
        + (data.defense or 0) * 0.8
        + (data.speed or 0) * 0.5
        + (data.hpMax or 0) / 10
        + (data.mpMax or 0) / 10
    )
end

--- 编码境界为排行榜整数: tier*100 + sub*10
local function EncodeRealm(tier, sub)
    return tier * 100 + sub * 10
end

--- 在缓存数据上附加派生字段（每次修改后调用）
local function AttachDerived(data)
    if not data then return data end
    local tier = data.tier or 1
    local sub  = data.sub or 1
    data.realmName      = DataRealms.GetFullName(tier, sub)
    data.cultivationMax = GetNextCultivationReq(tier, sub)
    local realm = DataRealms.GetRealm(tier)
    data.lifespanMax    = realm and realm.lifespan or 100
    data.power          = CalcPower(data)
    return data
end

--- 构造新角色默认数据
local function CreateDefaultData(info)
    local s = DataAttr.INITIAL_STATS
    local c = DataAttr.INITIAL_CULTIVATION
    return {
        -- 身份
        name        = info.name or "无名",
        gender      = info.gender or "男",
        avatarIndex = info.avatarIndex or 1,
        -- 境界（源数据）
        tier = 1, sub = 1,
        -- 修真属性
        rootBone = info.rootBone or c.rootBone,
        wisdom   = info.wisdom   or c.wisdom,
        fortune  = info.fortune  or c.fortune,
        daoHeart = info.daoHeart or c.daoHeart,
        sense    = info.sense    or c.sense,
        -- 战斗属性
        hp = s.hp, hpMax = s.hpMax,
        mp = s.mp, mpMax = s.mpMax,
        attack = s.attack, defense = s.defense,
        speed = s.speed, crit = s.crit,
        dodge = s.dodge, hit = s.hit,
        -- 修炼进度
        cultivation = 0,
        lifespan    = 0,
        gameYear    = 1,
        -- 货币
        spiritStone = 0,   -- 仙石
        lingStone   = 100, -- 灵石（新手赠送）
        -- 背包 & 功法 & 法宝 & 丹药
        bagCapacity = 50,  -- 初始背包容量
        bagItems    = {},
        skills      = {
            { name = "吐纳术", level = 1, maxLevel = 10, type = "基础",
              desc = "最基本的修炼法门，引导天地灵气入体。",
              effect = "修炼速度+15%" },
        },
        artifacts   = {},
        daoInsights = {},
        pills       = {},
        pillUsage   = {},  -- { ["丹药名"] = 已服用次数 } 本境界
        tradingListings = {},  -- 寄售中的物品列表
        -- 任务 & 试炼
        quests = { daily = {}, main = {}, side = {} },
        trials = {},
        -- 日志
        cultivationLogs = {},
        -- 时间戳
        lastSaveTs = os.time(),
        createdAt  = os.time(),
    }
end

-- ============================================================================
-- 云端读取（Load-Gate）
-- ============================================================================

--- 异步加载玩家数据，仅在标题页调用一次
---@param callback fun(success: boolean, isNewPlayer: boolean)
function M.Load(callback)
    if loading_ then return end
    if loaded_ then
        if callback then callback(true, playerData_ == nil) end
        return
    end
    loading_ = true
    Loading.Start("正在加载数据...")

    -- 尝试恢复 clientCloud：
    -- 1) C++ 原生注入的 clientScore
    -- 2) 网络模式下由 client_net.lua 注入的 polyfill
    ---@diagnostic disable-next-line: undefined-global
    if clientCloud == nil and clientScore ~= nil then
        ---@diagnostic disable-next-line: undefined-global
        clientCloud = clientScore
        print("[GamePlayer] 延迟 fallback: clientScore -> clientCloud 成功")
    end
    ---@diagnostic disable-next-line: undefined-global
    if clientCloud == nil and IsNetworkMode() and network.serverConnection then
        local ClientNet = require("network.client_net")
        if not ClientNet.IsPolyfill() then
            ClientNet.InjectPolyfill()
        end
    end

    ---@diagnostic disable-next-line: undefined-global
    if clientCloud == nil then
        loadRetryCount_ = loadRetryCount_ + 1
        ---@diagnostic disable-next-line: undefined-global
        print("[GamePlayer] clientCloud 未就绪 (第" .. loadRetryCount_ .. "次)"
            .. " | clientScore:" .. tostring(clientScore)
            .. " | IsNetworkMode:" .. tostring(IsNetworkMode())
            .. " | serverConn:" .. tostring(network.serverConnection))
        if loadRetryCount_ >= LOAD_RETRY_MAX then
            loading_ = false
            loaded_  = false
            Loading.Stop()
            loadRetrying_ = false
            print("[GamePlayer] clientCloud 注入超时，已重试 " .. loadRetryCount_ .. " 次")
            local Toast = require("ui_toast")
            Toast.Show("云存储服务未就绪，请退出重试")
            if callback then callback(false, false) end
            return
        end
        loading_ = false
        loadRetrying_   = true
        loadRetryTimer_ = 0
        loadCallback_   = callback
        return
    end

    local key = GameServer.GetServerKey(PLAYER_KEY)
    print("[GamePlayer] 开始加载, key:", key)

    ---@diagnostic disable-next-line: undefined-global
    clientCloud:Get(key, {
        ok = function(values, _iscores)
            loading_ = false
            loaded_  = true
            Loading.Stop()
            local raw = values[key]
            if raw and type(raw) == "table" then
                playerData_ = raw
                AttachDerived(playerData_)
                print("[GamePlayer] 加载成功, 角色:", playerData_.name)
            elseif raw and type(raw) == "string" and #raw > 2 then
                ---@diagnostic disable-next-line: undefined-global
                local ok2, data = pcall(cjson.decode, raw)
                if ok2 and type(data) == "table" then
                    playerData_ = data
                    AttachDerived(playerData_)
                    print("[GamePlayer] 加载成功(json), 角色:", playerData_.name)
                else
                    print("[GamePlayer] JSON 解析失败, 视为新玩家")
                    playerData_ = nil
                end
            else
                print("[GamePlayer] 无角色数据, 新玩家")
                playerData_ = nil
            end
            -- 加载成功后同步服务端货币余额
            if playerData_ then
                M.SyncCurrencyFromServer(function(ok3)
                    if not ok3 then
                        print("[GamePlayer] 货币同步失败，使用本地缓存值")
                    end
                    if callback then callback(true, false) end
                end)
            else
                if callback then callback(true, true) end
            end
        end,
        error = function(code, reason)
            loading_ = false
            print("[GamePlayer] 加载失败:", code, reason)
            Debug.LogError("[网络] 云数据加载失败: code=" .. tostring(code) .. " reason=" .. tostring(reason))
            playerData_ = nil
            -- 启动自动重试（保持 Loading 遮罩）
            loadRetrying_  = true
            loadRetryTimer_ = 0
            loadCallback_  = callback
            local Toast = require("ui_toast")
            Toast.Show("网络异常，正在自动重试...")
        end,
    })
end

-- ============================================================================
-- 云端写入
-- ============================================================================

--- 保存玩家数据到云端（BatchSet：主数据 + 3 个排行榜 iscores）
---@param callback? fun(success: boolean)
function M.Save(callback)
    ---@diagnostic disable-next-line: undefined-global
    if not playerData_ or saving_ or clientCloud == nil then
        if callback then callback(false) end
        return
    end
    saving_ = true
    dirty_  = false
    playerData_.lastSaveTs = os.time()

    -- 构造可序列化副本（排除派生字段和货币字段）
    local toSave = {}
    for k, v in pairs(playerData_) do
        if not DERIVED_FIELDS[k] and not CURRENCY_FIELDS[k] then
            toSave[k] = v
        end
    end

    local key = GameServer.GetServerKey(PLAYER_KEY)

    -- P1: 网络模式下排行榜由服务端自动计算，客户端不再写 iscores
    ---@diagnostic disable-next-line: undefined-global
    local batch = clientCloud:BatchSet():Set(key, toSave)

    if not IsNetworkMode() then
        -- 单机模式：客户端仍需写排行榜
        local realmKey  = GameServer.GetGroupKey(REALM_RANK_KEY)
        local powerKey  = GameServer.GetGroupKey(POWER_RANK_KEY)
        local wealthKey = GameServer.GetGroupKey(WEALTH_RANK_KEY)
        local tier = playerData_.tier or 1
        local sub  = playerData_.sub or 1
        batch:SetInt(realmKey,  EncodeRealm(tier, sub))
             :SetInt(powerKey,  CalcPower(playerData_))
             :SetInt(wealthKey, (currencyCache_.lingStone or 0)
                              + (currencyCache_.spiritStone or 0) * 100)
    end

    batch:Save("auto_save", {
            ok = function()
                saving_ = false
                if saveFailCount_ > 0 then
                    print("[GamePlayer] 网络恢复，保存成功（此前失败 " .. saveFailCount_ .. " 次）")
                end
                saveFailCount_ = 0
                if callback then callback(true) end
            end,
            error = function(code, reason)
                saving_ = false
                dirty_ = true  -- 失败后重新标脏
                saveFailCount_ = saveFailCount_ + 1
                print("[GamePlayer] 保存失败(" .. saveFailCount_ .. "):", code, reason)
                Debug.LogError("[网络] 云数据保存失败: code=" .. tostring(code) .. " reason=" .. tostring(reason))
                if saveFailCount_ == SAVE_FAIL_THRESHOLD then
                    local Toast = require("ui_toast")
                    Toast.Show("网络异常，数据暂未保存，请检查网络连接")
                end
                if callback then callback(false) end
            end,
        })
end

-- ============================================================================
-- 同步读取接口（UI 层调用）
-- ============================================================================

--- 获取玩家数据（含派生字段），未加载返回 nil
---@return table|nil
function M.Get()
    return playerData_
end

--- 是否已完成加载
function M.IsLoaded() return loaded_ end

--- 是否有角色数据
function M.HasCharacter() return loaded_ and playerData_ ~= nil end

--- 标记数据已修改
function M.MarkDirty() dirty_ = true end

-- ============================================================================
-- 角色创建（传承页调用）
-- ============================================================================

--- 创建新角色并立即保存
---@param charInfo table { name, gender, avatarIndex, rootBone?, ... }
---@param callback? fun(success: boolean)
function M.CreateCharacter(charInfo, callback)
    playerData_ = CreateDefaultData(charInfo)
    AttachDerived(playerData_)
    loaded_ = true
    dirty_  = false

    -- 初始化货币缓存（新手赠送灵石 100）
    local initLing   = playerData_.lingStone or 100
    local initSpirit = playerData_.spiritStone or 0
    currencyCache_.lingStone   = initLing
    currencyCache_.spiritStone = initSpirit
    currencyLoaded_ = true

    print("[GamePlayer] 创建角色:", playerData_.name, playerData_.gender)

    -- 先保存角色数据，再同步初始货币到服务端
    M.Save(function(saveOk)
        ---@diagnostic disable-next-line: undefined-global
        if IsNetworkMode() and initLing > 0 then
            CloudPolyfill.CurrencyAdd("lingStone", initLing, {
                ok = function(result)
                    print("[GamePlayer] 新手灵石已同步到服务端")
                    if callback then callback(saveOk) end
                end,
                error = function(code, reason)
                    print("[GamePlayer] 新手灵石同步失败:", reason)
                    if callback then callback(saveOk) end
                end,
            })
        else
            if callback then callback(saveOk) end
        end
    end)
end

-- ============================================================================
-- Update（main.lua 每帧调用，驱动自动存档）
-- ============================================================================

---@param dt number
function M.Update(dt)
    -- Load 自动重试
    if loadRetrying_ and not loading_ then
        ---@diagnostic disable-next-line: undefined-global
        if clientCloud ~= nil then
            -- polyfill/clientCloud 已就绪，立即重试（不等定时器）
            print("[GamePlayer] clientCloud 已就绪，立即重试加载")
            loadRetrying_ = false
            M.Load(loadCallback_)
            return
        end
        loadRetryTimer_ = loadRetryTimer_ + dt
        if loadRetryTimer_ >= LOAD_RETRY_INTERVAL then
            loadRetryTimer_ = 0
            ---@diagnostic disable-next-line: undefined-global
            print("[GamePlayer] 重试加载 #" .. (loadRetryCount_ + 1)
                .. " | clientCloud:" .. tostring(clientCloud)
                .. " | clientScore:" .. tostring(clientScore))
            loadRetrying_ = false
            M.Load(loadCallback_)
        end
    end

    -- 自动存档
    if not dirty_ or not playerData_ then return end
    saveTimer_ = saveTimer_ + dt
    if saveTimer_ >= SAVE_INTERVAL then
        saveTimer_ = 0
        M.Save()
    end
end

-- ============================================================================
-- 数据修改器（全部自动标脏 + 刷新派生字段）
-- ============================================================================

--- 增加修为
---@param amount number
function M.AddCultivation(amount)
    if not playerData_ then return end
    playerData_.cultivation = (playerData_.cultivation or 0) + amount
    AttachDerived(playerData_)
    dirty_ = true
end

--- 设置境界（突破后调用）
---@param tier number
---@param sub number
function M.SetRealm(tier, sub)
    if not playerData_ then return end
    playerData_.tier = tier
    playerData_.sub  = sub
    playerData_.cultivation = 0
    AttachDerived(playerData_)
    dirty_ = true
end

--- 应用大境界突破增幅
---@param fromTier number 突破前的大境界阶数
function M.ApplyBreakBonus(fromTier)
    if not playerData_ then return end
    local b = DataRealms.GetBreakBonus(fromTier)
    if not b then return end
    playerData_.attack  = (playerData_.attack or 0)  + b.atk
    playerData_.defense = (playerData_.defense or 0) + b.def
    playerData_.hpMax   = (playerData_.hpMax or 0)   + b.hp
    playerData_.hp      = playerData_.hpMax
    playerData_.speed   = (playerData_.speed or 0)   + b.spd
    playerData_.crit    = (playerData_.crit or 0)    + b.crit
    playerData_.sense   = (playerData_.sense or 0)   + (b.sense or 0)
    AttachDerived(playerData_)
    dirty_ = true
end

--- 获取货币余额（从服务端货币缓存读取）
---@param currency string "lingStone"|"spiritStone"
---@return number
function M.GetCurrency(currency)
    return currencyCache_[currency] or 0
end

--- 增减货币（通过服务端 serverCloud.money 原子操作）
--- 本地乐观更新 + 异步同步到服务端
---@param currency string "lingStone"|"spiritStone"
---@param amount number 正数增加，负数减少
---@param callback? fun(success: boolean, balance: number) 可选回调
---@return boolean 余额不足时返回 false（本地预检查）
function M.AddCurrency(currency, amount, callback)
    if not playerData_ then return false end
    local cur = currencyCache_[currency] or 0

    if amount > 0 then
        -- 增加：乐观更新本地缓存，异步通知服务端
        currencyCache_[currency] = cur + amount
        -- 同步到 playerData_ 用于 UI 显示和财富排行
        playerData_[currency] = currencyCache_[currency]
        dirty_ = true

        ---@diagnostic disable-next-line: undefined-global
        if IsNetworkMode() then
            CloudPolyfill.CurrencyAdd(currency, amount, {
                ok = function(result)
                    if result.balance and result.balance >= 0 then
                        currencyCache_[currency] = result.balance
                        if playerData_ then
                            playerData_[currency] = result.balance
                        end
                    end
                    if callback then callback(true, currencyCache_[currency]) end
                end,
                error = function(code, reason)
                    print("[GamePlayer] 货币增加服务端同步失败:", currency, amount, reason)
                    if callback then callback(true, currencyCache_[currency]) end
                end,
            })
        else
            if callback then callback(true, currencyCache_[currency]) end
        end
        return true

    elseif amount < 0 then
        -- 扣除：先本地预检查余额
        local cost = math.abs(amount)
        if cur < cost then return false end

        -- 乐观更新
        currencyCache_[currency] = cur - cost
        playerData_[currency] = currencyCache_[currency]
        dirty_ = true

        ---@diagnostic disable-next-line: undefined-global
        if IsNetworkMode() then
            CloudPolyfill.CurrencyCost(currency, cost, {
                ok = function(result)
                    if result.balance and result.balance >= 0 then
                        currencyCache_[currency] = result.balance
                        if playerData_ then
                            playerData_[currency] = result.balance
                        end
                    end
                    if callback then callback(true, currencyCache_[currency]) end
                end,
                error = function(code, reason)
                    -- 服务端扣除失败（真实余额不足）→ 回滚本地
                    print("[GamePlayer] 货币扣除失败，回滚:", currency, cost, reason)
                    currencyCache_[currency] = cur  -- 回滚
                    if playerData_ then
                        playerData_[currency] = cur
                    end
                    local Toast = require("ui_toast")
                    Toast.Show("余额不足，操作失败")
                    if callback then callback(false, cur) end
                end,
            })
        else
            if callback then callback(true, currencyCache_[currency]) end
        end
        return true
    end

    -- amount == 0
    if callback then callback(true, cur) end
    return true
end

--- 仅更新本地货币缓存（服务端已通过 money:Add 发放，不再重复请求）
--- 用于服务端结算回复后，客户端乐观同步显示
---@param currency string "lingStone"|"spiritStone"
---@param amount number 增加量（正数）
function M.AddCurrencyLocal(currency, amount)
    if not playerData_ then return end
    if amount <= 0 then return end
    currencyCache_[currency] = (currencyCache_[currency] or 0) + amount
    playerData_[currency] = currencyCache_[currency]
    dirty_ = true
end

--- 从服务端同步货币余额（加载时调用一次）
---@param callback? fun(success: boolean)
function M.SyncCurrencyFromServer(callback)
    ---@diagnostic disable-next-line: undefined-global
    if not IsNetworkMode() then
        -- 单机模式：从 playerData_ 读取
        if playerData_ then
            currencyCache_.lingStone   = playerData_.lingStone or 0
            currencyCache_.spiritStone = playerData_.spiritStone or 0
        end
        currencyLoaded_ = true
        if callback then callback(true) end
        return
    end

    CloudPolyfill.CurrencyGet({
        ok = function(result)
            local balances = result.balances or {}
            currencyCache_.lingStone   = balances.lingStone or 0
            currencyCache_.spiritStone = balances.spiritStone or 0
            -- 同步到 playerData_ 用于 UI 显示
            if playerData_ then
                playerData_.lingStone   = currencyCache_.lingStone
                playerData_.spiritStone = currencyCache_.spiritStone
            end
            currencyLoaded_ = true
            print("[GamePlayer] 货币同步成功: 灵石=" .. currencyCache_.lingStone
                .. " 仙石=" .. currencyCache_.spiritStone)
            if callback then callback(true) end
        end,
        error = function(code, reason)
            print("[GamePlayer] 货币同步失败:", reason)
            -- 失败时用 playerData_ 中的旧值
            if playerData_ then
                currencyCache_.lingStone   = playerData_.lingStone or 0
                currencyCache_.spiritStone = playerData_.spiritStone or 0
            end
            currencyLoaded_ = true
            if callback then callback(false) end
        end,
    })
end

--- 添加背包物品（自动堆叠同名物品，自动附加分类信息）
---@param item table { name, count?, rarity?, desc?, category?, subType? }
function M.AddItem(item)
    if not playerData_ then return end
    for _, e in ipairs(playerData_.bagItems) do
        if e.name == item.name then
            e.count = (e.count or 0) + (item.count or 1)
            dirty_ = true
            return
        end
    end
    -- 自动推断分类
    local cat = item.category
    local sub = item.subType
    if not cat then
        local DataItems = require("data_items")
        cat, sub = DataItems.InferCategory(item.name)
    end
    table.insert(playerData_.bagItems, {
        name     = item.name,
        count    = item.count or 1,
        rarity   = item.rarity or "common",
        desc     = item.desc or "",
        category = cat,
        subType  = sub,
        locked   = false,
    })
    dirty_ = true
end

--- 移除背包物品（按索引）
---@param index number
---@param count? number 默认移除全部
---@return boolean
function M.RemoveItem(index, count)
    if not playerData_ then return false end
    local items = playerData_.bagItems
    if index < 1 or index > #items then return false end
    local item = items[index]
    local n = count or item.count
    if item.count <= n then
        table.remove(items, index)
    else
        item.count = item.count - n
    end
    dirty_ = true
    return true
end

--- 按名称移除物品
---@param name string
---@param count? number
---@return boolean
function M.RemoveItemByName(name, count)
    if not playerData_ then return false end
    for i, item in ipairs(playerData_.bagItems) do
        if item.name == name then
            return M.RemoveItem(i, count)
        end
    end
    return false
end

--- 添加修炼日志（自动限长）
---@param text string
function M.AddLog(text)
    if not playerData_ then return end
    local logs = playerData_.cultivationLogs
    table.insert(logs, text)
    while #logs > MAX_LOGS do table.remove(logs, 1) end
    dirty_ = true
end

--- 增加寿命 / 游戏年份
---@param years number
function M.AddLifespan(years)
    if not playerData_ then return end
    playerData_.lifespan = (playerData_.lifespan or 0) + years
    playerData_.gameYear = (playerData_.gameYear or 1) + years
    dirty_ = true
end

--- 恢复气血
---@param amount number
function M.HealHP(amount)
    if not playerData_ then return end
    playerData_.hp = math.min(
        playerData_.hpMax or 800,
        (playerData_.hp or 0) + amount
    )
    dirty_ = true
end

--- 恢复灵力
---@param amount number
function M.HealMP(amount)
    if not playerData_ then return end
    playerData_.mp = math.min(
        playerData_.mpMax or 200,
        (playerData_.mp or 0) + amount
    )
    dirty_ = true
end

--- 计算离线收益（返回离线秒数和获得的修为）
---@return number seconds, number cultivation
function M.CalcOfflineGains()
    if not playerData_ then return 0, 0 end
    local elapsed = math.max(0, os.time() - (playerData_.lastSaveTs or os.time()))
    if elapsed < 60 then return 0, 0 end
    local DataFormulas = require("data_formulas")
    local perSec = DataFormulas.CalcCultivationPerSec(
        playerData_.tier or 1,
        playerData_.rootBone or "中品灵根",
        0, 0
    )
    local gained = math.floor(perSec * elapsed * 0.5)  -- 离线效率 50%
    return elapsed, gained
end

--- 强制立即保存
---@param callback? fun(success: boolean)
function M.ForceSave(callback)
    dirty_ = false
    saveTimer_ = 0
    M.Save(callback)
end

-- ============================================================================
-- 丹药服用次数管理（每境界重置）
-- ============================================================================

--- 获取某丹药在本境界的已服用次数
---@param pillName string
---@return number
function M.GetPillUsage(pillName)
    if not playerData_ then return 0 end
    local usage = playerData_.pillUsage or {}
    return usage[pillName] or 0
end

--- 增加某丹药的服用次数
---@param pillName string
function M.AddPillUsage(pillName)
    if not playerData_ then return end
    playerData_.pillUsage = playerData_.pillUsage or {}
    playerData_.pillUsage[pillName] = (playerData_.pillUsage[pillName] or 0) + 1
    dirty_ = true
end

--- 重置丹药服用次数（突破大境界后调用）
function M.ResetPillUsage()
    if not playerData_ then return end
    playerData_.pillUsage = {}
    dirty_ = true
end

--- 重新计算派生字段（装备/功法变更后调用）
function M.RefreshDerived()
    if not playerData_ then return end
    AttachDerived(playerData_)
    dirty_ = true
end

--- 重置状态（切换服务器时调用）
function M.Reset()
    playerData_ = nil
    dirty_      = false
    saveTimer_  = 0
    loaded_     = false
    loading_    = false
    saving_     = false
    saveFailCount_  = 0
    loadRetrying_   = false
    loadRetryTimer_ = 0
    loadCallback_   = nil
    loadRetryCount_ = 0
    -- 重置货币缓存
    currencyCache_.lingStone   = 0
    currencyCache_.spiritStone = 0
    currencyLoaded_ = false
end

return M
