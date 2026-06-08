---@diagnostic disable: assign-type-mismatch, return-type-mismatch
-- ============================================================================
-- DataLoader - JSON 配置文件加载器
-- Project Smith / P1-A3
--
-- 加载 Config/data/ 目录下的 JSON 配置文件，带缓存。
-- ============================================================================

local DataLoader = {}

---@type table<string, table>
local cache_ = {}

--- 读取资源文件的全部文本内容
---@param path string 资源路径（不含 scripts/ 前缀）
---@return string|nil
local function ReadFileContent(path)
    local file = cache:GetFile(path)
    if not file then
        return nil
    end
    local lines = {}
    while not file.eof do
        lines[#lines + 1] = file:ReadLine()
    end
    return table.concat(lines, "\n")
end

--- 加载并解析 JSON 配置文件
---@param filename string 文件路径（如 "Config/data/weapon_recipes.json"）
---@return table|nil data 解析后的 table，失败返回 nil
function DataLoader.Load(filename)
    -- 命中缓存
    if cache_[filename] then
        return cache_[filename]
    end

    local content = ReadFileContent(filename)
    if not content then
        print("[DataLoader] File not found: " .. filename)
        return nil
    end

    local ok, data = pcall(cjson.decode, content)
    if not ok then
        print("[DataLoader] JSON parse error in " .. filename .. ": " .. tostring(data))
        return nil
    end

    cache_[filename] = data
    print("[DataLoader] Loaded: " .. filename)
    return data
end

--- 批量加载多个配置文件
---@param filenames string[] 文件路径数组
---@return table<string, table> results { filename = data }
function DataLoader.LoadAll(filenames)
    local results = {}
    for i = 1, #filenames do
        results[filenames[i]] = DataLoader.Load(filenames[i])
    end
    return results
end

--- 清空缓存（热重载用）
function DataLoader.ClearCache()
    cache_ = {}
end

return DataLoader
