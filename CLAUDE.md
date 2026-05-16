# Project Smith - 古代铁匠模拟器 开发规范

> 本文件是项目级 AI 开发约束，所有代码生成和修改必须遵守以下规则。

---

## 项目概览

- **项目代号**: Project Smith
- **游戏名称**: 古代铁匠模拟器
- **品类**: Hybrid-Casual（步骤解谜 + 轻经营 + 叙事收集）
- **屏幕方向**: 竖屏 9:16
- **设计文档**: `docs/ancient-workshop-mobile-gdd.md`
- **开发计划**: `docs/dev-plan.md`

---

## 1. UI 规范（强制）

### 1.1 禁止 Emoji

**在 UI 中绝对禁止使用任何 Emoji 表情符号。**

- 所有界面文本、按钮标签、提示信息、Toast、对话框一律使用纯中文或英文文字
- 代码中不得出现 Emoji 字符作为 UI 显示内容
- 日志和调试信息中也避免使用 Emoji

```lua
-- 禁止：不得在文本中插入任何 Emoji 字符
-- UI.Button { text = "⚔️ 开始锻造" }   -- 禁止
-- UI.Label { text = "🏆 品质：珍品" }   -- 禁止
-- UI.Label { text = "💰 铜钱: 500" }    -- 禁止

-- 正确：纯文字
UI.Button { text = "开始锻造" }
UI.Label { text = "品质: 珍品" }
UI.Label { text = "铜钱: 500" }
```

### 1.2 图标方案

图标的使用优先级（从高到低）：

1. **图片资源**（首选）：使用 `assets/image/` 目录下的 PNG/JPG 图标文件
2. **NanoVG 矢量绘制**（备选）：当无合适图片时，用 NanoVG 绘制简洁矢量图标
3. **禁止用 Emoji 替代图标**：任何需要图标的场景，都不得用 Emoji 字符充当

```lua
-- 正确：使用图片图标
UI.Image { source = "image/icon_coin.png", width = 24, height = 24 }

-- 正确：NanoVG 矢量图标（无图片时的替代方案）
-- 在 NanoVGRender 事件中绘制自定义图标

-- 禁止：用 Emoji 当图标
-- UI.Label { text = "" }  -- 绝对禁止
```

### 1.3 色彩规范

遵循 GDD 定义的古代工坊色板：

| 用途 | 色值 | 名称 |
|------|------|------|
| 主背景 | `#1A1A2E` | 炭黑 |
| 次背景 | `#16213E` | 深铁蓝 |
| 强调色 | `#E94560` | 炉火红 |
| 金属光泽 | `#D4A574` | 鎏金 |
| 正文文字 | `#E8E0D0` | 暖白 |
| 次要文字 | `#A0937D` | 烟灰 |
| 成功/高品质 | `#4ECDC4` | 青铜绿 |
| 警告 | `#FFD93D` | 淬火黄 |

### 1.4 字体规范

- 正文字体：`Fonts/MiSans-Regular.ttf`
- 标题/强调：`Fonts/MiSans-Bold.ttf`（如有）或加大字号
- NanoVG 字体名：`"sans"`（映射到 MiSans-Regular）

### 1.5 竖屏布局

- 设计基准：9:16 竖屏
- 分辨率模式：模式 B（系统逻辑分辨率），响应式布局
- 安全区域：顶部和底部各留 `5%` 高度作为安全边距
- UI 组件库：`urhox-libs/UI`（Yoga Flexbox 布局）

### 1.6 UI 更新策略（强制）

**优先增量更新，禁止无理由重建整页。**

#### 原则

| 优先级 | 策略 | 适用场景 |
|--------|------|---------|
| 首选 | **增量更新** | 数据变化只改受影响的元素（text/样式/增删子元素） |
| 例外 | **整页重建** | 页面切换、结构性大变（如订单列表全量刷新）、初始化 |

#### 增量更新要求

数据变化时，只修改受影响的 UI 属性，不销毁重建整棵 UI 树：

```lua
-- 正确：增量更新
function updateCoinsDisplay(newCoins)
    coinsLabel.text = "铜钱: " .. newCoins
end

function updateQualityBar(progress)
    qualityBar.width = math.floor(progress * 200) .. "px"
end

-- 错误：数据变了就重建整页
function updateCoinsDisplay(newCoins)
    rebuildHomeScreen()  -- 禁止！只是铜钱变了，不需要重建
end
```

#### 高频更新必须增量

以下场景绝对禁止重建，必须用增量方式更新：

- 倒计时 / 计时器显示（每秒更新）
- 血条 / 进度条（每帧更新）
- 分数 / 连击数（事件触发更新）
- 战斗日志 / 聊天消息（追加子元素，不重建列表）
- 小游戏内实时反馈（评分飘字、命中提示）

```lua
-- 正确：倒计时增量更新
function onTimerTick(remaining)
    timerLabel.text = string.format("%d", remaining)
end

-- 正确：战斗日志追加
function addLogEntry(msg)
    local entry = UI.Label { text = msg, fontSize = 14 }
    logContainer:addChild(entry)
end

-- 错误：每秒重建整个 HUD
function onTimerTick(remaining)
    buildHUD()  -- 禁止！
end
```

#### 重建的合法理由

仅以下情况允许整页重建：

1. **页面切换**：从主界面切到订单板、从锻造切到结算
2. **结构性变化**：订单列表数据源完全替换、章节切换导致 UI 结构不同
3. **初始化**：首次进入页面

#### 重建时必须处理副作用

如果确实需要重建，必须保存并恢复以下状态：

```lua
-- 重建前保存状态
local scrollY = listContainer.scrollY
local selectedIdx = currentSelectedIndex

-- 执行重建
rebuildOrderList(newOrders)

-- 重建后恢复状态
listContainer.scrollY = scrollY
selectOrder(selectedIdx)
```

需要保存/恢复的状态清单：
- 滚动位置（scrollX / scrollY）
- 选中项索引
- 输入框内容
- 展开/折叠状态
- 动画进度（如有）

---

## 2. 美术资源生成规范

### 2.1 图片生成模型

**所有 AI 生图必须指定使用 `gpt` 模型（GPT Image 2）。**

```
调用 generate_image / batch_generate_images / edit_image 时：
  model: "gpt"    -- 必须显式指定
```

### 2.2 图片资源目录

```
assets/
├── image/             # UI 图标、按钮图、装饰元素
│   ├── icon_*.png     # 功能图标（铜钱、声望、材料等）
│   ├── btn_*.png      # 按钮背景/纹理
│   └── deco_*.png     # 装饰元素
├── Textures/          # 场景背景、角色立绘、武器图鉴
│   ├── bg_*.png       # 场景背景
│   ├── char_*.png     # 角色立绘
│   └── weapon_*.png   # 武器成品图
├── Sounds/            # 音效
└── Music/             # BGM
```

### 2.3 图片尺寸参考

| 资源类型 | 推荐尺寸 | 说明 |
|---------|---------|------|
| UI 图标 | 128x128 | 铜钱、声望、材料等小图标 |
| 按钮图 | 256x128 | 可九宫格拉伸 |
| 角色立绘 | 512x1024 | 竖屏半身像 |
| 场景背景 | 1024x1024 | 9:16 裁切使用 |
| 武器图鉴 | 512x512 | 正方形展示 |

---

## 3. 代码规范

### 3.1 架构要求

采用模块化多文件架构，核心模块：

```
scripts/
├── main.lua              # 入口文件
├── Config/               # 数据配置层
├── Core/                 # 核心系统（状态、存档、评分、事件）
├── MiniGame/             # 小游戏子系统（可插拔模块）
├── Story/                # 叙事子系统
├── Screen/               # 界面层（各屏幕/弹窗，避免与 urhox-libs/UI 混淆）
└── Utils/                # 工具函数
```

### 3.2 自审要求

**每次代码编写完成后，必须执行自审流程：**

1. **语法检查**：确认无拼写错误、括号匹配、变量未定义
2. **规范检查**：
   - UI 中无 Emoji 字符
   - 图标使用图片或 NanoVG，未用 Emoji 替代
   - 数组索引从 1 开始
   - eventData 访问使用 `:GetInt()` / `:GetFloat()` 等方法
   - NanoVG 在 `NanoVGRender` 事件中渲染
   - 未使用 `graphics:SetMode()`
3. **逻辑检查**：
   - 数据流向正确（Config → Core → UI）
   - 事件监听/取消配对
   - 资源路径不含 `assets/` 或 `scripts/` 前缀
4. **构建验证**：调用 UrhoX MCP `build` 工具确认编译通过

### 3.3 模块接口约定

小游戏模块统一接口：

```lua
-- MiniGame 基类接口
local MiniGameBase = {}
MiniGameBase.__index = MiniGameBase

function MiniGameBase:init(config)    end  -- 初始化（传入难度/材料等参数）
function MiniGameBase:update(dt)      end  -- 每帧更新
function MiniGameBase:onInput(event)  end  -- 输入处理
function MiniGameBase:getScore()      end  -- 返回评分 (0.0~1.0)
function MiniGameBase:cleanup()       end  -- 清理资源
```

### 3.4 命名规范

| 类型 | 规范 | 示例 |
|------|------|------|
| 文件名 | PascalCase | `OreSelectGame.lua` |
| 模块/类名 | PascalCase | `GameState`, `QualityCalc` |
| 函数名 | camelCase | `calculateQuality()`, `onOrderAccept()` |
| 常量 | UPPER_SNAKE | `MAX_QUALITY_TIER`, `BASE_COIN_REWARD` |
| 局部变量 | camelCase | `currentScore`, `playerCoins` |
| 事件名 | snake_case 字符串 | `"minigame_complete"`, `"order_accepted"` |

---

## 4. 数据规范

### 4.1 配置数据格式

所有游戏配置使用 JSON 格式，存放在 `scripts/Config/data/` 目录：

```
scripts/Config/data/
├── weapon_recipes.json       # 武器配方
├── order_templates.json      # 订单模板
├── facility_upgrades.json    # 设施升级
├── quality_thresholds.json   # 品质阈值
└── chapter_config.json       # 章节配置
```

### 4.2 存档格式

本地存档使用 JSON，文件名 `save.json`：

```json
{
  "version": 1,
  "coins": 500,
  "fame": 120,
  "jade": 0,
  "materials": { "iron": 10, "copper": 5 },
  "facilities": { "furnace": 2, "anvil": 1 },
  "completedOrders": ["ORD-001", "ORD-002"],
  "storyProgress": { "chapter": 1, "nodeId": "CH1-010" },
  "relationships": { "keeper": 15, "shen": -5 },
  "factions": { "court": 20, "rivers": 10 },
  "codex": ["weapon_001"],
  "timestamp": 1700000000
}
```

---

## 5. 开发流程

### 5.1 每次开发的标准流程

```
1. 阅读 dev-plan.md 确认当前里程碑任务
2. 阅读相关引擎文档（principles.md, lua-scripting-guide.md）
3. 基于脚手架编写代码
4. 自审代码（见 3.2）
5. 调用 build 工具构建
6. 修复构建错误
7. Git commit（附带有意义的提交信息）
```

### 5.2 Git 提交规范

```
feat: 新功能
fix: 修复 Bug
refactor: 重构（不改功能）
art: 美术资源相关
data: 配置数据变更
docs: 文档更新
```

---

## 6. 关键约束清单

开发前必须逐项确认：

- [ ] UI 中无 Emoji 字符
- [ ] 图标使用图片资源或 NanoVG 矢量绘制
- [ ] AI 生图使用 gpt 模型
- [ ] 代码写完执行了自审流程
- [ ] 调用了 build 工具验证编译
- [ ] 竖屏 9:16 布局
- [ ] 数组索引从 1 开始
- [ ] 资源路径无 `assets/` `scripts/` 前缀
- [ ] NanoVG 在 NanoVGRender 事件中渲染
- [ ] 分辨率使用 GetWidth/GetHeight/GetDPR
