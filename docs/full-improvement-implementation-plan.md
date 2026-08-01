# 古代铁匠模拟器完整改造实施计划

> 状态：执行中
> 目标平台：横屏 16:9（Landscape）
> 视觉方向：极简水墨武侠风
> 核心原则：先保证数据安全，再补玩法闭环，随后强化剧情与长期循环，最后统一视觉与发布材料。

---

## 一、产品基线

### 1.1 屏幕与适配

- 固定采用横屏 16:9，不再按竖屏 9:16 设计。
- 设计分辨率统一为 1920×1080。
- UI 使用系统逻辑分辨率和设计分辨率缩放，兼容不同 DPR。
- 顶部、底部及左右各保留安全区域；移动端交互按钮最小触控区域不低于 44×44 逻辑像素。
- TapTap 发布配置使用 `screen_orientation = "landscape"`。
- 发布截图、宣传图、横版封面均以真实横屏实机画面为基础。

### 1.2 视觉规范

- 风格固定为“极简水墨武侠风”，不再使用 PixelForge/像素风作为全局主题描述。
- 主背景：烟墨黑、深墨蓝；强调色：炉火红、鎏金；成功色：青铜绿；警告色：淬火黄。
- 面板使用深色水墨晕染、极细淡墨或淡金描边；避免厚金属边框、铆钉、厚阴影和像素硬阴影。
- 按钮使用宣纸水墨渗透质感和轻微圆角；不使用 Emoji 作为图标。
- 同一层级的按钮、弹窗、卡片、进度条保持一致的边框、颜色、字号和交互反馈。

### 1.3 数据与架构原则

- `GameState` 是玩家数据唯一读写入口。
- 货币、材料、设施、关系、阵营和统计数值继续由 `SecureStore` 混淆存储。
- Screen 只处理展示和输入，不直接结算奖励、不直接写云存档。
- 配置走 JSON；运行时实例和存档结构分离。
- UI 高频更新必须增量更新；仅页面切换、数据源整体替换和初始化允许重建。
- 每次 Lua 代码改动后必须先跑 LSP Error 诊断，再运行 UrhoX build。

---

## 二、阶段与依赖顺序

## 阶段 0：规范、文档与发布基线

### 目标

锁定横屏和极简水墨方向，消除文档、代码注释和发布配置之间的冲突。

### 修改范围

- `CLAUDE.md`
- `docs/ancient-workshop-mobile-gdd.md`
- `docs/dev-plan.md`
- `docs/storage-architecture.md`
- `.project/project.json`
- `scripts/main.lua` 中主题命名与注释

### 工作项

1. 全部“竖屏 9:16”描述改为“横屏 16:9”。
2. 设计分辨率统一为 1920×1080。
3. 全局主题从 PixelForge 更名并调整为 InkWuxia/极简水墨主题。
4. 发布素材要求改为：横屏截图 1920×1080、横版宣传图 1920×1080、图标 512×512。
5. 保持 `.project/project.json` 的 `landscape` 配置，并补齐发布材料验收要求。

### 验收

- 文档、UI 初始化、布局导出说明和发布方向不再互相冲突。
- 全项目不再把 PixelForge 描述为产品视觉方向。

---

## 阶段 1：设置系统真正生效

### 目标

消除“能选择但不生效”的伪设置。

### 新增/修改范围

- 新增 `scripts/Core/SettingsManager.lua`
- 修改 `scripts/Core/GameState.lua`
- 修改 `scripts/Screen/SettingsScreen.lua`
- 修改 `scripts/main.lua`
- 修改 `scripts/Utils/BGMManager.lua`
- 修改 `scripts/Utils/SFXManager.lua`
- 修改 `scripts/Utils/Tween.lua`
- 修改 `scripts/Utils/ScreenRouter.lua`
- 按需修改 UI 根节点/Theme 应用接口

### 功能定义

- 主音效音量：立即作用于 `SOUND_EFFECT`。
- 音乐音量：立即作用于 `SOUND_MUSIC`。
- 环境音量：由环境循环音单独乘以环境增益。
- 画质：
  - `performance`：关闭非必要浮动/呼吸动画，降低动效频率。
  - `standard`：默认表现。
  - `high`：完整动效。
- 字体大小：全局字号比例 `small=0.90`、`medium=1.00`、`large=1.15`，页面重建时生效；设置页即时预览。
- 语言：首阶段支持 `zh-CN` 完整生效；其他语言若未完成翻译则隐藏，不显示伪选项。后续接入 i18n 后再开放。
- 低功耗：降低非必要动画更新频率并关闭装饰性动画。
- 振动：所有触觉反馈统一通过设置管理器判断；平台不支持时安全忽略。

### 数据迁移

- 存档版本升级。
- 老存档缺失设置字段时补默认值。
- 设置写入 `plainData_.settings`，不丢失旧的音量数据。

### 验收

- 每个可见选项在游戏中都有可观察效果。
- 未实现的语言或设备能力不显示为可选项。
- 重启后设置保持。

---

## 阶段 2：存档与进行中订单安全

### 目标

避免材料已扣但订单丢失，以及云读取失败后覆盖真实存档。

### 修改范围

- `scripts/Core/GameState.lua`
- `scripts/Core/OrderManager.lua`
- `scripts/MiniGame/MiniGameRunner.lua`
- `scripts/Screen/ForgeScreen.lua`
- `scripts/Screen/HomeScreen.lua`
- `scripts/main.lua`

### 存档结构

```json
{
  "activeOrder": {
    "orderId": "ORD_T1_001",
    "acceptedAt": 0,
    "currentStep": 1,
    "stepScores": [],
    "consumedMaterials": { "ore": 2, "charcoal": 1 },
    "status": "accepted"
  },
  "cloudSync": {
    "loadStatus": "loaded|new|temporary_offline",
    "baseTimestamp": 0
  }
}
```

### 行为

- 接单、进入工序、单步完成时更新 activeOrder。
- 正常完单后清除 activeOrder。
- 主动放弃按规则退还材料并清除 activeOrder。
- 重启后检测 activeOrder，提供“继续锻造/放弃订单”。
- 云加载失败进入临时离线模式；未经明确冲突处理，不覆盖远端存档。
- 云恢复后比较时间戳并提示选择较新存档。

### 验收

- 锻造中强制退出后重进可继续或退款。
- 模拟云超时后游玩，不会自动覆盖远端基线。
- 同一订单不能重复结算、重复退款或重复发奖。

---

## 阶段 3：设施与成长效果闭环

### 目标

统一主页设施和配置，让升级真实改变玩法。

### 修改范围

- `scripts/Config/data/facility_upgrades.json`
- `scripts/Config/FacilityConfig.lua`
- `scripts/Core/OrderManager.lua`
- `scripts/Core/QualityCalc.lua`
- `scripts/Screen/HomeScreen.lua`
- `scripts/Screen/UpgradePopup.lua`
- `scripts/Screen/ForgeScreen.lua`
- 六个小游戏模块

### 设施定义

| 设施 | 玩法效果 |
|---|---|
| 熔炉 | 扩大熔炼最佳温度区间 |
| 锻台 | 扩大锻打命中容差 |
| 淬火池 | 扩大淬火完美释放窗口 |
| 磨石 | 降低研磨路径偏差惩罚 |
| 展柜 | 提升订单铜钱奖励，不参与品质平均 |

### 行为

- 主页“库房”改为“淬火池”，与配置统一。
- 各小游戏读取对应设施等级和效果参数。
- `QualityCalc` 只计算真正与成品品质有关的设施，不把展柜混入品质。
- 展柜奖励加成在 `OrderManager` 结算时应用。

### 验收

- 每次升级都能在对应小游戏或奖励中观察到变化。
- 升级说明和实际效果一致。

---

## 阶段 4：材料品质玩法

### 目标

让高阶材料、订单要求和品质公式形成真实决策。

### 修改范围

- 新增 `scripts/Config/data/material_tiers.json`
- 新增 `scripts/Config/MaterialConfig.lua`
- 修改 `scripts/Core/GameState.lua`
- 修改 `scripts/Core/OrderManager.lua`
- 修改 `scripts/Core/QualityCalc.lua`
- 修改 `scripts/Screen/OrderBoardScreen.lua` 或新增锻造准备弹窗
- 修改 `scripts/Screen/ForgeScreen.lua`
- 修改 `scripts/Screen/ShopScreen.lua`

### 玩法

- 接单后、开始锻造前选择可用材料品质。
- 高品质材料数量独立保存和消耗。
- 不满足订单要求时允许继续，但降低匹配系数并明确警告。
- 实际 `usedMaterialTier` 传入品质结算，不再自动按订单要求代填。

### 验收

- 同一订单使用不同材料能产生不同品质和奖励。
- 高阶材料库存和商店来源可追踪。
- 放弃订单按实际消耗材料退款。

---

## 阶段 5：挑战、失败、重试与广告补救

### 目标

让小游戏成绩带来风险和选择，同时保持 Hybrid-Casual 的低挫败。

### 修改范围

- `scripts/Core/ChallengeModifier.lua`
- `scripts/Core/OrderManager.lua`
- `scripts/MiniGame/MiniGameBase.lua`
- `scripts/MiniGame/MiniGameRunner.lua`
- 六个小游戏模块
- `scripts/Screen/ForgeScreen.lua`
- `scripts/Utils/AdManager.lua`
- `scripts/Core/GameState.lua`

### 状态机

```text
playing → step_success → next_step
playing → step_failed → free_retry / ad_rescue / accept_flaw / abandon
```

### 规则

- 单步分数低于阈值进入失败处理，不直接无条件完单。
- 每单一次免费重试。
- 激励广告补救后该步固定为 Good。
- 接受瑕疵可继续，但最终品质上限受限。
- 放弃订单退回 40% 实际消耗材料。
- 挑战修饰符真正传入小游戏并改变时限、触控次数、材料上限或突发事件。
- 修饰符奖励只在挑战实际生效时发放。

### 验收

- 所有失败路径不会重复发奖/退款。
- 广告未开通时隐藏补救入口，但免费重试和瑕疵继续仍可用。
- 挑战 UI、玩法变化和结算加成一致。

---

## 阶段 6：订单长期循环

### 目标

避免 33 个订单全部完成后订单板永久为空。

### 修改范围

- 扩展 `scripts/Config/data/order_templates.json`
- 修改 `scripts/Config/OrderConfig.lua`
- 修改 `scripts/Core/GameState.lua`
- 修改 `scripts/Core/OrderManager.lua`
- 修改 `scripts/Screen/OrderBoardScreen.lua`
- 修改 `scripts/Utils/RedDotManager.lua`

### 订单类型

- `story`：主线订单，一次性。
- `character`：人物专属订单，一次性且受关系条件限制。
- `daily`：日常委托，按模板生成实例，可重复。
- `rare`：稀有订单，按刷新概率生成。
- `challenge`：带挑战修饰符的可重复订单。

### 存档

- 保存每日订单实例、刷新日期、已用刷新次数和每日广告次数。
- 已完成模板与已完成实例分开记录。

### 验收

- 主线订单不会重复。
- 日常订单跨日刷新。
- 全部主线完成后仍有可玩订单。

---

## 阶段 7：周目标、排行榜和运营入口

### 目标

让已有模块真正可访问。

### 修改范围

- `scripts/main.lua`
- `scripts/Core/WeeklyGoal.lua`
- `scripts/Core/Leaderboard.lua`
- 新增 `scripts/Screen/WeeklyGoalScreen.lua`
- 新增 `scripts/Screen/LeaderboardScreen.lua`
- 修改 `scripts/Screen/HomeScreen.lua`
- 修改 `scripts/Utils/RedDotManager.lua`

### 行为

- GameState 加载后初始化周目标和排行榜。
- 主页任务入口进入周目标，不再重复进入订单板。
- 排行榜支持加载中、空数据、失败重试。
- 周目标领奖具备单次领取保护。

### 验收

- 周目标能随订单、品质、武器线和挑战进度推进。
- 排行榜自动提交并可查看。

---

## 阶段 8：首单交互教程

### 目标

用第一张猎户短刀订单教会完整循环。

### 修改范围

- 新增 `scripts/Core/TutorialManager.lua`
- 修改 `scripts/Core/GameState.lua`
- 修改 `scripts/Screen/HomeScreen.lua`
- 修改 `scripts/Screen/OrderBoardScreen.lua`
- 修改 `scripts/Screen/ForgeScreen.lua`
- 修改首单涉及的小游戏

### 教程步骤

1. 高亮订单入口。
2. 自动选中猎户短刀主线订单。
3. 解释材料和接单消耗。
4. 选矿正确项更明显、时间更宽松。
5. 锻打节奏降低。
6. 研磨路径加粗。
7. 首次 Poor 自动给出补救教学。
8. 结算解释品质、奖励、图鉴和设施升级。

### 验收

- 教程进度可存档。
- 退出重进可从合理步骤恢复。
- 完成后不重复强制触发，可在设置中重看。

---

## 阶段 9：剧情与订单深度联动

### 目标

形成“人物诉求 → 指定订单 → 锻造结果 → 剧情反馈”的闭环。

### 修改范围

- 修改五章剧情 JSON
- 修改 `scripts/Story/StoryManager.lua`
- 修改 `scripts/Core/GameState.lua`
- 修改 `scripts/Core/OrderManager.lua`
- 修改 `scripts/Screen/StoryScreen.lua`
- 修改 `scripts/Screen/OrderBoardScreen.lua`
- 修改 `scripts/Story/EndingEvaluator.lua`

### 数据结构

```json
{
  "triggerOrder": {
    "orderId": "ORD_T1_001",
    "required": true,
    "returnNodeId": "CH1-005"
  }
}
```

### 行为

- 剧情订单自动选中并带“主线委托”标识。
- 下一剧情检查指定订单完成，不再只检查总数量。
- `storyFlags` 和 `choiceHistory` 持久化。
- 选择后显示关系、阵营、资源、线索和订单变化。
- 剧情入口显示下一节点的阻塞条件。
- 结局判定读取关键 Flag 和选择历史，不只依赖数值。

### 验收

- 完成无关订单不能错误推进指定剧情。
- 重启后关键选择不丢失。
- 结局页能回顾关键选择和主导路线。

---

## 阶段 10：剧情阅读体验

### 目标

提高长线剧情在移动设备上的可读性和回流体验。

### 修改范围

- `scripts/Screen/StoryScreen.lua`
- `scripts/Story/StoryManager.lua`
- 五章剧情 JSON
- 按需增加角色表情资源和字段

### 功能

- 最近 30～50 条对话记录。
- 可折叠章节摘要、当前目标、待完成主线订单。
- 跳过分为：完成当前文字、跳过当前节点、跳过本章。
- 跳过本章必须二次确认并应用明确的默认选择结果。
- choice 节点显示“请选择回应”。
- 核心角色支持显式 `expression` 字段；关键词音效只做兜底。

### 验收

- 自动播放遇到选择时有清晰提示。
- 跳过不会让关键状态缺失。
- 玩家中断后能快速回顾当前章节。

---

## 阶段 11：水墨视觉统一与发布收尾

### 目标

清理混合风格、重复入口、占位功能并达到发布准备状态。

### 修改范围

- `scripts/main.lua` Theme
- 全部 `scripts/Screen/*.lua`
- 布局导出文件
- `assets/image/` UI 资源
- `.project/project.json`

### 工作项

- 去除 PixelForge 命名、硬像素阴影和不一致的现代透明卡片。
- 主页面重复入口合并；未实现的信件/IAP 入口隐藏。
- 所有弹窗、按钮、标签、进度条统一水墨规范。
- 广告状态无效时隐藏广告入口。
- 准备横屏发布材料：图标、至少 3 张真实截图、宣传图、横版封面。

### 验收

- 主要页面视觉语言统一。
- 无 Emoji、无伪功能入口、无失效广告按钮。
- 发布配置与横屏素材一致。

---

## 三、通用验证门禁

每个阶段必须完成：

1. Lua LSP Error 诊断为 0。
2. 运行 UrhoX build 成功。
3. 核对 UI 中无 Emoji。
4. 核对资源路径无 `assets/` 或 `scripts/` 前缀。
5. 检查事件订阅和销毁配对。
6. 检查敏感数值未在模块级缓存明文。
7. 对存档结构变更执行旧档迁移测试。
8. 对经济交易执行重复点击、重进、断网和异常退出测试。

---

## 四、执行状态

| 阶段 | 状态 |
|---|---|
| 阶段 0：规范、文档与发布基线 | 执行中 |
| 阶段 1：设置系统真正生效 | 待开始 |
| 阶段 2：存档与进行中订单安全 | 待开始 |
| 阶段 3：设施与成长效果闭环 | 待开始 |
| 阶段 4：材料品质玩法 | 待开始 |
| 阶段 5：挑战、失败、重试与广告补救 | 待开始 |
| 阶段 6：订单长期循环 | 待开始 |
| 阶段 7：周目标、排行榜和运营入口 | 待开始 |
| 阶段 8：首单交互教程 | 待开始 |
| 阶段 9：剧情与订单深度联动 | 待开始 |
| 阶段 10：剧情阅读体验 | 待开始 |
| 阶段 11：水墨视觉统一与发布收尾 | 待开始 |
