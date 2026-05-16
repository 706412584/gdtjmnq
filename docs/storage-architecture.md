# 古代铁匠模拟器 - 存储架构设计

> **单机游戏 + 云变量自动存档 + 客户端内存混淆**
>
> 参考项目：问道长生（`docs/scripts/game_player.lua`）

---

## 一、架构概览

```
┌─────────────────────────────────────────────────────────┐
│                   Screen / MiniGame 层                   │
│         UI 读写只走 GameState 公开接口                     │
│    GameState.GetCoins()  GameState.AddCoins(50)          │
└────────────────────────┬────────────────────────────────┘
                         │ 统一入口
                         v
┌─────────────────────────────────────────────────────────┐
│                    GameState（数据中枢）                   │
│                                                         │
│  ┌──────────────┐  ┌──────────────┐  ┌───────────────┐  │
│  │ SecureStore   │  │ 非敏感字段   │  │  dirty 标记   │  │
│  │ (XOR 混淆)    │  │ (明文 table) │  │  + 自动存档   │  │
│  │              │  │              │  │  定时器       │  │
│  │ coins ──►    │  │ name = "..."│  │              │  │
│  │  encoded~key │  │ codex = {}  │  │  INTERVAL=5s │  │
│  │ fame ──►     │  │ storyProg.. │  │              │  │
│  │  encoded~key │  │              │  │              │  │
│  └──────────────┘  └──────────────┘  └───────────────┘  │
└────────────────────────┬────────────────────────────────┘
                         │ Save()/Load()
                         v
┌─────────────────────────────────────────────────────────┐
│                clientCloud（云变量）                       │
│                                                         │
│   key: "smith_save"  →  value: { 明文 JSON }             │
│                                                         │
│   Save: 解混淆 → 序列化 → clientCloud:Set()              │
│   Load: clientCloud:Get() → 反序列化 → 混淆入内存         │
└─────────────────────────────────────────────────────────┘
```

### 核心原则

| 原则 | 说明 |
|------|------|
| **单一数据中枢** | 所有游戏数据只在 `GameState` 中读写，禁止其他模块自建数据副本 |
| **敏感数值混淆** | 货币/材料/声望等可被 GG 搜索的数值，内存中只存 XOR 混淆值 |
| **操作即加密** | 读 = 解码到栈上短暂使用；写 = 修改后立即编码回去，明文不驻留 |
| **云端存明文** | clientCloud 存储明文 JSON（服务端可信），混淆仅保护客户端内存 |
| **脏标记自动存档** | 数据变更标 dirty，Update 每 5 秒检查一次，dirty 则自动 Save |

---

## 二、内存混淆方案 (SecureStore)

### 2.1 原理

GG（GameGuardian）通过以下方式定位内存中的数值：
1. **精确值搜索**：搜索 `500`（铜钱当前值）
2. **变化值搜索**：操作后搜索「减少了的值」→ 缩小范围
3. **模糊搜索**：搜索「没变的值」排除无关地址

**防御策略**：对每个敏感数值 `v`，内存中存储 `(encoded, key)` 而非 `v`：

```
encoded = v ~ key        -- XOR 编码（Lua 5.4 位运算）
key = 随机整数            -- 每次写入重新生成

读取: v = encoded ~ key   -- 解码（仅在栈上短暂存在）
写入: key = newRandom()
      encoded = v ~ key   -- 新 key 编码后写回
```

**为什么有效**：
- 内存中从来没有明文 `500`，GG 搜 `500` 找不到
- 每次写入 key 都变，`encoded` 也跟着变 → GG 的「值没变」搜索也定位不到
- 解码后的明文只在 Lua 栈上（局部变量），生命周期极短，GG 几乎不可能在这个窗口捕获

### 2.2 实现规格

```lua
-- scripts/Core/SecureStore.lua

local SecureStore = {}
SecureStore.__index = SecureStore

local KEY_RANGE = 0x7FFFFFFF  -- key 范围（31 位正整数）

--- 创建安全存储实例
function SecureStore.New()
    local self = setmetatable({}, SecureStore)
    self.data_ = {}    -- { [fieldName] = { encoded=int, key=int } }
    return self
end

--- 写入一个数值（立即编码）
---@param name string 字段名
---@param value number 明文数值（整数）
function SecureStore:Set(name, value)
    local intVal = math.floor(value)
    local key = math.random(1, KEY_RANGE)
    self.data_[name] = {
        encoded = intVal ~ key,   -- XOR 编码
        key = key,
    }
end

--- 读取一个数值（解码）
---@param name string
---@return number 明文数值
function SecureStore:Get(name)
    local entry = self.data_[name]
    if not entry then return 0 end
    return entry.encoded ~ entry.key  -- XOR 解码
end

--- 增减数值（解码 → 计算 → 重新编码，key 自动轮换）
---@param name string
---@param delta number
---@return number 操作后的新值
function SecureStore:Add(name, delta)
    local cur = self:Get(name)
    local newVal = cur + math.floor(delta)
    self:Set(name, newVal)  -- 重新编码（新 key）
    return newVal
end

--- 检查余额是否足够
---@param name string
---@param cost number
---@return boolean
function SecureStore:CanAfford(name, cost)
    return self:Get(name) >= math.floor(cost)
end

--- 批量导出明文（Save 用）
---@return table<string, number>
function SecureStore:ExportAll()
    local plain = {}
    for name, _ in pairs(self.data_) do
        plain[name] = self:Get(name)
    end
    return plain
end

--- 批量导入明文（Load 用）
---@param plain table<string, number>
function SecureStore:ImportAll(plain)
    for name, value in pairs(plain) do
        self:Set(name, value)
    end
end

--- 清空
function SecureStore:Clear()
    self.data_ = {}
end

return SecureStore
```

### 2.3 哪些字段需要混淆

| 类别 | 字段 | 混淆 | 理由 |
|------|------|------|------|
| 货币 | coins, fame, jade | 是 | GG 首要目标 |
| 材料数量 | materials.ore, materials.charcoal, ... | 是 | 可被搜索 |
| 设施等级 | facilities.furnace, facilities.anvil, ... | 是 | 等级影响收益 |
| 统计数值 | stats.totalForged, stats.perfectCount | 是 | 可能影响奖励计算 |
| 角色名 | name | 否 | 字符串，GG 不搜 |
| 已完成订单列表 | completedOrders | 否 | 字符串数组 |
| 剧情进度 | storyProgress | 否 | 结构数据 |
| 角色关系 | relationships.* | 是 | 整数，可能被修改 |
| 阵营声望 | factions.* | 是 | 整数 |
| 图鉴列表 | codex | 否 | 字符串数组 |
| 存档版本 | version | 否 | 不敏感 |
| 时间戳 | timestamp | 否 | 不敏感 |

**规则**：所有 `number` 类型且影响游戏经济/进度的字段 → 混淆；`string`/`boolean`/`table（结构）` → 不混淆。

---

## 三、GameState 统一入口

### 3.1 职责

GameState 是**唯一**的数据读写入口，职责：

1. **Load-Gate**：启动时从 clientCloud 异步加载一次，之后全部同步读取
2. **内存混淆**：敏感数值通过 SecureStore 存储
3. **脏标记 + 自动存档**：数据变更标 dirty，每 5 秒自动 Save
4. **导入导出**：Load 时明文→混淆；Save 时混淆→明文→云端

### 3.2 接口设计

```lua
-- scripts/Core/GameState.lua 公开接口

local M = {}

-- ====== 生命周期 ======
M.Load(callback)           -- 异步加载（仅标题页调一次）
M.Save(callback?)          -- 手动保存（一般不需要，自动存档覆盖）
M.ForceSave(callback?)     -- 强制立即保存（退出/切后台时调用）
M.Update(dt)               -- main.lua 每帧调用（驱动自动存档定时器）
M.IsLoaded()               -- 是否已加载完成
M.Reset()                  -- 重置（开发调试用）

-- ====== 货币 ======
M.GetCoins()               -- 读取铜钱
M.AddCoins(amount)         -- 增加铜钱（正数加，负数减）
M.CanAffordCoins(cost)     -- 能否支付
M.GetFame()                -- 读取声望
M.AddFame(amount)          -- 增加声望
M.GetJade()                -- 读取玉石（高级货币）
M.AddJade(amount)          -- 增加玉石

-- ====== 材料 ======
M.GetMaterial(matId)       -- 读取某种材料数量
M.AddMaterial(matId, n)    -- 增减材料
M.CanAffordMaterial(matId, cost)
M.GetAllMaterials()        -- 返回 { matId = count, ... } 全部明文（UI 展示用）

-- ====== 设施 ======
M.GetFacilityLevel(facId)  -- 读取设施等级
M.SetFacilityLevel(facId, level) -- 设置设施等级

-- ====== 订单 / 图鉴 ======
M.GetCompletedOrders()     -- 返回已完成订单 ID 列表（明文 table）
M.CompleteOrder(orderId)   -- 标记订单完成
M.GetCodex()               -- 返回已解锁武器 ID 列表
M.UnlockCodex(weaponId)    -- 解锁图鉴

-- ====== 剧情 / 关系（P2）======
M.GetStoryProgress()       -- { chapter, nodeId }
M.SetStoryProgress(chapter, nodeId)
M.GetRelationship(npcId)   -- 读取好感度
M.AddRelationship(npcId, delta)
M.GetFaction(factionId)    -- 读取阵营声望
M.AddFaction(factionId, delta)

-- ====== 统计 ======
M.GetStat(statName)        -- 读取统计值
M.AddStat(statName, delta) -- 增加统计值

-- ====== 存档元信息 ======
M.GetSaveVersion()         -- 当前存档版本号
M.CreateNewSave()          -- 创建全新存档（新游戏）
```

### 3.3 内部结构

```lua
-- GameState 内部（不对外暴露）

local secureStore = SecureStore.New()   -- 敏感数值（混淆存储）
local plainData = {                     -- 非敏感数据（明文 table）
    version = 1,
    completedOrders = {},
    codex = {},
    storyProgress = { chapter = 1, nodeId = "CH1-001" },
    timestamp = 0,
}

local dirty_     = false
local saveTimer_ = 0
local loaded_    = false
local SAVE_INTERVAL = 5.0
```

### 3.4 Save/Load 流程

**Load 流程**：
```
clientCloud:Get("smith_save")
    ↓ ok
解析 JSON → plain table
    ↓
敏感字段 → secureStore:ImportAll({ coins=500, fame=120, ... })
非敏感字段 → 直接赋值给 plainData
    ↓
loaded_ = true
回调 callback(true)
```

**Save 流程**：
```
secureStore:ExportAll() → { coins=500, fame=120, ... }
    ↓
合并 plainData → 完整 save table
    ↓
clientCloud:Set("smith_save", saveTable, { ok=..., error=... })
    ↓
dirty_ = false
```

### 3.5 自动存档时序

```lua
function M.Update(dt)
    if not dirty_ or not loaded_ then return end
    saveTimer_ = saveTimer_ + dt
    if saveTimer_ >= SAVE_INTERVAL then
        saveTimer_ = 0
        M.Save()
    end
end
```

---

## 四、云变量方案

### 4.1 使用 clientCloud（纯客户端）

本项目是**单机游戏**，不需要 serverCloud/多人同步。使用 `clientCloud` 即可：

| API | 用途 |
|-----|------|
| `clientCloud:Set(key, value, callbacks)` | 写入云变量 |
| `clientCloud:Get(key, callbacks)` | 读取云变量 |
| `clientCloud:BatchSet()` | 批量写入（原子操作） |

### 4.2 云变量 Key 设计

```lua
local SAVE_KEY = "smith_save"   -- 主存档数据
```

只用一个 key 存整个存档。理由：
- 单机游戏数据量不大（< 64KB）
- 一次读写完成，不需要分 key 管理
- 简化代码和调试

### 4.3 存档数据结构（云端明文）

```json
{
    "version": 1,
    "coins": 500,
    "fame": 120,
    "jade": 0,
    "materials": {
        "ore": 10, "charcoal": 5, "grinding_agent": 2,
        "wood": 2, "leather": 1, "pattern_gold": 0, "meteorite": 0
    },
    "facilities": {
        "furnace": 2, "anvil": 1, "quench_pool": 1,
        "grinder": 1, "display": 1
    },
    "completedOrders": ["ORD_T1_001", "ORD_T1_002"],
    "codex": ["WEAPON_001"],
    "storyProgress": { "chapter": 1, "nodeId": "CH1-010" },
    "relationships": { "keeper": 15, "shen": -5 },
    "factions": { "court": 20, "guild": 10, "rivers": 0, "craftsman": 5 },
    "stats": { "totalForged": 12, "perfectCount": 3, "bestQualityTier": 3 },
    "timestamp": 1700000000
}
```

### 4.4 存档版本迁移

当存档结构变化时，通过 version 字段做迁移：

```lua
local MIGRATIONS = {
    -- version 1 → 2: 新增 jade 字段
    [1] = function(data)
        data.jade = data.jade or 0
        data.version = 2
    end,
    -- version 2 → 3: materials 结构变更
    [2] = function(data)
        data.materials.meteorite = data.materials.meteorite or 0
        data.version = 3
    end,
}

local function MigrateData(data)
    local current = data.version or 1
    while MIGRATIONS[current] do
        MIGRATIONS[current](data)
        current = data.version
    end
    return data
end
```

---

## 五、敏感数值的读写规范

### 5.1 黄金法则

```
明文不驻留内存
  ├─ 读：解码 → 使用 → 丢弃（局部变量出作用域即消失）
  ├─ 写：计算新值 → 立即编码 → 明文出栈
  └─ 禁止：将明文缓存到模块级变量或全局变量
```

### 5.2 正确示例

```lua
-- ✅ 正确：通过 GameState 接口读写
function onOrderComplete(reward)
    GameState.AddCoins(reward.coins)    -- 内部：解码→加→重编码→标脏
    GameState.AddFame(reward.fame)
    GameState.AddMaterial("ore", reward.ore or 0)

    -- 读取用于 UI 显示（栈上临时值）
    local coins = GameState.GetCoins()
    coinsLabel.text = "铜钱: " .. coins
    -- coins 在函数结束后出栈，不驻留
end
```

### 5.3 禁止示例

```lua
-- ❌ 错误：缓存明文到模块级变量
local cachedCoins = 0  -- GG 可以搜到这个值！

function updateUI()
    cachedCoins = GameState.GetCoins()  -- 明文长期驻留！
    coinsLabel.text = "铜钱: " .. cachedCoins
end

-- ❌ 错误：绕过 GameState 直接操作数据
playerData.coins = playerData.coins + 100  -- 绕过混淆！

-- ❌ 错误：在全局 table 中存明文副本
G_UI_DATA = { coins = GameState.GetCoins() }  -- 副本可被 GG 搜到！
```

### 5.4 UI 显示的正确方式

UI 展示数值时，允许在 label.text 中存字符串形式（GG 不搜字符串）：

```lua
-- ✅ 安全：UI 组件的 text 属性是字符串，GG 不搜字符串
coinsLabel.text = "铜钱: " .. GameState.GetCoins()

-- ✅ 安全：格式化后赋值
fameLabel.text = string.format("声望: %d", GameState.GetFame())
```

---

## 六、初始化种子 + 防重放

### 6.1 随机种子初始化

```lua
-- main.lua 的 Start() 中，在任何 SecureStore 操作之前：
math.randomseed(os.time() + os.clock() * 1000)
-- 额外搅动
for i = 1, 10 do math.random() end
```

### 6.2 校验和（可选增强）

对于高价值数值（铜钱、玉石），可以额外存一个校验和：

```lua
-- 写入时同时存校验
function SecureStore:SetWithCheck(name, value)
    self:Set(name, value)
    self:Set(name .. "_chk", value * 7 + 13)  -- 简单线性校验
end

-- 读取时验证
function SecureStore:GetWithCheck(name)
    local val = self:Get(name)
    local chk = self:Get(name .. "_chk")
    if chk ~= val * 7 + 13 then
        -- 校验失败 → 内存被篡改！
        print("[SecureStore] 篡改检测: " .. name)
        return 0, false  -- 返回 0 + 篡改标记
    end
    return val, true
end
```

这属于可选增强，P1 阶段先用基础 XOR 即可。

---

## 七、与参考项目的对比

| 维度 | 参考项目（问道长生） | 本项目（铁匠模拟器） |
|------|---------------------|---------------------|
| 网络模式 | 单机+多人 双模式 | **纯单机** |
| 云变量 | clientCloud + serverCloud.money | **仅 clientCloud** |
| 货币操作 | serverCloud.money 原子操作 | **SecureStore + clientCloud:Set** |
| 内存保护 | 无 | **XOR 混淆 + key 轮换** |
| 自动存档 | dirty + 5s 定时器 | **相同模式** |
| Load-Gate | 标题页异步加载一次 | **相同模式** |
| 派生字段 | DERIVED_FIELDS 排除 | **不需要**（本项目没有复杂派生） |
| Can/Do 模式 | CanUsePill/DoUsePill | **CanAfford/Add 简化版** |
| 存档迁移 | 无显式 migration | **version + MIGRATIONS 表** |
| 数据中枢 | game_player.lua | **GameState.lua** |

---

## 八、文件清单

| 文件 | 职责 | 里程碑 |
|------|------|--------|
| `scripts/Core/SecureStore.lua` | XOR 内存混淆模块 | P1-A（框架） |
| `scripts/Core/GameState.lua` | 统一数据中枢 | P1-A（框架） |
| — | 无 SaveManager.lua | 合并到 GameState |

> SaveManager 合并进 GameState：本项目数据结构简单，不需要独立存档管理器。
> 参考项目也是在 game_player.lua 中同时处理状态管理和存档。

---

## 九、FAQ

**Q: XOR 混淆能不能被专业逆向工具绕过？**
A: 可以。XOR 不是加密，是混淆。目标是挡住 95% 用 GG 搜值修改的普通玩家。专业逆向（Frida/IDA）理论上可以还原，但成本远高于收益（单机休闲游戏不值得）。

**Q: 为什么不用更复杂的加密？**
A: 性能和复杂度平衡。敏感数值每帧可能读取多次（UI 刷新），XOR 是一条指令的事，AES 等加密开销大且代码复杂。XOR + key 轮换已经足够让 GG 的值搜索失效。

**Q: 能不能做服务端校验？**
A: 可以作为 P3 增强。用 serverCloud.money 做货币原子操作，服务端校验余额。但 P1 阶段不需要，先用纯客户端方案快速出原型。

**Q: clientCloud 存的明文会不会被抓包篡改？**
A: clientCloud 的传输链路由引擎加密，客户端无法直接拦截。且云变量是服务端存储，本地没有明文文件可以修改。
