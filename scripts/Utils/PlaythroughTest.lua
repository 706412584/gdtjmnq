-- ============================================================================
-- PlaythroughTest - 自动化 Playthrough 测试工具
-- Project Smith / 开发调试用
--
-- 用途：
--   模拟玩家完整流程，验证 StoryManager / GameState / ScreenRouter 的协作正确性。
--   包括：对话推进、分支选择、triggerOrder 跳转、条件检测、数值变化。
--
-- 使用方式：
--   在 main.lua 的 Start() 中临时添加:
--     require("Utils.PlaythroughTest").Run()
--   或在运行时通过控制台调用。
--
-- 输出：
--   全部结果打印到控制台（print），通过/失败一目了然。
-- ============================================================================

local StoryManager = require("Story.StoryManager")
local GameState    = require("Core.GameState")
local EventBus     = require("Core.EventBus")

local PlaythroughTest = {}

-- 测试统计
local passed_ = 0
local failed_ = 0
local tests_ = {}

-- ============================================================================
-- 断言工具
-- ============================================================================

local function Assert(condition, msg)
    if condition then
        passed_ = passed_ + 1
        tests_[#tests_ + 1] = { pass = true, msg = msg }
    else
        failed_ = failed_ + 1
        tests_[#tests_ + 1] = { pass = false, msg = msg }
        print("[TEST FAIL] " .. msg)
    end
end

local function AssertEqual(actual, expected, msg)
    if actual == expected then
        passed_ = passed_ + 1
        tests_[#tests_ + 1] = { pass = true, msg = msg }
    else
        failed_ = failed_ + 1
        tests_[#tests_ + 1] = { pass = false, msg = msg .. " (expected=" .. tostring(expected) .. ", got=" .. tostring(actual) .. ")" }
        print("[TEST FAIL] " .. msg .. " | expected=" .. tostring(expected) .. " got=" .. tostring(actual))
    end
end

local function AssertNotNil(value, msg)
    Assert(value ~= nil, msg)
end

-- ============================================================================
-- 测试用例
-- ============================================================================

--- 测试 1: GameState 默认存档初始化
local function TestDefaultSave()
    print("\n--- Test: Default Save Initialization ---")

    AssertEqual(GameState.GetCoins(), 0, "初始铜钱应为 0")
    AssertEqual(GameState.GetFame(), 0, "初始声望应为 0")
    AssertEqual(GameState.GetJade(), 0, "初始玉石应为 0")
    AssertEqual(GameState.GetMaterial("ore"), 5, "初始矿石应为 5")
    AssertEqual(GameState.GetMaterial("charcoal"), 3, "初始木炭应为 3")
    AssertEqual(GameState.GetFacilityLevel("furnace"), 1, "初始熔炉等级应为 1")
    AssertEqual(GameState.GetFacilityLevel("anvil"), 1, "初始铁砧等级应为 1")

    local progress = GameState.GetStoryProgress()
    AssertEqual(progress.chapter, 1, "初始章节应为 1")
    AssertEqual(progress.nodeId, "CH1-001", "初始节点应为 CH1-001")
end

--- 测试 2: StoryManager 初始化和节点加载
local function TestStoryManagerInit()
    print("\n--- Test: StoryManager Initialization ---")

    local node = StoryManager.GetCurrentNode()
    AssertNotNil(node, "当前节点不应为 nil")
    if node then
        AssertEqual(node.id, "CH1-001", "当前节点 ID 应为 CH1-001")
        AssertEqual(node.type, "dialogue", "CH1-001 类型应为 dialogue")
        Assert(node.lines ~= nil and #node.lines > 0, "CH1-001 应有对话行")
        AssertEqual(#node.lines, 6, "CH1-001 应有 6 行对话")
    end

    Assert(StoryManager.HasPendingStory(), "开局应有待展示剧情")
end

--- 测试 3: 对话节点推进
local function TestDialogueAdvance()
    print("\n--- Test: Dialogue Node Advance ---")

    -- 完成 CH1-001 节点
    StoryManager.CompleteDialogueNode()
    local chapter, nodeId = StoryManager.GetProgress()
    AssertEqual(nodeId, "CH1-002", "完成 CH1-001 后应推进到 CH1-002")

    local node = StoryManager.GetCurrentNode()
    AssertNotNil(node, "CH1-002 节点不应为 nil")
    if node then
        AssertEqual(node.title, "第一笔活计", "CH1-002 标题应为 '第一笔活计'")
    end

    -- 完成 CH1-002
    StoryManager.CompleteDialogueNode()
    chapter, nodeId = StoryManager.GetProgress()
    AssertEqual(nodeId, "CH1-003", "完成 CH1-002 后应推进到 CH1-003")
end

--- 测试 4: 选择节点（好感度变化）
local function TestChoiceNode()
    print("\n--- Test: Choice Node (CH1-003) ---")

    local node = StoryManager.GetCurrentNode()
    AssertNotNil(node, "CH1-003 节点不应为 nil")
    if node then
        AssertEqual(node.type, "choice", "CH1-003 类型应为 choice")
        Assert(node.choices ~= nil and #node.choices == 3, "CH1-003 应有 3 个选择")
    end

    -- 选择第 1 项：先修炉子 → keeper +6, craftsman +4
    local keeperBefore = GameState.GetRelationship("keeper")
    local craftsmanBefore = GameState.GetFaction("craftsman")

    StoryManager.MakeChoice(1)

    local keeperAfter = GameState.GetRelationship("keeper")
    local craftsmanAfter = GameState.GetFaction("craftsman")

    AssertEqual(keeperAfter - keeperBefore, 6, "选择1: keeper 好感度应 +6")
    AssertEqual(craftsmanAfter - craftsmanBefore, 4, "选择1: craftsman 阵营应 +4")

    local chapter, nodeId = StoryManager.GetProgress()
    AssertEqual(nodeId, "CH1-004", "选择后应推进到 CH1-004")
end

--- 测试 5: triggerOrder 节点
local function TestTriggerOrder()
    print("\n--- Test: TriggerOrder Node (CH1-004) ---")

    local node = StoryManager.GetCurrentNode()
    AssertNotNil(node, "CH1-004 节点不应为 nil")
    if node then
        AssertEqual(node.triggerOrder, true, "CH1-004 应有 triggerOrder=true")
    end

    -- 完成该节点后，StoryScreen 应跳转到 orderBoard
    -- 这里只验证 StoryManager 推进逻辑
    StoryManager.CompleteDialogueNode()
    local chapter, nodeId = StoryManager.GetProgress()
    AssertEqual(nodeId, "CH1-005", "完成 CH1-004 后应推进到 CH1-005")
end

--- 测试 6: 条件检测（ordersCompleted）
local function TestConditionCheck()
    print("\n--- Test: Condition Check (CH1-005) ---")

    local node = StoryManager.GetCurrentNode()
    AssertNotNil(node, "CH1-005 节点不应为 nil")
    if node then
        AssertNotNil(node.condition, "CH1-005 应有 condition")
        AssertEqual(node.condition.type, "ordersCompleted", "条件类型应为 ordersCompleted")
        AssertEqual(node.condition.min, 1, "条件最小值应为 1")
    end

    -- 未完成任何订单时，HasPendingStory 应返回 false（条件不满足）
    local hasPending = StoryManager.HasPendingStory()
    Assert(not hasPending, "无订单完成时，CH1-005 不应待展示")

    -- 模拟完成一个订单
    GameState.CompleteOrder("ORD_TEST_001")
    hasPending = StoryManager.HasPendingStory()
    Assert(hasPending, "完成订单后，CH1-005 应待展示")
end

--- 测试 7: 完整对话推进到选择分支（CH1-006 → CH1-007）
local function TestSecondChoiceNode()
    print("\n--- Test: Second Choice Branch (CH1-006 -> CH1-007) ---")

    -- 推进 CH1-005
    StoryManager.CompleteDialogueNode()
    local chapter, nodeId = StoryManager.GetProgress()
    AssertEqual(nodeId, "CH1-006", "完成 CH1-005 后应推进到 CH1-006")

    -- 推进 CH1-006
    StoryManager.CompleteDialogueNode()
    chapter, nodeId = StoryManager.GetProgress()
    AssertEqual(nodeId, "CH1-007", "完成 CH1-006 后应推进到 CH1-007")

    -- CH1-007 是选择节点
    local node = StoryManager.GetCurrentNode()
    if node then
        AssertEqual(node.type, "choice", "CH1-007 类型应为 choice")
        Assert(node.choices ~= nil and #node.choices == 3, "CH1-007 应有 3 个选择")
    end

    -- 选择第 2 项："忍住好奇" → keeper +6, craftsman +3
    local keeperBefore = GameState.GetRelationship("keeper")
    StoryManager.MakeChoice(2)
    local keeperAfter = GameState.GetRelationship("keeper")
    AssertEqual(keeperAfter - keeperBefore, 6, "选择2: keeper 好感度应 +6")

    chapter, nodeId = StoryManager.GetProgress()
    AssertEqual(nodeId, "CH1-008B", "选择2 应推进到 CH1-008B")
end

--- 测试 8: EventBus 事件触发验证
local function TestEventBusIntegration()
    print("\n--- Test: EventBus Integration ---")

    local eventFired = false
    local unsub = EventBus.On("coins_changed", function(data)
        eventFired = true
    end)

    GameState.AddCoins(100)
    Assert(eventFired, "AddCoins 应触发 coins_changed 事件")
    AssertEqual(GameState.GetCoins(), 100, "加 100 铜钱后应为 100")

    -- 清理
    unsub()
    -- 恢复（防止影响后续测试）
    GameState.AddCoins(-100)
end

--- 测试 9: 角色配置完整性
local function TestCharacterConfigs()
    print("\n--- Test: Character Configs ---")

    local configs = {
        { id = "keeper",  expectedName = "老掌柜" },
        { id = "shen",    expectedName = "沈绫" },
        { id = "hunter",  expectedName = "猎户" },
        { id = "narrator", expectedName = "" },
        { id = "player",  expectedName = "主角" },
    }

    for i = 1, #configs do
        local cfg = StoryManager.GetCharacterConfig(configs[i].id)
        AssertNotNil(cfg, configs[i].id .. " 角色配置不应为 nil")
        AssertEqual(cfg.name, configs[i].expectedName, configs[i].id .. " 名字应为 '" .. configs[i].expectedName .. "'")
    end
end

--- 测试 10: SecureStore 混淆验证（add/get 一致性）
local function TestSecureStoreConsistency()
    print("\n--- Test: SecureStore Consistency ---")

    -- 多次加减验证
    local initialFame = GameState.GetFame()
    GameState.AddFame(50)
    GameState.AddFame(30)
    AssertEqual(GameState.GetFame(), initialFame + 80, "连续 AddFame 50+30 后应正确累加")
    GameState.AddFame(-80) -- 恢复

    -- 材料操作
    local initialOre = GameState.GetMaterial("ore")
    GameState.AddMaterial("ore", 10)
    AssertEqual(GameState.GetMaterial("ore"), initialOre + 10, "AddMaterial ore +10 应正确")
    GameState.AddMaterial("ore", -10) -- 恢复
end

-- ============================================================================
-- 运行入口
-- ============================================================================

--- 运行所有测试
function PlaythroughTest.Run()
    print("========================================")
    print("  PlaythroughTest - 开始")
    print("========================================")

    passed_ = 0
    failed_ = 0
    tests_ = {}

    -- 重置到初始状态
    GameState.Reset()
    StoryManager.Init()

    -- 按顺序执行测试
    TestDefaultSave()
    TestStoryManagerInit()
    TestDialogueAdvance()
    TestChoiceNode()
    TestTriggerOrder()
    TestConditionCheck()
    TestSecondChoiceNode()
    TestEventBusIntegration()
    TestCharacterConfigs()
    TestSecureStoreConsistency()

    -- 汇总结果
    print("\n========================================")
    print(string.format("  结果: %d 通过, %d 失败 (共 %d)", passed_, failed_, passed_ + failed_))
    print("========================================")

    if failed_ > 0 then
        print("\n失败项目:")
        for i = 1, #tests_ do
            if not tests_[i].pass then
                print("  [X] " .. tests_[i].msg)
            end
        end
    end

    print("\n[PlaythroughTest] Done.\n")
    return failed_ == 0
end

return PlaythroughTest
