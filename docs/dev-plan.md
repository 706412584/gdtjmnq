# 古代铁匠模拟器 - 开发计划

> **项目代号**: Project Smith
> **技术平台**: UrhoX (Lua 5.4)
> **屏幕方向**: 竖屏 9:16
> **参考文档**: `docs/ancient-workshop-mobile-gdd.md`
> **开发规范**: `/workspace/CLAUDE.md`

---

## 一、总体策略

### 1.1 开发原则

- **分期交付**：将 GDD 的完整内容拆为 3 个里程碑，每期产出可运行版本
- **核心优先**：先跑通「接单 - 小游戏 - 评分 - 奖励」主循环，再叠加外围系统
- **数据驱动**：配方/订单/对话/品质全部走 JSON 配置，不硬编码
- **模块化**：小游戏可插拔，新增玩法只需增加一个模块文件

### 1.2 技术选型

| 层面 | 方案 | 说明 |
|------|------|------|
| UI 框架 | urhox-libs/UI (Yoga Flexbox) | 竖屏全 UI 游戏最优解 |
| 自定义图形 | NanoVG | 小游戏内温度条/路径/火花等 |
| 分辨率 | 模式 B（系统逻辑分辨率） | 响应式布局，自动适配 |
| 数据格式 | JSON (cjson) | 配置 + 存档 |
| 存档 | File API + JSON | 本地 save.json |
| 脚手架 | scaffold-2d.lua | 竖屏 2D UI 游戏 |
| 美术生成 | generate_image (model: gpt) | 立绘/背景/图标 |
| 音效生成 | text_to_sound_effect | 锤打/火焰/淬火等 |

---

## 二、项目架构

### 2.1 目录结构

```
scripts/
├── main.lua                    # 入口：初始化 + 场景路由
│
├── Config/                     # 数据配置层
│   ├── DataLoader.lua          # JSON 配置加载器
│   ├── WeaponRecipes.lua       # 武器配方数据接口
│   ├── OrderConfig.lua         # 订单配置数据接口
│   ├── FacilityConfig.lua      # 设施升级数据接口
│   ├── QualityThreshold.lua    # 品质阈值数据接口
│   └── data/                   # JSON 数据文件
│       ├── weapon_recipes.json
│       ├── order_templates.json
│       ├── facility_upgrades.json
│       ├── quality_thresholds.json
│       └── chapter_config.json
│
├── Core/                       # 核心系统
│   ├── GameState.lua           # 全局状态管理（货币/材料/设施/进度）
│   ├── SaveManager.lua         # 本地存档读写
│   ├── QualityCalc.lua         # 品质评分公式引擎
│   ├── OrderManager.lua        # 订单生成/完成逻辑
│   └── EventBus.lua            # 发布-订阅事件总线
│
├── MiniGame/                   # 小游戏子系统
│   ├── MiniGameBase.lua        # 基类（统一生命周期接口）
│   ├── MiniGameRunner.lua      # 小游戏调度器（按订单步骤依次运行）
│   ├── OreSelectGame.lua       # 选矿去杂（点击选择 + 清除）
│   ├── SmeltingGame.lua        # 控火熔炼（温度条停止点）
│   ├── ForgingGame.lua         # 锻打塑形（节奏点击 + 拖拽）
│   ├── QuenchingGame.lua       # 淬火时机（长按释放）
│   ├── PolishingGame.lua       # 研磨开刃（路径拖拽）
│   └── AssemblyGame.lua        # 组装装饰（顺序放置）
│
├── Story/                      # 叙事子系统（P2 实现）
│   ├── StoryManager.lua        # 对话流程驱动引擎
│   ├── StoryData.lua           # story_node / story_choice 数据
│   ├── RelationshipTracker.lua # 角色好感度 + 阵营变量
│   └── EndingEvaluator.lua     # 结局条件判定
│
├── Screen/                     # 界面层
│   ├── HomeScreen.lua          # 工坊主界面
│   ├── OrderBoardScreen.lua    # 订单板
│   ├── ForgeScreen.lua         # 锻造界面（承载小游戏）
│   ├── ResultScreen.lua        # 结算界面
│   ├── CodexScreen.lua         # 名器图鉴（P2 实现）
│   ├── StoryScreen.lua         # 对话界面（P2 实现）
│   ├── UpgradeScreen.lua       # 设施升级界面
│   └── SettingsScreen.lua      # 设置界面
│
└── Utils/                      # 工具
    ├── Tween.lua               # 补间动画
    ├── Timer.lua               # 定时器
    └── ScreenRouter.lua        # 界面切换路由
```

### 2.2 核心数据流

```
                  ┌──────────────┐
                  │  OrderConfig │  (JSON)
                  └──────┬───────┘
                         v
┌─────────┐     ┌────────────────┐     ┌──────────────────┐
│  Home   │────>│  OrderBoard    │────>│  ForgeScreen     │
│  Screen │     │  (选择订单)     │     │  (小游戏调度)     │
└─────────┘     └────────────────┘     └────────┬─────────┘
     ^                                          │
     │                                          v
     │                                 ┌────────────────┐
     │                                 │ MiniGameRunner  │
     │                                 │ (依次运行N个    │
     │                                 │  小游戏模块)    │
     │                                 └────────┬───────┘
     │                                          │ 各步骤分数
     │                                          v
     │                                 ┌────────────────┐
     │                                 │  QualityCalc   │
     │                                 │  (品质评分)     │
     │                                 └────────┬───────┘
     │                                          │
     │                                          v
     │          ┌──────────────┐       ┌────────────────┐
     │          │  GameState   │<──────│  ResultScreen  │
     │          │  (更新货币    │       │  (展示品质+奖励)│
     │          │   材料/声望)  │       └────────────────┘
     │          └──────┬───────┘
     │                 │
     └─────────────────┘
```

### 2.3 模块间通信

```lua
-- EventBus 事件定义
"order_accepted"      -- { orderId, weaponLine, steps }
"minigame_start"      -- { stepType, difficulty }
"minigame_complete"   -- { stepType, score, rating }
"all_steps_complete"  -- { scores[], orderId }
"quality_calculated"  -- { finalScore, qualityTier, rewards }
"reward_collected"    -- { coins, fame, materials, codexId }
"facility_upgraded"   -- { facilityId, newLevel }
"story_triggered"     -- { nodeId, chapter }
"screen_change"       -- { from, to }
```

---

## 三、里程碑计划

### P1：核心可玩原型（MVP）

**目标**：跑通「接单 - 锻造 - 评分 - 奖励 - 升级」完整循环。

#### P1-A：基础框架搭建

| 编号 | 任务 | 输出文件 | 依赖 |
|------|------|---------|------|
| P1-A1 | 项目入口 + 场景路由 | `main.lua`, `Utils/ScreenRouter.lua` | - |
| P1-A2 | 事件总线 | `Core/EventBus.lua` | - |
| P1-A3 | JSON 配置加载器 | `Config/DataLoader.lua` | - |
| P1-A4 | 全局状态管理 | `Core/GameState.lua` | P1-A2 |
| P1-A5 | 本地存档 | `Core/SaveManager.lua` | P1-A4 |
| P1-A6 | 补间动画 + 定时器 | `Utils/Tween.lua`, `Utils/Timer.lua` | - |

#### P1-B：配置数据

| 编号 | 任务 | 输出文件 | 依赖 |
|------|------|---------|------|
| P1-B1 | 武器配方数据（短刃 3 把） | `Config/data/weapon_recipes.json` | - |
| P1-B2 | 订单模板（T1-T2 共 5 个） | `Config/data/order_templates.json` | - |
| P1-B3 | 品质阈值配置 | `Config/data/quality_thresholds.json` | - |
| P1-B4 | 设施升级数据（熔炉/锻台 Lv1-3） | `Config/data/facility_upgrades.json` | - |
| P1-B5 | 数据接口模块 | `Config/WeaponRecipes.lua` 等 | P1-A3, P1-B1~B4 |

#### P1-C：小游戏系统

| 编号 | 任务 | 输出文件 | 依赖 |
|------|------|---------|------|
| P1-C1 | 小游戏基类 + 调度器 | `MiniGame/MiniGameBase.lua`, `MiniGame/MiniGameRunner.lua` | P1-A2 |
| P1-C2 | 选矿去杂小游戏 | `MiniGame/OreSelectGame.lua` | P1-C1 |
| P1-C3 | 锻打塑形小游戏 | `MiniGame/ForgingGame.lua` | P1-C1 |
| P1-C4 | 研磨开刃小游戏 | `MiniGame/PolishingGame.lua` | P1-C1 |

#### P1-D：核心界面

| 编号 | 任务 | 输出文件 | 依赖 |
|------|------|---------|------|
| P1-D1 | 工坊主界面 | `Screen/HomeScreen.lua` | P1-A1, P1-A4 |
| P1-D2 | 订单板界面 | `Screen/OrderBoardScreen.lua` | P1-B2, P1-B5 |
| P1-D3 | 锻造界面（承载小游戏） | `Screen/ForgeScreen.lua` | P1-C1 |
| P1-D4 | 结算界面 | `Screen/ResultScreen.lua` | P1-A4 |
| P1-D5 | 品质评分引擎 | `Core/QualityCalc.lua` | P1-B3 |
| P1-D6 | 订单管理器 | `Core/OrderManager.lua` | P1-B2, P1-A4 |

#### P1-E：美术资源（首批）

| 编号 | 任务 | 资源 | 说明 |
|------|------|------|------|
| P1-E1 | UI 图标集 | `assets/image/icon_*.png` | 铜钱/声望/材料/设施等 (gpt 模型) |
| P1-E2 | 工坊主界面背景 | `assets/Textures/bg_home.png` | 破旧铁铺场景 |
| P1-E3 | 武器成品图（短刃 3 把） | `assets/Textures/weapon_*.png` | 猎户小刀/护卫直刀/劈山刀 |
| P1-E4 | 音效 | `assets/Sounds/` | 锤打/火焰/淬火/磨刀/完成 |

#### P1 交付标准

- [ ] 玩家可从主界面进入订单板，选择一个订单
- [ ] 依次完成 3 个小游戏（选矿/锻打/研磨）
- [ ] 品质评分计算并展示结果
- [ ] 奖励写入 GameState，铜钱/声望数值正确更新
- [ ] 可以升级熔炉（消耗铜钱），升级后影响品质系数
- [ ] 本地存档正常读写
- [ ] 全程无 Emoji，图标使用图片资源

---

### P2：完整循环 + 叙事

**目标**：补全全部 6 个小游戏，接入第 1 章剧情，实现设施升级和图鉴系统。

#### P2-A：剩余小游戏

| 编号 | 任务 | 输出文件 |
|------|------|---------|
| P2-A1 | 控火熔炼小游戏 | `MiniGame/SmeltingGame.lua` |
| P2-A2 | 淬火时机小游戏 | `MiniGame/QuenchingGame.lua` |
| P2-A3 | 组装装饰小游戏 | `MiniGame/AssemblyGame.lua` |

#### P2-B：叙事系统

| 编号 | 任务 | 输出文件 |
|------|------|---------|
| P2-B1 | 对话流程引擎 | `Story/StoryManager.lua` |
| P2-B2 | 第 1 章对话数据 | `Story/data/chapter1_nodes.json`, `chapter1_choices.json` |
| P2-B3 | 角色关系追踪 | `Story/RelationshipTracker.lua` |
| P2-B4 | AVG 对话界面 | `Screen/StoryScreen.lua` |

#### P2-C：扩展内容

| 编号 | 任务 | 输出文件 |
|------|------|---------|
| P2-C1 | 长剑武器线（配方 + 订单） | 更新 JSON 配置 |
| P2-C2 | 设施升级界面 | `Screen/UpgradeScreen.lua` |
| P2-C3 | 名器图鉴界面 | `Screen/CodexScreen.lua` |
| P2-C4 | 订单管理器扩展（T1-T3 共 12 个订单） | 更新 JSON + `Core/OrderManager.lua` |

#### P2-D：美术资源（第二批）

| 编号 | 任务 | 资源 |
|------|------|------|
| P2-D1 | 角色立绘（掌柜/沈灵/陆尘） | `assets/Textures/char_*.png` |
| P2-D2 | 对话背景（铁铺/后院/街市） | `assets/Textures/bg_story_*.png` |
| P2-D3 | 长剑成品图（3 把） | `assets/Textures/weapon_*.png` |
| P2-D4 | BGM（工坊日常/锻造紧张） | `assets/Music/` |

#### P2 交付标准

- [ ] 全部 6 个小游戏可玩
- [ ] 第 1 章剧情完整（约 15 个对话节点 + 分支选择）
- [ ] 选择影响角色好感度和阵营变量
- [ ] 2 条武器线（短刃 + 长剑），12 个订单
- [ ] 设施升级界面，5 个设施可升级
- [ ] 名器图鉴可查看已完成武器
- [ ] 角色立绘在对话中正确显示

---

### P3：完整游戏 + 变现

**目标**：全部 5 章剧情、4 条武器线、多结局、广告接入、云存档。

#### P3-A：完整剧情

| 编号 | 任务 |
|------|------|
| P3-A1 | 第 2-5 章对话数据 |
| P3-A2 | 多结局判定系统 |
| P3-A3 | 角色专属结局 |

#### P3-B：完整内容

| 编号 | 任务 |
|------|------|
| P3-B1 | 重剑 + 礼器武器线 |
| P3-B2 | T4-T5 订单模板（28+ 个订单） |
| P3-B3 | 挑战修饰符（限时/连单/突发事件） |
| P3-B4 | 每周目标系统 |

#### P3-C：变现与运营

| 编号 | 任务 |
|------|------|
| P3-C1 | 广告接入（激励视频 + 插屏） |
| P3-C2 | 云存档/排行榜（clientCloud） |
| P3-C3 | 设置界面（音量/广告去除/关于） |

#### P3-D：美术完善

| 编号 | 任务 |
|------|------|
| P3-D1 | 剩余角色立绘 |
| P3-D2 | 全部章节背景 |
| P3-D3 | 全部武器成品图 |
| P3-D4 | 完整音效库 + BGM |

#### P3 交付标准

- [ ] 5 章剧情完整可玩，5 个主结局可达成
- [ ] 4 条武器线，28+ 个订单
- [ ] 广告正常展示和奖励发放
- [ ] 云排行功能
- [ ] 全部美术资源到位

---

## 四、品质评分系统（技术规格）

### 4.1 公式

```
FinalScore = BaseScore * MaterialCoeff * StepAvgCoeff * ToolCoeff * OrderMatchCoeff * BonusCoeff
```

### 4.2 各系数说明

| 系数 | 来源 | 范围 |
|------|------|------|
| BaseScore | 武器配方定义 | 100~230 |
| MaterialCoeff | 使用的材料等级 | 0.8~1.5 |
| StepAvgCoeff | 所有小游戏评分的均值 | 0.75~1.15 |
| ToolCoeff | 设施等级加成 | 1.0~1.3 |
| OrderMatchCoeff | 材料是否匹配订单要求 | 0.9~1.1 |
| BonusCoeff | 特殊条件加成（首次/连续完美） | 1.0~1.2 |

### 4.3 品质阈值

| 品质 | 分数范围 | 奖励倍率 |
|------|---------|---------|
| 凡品 | <120 | x0.6 |
| 良品 | 120-169 | x0.8 |
| 上品 | 170-229 | x1.0 |
| 珍品 | 230-309 | x1.3 |
| 名器 | 310-409 | x1.8 |
| 传世 | 410+ | x2.5 |

### 4.4 单步评分映射

| 评价 | 分数系数 | 判定条件 |
|------|---------|---------|
| Perfect | 1.15 | 精确命中最佳区间 |
| Great | 1.05 | 接近最佳区间 |
| Good | 0.95 | 在可接受范围内 |
| Poor | 0.75 | 明显偏离 |

---

## 五、小游戏技术规格

### 5.1 统一接口

```lua
local MiniGameBase = {}
MiniGameBase.__index = MiniGameBase

function MiniGameBase:init(config)
    -- config.difficulty: 1-5
    -- config.materialTier: 材料等级
    -- config.facilityLevel: 设施等级
end

function MiniGameBase:update(dt)
    -- 每帧更新（计时/动画/判定）
end

function MiniGameBase:onTouchStart(x, y) end
function MiniGameBase:onTouchMove(x, y)  end
function MiniGameBase:onTouchEnd(x, y)   end

function MiniGameBase:getScore()
    -- 返回 { score=0.0~1.0, rating="Perfect"|"Great"|"Good"|"Poor" }
end

function MiniGameBase:cleanup() end
```

### 5.2 各小游戏规格

| 小游戏 | 渲染方式 | 输入 | 核心算法 | P1/P2 |
|--------|---------|------|---------|-------|
| 选矿去杂 | UI 组件 | 点击 | 3选1正确率 + 杂质清除速度 | P1 |
| 控火熔炼 | NanoVG | 点击 | 停止点距最佳区间距离 | P2 |
| 锻打塑形 | NanoVG | 节奏点击+拖拽 | 节拍准确度 + 轮廓吻合度 | P1 |
| 淬火时机 | NanoVG | 长按释放 | 释放时机在目标窗口内的精度 | P2 |
| 研磨开刃 | NanoVG | 路径拖拽 | 轨迹vs理想路径偏差积分 | P1 |
| 组装装饰 | UI 组件 | 拖拽排列 | 顺序正确率 + 速度 | P2 |

---

## 六、数据结构定义

### 6.1 武器配方 (weapon_recipes.json)

```json
[
  {
    "id": "WEAPON_001",
    "name": "猎户小刀",
    "line": "short_blade",
    "baseScore": 100,
    "steps": ["ore_select", "forging", "polishing"],
    "requiredMaterials": { "ore": 2, "charcoal": 1 },
    "unlockChapter": 1,
    "description": "山间猎户常用的短刃，实用为主"
  }
]
```

### 6.2 订单模板 (order_templates.json)

```json
[
  {
    "id": "ORD_T1_001",
    "tier": 1,
    "chapter": 1,
    "customerName": "猎户张三",
    "customerType": "common",
    "weaponId": "WEAPON_001",
    "dialogue": "大侠，帮我打一把趁手的猎刀",
    "requiredMaterialTier": 1,
    "baseRewardCoins": 50,
    "baseRewardFame": 10,
    "bonusMaterials": { "ore": 1 }
  }
]
```

### 6.3 存档结构 (save.json)

```json
{
  "version": 1,
  "coins": 0,
  "fame": 0,
  "jade": 0,
  "materials": {
    "ore": 5,
    "charcoal": 3,
    "grinding_agent": 2,
    "wood": 2,
    "leather": 1,
    "pattern_gold": 0,
    "meteorite": 0
  },
  "facilities": {
    "furnace": 1,
    "anvil": 1,
    "quench_pool": 1,
    "grinder": 1,
    "display": 1
  },
  "completedOrders": [],
  "codex": [],
  "storyProgress": {
    "chapter": 1,
    "nodeId": "CH1-001"
  },
  "relationships": {
    "keeper": 0,
    "shen": 0,
    "luchen": 0,
    "magistrate": 0,
    "disciple": 0,
    "hanzhu": 0
  },
  "factions": {
    "court": 0,
    "guild": 0,
    "rivers": 0,
    "craftsman": 0
  },
  "stats": {
    "totalForged": 0,
    "perfectCount": 0,
    "bestQualityTier": 0
  },
  "timestamp": 0
}
```

---

## 七、开发顺序（推荐执行路径）

### P1 阶段建议执行顺序

```
第 1 步: P1-A1 + P1-A2 + P1-A3 + P1-A6  (基础框架，并行)
第 2 步: P1-A4 + P1-A5                    (状态 + 存档)
第 3 步: P1-B1~B5                         (配置数据 + 接口)
第 4 步: P1-C1                            (小游戏基类 + 调度器)
第 5 步: P1-C2                            (选矿小游戏)
第 6 步: P1-D1 + P1-D2                    (主界面 + 订单板)
第 7 步: P1-D3 + P1-D5 + P1-D6            (锻造界面 + 评分 + 订单管理)
第 8 步: P1-C3                            (锻打小游戏)
第 9 步: P1-C4                            (研磨小游戏)
第10步: P1-D4                             (结算界面)
第11步: P1-E1~E4                          (美术 + 音效)
第12步: 全流程联调测试
```

---

## 八、风险与对策

| 风险 | 影响 | 对策 |
|------|------|------|
| 小游戏手感需要反复调参 | 开发耗时增加 | 将判定参数提取到 JSON 配置，支持热调 |
| 竖屏下小游戏操作空间有限 | 体验受影响 | 充分利用 NanoVG 自由绘制，按钮做大 |
| 5 章剧情内容量大 | P3 工期长 | 对话数据走 JSON 配置，批量生产 |
| 美术资源风格一致性 | 视觉不统一 | 固定 AI 生图 prompt 模板，统一种子 |

---

## 九、验收清单

### 每次提交前必检

- [ ] 代码无 Emoji 字符（UI 文本/按钮/标签/提示）
- [ ] 图标使用图片资源或 NanoVG，无 Emoji 替代
- [ ] AI 生图使用 gpt 模型
- [ ] 数组索引从 1 开始
- [ ] NanoVG 在 NanoVGRender 事件中渲染
- [ ] 资源路径无 assets/ scripts/ 前缀
- [ ] 调用 build 工具验证编译通过
- [ ] 存档读写正常
- [ ] 竖屏布局在不同分辨率下无溢出
