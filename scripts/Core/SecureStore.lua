-- ============================================================================
-- SecureStore - 内存混淆模块
-- Project Smith / P1-A4
--
-- XOR + key 轮换方案，防止 GameGuardian 精确值搜索和变化值搜索。
-- 原理：内存中存 (encoded, key)，encoded = value ~ key，
--       每次写入生成新 key，GG 搜不到稳定的明文值。
--
-- 使用约束（见 CLAUDE.md §4.3）：
--   - 仅通过 GameState 接口调用，外部不直接使用
--   - 读取的明文只在栈上临时使用，不缓存到模块级变量
-- ============================================================================

local SecureStore = {}
SecureStore.__index = SecureStore

--- key 范围（31 位正整数，避免溢出）
local KEY_RANGE = 0x7FFFFFFF

--- 创建安全存储实例
---@return table SecureStore 实例
function SecureStore.New()
    local self = setmetatable({}, SecureStore)
    ---@type table<string, { encoded: integer, key: integer }>
    self.data_ = {}
    return self
end

--- 写入一个数值（立即编码，key 轮换）
---@param name string 字段名
---@param value number 明文数值
function SecureStore:Set(name, value)
    local intVal = math.floor(value)
    local key = math.random(1, KEY_RANGE)
    self.data_[name] = {
        encoded = intVal ~ key,
        key = key,
    }
end

--- 读取一个数值（解码到栈上）
---@param name string
---@return number 明文数值
function SecureStore:Get(name)
    local entry = self.data_[name]
    if not entry then return 0 end
    return entry.encoded ~ entry.key
end

--- 增减数值（解码 -> 计算 -> 重新编码，key 自动轮换）
---@param name string
---@param delta number
---@return number 操作后的新值
function SecureStore:Add(name, delta)
    local cur = self:Get(name)
    local newVal = cur + math.floor(delta)
    self:Set(name, newVal)
    return newVal
end

--- 检查余额是否足够
---@param name string
---@param cost number
---@return boolean
function SecureStore:CanAfford(name, cost)
    return self:Get(name) >= math.floor(cost)
end

--- 检查字段是否存在
---@param name string
---@return boolean
function SecureStore:Has(name)
    return self.data_[name] ~= nil
end

--- 批量导出明文（Save 时使用）
---@return table<string, number>
function SecureStore:ExportAll()
    local plain = {}
    for name, _ in pairs(self.data_) do
        plain[name] = self:Get(name)
    end
    return plain
end

--- 批量导入明文（Load 时使用）
---@param plain table<string, number>
function SecureStore:ImportAll(plain)
    for name, value in pairs(plain) do
        self:Set(name, value)
    end
end

--- 清空所有数据
function SecureStore:Clear()
    self.data_ = {}
end

return SecureStore
