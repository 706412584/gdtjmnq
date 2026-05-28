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

### 2.2 美术风格（强制）

**所有 AI 生成的图片资源必须偏向手游风格，禁止写实/照片风格。**

| 资源类型 | 风格要求 | prompt 关键词参考 |
|---------|---------|------------------|
| 角色立绘 | 手绘半写实、国风水墨手游 | `手游立绘风格`、`国风手游角色`、`半写实手绘` |
| 武器图鉴 | 手绘道具图鉴、清晰轮廓 | `手游道具图鉴`、`游戏装备icon` |
| 场景背景 | 手绘场景、色彩鲜明 | `手游场景概念图`、`国风手绘背景` |
| UI 图标 | 扁平/微拟物手游图标 | `手游UI图标`、`游戏图标设计` |
| **UI 组件** | **天刀/剑三武侠水墨风** | 见 2.6 UI 美术风格 |

**prompt 编写规则**：
- 必须包含风格限定词（如 `手游风格`、`游戏美术`、`手绘`、`国风` 等）
- 禁止出现 `照片`、`摄影`、`写实`、`realistic photo` 等写实关键词
- 同一批次资源保持风格统一（同类资源使用相近的风格描述词）

```lua
-- 正确：带手游风格限定
-- prompt = "古代中国铁匠，手游立绘风格，国风水墨，半身像，深色背景"

-- 错误：无风格限定或偏写实
-- prompt = "古代中国铁匠，写实风格，照片质感"
-- prompt = "古代中国铁匠"  -- 缺少风格限定，结果不可控
```

### 2.3 图片资源目录

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

### 2.4 图片尺寸参考

| 资源类型 | 推荐尺寸 | 说明 |
|---------|---------|------|
| UI 图标 | 128x128 | 铜钱、声望、材料等小图标 |
| 按钮图 | 256x128 | 可九宫格拉伸 |
| 角色立绘 | 512x1024 | 竖屏半身像 |
| 场景背景 | 1024x1024 | 9:16 裁切使用 |
| 武器图鉴 | 512x512 | 正方形展示 |

### 2.5 资源生成失败处理（强制）

**当 AI 资源生成（图片/音乐/音效/3D模型）调用返回失败或超时时，必须先检查本地文件是否已生成成功，禁止盲目重试。**

MCP 工具调用可能因网络超时返回错误，但后台任务实际已完成并写入了文件。直接重试会导致重复生成、浪费配额。

```
资源生成调用失败/超时
  ↓
先检查本地目标路径是否已有文件（ls / Glob）
  ↓
├─ 文件已存在且大小合理 → 直接使用，跳过重试
└─ 文件不存在 → 重试生成（单张逐个重试，避免批量再次超时）
```

```bash
# 示例：批量生图超时后检查
ls -la /workspace/assets/image/char_*.png
# 如果目标文件已存在且 > 10KB，说明后台生成成功，无需重试
```

**规则要点**：
- 超时 ≠ 失败，先验证本地文件再决定下一步
- 批量生成超时时，改为逐张重试仍缺失的资源
- 对于 3D 模型等异步任务，用 `query_3d_model_task` 轮询确认状态

### 2.6 UI 美术风格（强制）

**UI 组件美术风格：极简水墨风**

参考图合集：
- 按钮：`assets/image/ui_btn_ink_minimal_20260518071457.png`
- 弹窗面板：`assets/image/ui_panel_ink_minimal_20260518071446.png`
- 辅助组件：`assets/image/ui_misc_ink_minimal_20260518071427.png`
- 道具格：`assets/image/ui_slots_ink_minimal_20260518071427.png`

**风格特征**：
- 极简水墨，边框极细（淡墨细线描边，无厚重金属边框）
- 无铆钉、无云纹、无回字纹、无角饰
- 面板背景为深色水墨晕染，竹叶远山若隐若现
- 按钮表面宣纸水墨渗透质感，边角微圆
- 分隔线为水墨山水飞鸟剪影，空灵留白
- 卷轴极简轮廓线 + 宣纸质感，无厚重卷轴头

**UI 组件 prompt 关键词模板**：
```
中国武侠手游UI，极简水墨风格，极细淡墨描边，
无金属边框无铆钉无云纹，宣纸水墨晕染质感，
竹叶远山若隐若现，留白简洁，中国画意境，
游戏UI组件，黑色背景，无文字，高清
```

**色彩基调**（与 1.3 色彩规范配合）：
| 用途 | 描述 |
|------|------|
| 按钮底色 | 深红/藏青/墨绿/鎏金/烟灰/紫罗兰（水墨晕染质感） |
| 边框 | 淡墨色极细线描边（无金属感） |
| 面板底 | 深色水墨晕染（竹叶/远山若隐若现） |
| 对话框 | 极简卷轴轮廓 + 宣纸质感 |
| 分隔线 | 水墨山水飞鸟剪影，空灵留白 |
| 进度条 | 极细渐变条，红/蓝/金填充，无边框轨道 |

**生成规则**：
- 所有 UI 组件合集图必须使用 `ui_btn_ink_minimal_*.png` 作为 `reference_images` 风格参考
- 合集图黑色纯背景（便于切片去背景）
- 进度条只生成空轨道（无填充值），填充部分单独生成
- 按钮必须覆盖 6 种颜色变体（红/蓝/绿/金/灰/紫）

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

> **详细架构设计**：`docs/storage-architecture.md`

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

### 4.2 存储架构（强制）

**单机 + clientCloud 云存档 + 内存混淆**，不做多人游戏。

| 层面 | 方案 |
|------|------|
| 数据中枢 | `GameState.lua` — 唯一读写入口 |
| 内存保护 | `SecureStore.lua` — XOR + key 轮换，防 GG 搜值 |
| 云存档 | `clientCloud:Set/Get` — 自动存档（5 秒间隔） |
| 存档格式 | 云端明文 JSON，key = `"smith_save"` |

### 4.3 内存混淆规则（强制）

**所有 number 类型的游戏经济/进度数值必须走 SecureStore 混淆存储。**

混淆字段：`coins`, `fame`, `jade`, `materials.*`, `facilities.*`, `relationships.*`, `factions.*`, `stats.*`

非混淆字段：`version`, `name`, `completedOrders`, `codex`, `storyProgress`, `timestamp`

```lua
-- ✅ 正确：通过 GameState 统一接口
GameState.AddCoins(50)
local coins = GameState.GetCoins()  -- 栈上临时值，用完即弃
coinsLabel.text = "铜钱: " .. coins

-- ❌ 错误：缓存明文到模块级变量
local cachedCoins = GameState.GetCoins()  -- 长期驻留，GG 可搜！

-- ❌ 错误：绕过 GameState 直接操作
playerData.coins = playerData.coins + 100  -- 绕过混淆！

-- ❌ 错误：在全局 table 中存明文副本
G_DATA = { coins = GameState.GetCoins() }  -- 副本可被 GG 搜到！
```

**黄金法则**：明文不驻留内存。读 = 解码到栈上临时使用；写 = 计算后立即编码回去。

### 4.4 存档数据结构（云端明文 JSON）

```json
{
  "version": 1,
  "coins": 500,
  "fame": 120,
  "jade": 0,
  "materials": { "ore": 10, "charcoal": 5 },
  "facilities": { "furnace": 2, "anvil": 1 },
  "completedOrders": ["ORD_T1_001", "ORD_T1_002"],
  "codex": ["WEAPON_001"],
  "storyProgress": { "chapter": 1, "nodeId": "CH1-010" },
  "relationships": { "keeper": 15, "shen": -5 },
  "factions": { "court": 20, "guild": 10 },
  "stats": { "totalForged": 12, "perfectCount": 3, "bestQualityTier": 3 },
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

### 5.3 Git 推送方法（强制）

**沙箱环境无原生 SSH 客户端，必须通过 paramiko SSH wrapper 推送代码。**

**远程仓库**：`git@github.com:706412584/gdtjmnq.git`（别名 `origin`）

**原理**：脚本用 paramiko 库，先向 HTTP 代理（`127.0.0.1:1080`）发 CONNECT 请求建立到 `ssh.github.com:443` 的隧道，再在隧道上完成 SSH 认证和 git 数据传输。

| 配置项 | 值 |
|--------|------|
| HTTP 代理 | `127.0.0.1:1080` |
| SSH 目标 | `ssh.github.com:443` |
| 私钥路径 | `/workspace/.ssh/id_ed25519` |
| SSH Wrapper | `/home/Maker/ssh_wrapper.py` |
| 推送快捷脚本 | `/home/Maker/git_push.sh` |

**推送命令**：

```bash
# 方式 1：快捷脚本（推荐）
/home/Maker/git_push.sh                    # 推送当前分支
/home/Maker/git_push.sh master             # 推送指定分支
/home/Maker/git_push.sh master --force     # 强制推送

# 方式 2：手动指定 GIT_SSH_COMMAND
cd /workspace
GIT_SSH_COMMAND="/usr/bin/python3 /home/Maker/ssh_wrapper.py" git push origin master
```

**注意事项**：
- 推送前必须先 `git add` + `git commit`
- `.gitignore` 已配置排除引擎敏感目录（engine-docs/、examples/、urhox-libs/ 等）和 `.ssh/` 密钥
- 只有 `scripts/`、`assets/`、`docs/` 等用户代码会被推送
- 如果推送认证失败，检查 `/workspace/.ssh/id_ed25519` 私钥是否存在且对应公钥已添加到 GitHub

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
- [ ] 敏感数值（货币/材料/等级/声望等）走 SecureStore 混淆，不存明文
- [ ] 所有数据读写通过 GameState 接口，无模块自建数据副本
- [ ] 无模块级/全局变量缓存明文数值（UI 显示用栈上临时值）
