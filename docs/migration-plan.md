# UI 迁移计划：Screen/*.lua → ui_*.lua 布局

> **方向**：保留游戏逻辑基础设施（ScreenRouter, GameState, StoryManager, EventBus, Timer, Tween, BGM, SFX），将各 Screen 模块的 UI 构建代码替换为 `ui_*.lua` 布局编辑器输出的视觉层，并在其上绑定交互逻辑。

---

## 架构概览

```
┌─────────────────────────────────────────────────────┐
│  main.lua (入口 + 路由注册)                           │
│    ↓                                                │
│  ScreenRouter.GoTo("home") / GoTo("story") / ...    │
│    ↓                                                │
│  Screen/HomeScreen.lua  ← 调用 → ui_HomeScreen_.Build()│
│  Screen/StoryScreen.lua ← 调用 → ui_StoryScreen_.Build()│
│  ...                                                │
└─────────────────────────────────────────────────────┘
```

**核心思路**：

1. **Screen 模块保留**：继续作为 ScreenRouter 的注册单元，保留 `Create(container, params)` + `Update(dt)` + `Destroy()` 接口
2. **UI 构建替换**：Screen 模块内部不再手动构建 UI 树，而是调用对应 `ui_*.lua` 的 `Build()` 函数获取 UI 根节点
3. **逻辑绑定**：通过 `FindById("id")` 获取关键元素引用，绑定点击事件和增量更新

---

## 映射关系

| Screen 模块 | ui_*.lua 布局文件 | 状态 |
|---|---|---|
| `Screen/HomeScreen.lua` | `ui_HomeScreen_工坊主界面.lua` | 待迁移（优先） |
| `Screen/StoryScreen.lua` | `ui_StoryScreen_剧情对话.lua` | 待迁移（优先） |
| `Screen/OrderBoardScreen.lua` | `ui_OrderBoardScreen_订单板.lua` | 待迁移 |
| `Screen/ForgeScreen.lua` | `ui_ForgeScreen_锻造界面.lua` | 待迁移 |
| `Screen/ResultScreen.lua` | `ui_ResultScreen_结算界面.lua` | 待迁移 |
| `Screen/UpgradeScreen.lua` | `ui_UpgradeScreen_设施升级.lua` | 待迁移 |
| `Screen/CodexScreen.lua` | `ui_CodexScreen_名器图鉴.lua` | 待迁移 |
| `Screen/SettingsScreen.lua` | `ui_SettingsScreen_设置.lua` | 待迁移 |

---

## 迁移模板（每个 Screen 的标准做法）

```lua
-- Screen/XxxScreen.lua 迁移后的标准结构
local UI = require("urhox-libs/UI")
local ScreenRouter = require("Utils.ScreenRouter")
local GameState = require("Core.GameState")
local EventBus = require("Core.EventBus")
-- ... 其他依赖

local XxxLayout = require("ui_XxxScreen_中文名")  -- 引入布局模块

local XxxScreen = {}

function XxxScreen.Create(container, params)
    local screen = {}

    -- 1. 调用布局的 Build() 获取 UI 树
    local root = XxxLayout.Build()
    container:AddChild(root)

    -- 2. 通过 FindById 获取需要动态更新的元素引用
    local someLabel = root:FindById("res_v_c")
    local someButton = root:FindById("plate_n")
    -- ...

    -- 3. 绑定数据（初始值）
    someLabel.text = tostring(GameState.GetCoins())

    -- 4. 绑定交互事件
    someButton.onClick = function()
        ScreenRouter.GoTo("targetScreen")
    end

    -- 5. 订阅 EventBus 实现增量更新
    local subId = EventBus.On("coins_changed", function(data)
        someLabel.text = tostring(data.newValue)
    end)

    -- 6. Destroy 清理
    function screen.Destroy()
        EventBus.Off("coins_changed", subId)
    end

    -- 7. Update（如有需要）
    function screen.Update(dt)
        -- 动画/定时器逻辑
    end

    return screen
end

return XxxScreen
```

---

## 关键问题：横屏布局 → 竖屏适配

**现状**：`ui_*.lua` 文件头部标注 `建议 screen_orientation: landscape`，但项目实际是竖屏 9:16。

**解决方案**：

由于布局使用 `position = "absolute"` + 百分比（如 `left = "30.75%"`）+ 固定像素值混合，需要：

1. **HomeScreen / StoryScreen**（已有竖屏修改记录）：检查 git log 中最新版本是否已经适配竖屏；如果是，直接使用
2. **其他 Screen**：需要调整布局元素的位置百分比/像素值以适应竖屏比例
3. **长期方案**：在布局编辑器中重新导出竖屏版本

**短期策略**：先迁移逻辑绑定，布局微调后续单独处理。优先保证功能可用。

---

## 各 Screen 迁移详细规划

### Phase 1: StoryScreen（最核心的交互逻辑）

**保留的游戏逻辑**：
- `StoryManager.GetCurrentNode()` / `CompleteDialogueNode()` / `MakeChoice()`
- `ShowNextLine()` — 逐行推进对话
- `ShowChoices()` — 动态生成选项按钮
- `OnChoiceSelected(idx)` — 选择处理 + 效果应用
- `FinishNode()` / `LoadNextNode()` — 节点推进流程
- `UpdatePortrait(speakerId)` — 角色立绘切换
- `UpdateBackground(bgPath)` — 背景图切换
- `SFXManager` 音效触发（语气音效逻辑）
- 点击任意位置推进 / 选择模式屏蔽点击

**ui_StoryScreen 中的关键 ID**：
| ID | 用途 | 动态操作 |
|---|---|---|
| `ph_1` | 背景图容器 | `backgroundImage = bgPath` |
| `ph_i` → `sr_j` | 角色立绘 | `backgroundImage = portrait` |
| `tx_11` | 角色名 | `text = name` |
| `tx_12` | 对话文本 | `text = dialogue` |
| `plate_13` | 选项按钮1 | 点击 → OnChoiceSelected(1) |
| `plate_16` | 选项按钮2 | 点击 → OnChoiceSelected(2) |
| `plate_19` | 选项按钮3 | 点击 → OnChoiceSelected(3) |
| `plate_1c` | 选项按钮4 | 点击 → OnChoiceSelected(4) |
| `sr_z` | 对话底板 | 点击 → ShowNextLine() |
| `tx_o` | 角色名（大标题） | `text = name` |
| `tx_p` | 角色描述 | `text = desc` |
| `df_q` | 章节信息面板 | 初始化时填充 |
| `tx_w` | 章节标题 | `text = chapterTitle` |
| `tx_y` | 章节摘要 | `text = summary` |

**迁移步骤**：
1. 改写 `Screen/StoryScreen.lua`，`Create()` 中调用 `ui_StoryScreen_剧情对话.Build()`
2. 用 `FindById` 获取上述元素引用
3. 选项按钮初始隐藏（`display = "none"`），有选择时动态显示并设置文本+点击
4. 对话底板区域绑定点击推进
5. 保留全部 SFXManager 逻辑
6. 保留 StoryManager 推进流程

---

### Phase 2: HomeScreen（数据绑定+导航枢纽）

**保留的游戏逻辑**：
- `GameState.GetCoins()` / `GetFame()` / `GetJade()` — 顶部货币栏
- 设施卡片点击 → `ScreenRouter.GoTo("upgrade")`
- 接单按钮 → `ScreenRouter.GoTo("orderBoard")`
- 设置按钮 → `ScreenRouter.GoTo("settings")`
- 图鉴按钮 → `ScreenRouter.GoTo("codex")`
- `EventBus.On("coins_changed")` 等 — 增量更新货币显示
- `StoryManager.HasPendingStory()` — 检查是否有待播剧情

**ui_HomeScreen 中的关键 ID**：
| ID | 用途 | 动态操作 |
|---|---|---|
| `tx_6` | 章节标题 | `text = chapterName` |
| `res_v_c` | 铜钱数值 | `text = coins` |
| `res_v_h` | 玉璧数值 | `text = jade` |
| `res_v_m` | 声望数值 | `text = fame` |
| `plate_n` | "邮"按钮 | 暂不绑定 |
| `plate_q` | "务"按钮 | → orderBoard |
| `plate_t` | "友"按钮 | 暂不绑定 |
| `plate_w` | "设"按钮 | → settings |
| `ph_1a` | 设施卡-熔炉 | → upgrade (furnace) |
| `ph_1f` | 设施卡-锻台 | → upgrade (anvil) |
| 其他设施卡 | 磨石/淬火池/库房/陈列 | → upgrade (对应设施) |

**迁移步骤**：
1. 改写 `Screen/HomeScreen.lua`，调用 `ui_HomeScreen_工坊主界面.Build()`
2. 用 `FindById` 获取货币 Label 引用
3. 初始化时填充 GameState 数据
4. 绑定顶部按钮（务/设）点击→路由
5. 绑定设施卡片点击→升级界面
6. 订阅 EventBus 增量更新货币
7. 检测 StoryManager.HasPendingStory()

---

### Phase 3: 其余 Screen（按使用频率排序）

| 顺序 | Screen | 核心逻辑 |
|---|---|---|
| 3 | OrderBoardScreen | 订单列表渲染、接单按钮、条件检查 |
| 4 | ForgeScreen | 小游戏入口、材料选择、品质计算 |
| 5 | ResultScreen | 评分展示、奖励发放、动画 |
| 6 | UpgradeScreen | 设施列表、升级消耗、确认弹窗 |
| 7 | CodexScreen | 已解锁武器列表、图鉴详情 |
| 8 | SettingsScreen | 音量滑块、存档管理 |

---

## 保持不变的模块（不需要迁移）

| 模块 | 路径 | 说明 |
|---|---|---|
| main.lua | `scripts/main.lua` | 入口 + 路由注册（仅需调整 require 路径） |
| ScreenRouter | `scripts/Utils/ScreenRouter.lua` | 路由框架，不变 |
| GameState | `scripts/Core/GameState.lua` | 数据中枢，不变 |
| EventBus | `scripts/Core/EventBus.lua` | 事件总线，不变 |
| StoryManager | `scripts/Story/StoryManager.lua` | 对话引擎，不变 |
| Timer | `scripts/Utils/Timer.lua` | 定时器，不变 |
| Tween | `scripts/Utils/Tween.lua` | 缓动动画，不变 |
| BGMManager | `scripts/Utils/BGMManager.lua` | BGM，不变 |
| SFXManager | `scripts/Utils/SFXManager.lua` | SFX，不变 |
| Config/* | `scripts/Config/` | 配置数据，不变 |

---

## 注意事项

### 1. FindById 层级问题
`FindById` 只搜索**直接子树**（从调用节点向下递归）。如果布局嵌套很深，需从 root 开始搜索。

### 2. 选项按钮动态化
StoryScreen 的选项数量不固定（1-4 个），但 ui 布局中固定了 4 个 `plate_13/16/19/1c`。迁移时：
- 初始化全部隐藏（`display = "none"`）
- 有选择时按实际数量显示对应按钮并设置文本
- 文本更新用 `FindById("tx_15").text = choice.text`

### 3. 横屏坐标 → 竖屏适配
部分 `ui_*.lua` 的像素坐标（如 `left = 1492.71`）明显是基于横屏宽度设计的。对于竖屏：
- 使用百分比定位的元素基本自动适配
- 使用绝对像素定位的元素可能溢出屏幕
- **StoryScreen 和 HomeScreen 在 git 历史中有竖屏版本，需检查并使用**

### 4. 增量更新原则不变
迁移后仍然遵循增量更新策略：
- 数据变化 → 只改受影响的 Label.text / Panel.opacity
- 禁止在数据变化时重建整个 `Build()` 树

---

## 执行顺序

```
1. [ ] 检查 ui_StoryScreen / ui_HomeScreen 是否已有竖屏版本
2. [ ] 迁移 StoryScreen（逻辑最复杂，先搞定）
3. [ ] 迁移 HomeScreen（数据绑定+导航枢纽）
4. [ ] Build + 验证这两个核心屏幕可运行
5. [ ] 迁移 OrderBoardScreen
6. [ ] 迁移 ForgeScreen + ResultScreen
7. [ ] 迁移 UpgradeScreen + CodexScreen + SettingsScreen
8. [ ] 全量 Build + 玩法测试
```

---

*创建时间: 2026-06-13*
*最后更新: 2026-06-13*
