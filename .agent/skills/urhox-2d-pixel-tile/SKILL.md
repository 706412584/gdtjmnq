---
name: urhox-2d-pixel-tile
description: UrhoX 2D 像素瓦片游戏开发完整指南。当用户要做 2D 像素游戏、瓦片地图、top-down/横版 2D、像素风塔防/农场/ARPG、2D Scene、StaticSprite2D、PhysicsWorld2D、spritesheet 动画、分辨率适配、碰撞体、移动端 HUD 或从 raw NanoVG 原型迁移到原生 2D 场景时必须使用。尤其适用于“像素瓦片”“2D引擎”“不同分辨率适配”“碰撞检测”“瓦片图集”“角色动画”“UI叠加层”等需求。
---

# UrhoX 2D 像素瓦片开发 Skill

目标：帮助构建可扩展的 UrhoX 2D 像素瓦片游戏。优先使用 **UrhoX 原生 2D Scene** 承载玩法，用 **urhox-libs/UI** 承载 HUD/菜单。raw NanoVG 可用于快速原型和特殊绘制，但正式玩法实体、碰撞、动画和瓦片地图应逐步迁移到 2D Scene 架构。

## 触发后先做的事

1. 读取项目规则（如存在）：`PROJECT_RULES.md`。
2. 如果项目已有脚本，先读 `scripts/main.lua` 或相关模块，不要凭空改代码。
3. 如果涉及 raw NanoVG，必须同时遵循 `nvg-resolution-mode` 的分辨率规则。
4. 如果涉及 UI/HUD，必须使用 `urhox-libs/UI`，不要用废弃原生 UIElement。
5. 修改 Lua 后先做 LSP Error 诊断，再调用官方 build 工具。

## 推荐架构

```text
scripts/
  main.lua                 -- 生命周期、Scene/UI 初始化、事件订阅
  scene2d_map.lua          -- 瓦片地图、图集切片、场景节点构建
  logic_game.lua           -- 玩法状态、移动、战斗、波次、碰撞回调
  ui_hud.lua               -- PixelForge/UI HUD 构建与更新
  config.lua               -- 米制尺寸、瓦片尺寸、资源表、数值
assets/
  image/                   -- 像素图集、spritesheet、tile atlas
  Fonts/                   -- PixelForge 或项目字体
```

原则：
- `Scene` 层只做玩法实体、碰撞、动画、相机。
- `UI` 层只做资源条、按钮、提示、菜单、弹窗。
- 玩法坐标统一用米制世界坐标，不把屏幕像素坐标直接塞进 Scene 逻辑。

## 最小原生 2D Scene 骨架

```lua
local UI = require("urhox-libs/UI")

---@type Scene
local scene_ = nil
---@type Node
local cameraNode_ = nil

local WORLD_W, WORLD_H = 6.4, 3.6

local function CreateScene2D()
    scene_ = Scene()
    scene_:CreateComponent("Octree")
    local physicsWorld = scene_:CreateComponent("PhysicsWorld2D")
    physicsWorld.gravity = Vector2(0, 0)

    cameraNode_ = scene_:CreateChild("Camera2D")
    local camera = cameraNode_:CreateComponent("Camera")
    camera.orthographic = true

    local aspect = graphics:GetWidth() / graphics:GetHeight()
    camera.orthoSize = math.min(WORLD_H, WORLD_W / aspect)
    cameraNode_.position = Vector3(WORLD_W * 0.5, WORLD_H * 0.5, -10)
    renderer:SetViewport(0, Viewport:new(scene_, camera))
end

function Start()
    CreateScene2D()
    UI.Init({ scale = UI.Scale.DEFAULT })
    SubscribeToEvent("Update", "HandleUpdate")
    SubscribeToEvent("PhysicsBeginContact2D", "HandleBeginContact")
    SubscribeToEvent("PhysicsEndContact2D", "HandleEndContact")
end

function Stop()
    UI.Shutdown()
end
```

## 分辨率与相机适配

### 原生 2D Scene 适配

用正交相机显示一个“世界米制区域”，让不同屏幕看到合理范围。

- 横屏策略：优先锁定世界高度，宽屏多显示左右区域。
- 竖屏策略：优先锁定世界宽度，或按玩法要求重新布局。
- 不使用 `graphics:SetMode()`。

```lua
local function UpdateCameraFit(camera, worldW, worldH)
    local aspect = graphics:GetWidth() / graphics:GetHeight()
    camera.orthoSize = math.min(worldH, worldW / aspect)
    -- 如果想完整显示世界，用 math.max(worldH, worldW / aspect)
end
```

选择：
- `math.min`：填满屏幕，边缘可能裁切，适合战斗场景。
- `math.max`：完整显示世界，可能有空边，适合编辑器/棋盘。

### UI/HUD 适配

HUD 使用 `urhox-libs/UI`：

```lua
UI.Init({
    theme = PixelForgeTheme,
    scale = UI.Scale.DEFAULT,
})
```

规则：
- HUD 用百分比、SafeArea、Flexbox。
- 横向按钮组设置 `flexShrink = 1`，避免小屏溢出。
- UI 坐标不要直接参与世界碰撞。

### raw NanoVG 适配

仅当项目仍有 raw NanoVG 2D 绘制时：
- 未明确设计分辨率，使用 `nvg-resolution-mode` 模式 B。
- 明确 1366×768 / 1920×1080 等设计尺寸，使用模式 A。
- 输入坐标需要从物理像素除以 `dpr`，再按模式转换。

## 坐标与单位

UrhoX 长度单位是米。推荐定义固定换算：

```lua
local PIXEL_SIZE = 0.01      -- 1 像素 = 0.01 米
local TILE_PX = 32
local TILE_M = TILE_PX * PIXEL_SIZE  -- 0.32 米
```

规则：
- 瓦片地图、角色、碰撞体都用米。
- 如果资源是 32×32 像素图块，Scene 中一格通常是 `0.32m`。
- Lua 数组从 1 开始，瓦片索引从 `row=1, col=1` 开始。

```lua
local function TileToWorld(col, row, originX, originY, tileM)
    return originX + (col - 0.5) * tileM, originY - (row - 0.5) * tileM
end
```

## 瓦片图集切片

像素瓦片必须保持硬边：

```lua
local tex = Texture2D:new()
tex:SetNumLevels(1)
tex:SetFilterMode(FILTER_NEAREST)
tex:SetAddressMode(COORD_U, ADDRESS_CLAMP)
tex:SetAddressMode(COORD_V, ADDRESS_CLAMP)
tex:SetData(subImage)
```

创建瓦片节点：

```lua
local tile = scene_:CreateChild("tile_" .. row .. "_" .. col)
tile:SetPosition2D(x, y)
local spr = tile:CreateComponent("StaticSprite2D")
spr.layer = 0
spr.sprite = dummySprite  -- 必须设置一个有效 pow2 Sprite2D 作为基底
spr.useDrawRect = true
spr.drawRect = Rect(-tileM / 2, -tileM / 2, tileM / 2, tileM / 2)
spr.customMaterial = material
```

建议：
- 缓存切片 material，key 使用 `tsetIdx .. "_" .. tileIdx`。
- 大地图后续再做 chunk/合批；MVP 先逐格节点可接受。

**关键：customMaterial 与 textureRect 互斥**

同一个 StaticSprite2D 不能同时使用两者：
- 瓦片地图：用 customMaterial（DiffUnlit + GetSubimage 切片纹理）
- 角色/道具：用 textureRect（UV 坐标裁切）

使用 customMaterial 时仍需设置 spr.sprite（任何有效 pow2 纹理即可），否则渲染为空。

## Spritesheet 动画

适合角色 idle/walk/attack。用 `textureRect` 选帧：

```lua
local function SetSheetFrame(spr, spritePath, frameIdx, count, cols, flipX)
    local sprite2d = cache:GetResource("Sprite2D", spritePath)
    if not sprite2d then return end
    spr:SetSprite(sprite2d)
    spr:SetUseTextureRect(true)

    local rows = math.max(1, math.ceil(count / cols))
    local f = frameIdx % count
    local col = f % cols
    local row = math.floor(f / cols)
    local u0 = col / cols
    local u1 = (col + 1) / cols
    local v0 = row / rows
    local v1 = (row + 1) / rows

    spr.textureRect = flipX and Rect(u1, v1, u0, v0) or Rect(u0, v1, u1, v0)
end
```


**textureRect 坐标说明**：`Rect(uLeft, vBottom, uRight, vTop)`
- V=0 是纹理顶部，V=1 是纹理底部
- 正常显示：`Rect(u0, v1, u1, v0)`（v1>v0，底在前顶在后）
- 水平翻转：交换 u0/u1 → `Rect(u1, v1, u0, v0)`
- 单行 spritesheet 简写：`Rect(frameIdx/count, 1.0, (frameIdx+1)/count, 0.0)`

也可用于任意 UV 矩形裁切道具/装饰（非网格），直接传小数 UV 坐标即可。
动画状态应由逻辑层决定，例如 `idle / walk / attack / hurt / death`。

## 碰撞设计

实现碰撞前先写注释说明碰撞区域：

```text
[角色] 0.22m × 0.28m 动态刚体，category=2，mask=1|4|8
[墙体] 0.32m × 0.32m 静态刚体，category=1
[敌人] 0.24m × 0.30m 动态刚体，category=4
[触发器] trigger=true，只触发拾取/伤害，不阻挡移动
```

关键规则：
- `RigidBody2D` 和碰撞形状组件（`CollisionBox2D`/`CollisionCircle2D`）放在同一个节点。
- 触发器使用 `shape.trigger = true`。
- 使用 `categoryBits` / `maskBits` 管理阵营和碰撞层。
- 不要用数字猜输入枚举；输入使用 `KEY_*`、`MOUSEB_*`。

静态墙：

```lua
local n = scene_:CreateChild("wall")
n:SetPosition2D(x, y)
local body = n:CreateComponent("RigidBody2D")
body.bodyType = BT_STATIC
local shape = n:CreateComponent("CollisionBox2D")
shape:SetSize(tileM, tileM)
shape.categoryBits = 1
shape.maskBits = 65535
```

动态角色：

```lua
local body = player:CreateComponent("RigidBody2D")
body.bodyType = BT_DYNAMIC
body.fixedRotation = true
body.gravityScale = 0
local shape = player:CreateComponent("CollisionBox2D")
shape:SetSize(0.22, 0.28)
shape.categoryBits = 2
shape.maskBits = 1 + 4 + 8
shape:SetCenter(0, -0.10)  -- 碰撞体偏移到脚部区域，更符合视觉遮挡
```

碰撞回调：

```lua
function HandleBeginContact(eventType, eventData)
    local nodeA = eventData["NodeA"]:GetPtr("Node")
    local nodeB = eventData["NodeB"]:GetPtr("Node")
    local shapeA = eventData["ShapeA"]:GetPtr("CollisionShape2D")
    local shapeB = eventData["ShapeB"]:GetPtr("CollisionShape2D")
    -- 交给 logic.OnContact(nodeA, nodeB, shapeA, shapeB, true)
end
```

## 输入与屏幕点击

### UI 点击

由 UI 组件 `onClick` 处理。

### 世界点击

需要把屏幕坐标转换到世界。优先使用引擎相机转换 API（如果项目已有封装就用封装）。若手动换算，记住 `camera.orthoSize` 是视野全高度，半高要乘 0.5：

```lua
local function ScreenToWorld2D(screenX, screenY, cameraNode, camera)
    local physW, physH = graphics:GetWidth(), graphics:GetHeight()
    local ndcX = (screenX / physW) * 2 - 1
    local ndcY = 1 - (screenY / physH) * 2
    local aspect = physW / physH
    local halfH = camera.orthoSize * 0.5
    local halfW = halfH * aspect
    local cp = cameraNode.position
    return cp.x + ndcX * halfW, cp.y + ndcY * halfH
end
```

## 图层建议

- tile ground：`layer = 0`
- props / crops：`layer = 5`
- actors：`layer = 10`
- projectiles / effects：`layer = 15`
- UI：urhox-libs/UI 自动叠加在 Scene 之上

## 迁移 raw NanoVG MVP 到 2D Scene 的步骤

1. 保留当前玩法数据结构，先新增 `scene2d_map.lua` 构建地块和温室节点。
2. 把视觉实体从 NanoVG draw 函数替换为 `StaticSprite2D` 或临时 placeholder sprite。
3. 加 `PhysicsWorld2D` 和基本碰撞体：温室、敌人、守卫、地块触发器。
4. 把攻击判定从屏幕距离改为世界坐标距离。
5. HUD 保留 PixelForge UI，仅改为读取逻辑层状态。
6. raw NanoVG 只保留特殊效果；能用 Sprite/粒子表达的逐步迁移。

## 验证清单

- [ ] 没有 `graphics:SetMode()`。
- [ ] UI 使用 `urhox-libs/UI`。
- [ ] raw NanoVG 如存在，使用 `NanoVGRender` 事件和正确 DPR/设计分辨率模式。
- [ ] 瓦片/角色/碰撞统一米制坐标。
- [ ] `RigidBody2D` 与碰撞形状在同一节点。
- [ ] 瓦片图集使用 `FILTER_NEAREST`。
- [ ] customMaterial 与 textureRect 未混用在同一 StaticSprite2D。
- [ ] 使用 customMaterial 的节点已设置 dummySprite。
- [ ] 角色碰撞体用 SetCenter 偏移到脚部。
- [ ] 输入使用 `KEY_*` / `MOUSEB_*` 枚举。
- [ ] LSP Error 数量为 0。
- [ ] 调用官方 build 工具成功。
- [ ] 若项目规则要求，每次功能/修复后提交 Git。

## 适合参考的项目内资料

如果存在以下目录，可以读取其用户提供的参考项目：

- `docs/像素demo`
- `docs/2d像素瓦片`

重点看：
- `sce-lua/scripts/main.lua`：2D Scene + UI 分层启动方式。
- `scene2d_*.lua`：瓦片图集切片、StaticSprite2D、碰撞节点构建。
- `logic_*.lua`：移动、AI、动画、碰撞回调组织方式。
