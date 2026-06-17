# 剧情 / 关系系统激活计划

> 本文记录"结局系统接通 + 好感度系统激活"的完整方案与实现，供检查核对。
> 背景：剧情文本、好感度数据、结局判定都已写好，但**没接进游戏**——
> 玩家走完 5 章看不到结局，也看不到任何好感度反馈。本次把这些"零件装上车"。

---

## 一、问题诊断（实施前）

| 系统 | 现状 | 问题 |
|------|------|------|
| 5 章剧情文本 | ✅ 完整 | 无 |
| 抉择写入好感/阵营 | ✅ 完整（StoryManager.ApplyEffects） | 无 |
| `EndingEvaluator`（5 结局判定） | ⚠️ 写好但**零调用** | 终章玩完直接回主界面，无结局 |
| 结局阈值 | ❌ 全部不可达 | 见下表，每个玩家只会得到失败结局 |
| 好感度展示 | ❌ 无任何界面 | 玩家感知不到关系变化 |
| `RelationshipTracker` | ❌ 死代码（无人引用）+ 重复的第二套结局判定 | 冗余 |

### 结局阈值不可达实测（单周目最优累加上限）

| 结局 | 原关键门槛 | 实际可达上限 | 原判定 |
|------|-----------|------------|--------|
| 守道匠宗 | keeper ≥ 70 | keeper **50** | 不可达 |
| 御用神匠 | magistrate ≥ 70 | magistrate **26** | 不可达 |
| 江湖名坊 | rivers≥70 & luchen≥70 | rivers48 / luchen42 | 不可达 |
| 商会铸局 | guild≥70 & shen≥65 | guild48 / shen28 | 不可达 |
| 断火残坊(失败) | 兜底 | — | 永远只有这个 |

阵营可达上限：craftsman 99 / court 82 / guild 48 / rivers 48。
角色可达上限：keeper 50 / luchen 42 / shen 28 / magistrate 26 / truth 13。

---

## 二、重标后的结局阈值（可达 + 可区分）

判定按优先级顺序执行：断火残坊 → 守道匠宗 → 御用神匠 → 江湖名坊 → 商会铸局 → 兜底断火残坊。
最终章 CH5-004「名器献给谁」给所选阵营 +20，是结局的决定性一击。

| 结局 | 阵营主判 | 角色/真相副判 | 设计意图 |
|------|---------|--------------|---------|
| **断火残坊** broken_forge | 关键角色断裂数 ≥ 2（好感≤−20） | 且 真相 ≤ 1 | 蓄意破坏关系 + 无视真相才触发 |
| **守道匠宗** craftsman_way | craftsman ≥ 55 | keeper ≥ 28 且 truth ≥ 4 | 专注匠道、亲近老掌柜、追真相 |
| **御用神匠** imperial_smith | court ≥ 50 | magistrate ≥ 14 | 投靠朝廷、得县尉支持 |
| **江湖名坊** jianghu_forge | rivers ≥ 30 | luchen ≥ 24 | 结交江湖、护陆沉 |
| **商会铸局** guild_foundry | guild ≥ 30 | shen ≥ 14 | 商会路线、与沈绫结盟 |

> 阈值均在可达上限内并留余量；优先级保证一条专注路线落到对应结局，
> 平衡型/破坏型玩家落到兜底失败结局。

---

## 三、每个结局的尾声文本（epilogue）

- **守道匠宗**：你回绝了所有招揽，守着这间小铺，把残卷上的古法一锤一锤敲回人间。多年后，"守道"二字成了匠人之间的暗号——铁要烧透，心要烧硬。
- **御用神匠**：王都的诏书送到那天，炉火映红了半条街。你成了御用神匠，住进了高墙，再没人敢压你的价——也再没人敢直呼你的名字。
- **江湖名坊**：你的刀流落江湖，斩过不平，也染过血。庙堂始终容不下你，可每一个握过你刀的人，都记得这间小坊的名字。
- **商会铸局**：账册越来越厚，炉子越来越多。商会的旗号挂上门楣，你赚到了所有人羡慕的银子，只是夜深时偶尔会想起，最初那把猎户的短刀。
- **断火残坊**：债没还清，人也散了。某个清晨，炉火彻底熄了。这间铺子，终究没能撑过那个寒冬。

---

## 四、好感度 / 阵营展示界面（RelationshipScreen）

新增"人物关系"界面，复用主界面顶部**"友"按钮**（原为"敬请期待"占位）作为入口：

- **阵营倾向**：朝廷 / 商会 / 江湖 / 匠道 —— 横向进度条 + 数值
- **人物好感**：老掌柜 / 沈绫 / 陆沉 / 县尉 / 阿晦 —— 头像名 + 好感值 + 已解锁等级（复用 RelationshipTracker.CHARACTER_THRESHOLDS）
- **真相揭露度** truth —— 单独一条
- 竖屏 9:16，暖色调，与全局主题统一

---

## 五、死代码清理

- 删除 `RelationshipTracker.EvaluateEndings`（与 `EndingEvaluator` 重复、ID 不一致）
- `RelationshipTracker` 转为"被使用"：RelationshipScreen 通过它读阵营名/角色阈值
- 结局判定全项目统一走 `EndingEvaluator`

---

## 六、改动文件清单

| 文件 | 改动 |
|------|------|
| `scripts/Story/EndingEvaluator.lua` | 重标 5 结局阈值；ENDINGS 增加 `epilogue` 尾声文本 |
| `scripts/Screen/EndingScreen.lua` | 新建：结局展示（名称/尾声/决定性数值/回工坊） |
| `scripts/Screen/RelationshipScreen.lua` | 新建：阵营 + 好感度展示 |
| `scripts/Screen/StoryScreen.lua` | 终章完成（storyProgress.done）→ 跳 EndingScreen |
| `scripts/Screen/HomeScreen.lua` | "友"按钮 → 人物关系界面 |
| `scripts/Story/StoryManager.lua` | 增加 `IsStoryDone()` 辅助 |
| `scripts/Story/RelationshipTracker.lua` | 删除重复 EvaluateEndings |
| `scripts/main.lua` | 注册 ending / relationship 屏幕 |

---

## 七、验收点

- [ ] 走完第五章 → 弹出结局界面（不再静默回主界面）
- [ ] 不同抉择路线 → 不同结局（专注一条线能拿到对应正面结局）
- [ ] 主界面"友"→ 看到各角色好感、各阵营倾向
- [ ] 好感/阵营数值随剧情抉择实时变化
- [ ] 构建通过、无死代码冲突

*生成于实施前，供检查。*

---

## 八、可选增量（第二批，已实现）

在「结局 + 好感度展示」激活完成后，进一步把这两套数据接入实际玩法。

### 8.1 结局图鉴 / 回顾

- 复用 `EndingEvaluator.EvaluateAll()`（实时判定）+ 新增持久化 `GameState.GetAchievedEndings()`。
- 在名器图鉴左侧分类新增「结局」分区（复用 `cat_u` 占位按钮）。
- 每个结局卡片三态：
  - **已达成**：显示结局名 + 尾声全文（鎏金高亮，路线主题色描边）。
  - **条件已满足**：当前数据正指向该结局，提示完成终章即可抵达（青铜绿徽章）。
  - **未解锁**：名称隐藏为「？？？」，仅显示路线提示（烟灰）。
- 抵达结局时 `EndingScreen` 调 `GameState.MarkEndingAchieved(id)` 落档。

涉及文件：`GameState.lua`（achievedEndings 字段 + 存取）、`EndingEvaluator.lua`（GetEndingList 带 epilogue）、`EndingScreen.lua`（落档）、`CodexScreen.lua`（结局覆盖层 + 分区切换）。

### 8.2 好感度接入实际玩法

**前置修正**：`CHARACTER_THRESHOLDS` 原 L1/L2（30~70）超出剧情可达上限（实测：keeper~50/shen~28/luchen~42/magistrate~26/disciple~19），全部重标为可达值，否则解锁永不触发。

| 玩法钩子 | 触发条件 | 效果 |
|---------|---------|------|
| 商店折扣 | 沈绫 L1=12 / L2=22 | 全场 5% / 10% 折扣（铜钱 + 玉璧），ShopScreen 实时显示原价划线 + 折后价 |
| 专属订单 · 沈绫密约 | 沈绫 L2 | 解锁 `ORD_SP_SHEN`（高额稀有材料回报） |
| 专属订单 · 陆沉相托 | 陆沉 L1=18 | 解锁 `ORD_SP_LUCHEN` |
| 专属订单 · 老掌柜真传 | 老掌柜 L2=40 | 解锁 `ORD_SP_KEEPER`（终章名器，最高回报） |

- 订单门槛由 `OrderConfig.GetAvailable` 过滤 `order.favorRequirement`，未达标的特殊订单不出现在订单板。
- 订单板对带门槛的订单加「· 专属」标记。

涉及文件：`RelationshipTracker.lua`（重标阈值 + GetShopDiscountRate / MeetsFavorRequirement）、`ShopScreen.lua`（折扣价）、`OrderConfig.lua`（好感过滤）、`order_templates.json`（3 个专属订单）、`OrderBoardScreen.lua`（专属标记）。

*第二批增量实现后补记。*
