# SCE Lua 导出器 — JS 2D 节点 → UrhoX Lua 映射参考

> 面向布局编辑器 sceLuaExporter 开发者。
> 目标：将 JS 2D 引擎的玩法节点导出为 UrhoX 原生 2D 场景代码（方案 C）。

---

## 一、架构概览

```
┌──────────────────────────────────────────────────┐
│  UI 层: urhox-libs/UI (HUD/血条/分数/菜单)        │ ← 现有 sceLuaExporter 已支持
├──────────────────────────────────────────────────┤
│  2D 场景层: UrhoX 原生 2D                         │ ← 新增导出目标
│  · StaticSprite2D / AnimatedSprite2D             │
│  · TileMap2D (TMX)                               │
│  · RigidBody2D + CollisionShape2D (Box2D)        │
│  · Camera (orthographic)                         │
│  · ParticleEmitter2D                             │
├──────────────────────────────────────────────────┤
│  游戏循环: SubscribeToEvent("Update", handler)    │ ← 每帧逻辑
│  碰撞回调: SubscribeToEvent("PhysicsBeginContact2D", handler) │
└──────────────────────────────────────────────────┘
```

两层共存：UI 叠在 2D 场景上方，互不冲突。

---

## 二、导出代码结构模板

```lua
-- main.lua（入口）
local UI = require("urhox-libs/UI")

-- ═══ 2D 场景层 ═══
local scene_ = Scene()
scene_:CreateComponent("Octree")
scene_:CreateComponent("PhysicsWorld2D")

-- 正交相机
local cameraNode = scene_:CreateChild("Camera")
local camera = cameraNode:CreateComponent("Camera")
camera.orthographic = true
camera.orthoSize = 10.0          -- 视野高度（米）
cameraNode.position = Vector3(0, 0, -10)
renderer:SetViewport(0, Viewport:new(scene_, camera))

-- ═══ 场景内容（由导出器生成） ═══
require("Game2D_Level")          -- 2D 玩法节点
require("Game2D_Logic")          -- 游戏逻辑脚本

-- ═══ UI 层（现有导出） ═══
UI.Init({ fonts = { ... }, scale = UI.Scale.DEFAULT })
local hud = require("ui_HUD")
UI.SetRoot(hud.Build())

function Start()
    SubscribeToEvent("Update", "HandleUpdate")
    SubscribeToEvent("PhysicsBeginContact2D", "HandleCollision")
end

function HandleUpdate(eventType, eventData)
    local dt = eventData["TimeStep"]:GetFloat()
    -- 游戏逻辑每帧更新
end

function HandleCollision(eventType, eventData)
    local nodeA = eventData["NodeA"]:GetPtr("Node")
    local nodeB = eventData["NodeB"]:GetPtr("Node")
    -- 碰撞逻辑
end
```

---

## 三、节点类型映射表

### 3.1 总览

| JS 2D 节点 | UrhoX 导出 | 关键组件 |
|------------|-----------|---------|
| `GameScene2D` | Scene + PhysicsWorld2D + Camera | 场景根 |
| `Camera2D` | Node + Camera (orthographic) | 正交相机 |
| `CharacterController2D` | Node + StaticSprite2D + RigidBody2D + CollisionShape | 玩家 |
| `Enemy2D` | Node + StaticSprite2D + RigidBody2D + CollisionShape | 敌人 |
| `Pickup2D` | Node + StaticSprite2D + RigidBody2D(Static) + CollisionShape(trigger) | 可拾取物 |
| `TileMap2D` | Node + TileMap2D (TmxFile2D) | 瓦片地图 |
| `Platform2D` | Node + StaticSprite2D + RigidBody2D(Static) + CollisionBox2D | 平台 |
| `Projectile2D` | Node + StaticSprite2D + RigidBody2D(Dynamic, bullet) + CollisionCircle2D | 弹射物 |
| `ParticleEffect2D` | Node + ParticleEmitter2D | 2D 粒子 |
| `Sprite2D` (静态) | Node + StaticSprite2D | 背景/装饰 |
| `AnimatedSprite2D` | Node + AnimatedSprite2D (Spine/Spriter) | 骨骼动画 |
| `AreaTrigger2D` | Node + RigidBody2D(Static) + CollisionBox2D(trigger) | 触发区域 |

---

## 四、逐节点详细映射

### 4.1 GameScene2D（场景根）

```lua
-- JS 属性 → UrhoX 映射
-- gravity: Vector2          → physicsWorld.gravity
-- pixelsPerUnit: number     → PIXELS_PER_UNIT 常量（影响 orthoSize 计算）
-- bounds: Rect              → 用于相机限制

local scene_ = Scene()
scene_:CreateComponent("Octree")
-- scene_:CreateComponent("DebugRenderer")  -- 调试用

local physicsWorld = scene_:CreateComponent("PhysicsWorld2D")
physicsWorld.gravity = Vector2(0, -9.81)           -- 根据 JS gravity 属性
physicsWorld.velocityIterations = 8
physicsWorld.positionIterations = 3
```

### 4.2 Camera2D（正交相机）

```lua
-- JS 属性 → UrhoX 映射
-- viewportHeight: number    → camera.orthoSize（单位：米）
-- zoom: number              → camera.zoom
-- followTarget: string      → 逻辑代码中的相机跟随
-- bounds: Rect              → 相机移动限制（逻辑代码）
-- offset: Vector2           → cameraNode.position2D 偏移

local cameraNode = scene_:CreateChild("Camera2D")
local camera = cameraNode:CreateComponent("Camera")
camera.orthographic = true
camera.orthoSize = 10.0                   -- viewportHeight（米）
camera.zoom = 1.0                          -- zoom
cameraNode.position = Vector3(0, 0, -10)   -- Z=-10 看向 Z+

-- 相机跟随逻辑（在 Update 中）：
-- cameraNode.position2D = targetNode.position2D + offset
```

**orthoSize 计算规则**：
```lua
-- 如果 JS 用像素定义视口高度：
camera.orthoSize = viewportHeightPixels / PIXELS_PER_UNIT

-- 如果 JS 直接用世界单位：
camera.orthoSize = viewportHeightWorld
```

### 4.3 CharacterController2D（玩家角色）

```lua
-- JS 属性 → UrhoX 映射
-- sprite: string            → StaticSprite2D.sprite
-- size: Vector2             → CollisionBox2D:SetSize() 或 CollisionCircle2D.radius
-- speed: number             → 逻辑常量（米/秒）
-- jumpForce: number         → ApplyLinearImpulseToCenter 力度
-- gravityScale: number      → body.gravityScale
-- fixedRotation: boolean    → body.fixedRotation

local playerNode = scene_:CreateChild("Player")
playerNode:SetPosition2D(spawnX, spawnY)

-- 精灵
local sprite = playerNode:CreateComponent("StaticSprite2D")
sprite.sprite = cache:GetResource("Sprite2D", "Sprites/player.png")
sprite.blendMode = BLEND_ALPHA
sprite.layer = 10                          -- 玩家在较高层
sprite.orderInLayer = 0

-- 刚体
local body = playerNode:CreateComponent("RigidBody2D")
body.bodyType = BT_DYNAMIC
body.fixedRotation = true                  -- 不旋转
body.gravityScale = 1.0
body.linearDamping = 0.0
body.bullet = false                        -- 高速时改 true

-- 碰撞体（主体）
local bodyShape = playerNode:CreateComponent("CollisionBox2D")
bodyShape:SetSize(0.8, 1.6)               -- 宽×高（米）
bodyShape.density = 1.0
bodyShape.friction = 0.2
bodyShape.restitution = 0.0
bodyShape.categoryBits = 2                 -- CATEGORY_PLAYER
bodyShape.maskBits = 0xFFFF                -- 与所有碰撞

-- 脚底传感器（地面检测）
local footSensor = playerNode:CreateComponent("CollisionCircle2D")
footSensor.radius = 0.3
footSensor.center = Vector2(0, -0.75)      -- 偏移到脚底 ⚠️ 用 center，不是子节点
footSensor.trigger = true                   -- 传感器模式
footSensor.categoryBits = 4                -- CATEGORY_FOOT_SENSOR
footSensor.maskBits = 1                    -- 只检测地面
```

**移动/跳跃逻辑（Update 中）**：
```lua
-- 水平移动
local vel = body.linearVelocity
body.linearVelocity = Vector2(moveDir * speed, vel.y)

-- 跳跃（仅当 isGrounded）
body:ApplyLinearImpulseToCenter(Vector2(0, jumpForce), true)
```

### 4.4 Enemy2D（敌人）

```lua
-- JS 属性 → UrhoX 映射
-- sprite: string            → StaticSprite2D.sprite
-- patrol: boolean           → 逻辑：左右巡逻
-- patrolRange: number       → 巡逻范围（米）
-- speed: number             → 移动速度
-- damage: number            → 碰撞时的伤害值
-- health: number            → 逻辑变量

local enemyNode = scene_:CreateChild("Enemy")
enemyNode:SetPosition2D(posX, posY)

local sprite = enemyNode:CreateComponent("StaticSprite2D")
sprite.sprite = cache:GetResource("Sprite2D", "Sprites/enemy.png")
sprite.blendMode = BLEND_ALPHA
sprite.layer = 10

local body = enemyNode:CreateComponent("RigidBody2D")
body.bodyType = BT_DYNAMIC                 -- 或 BT_KINEMATIC（不受物理力）
body.fixedRotation = true
body.gravityScale = 1.0

local shape = enemyNode:CreateComponent("CollisionBox2D")
shape:SetSize(0.8, 0.8)
shape.density = 1.0
shape.friction = 0.3
shape.categoryBits = 8                     -- CATEGORY_ENEMY
shape.maskBits = 1 | 2                     -- 碰地面和玩家
```

**巡逻逻辑（Update 中）**：
```lua
-- Kinematic 巡逻
local pos = enemyNode:GetPosition2D()
if pos.x > spawnX + patrolRange then moveDir = -1 end
if pos.x < spawnX - patrolRange then moveDir = 1 end
body.linearVelocity = Vector2(moveDir * speed, body.linearVelocity.y)
sprite.flipX = (moveDir < 0)
```

### 4.5 Pickup2D（可拾取物）

```lua
-- JS 属性 → UrhoX 映射
-- sprite: string            → StaticSprite2D.sprite
-- type: string              → 自定义标识（"coin"/"health"/"key"）
-- value: number             → 拾取奖励值
-- bobAnimation: boolean     → 上下浮动动画

local pickupNode = scene_:CreateChild("Pickup_coin")
pickupNode:SetPosition2D(posX, posY)

local sprite = pickupNode:CreateComponent("StaticSprite2D")
sprite.sprite = cache:GetResource("Sprite2D", "Sprites/coin.png")
sprite.blendMode = BLEND_ALPHA
sprite.layer = 5

-- 静态刚体 + 触发器（检测但不阻挡）
local body = pickupNode:CreateComponent("RigidBody2D")
body.bodyType = BT_STATIC

local shape = pickupNode:CreateComponent("CollisionCircle2D")
shape.radius = 0.4
shape.trigger = true                       -- ⚠️ 关键：传感器模式
shape.categoryBits = 16                    -- CATEGORY_PICKUP
shape.maskBits = 2                         -- 只被玩家触发
```

**拾取逻辑（碰撞回调中）**：
```lua
function HandleCollision(eventType, eventData)
    local nodeA = eventData["NodeA"]:GetPtr("Node")
    local nodeB = eventData["NodeB"]:GetPtr("Node")
    -- 判断是否为 pickup + player 碰撞
    if isPickup(nodeA) then
        collectPickup(nodeA)
        nodeA:Remove()  -- 销毁
    end
end
```

### 4.6 TileMap2D（瓦片地图）

```lua
-- JS 属性 → UrhoX 映射
-- tmxFile: string           → TmxFile2D 资源路径
-- (或) tileData: array      → 需转成 .tmx 文件

local mapNode = scene_:CreateChild("TileMap")
local tileMap = mapNode:CreateComponent("TileMap2D")
tileMap.tmxFile = cache:GetResource("TmxFile2D", "Maps/level1.tmx")

-- 读取地图信息
local info = tileMap.info
-- info.width / info.height: 格子数
-- info.tileWidth / info.tileHeight: 格子世界尺寸（米）
-- info.mapWidth / info.mapHeight: 地图总世界尺寸（米）
-- info.orientation: O_ORTHOGONAL / O_ISOMETRIC / O_HEXAGONAL

-- 遍历对象层（放置敌人/拾取物等）
local numLayers = tileMap.numLayers
for i = 0, numLayers - 1 do
    local layer = tileMap:GetLayer(i)
    if layer.layerType == LT_OBJECT_GROUP then
        for j = 0, layer.numObjects - 1 do
            local obj = layer:GetObject(j)
            -- obj.name, obj.type, obj.position, obj.size
            -- 根据 type 生成对应游戏对象
        end
    end
end
```

**如果 JS 端用自定义格式而非 TMX**：
导出器需要生成 `.tmx` XML 文件到 assets 目录，或者用代码逐 tile 创建 StaticSprite2D：

```lua
-- 手动铺 tile（无 TMX 时的备选）
for row = 1, mapHeight do
    for col = 1, mapWidth do
        local tileId = tileData[row][col]
        if tileId > 0 then
            local tileNode = scene_:CreateChild("Tile")
            tileNode:SetPosition2D((col - 1) * tileSize, (row - 1) * tileSize)
            local spr = tileNode:CreateComponent("StaticSprite2D")
            spr.sprite = spriteSheet:GetSprite("tile_" .. tileId)
            spr.layer = 0
        end
    end
end
```

### 4.7 Platform2D（静态平台）

```lua
local platNode = scene_:CreateChild("Platform")
platNode:SetPosition2D(posX, posY)

-- 可选：带贴图
local sprite = platNode:CreateComponent("StaticSprite2D")
sprite.sprite = cache:GetResource("Sprite2D", "Sprites/platform.png")
sprite.blendMode = BLEND_ALPHA
sprite.layer = 0

-- 静态刚体（不动）
local body = platNode:CreateComponent("RigidBody2D")
body.bodyType = BT_STATIC

local shape = platNode:CreateComponent("CollisionBox2D")
shape:SetSize(4.0, 0.5)                   -- 平台宽×厚（米）
shape.friction = 0.6
shape.categoryBits = 1                     -- CATEGORY_GROUND
shape.maskBits = 0xFFFF
```

**移动平台**：改为 `BT_KINEMATIC`，在 Update 中改 position：
```lua
body.bodyType = BT_KINEMATIC
-- Update 中：
local t = math.sin(elapsedTime * speed) * range
platNode:SetPosition2D(startX + t, posY)
```

### 4.8 Projectile2D（子弹/弹射物）

```lua
local bulletNode = scene_:CreateChild("Bullet")
bulletNode:SetPosition2D(startX, startY)

local sprite = bulletNode:CreateComponent("StaticSprite2D")
sprite.sprite = cache:GetResource("Sprite2D", "Sprites/bullet.png")
sprite.blendMode = BLEND_ALPHA
sprite.layer = 15

local body = bulletNode:CreateComponent("RigidBody2D")
body.bodyType = BT_DYNAMIC
body.bullet = true                         -- ⚠️ CCD 防穿透
body.gravityScale = 0.0                    -- 子弹通常不受重力
body.fixedRotation = true

local shape = bulletNode:CreateComponent("CollisionCircle2D")
shape.radius = 0.1
shape.trigger = true                       -- 碰即销毁，不产生物理反弹
shape.categoryBits = 32                    -- CATEGORY_PROJECTILE
shape.maskBits = 1 | 8                     -- 碰地面和敌人

-- 发射
body.linearVelocity = Vector2(dirX * bulletSpeed, dirY * bulletSpeed)
```

### 4.9 AreaTrigger2D（触发区域）

```lua
-- 不可见区域，进入时触发事件（过关、剧情、伤害区等）
local triggerNode = scene_:CreateChild("Trigger_goal")
triggerNode:SetPosition2D(posX, posY)

local body = triggerNode:CreateComponent("RigidBody2D")
body.bodyType = BT_STATIC

local shape = triggerNode:CreateComponent("CollisionBox2D")
shape:SetSize(2.0, 3.0)
shape.trigger = true
shape.categoryBits = 64                    -- CATEGORY_TRIGGER
shape.maskBits = 2                         -- 只对玩家触发
```

### 4.10 ParticleEffect2D（2D 粒子）

```lua
-- 使用 Cocos2d plist 格式
local particleNode = scene_:CreateChild("Particles")
particleNode:SetPosition2D(posX, posY)

local emitter = particleNode:CreateComponent("ParticleEmitter2D")
emitter.effect = cache:GetResource("ParticleEffect2D", "Particles/fire.plist")
emitter.blendMode = BLEND_ADD
emitter.layer = 20
emitter.emitting = true
```

### 4.11 AnimatedSprite2D（骨骼动画角色）

```lua
-- Spine 动画
local charNode = scene_:CreateChild("AnimChar")
charNode:SetPosition2D(posX, posY)

local animSprite = charNode:CreateComponent("AnimatedSprite2D")
animSprite.animationSet = cache:GetResource("AnimationSet2D", "Spine/hero.json")
animSprite:SetAnimation("idle", LM_FORCE_LOOPED)
animSprite.speed = 1.0
animSprite.blendMode = BLEND_ALPHA
animSprite.layer = 10

-- 切换动画
animSprite:SetAnimation("run", LM_FORCE_LOOPED)
animSprite:SetAnimation("jump", LM_FORCE_CLAMPED)  -- 播一次
```

### 4.12 Sprite Sheet 帧动画（无骨骼）

```lua
-- 加载 sprite sheet
local sheet = cache:GetResource("SpriteSheet2D", "Sprites/player_sheet.xml")
-- 或代码定义：
local texture = cache:GetResource("Texture2D", "Sprites/player_sheet.png")
local sheet = SpriteSheet2D:new()
sheet:SetTexture(texture)
sheet:DefineSprite("idle_0", IntRect(0, 0, 64, 64), Vector2(0.5, 0.5))
sheet:DefineSprite("idle_1", IntRect(64, 0, 128, 64), Vector2(0.5, 0.5))
sheet:DefineSprite("idle_2", IntRect(128, 0, 192, 64), Vector2(0.5, 0.5))
-- ...

-- 帧动画逻辑（Update 中）
local frameTime = 0.1   -- 每帧时长（秒）
animTimer = animTimer + dt
if animTimer >= frameTime then
    animTimer = animTimer - frameTime
    currentFrame = (currentFrame % totalFrames) + 1
    sprite.sprite = sheet:GetSprite("idle_" .. (currentFrame - 1))
end
```

---

## 五、碰撞分类（categoryBits）建议

| 常量名 | 位值 | 用途 |
|--------|------|------|
| `CATEGORY_GROUND` | 1 (bit 0) | 地面/平台/墙壁 |
| `CATEGORY_PLAYER` | 2 (bit 1) | 玩家主体 |
| `CATEGORY_FOOT_SENSOR` | 4 (bit 2) | 玩家脚底传感器 |
| `CATEGORY_ENEMY` | 8 (bit 3) | 敌人 |
| `CATEGORY_PICKUP` | 16 (bit 4) | 可拾取物 |
| `CATEGORY_PROJECTILE` | 32 (bit 5) | 子弹/弹射物 |
| `CATEGORY_TRIGGER` | 64 (bit 6) | 触发区域 |
| `CATEGORY_ONEWAY` | 128 (bit 7) | 单向平台 |

**碰撞矩阵示例**：
```lua
-- 玩家碰地面、敌人、拾取物
playerShape.categoryBits = 2
playerShape.maskBits = 1 | 8 | 16 | 64    -- ground + enemy + pickup + trigger

-- 敌人碰地面和玩家
enemyShape.categoryBits = 8
enemyShape.maskBits = 1 | 2                -- ground + player

-- 拾取物只被玩家触发
pickupShape.categoryBits = 16
pickupShape.maskBits = 2                   -- player only
pickupShape.trigger = true
```

---

## 六、渲染层级（layer + orderInLayer）

| layer 值 | 用途 |
|----------|------|
| -10 | 远景背景（视差） |
| -5 | 近景背景 |
| 0 | 地图/平台 Tile |
| 5 | 拾取物/装饰 |
| 10 | 玩家/敌人 |
| 15 | 子弹/特效前景 |
| 20 | 粒子 |

同 layer 内用 `orderInLayer` 细排（值大的在前面）。

---

## 七、坐标系对照

| 概念 | JS 2D 引擎 (Canvas) | UrhoX 2D |
|------|---------------------|-----------|
| 原点 | 左上角 | 世界中心 (0,0) |
| Y 方向 | ↓ 向下为正 | ↑ 向上为正 |
| 单位 | 像素 (px) | 米 (m) |
| 旋转 | 顺时针为正 (rad) | 逆时针为正 (deg) |
| 相机 | viewport transform | Node position + orthoSize |

**导出器坐标转换公式**：
```javascript
// JS → UrhoX 坐标转换（在导出器 TypeScript 中）
function jsToUrho(jsX, jsY, pixelsPerUnit, canvasHeight) {
    const urhoX = jsX / pixelsPerUnit;
    const urhoY = (canvasHeight - jsY) / pixelsPerUnit;  // Y 翻转
    return { x: urhoX, y: urhoY };
}

// JS 旋转 → UrhoX 旋转
function jsRotToUrho(radians) {
    return -radians * (180 / Math.PI);  // 弧度→角度，方向取反
}

// JS 尺寸 → UrhoX 尺寸（只缩放，不翻转）
function jsSizeToUrho(widthPx, heightPx, pixelsPerUnit) {
    return {
        width: widthPx / pixelsPerUnit,
        height: heightPx / pixelsPerUnit
    };
}
```

---

## 八、物理关节（Joints）映射

| JS 概念 | UrhoX 组件 | 关键属性 |
|---------|-----------|---------|
| 弹簧连接 | `ConstraintDistance2D` | `ownerBodyAnchor`, `otherBodyAnchor`, `frequencyHz`, `dampingRatio` |
| 铰链/旋转轴 | `ConstraintRevolute2D` | `anchor`, `enableLimit`, `lowerAngle`, `upperAngle`, `enableMotor` |
| 滑轨 | `ConstraintPrismatic2D` | `anchor`, `axis`, `enableLimit`, `lowerTranslation`, `upperTranslation` |
| 绳索（最大长度） | `ConstraintRope2D` | `ownerBodyAnchor`, `otherBodyAnchor`, `maxLength` |
| 焊接（刚性） | `ConstraintWeld2D` | `anchor`, `frequencyHz`, `dampingRatio` |
| 滑轮 | `ConstraintPulley2D` | `ownerBodyGroundAnchor`, `otherBodyGroundAnchor`, `ratio` |
| 鼠标拖拽 | `ConstraintMouse2D` | `target`, `maxForce`, `frequencyHz`, `dampingRatio` |
| 车轮 | `ConstraintWheel2D` | `anchor`, `axis`, `frequencyHz`, `dampingRatio`, `enableMotor` |

```lua
-- 示例：绳索关节
local rope = nodeA:CreateComponent("ConstraintRope2D")
rope.otherBody = nodeB:GetComponent("RigidBody2D")
rope.ownerBodyAnchor = Vector2(0, -0.5)
rope.otherBodyAnchor = Vector2(0, 0.5)
rope.maxLength = 3.0
rope.collideConnected = false
```

---

## 九、Sprite Sheet XML 格式参考

UrhoX 支持的 SpriteSheet2D XML 格式：

```xml
<!-- assets/Sprites/player_sheet.xml -->
<SpriteSheet texture="player_sheet.png">
    <Sprite name="idle_0" x="0" y="0" width="64" height="64" hotSpotX="0.5" hotSpotY="0.5" />
    <Sprite name="idle_1" x="64" y="0" width="64" height="64" hotSpotX="0.5" hotSpotY="0.5" />
    <Sprite name="run_0" x="0" y="64" width="64" height="64" hotSpotX="0.5" hotSpotY="0.5" />
    <Sprite name="run_1" x="64" y="64" width="64" height="64" hotSpotX="0.5" hotSpotY="0.5" />
</SpriteSheet>
```

**导出器职责**：如果 JS 端有 spritesheet 定义，导出器需生成这个 XML 并放入 `assets/Sprites/` 目录。

---

## 十、TMX 地图文件格式参考

UrhoX 支持标准 Tiled 编辑器的 TMX 格式：

```xml
<?xml version="1.0" encoding="UTF-8"?>
<map version="1.0" orientation="orthogonal" width="40" height="20" tilewidth="1" tileheight="1">
    <tileset firstgid="1" name="tiles" tilewidth="64" tileheight="64">
        <image source="tileset.png" width="640" height="640"/>
    </tileset>
    <layer name="Ground" width="40" height="20">
        <data encoding="csv">
            1,1,1,0,0,2,2,2,...
        </data>
    </layer>
    <objectgroup name="Entities">
        <object name="player_spawn" type="spawn" x="128" y="256" width="64" height="64"/>
        <object name="enemy_1" type="enemy" x="512" y="256" width="64" height="64">
            <properties>
                <property name="patrol" value="true"/>
                <property name="speed" value="2.0"/>
            </properties>
        </object>
    </objectgroup>
</map>
```

**导出器职责**：如果 JS 端有 tilemap 数据，生成 `.tmx` 文件到 `assets/Maps/`。

---

## 十一、游戏逻辑脚本模板

```lua
-- Game2D_Logic.lua（游戏逻辑，由导出器生成或手写）

local Game = {}

-- 引用（由场景构建代码填充）
Game.player = nil         -- Node
Game.enemies = {}         -- Node[]
Game.pickups = {}         -- Node[]
Game.camera = nil         -- Node

-- 配置（从 JS 节点属性导出）
Game.playerSpeed = 5.0           -- 米/秒
Game.playerJumpForce = 7.0       -- 米/秒
Game.isGrounded = false

function Game.Init(scene, playerNode, cameraNode, enemies, pickups)
    Game.player = playerNode
    Game.camera = cameraNode
    Game.enemies = enemies
    Game.pickups = pickups
end

function Game.Update(dt)
    Game.UpdatePlayer(dt)
    Game.UpdateEnemies(dt)
    Game.UpdateCamera(dt)
end

function Game.UpdatePlayer(dt)
    local body = Game.player:GetComponent("RigidBody2D")
    local vel = body.linearVelocity

    -- 水平输入
    local moveX = 0
    if input:GetKeyDown(KEY_A) or input:GetKeyDown(KEY_LEFT) then moveX = -1 end
    if input:GetKeyDown(KEY_D) or input:GetKeyDown(KEY_RIGHT) then moveX = 1 end
    body.linearVelocity = Vector2(moveX * Game.playerSpeed, vel.y)

    -- 翻转精灵
    if moveX ~= 0 then
        local spr = Game.player:GetComponent("StaticSprite2D")
        spr.flipX = (moveX < 0)
    end

    -- 跳跃
    if Game.isGrounded and input:GetKeyPress(KEY_SPACE) then
        body:ApplyLinearImpulseToCenter(Vector2(0, Game.playerJumpForce), true)
        Game.isGrounded = false
    end
end

function Game.UpdateCamera(dt)
    if Game.camera and Game.player then
        local target = Game.player:GetPosition2D()
        local camPos = Game.camera:GetPosition2D()
        -- 平滑跟随
        local lerped = camPos + (target - camPos) * math.min(1.0, 5.0 * dt)
        Game.camera:SetPosition2D(lerped)
    end
end

function Game.UpdateEnemies(dt)
    for _, enemy in ipairs(Game.enemies) do
        -- 巡逻逻辑...
    end
end

function Game.OnCollision(nodeA, nodeB, shapeA, shapeB)
    -- 脚底传感器检测地面
    if isFootSensor(shapeA) or isFootSensor(shapeB) then
        Game.isGrounded = true
    end
    -- 拾取物
    if isPickup(nodeA) then nodeA:Remove() end
    if isPickup(nodeB) then nodeB:Remove() end
end

return Game
```

---

## 十二、导出器决策树

```
JS 2D 节点
  │
  ├─ GameScene2D ──────→ Scene + PhysicsWorld2D + Octree
  ├─ Camera2D ─────────→ Node + Camera(orthographic)
  ├─ TileMap2D ────────→ 生成 .tmx + Node + TileMap2D 组件
  ├─ CharacterController2D ─→ Node + Sprite + RigidBody2D(Dynamic) + Shape
  ├─ Enemy2D ──────────→ Node + Sprite + RigidBody2D(Dynamic/Kinematic) + Shape
  ├─ Pickup2D ─────────→ Node + Sprite + RigidBody2D(Static) + Shape(trigger)
  ├─ Platform2D ───────→ Node + Sprite + RigidBody2D(Static) + Shape
  ├─ MovingPlatform2D ─→ Node + Sprite + RigidBody2D(Kinematic) + Shape
  ├─ Projectile2D ─────→ Node + Sprite + RigidBody2D(Dynamic,bullet) + Shape(trigger)
  ├─ AreaTrigger2D ────→ Node + RigidBody2D(Static) + Shape(trigger)
  ├─ ParticleEffect2D ─→ Node + ParticleEmitter2D
  ├─ AnimatedSprite2D ─→ Node + AnimatedSprite2D(Spine)
  ├─ Sprite2D (静态) ──→ Node + StaticSprite2D
  │
  └─ UI 节点（保持现有逻辑）──→ urhox-libs/UI 组件
```

---

## 十三、关键注意事项

1. **单位是米** — 所有 position/size/velocity 都是米，不是像素。导出器必须除以 `pixelsPerUnit`。

2. **Y 轴翻转** — JS Canvas Y↓，UrhoX Y↑。`urhoY = (canvasHeight - jsY) / pixelsPerUnit`。

3. **碰撞体在同一节点** — 所有 CollisionShape 必须和 RigidBody2D 在同一个 Node 上，用 `center` 偏移，不能用子节点。

4. **数组索引从 1** — Lua 数组从 1 开始，循环用 `for i = 1, #array`。

5. **sprite 的 hotSpot** — `(0.5, 0.5)` = 中心对齐，`(0.5, 0)` = 底部中心。影响旋转和定位原点。

6. **layer 决定绘制顺序** — 小的先画（在后面），大的后画（在前面）。

7. **trigger vs 实体碰撞** — `trigger = true` 只触发事件不产生物理碰撞（用于拾取物、区域检测）。

8. **物理单位** — 力=牛顿，冲量=牛顿·秒，速度=米/秒，质量=千克。

9. **NanoVG 可选** — 如果 JS 端有自绘图形（Canvas drawImage/fillRect 之类），可以额外用 NanoVG 渲染，但一般推荐用 StaticSprite2D。

10. **UI 和 2D 场景共存** — UI.SetRoot() 设置的 UI 层浮在 2D 场景上方，用于 HUD/菜单/血条。

---

## 十四、音频系统（音效 / BGM）

### 14.1 资源格式

| 格式 | 扩展名 | 用途 |
|------|--------|------|
| OGG Vorbis | `.ogg` | BGM（流式加载，体积小） |
| WAV | `.wav` | 短音效（低延迟） |
| MP3 | `.mp3` | BGM 备选 |

### 14.2 播放音效（2D 无方位）

```lua
-- 方式1: 在指定节点上创建 SoundSource 组件
local soundNode = scene_:CreateChild("SFX")
local source = soundNode:CreateComponent("SoundSource")
source.soundType = "Effect"              -- 类型标签（用于分组音量控制）
source.gain = 0.8                        -- float: 音量 0.0~1.0
source.frequency = 44100                 -- float: 采样率（Hz），改变可变调
source.panning = 0.0                     -- float: 声像 -1.0(左) ~ 1.0(右)，0=居中
source.autoRemoveMode = REMOVE_COMPONENT -- 播完自动移除组件

local sound = cache:GetResource("Sound", "Sounds/jump.ogg")
sound.looped = false                     -- bool: 是否循环
source:Play(sound)

-- 方式2: 快速一次性播放（Play 重载）
source:Play(sound, 44100, 1.0, 0.0)
-- 参数: Sound*, frequency: float, gain: float, panning: float
```

### 14.3 播放 BGM（循环）

```lua
local musicNode = scene_:CreateChild("BGM")
local musicSource = musicNode:CreateComponent("SoundSource")
musicSource.soundType = "Music"          -- "Music" 类型
musicSource.gain = 0.5

local music = cache:GetResource("Sound", "Music/level1.ogg")
music.looped = true                      -- ⚠️ 循环必须在 Play 前设置
musicSource:Play(music)
```

### 14.4 SoundSource 完整属性

| 属性/方法 | 类型 | 说明 |
|-----------|------|------|
| `soundType` | `string` | 类型标签：`"Effect"` / `"Music"` / `"Ambient"` / 自定义 |
| `gain` | `float` | 音量 0.0~1.0 |
| `frequency` | `float` | 播放频率(Hz)，改变可变速/变调 |
| `panning` | `float` | 声像 -1.0(全左) ~ 0(中) ~ 1.0(全右) |
| `autoRemoveMode` | `enum` | 播完后行为：`REMOVE_DISABLED` / `REMOVE_COMPONENT` / `REMOVE_NODE` |
| `playing` | `bool` (readonly) | 是否正在播放 |
| `timePosition` | `float` (readonly) | 当前播放位置（秒） |
| `:Play(sound)` | method | 播放 |
| `:Stop()` | method | 停止 |
| `:Seek(time)` | method | 跳转到指定时间（秒） |

### 14.5 全局音量控制

```lua
-- audio 是全局子系统
audio:SetMasterGain("Effect", 0.8)       -- 所有 soundType="Effect" 的音源
audio:SetMasterGain("Music", 0.5)        -- 所有 soundType="Music" 的音源
audio:SetMasterGain("Master", 1.0)       -- 总音量

-- 暂停/恢复某类声音
audio:PauseSoundType("Music")            -- 暂停所有 BGM
audio:ResumeSoundType("Music")           -- 恢复
audio:ResumeAll()                        -- 恢复全部
```

### 14.6 autoRemoveMode 枚举

| 枚举值 | 效果 |
|--------|------|
| `REMOVE_DISABLED` | 播完后禁用组件（默认），节点保留 |
| `REMOVE_COMPONENT` | 播完后自动删除 SoundSource 组件 |
| `REMOVE_NODE` | 播完后删除整个节点（适合一次性音效节点） |

### 14.7 导出器映射

| JS 2D 节点属性 | UrhoX 映射 |
|---------------|-----------|
| `bgm: "level1.ogg"` | SoundSource + soundType="Music" + looped=true |
| `sfx: "jump.wav"` | SoundSource + soundType="Effect" + autoRemoveMode |
| `volume: 0.8` | source.gain = 0.8 |
| `loop: true` | sound.looped = true |
| `pan: -0.5` | source.panning = -0.5 |

---

## 十五、触摸与移动端输入

### 15.1 原生触摸 API

```lua
-- 获取当前触摸点数量
local numTouches = input.numTouches       -- unsigned: 当前手指数

-- 遍历所有触摸点
for i = 0, numTouches - 1 do              -- ⚠️ 注意：索引从 0 开始（C++ 绑定）
    local touch = input:GetTouch(i)
    -- touch 属性：
    -- touch.touchID    : int     — 唯一触摸 ID（跨帧追踪同一手指）
    -- touch.position   : IntVector2 — 当前屏幕像素坐标
    -- touch.lastPosition : IntVector2 — 上一帧位置
    -- touch.delta      : IntVector2 — 帧间移动量（像素）
    -- touch.pressure   : float   — 压力值（0.0~1.0，部分设备支持）
end
```

### 15.2 触摸事件订阅

```lua
-- 触摸开始
SubscribeToEvent("TouchBegin", function(eventType, eventData)
    local touchID = eventData["TouchID"]:GetInt()      -- int: 触摸 ID
    local x = eventData["X"]:GetInt()                  -- int: 屏幕 X（像素）
    local y = eventData["Y"]:GetInt()                  -- int: 屏幕 Y（像素）
    local pressure = eventData["Pressure"]:GetFloat()  -- float: 压力
end)

-- 触摸移动
SubscribeToEvent("TouchMove", function(eventType, eventData)
    local touchID = eventData["TouchID"]:GetInt()
    local x = eventData["X"]:GetInt()
    local y = eventData["Y"]:GetInt()
    local dx = eventData["DX"]:GetInt()                -- int: X 方向移动量
    local dy = eventData["DY"]:GetInt()                -- int: Y 方向移动量
    local pressure = eventData["Pressure"]:GetFloat()
end)

-- 触摸结束
SubscribeToEvent("TouchEnd", function(eventType, eventData)
    local touchID = eventData["TouchID"]:GetInt()
    local x = eventData["X"]:GetInt()
    local y = eventData["Y"]:GetInt()
end)
```

### 15.3 屏幕坐标 → 2D 世界坐标转换

```lua
--- 将屏幕像素坐标转换为 2D 物理世界坐标
---@param screenX number 屏幕 X 像素
---@param screenY number 屏幕 Y 像素
---@param camera Camera 正交相机组件
---@return number worldX, number worldY
function ScreenToWorld2D(screenX, screenY, camera)
    local graphics = GetSubsystem("Graphics")
    local screenW = graphics:GetWidth()
    local screenH = graphics:GetHeight()

    -- 归一化到 -1 ~ +1
    local ndcX = (screenX / screenW) * 2.0 - 1.0
    local ndcY = 1.0 - (screenY / screenH) * 2.0     -- Y 翻转

    local orthoSize = camera.orthoSize
    local aspect = screenW / screenH

    local camPos = camera.node.position
    local worldX = camPos.x + ndcX * orthoSize * aspect * 0.5
    local worldY = camPos.y + ndcY * orthoSize * 0.5

    return worldX, worldY
end
```

### 15.4 GameHUD 虚拟摇杆（推荐方案）

```lua
require "urhox-libs.UI.GameHUD"

function Start()
    GameHUD.Initialize()

    local hud = GameHUD.Create({
        enableJump = true,              -- bool: 显示跳跃按钮
        -- enableRun = true,            -- bool: 显示奔跑按钮
        -- enableShooter = true,        -- bool: 射击系统（装备/射击/换弹）
    })

    joystick_ = hud.joystick            -- 虚拟摇杆引用
    jumpButton_ = hud.jumpButton        -- 跳跃按钮引用
end

function HandleUpdate(eventType, eventData)
    -- 获取摇杆方向（自动处理死区 + Y 轴翻转）
    if joystick_ then
        local moveX, moveY = joystick_:getMovement()
        -- moveX: float -1.0~1.0  左负右正
        -- moveY: float -1.0~1.0  默认上正下负（已翻转）
        -- 2D 横版只用 moveX
    end

    -- 跳跃按钮状态
    if jumpButton_ and jumpButton_.isPressed then
        -- 跳跃
    end
end
```

### 15.5 摇杆 `getMovement(invertY)` 方法

| 参数 | 类型 | 默认 | 说明 |
|------|------|------|------|
| `invertY` | `bool` | `true` | `true`: 上推返回 +1（3D/数学坐标）；`false`: 上推返回 -1（屏幕坐标） |
| 返回值 | `float, float` | — | `x, y` 范围 -1.0 ~ 1.0，死区内返回 0 |

### 15.6 导出器映射

| JS 输入概念 | UrhoX 映射 |
|------------|-----------|
| 虚拟摇杆 (左半屏) | `GameHUD.Create()` → `joystick_:getMovement()` |
| 跳跃按钮 | `GameHUD.Create({enableJump=true})` → `jumpButton_.isPressed` |
| 触摸视角 (右半屏) | `GameHUD.EnableTouchLook({...})` |
| 点击/Tap | `TouchBegin` 事件 → `ScreenToWorld2D` 转坐标 |
| 拖拽 | `TouchMove` 事件 → delta 累计 |
| 多指缩放 | 双指距离变化 → 修改 `camera.orthoSize` |
| 键盘 (PC调试) | 摇杆自动内置 WASD 绑定，无需额外代码 |

---

## 十六、完整碰撞事件系统

### 16.1 全局碰撞事件

| 事件名 | 触发时机 | 关键字段 |
|--------|---------|---------|
| `PhysicsBeginContact2D` | 两个 fixture 开始接触 | NodeA, NodeB, BodyA, BodyB, ShapeA, ShapeB |
| `PhysicsEndContact2D` | 两个 fixture 分离 | NodeA, NodeB, BodyA, BodyB, ShapeA, ShapeB |

### 16.2 eventData 字段详解

| 字段 | 获取方式 | 类型 | 说明 |
|------|---------|------|------|
| `NodeA` | `eventData["NodeA"]:GetPtr("Node")` | `Node*` | 碰撞体 A 所在节点 |
| `NodeB` | `eventData["NodeB"]:GetPtr("Node")` | `Node*` | 碰撞体 B 所在节点 |
| `BodyA` | `eventData["BodyA"]:GetPtr("RigidBody2D")` | `RigidBody2D*` | 刚体 A |
| `BodyB` | `eventData["BodyB"]:GetPtr("RigidBody2D")` | `RigidBody2D*` | 刚体 B |
| `ShapeA` | `eventData["ShapeA"]:GetPtr("CollisionShape2D")` | `CollisionShape2D*` | 碰撞形状 A |
| `ShapeB` | `eventData["ShapeB"]:GetPtr("CollisionShape2D")` | `CollisionShape2D*` | 碰撞形状 B |

### 16.3 完整地面检测示例（Begin + End 配对）

```lua
local groundContactCount = 0             -- int: 当前接触地面的 shape 数量
local isGrounded = false                 -- bool: 是否着地

function Start()
    SubscribeToEvent("PhysicsBeginContact2D", "HandleBeginContact")
    SubscribeToEvent("PhysicsEndContact2D", "HandleEndContact")
end

function HandleBeginContact(eventType, eventData)
    local nodeA = eventData["NodeA"]:GetPtr("Node")
    local nodeB = eventData["NodeB"]:GetPtr("Node")
    local shapeA = eventData["ShapeA"]:GetPtr("CollisionShape2D")
    local shapeB = eventData["ShapeB"]:GetPtr("CollisionShape2D")

    -- 判断是否为脚底传感器碰到了地面
    if IsFootSensor(shapeA, shapeB) and IsGround(nodeA, nodeB) then
        groundContactCount = groundContactCount + 1
        isGrounded = true
    end
end

function HandleEndContact(eventType, eventData)
    local nodeA = eventData["NodeA"]:GetPtr("Node")
    local nodeB = eventData["NodeB"]:GetPtr("Node")
    local shapeA = eventData["ShapeA"]:GetPtr("CollisionShape2D")
    local shapeB = eventData["ShapeB"]:GetPtr("CollisionShape2D")

    if IsFootSensor(shapeA, shapeB) and IsGround(nodeA, nodeB) then
        groundContactCount = groundContactCount - 1
        if groundContactCount <= 0 then
            groundContactCount = 0
            isGrounded = false
        end
    end
end

-- 辅助：判断碰撞对中是否含脚底传感器
function IsFootSensor(shapeA, shapeB)
    return (shapeA.categoryBits == 4) or (shapeB.categoryBits == 4)
    -- CATEGORY_FOOT_SENSOR = 4
end

-- 辅助：判断碰撞对中是否含地面节点
function IsGround(nodeA, nodeB)
    return nodeA.name == "Ground" or nodeB.name == "Ground"
        or nodeA.name:find("Platform") ~= nil
        or nodeB.name:find("Platform") ~= nil
end
```

### 16.4 节点级碰撞事件（针对特定节点）

```lua
-- 只监听某个节点的碰撞（更高效，减少无关判断）
SubscribeToEvent(playerNode, "NodeBeginContact2D", "HandlePlayerContact")
SubscribeToEvent(playerNode, "NodeEndContact2D", "HandlePlayerContactEnd")

function HandlePlayerContact(eventType, eventData)
    -- 此处 NodeA 一定是 playerNode
    local otherNode = eventData["NodeB"]:GetPtr("Node")
    local otherBody = eventData["BodyB"]:GetPtr("RigidBody2D")
    -- ...
end
```

### 16.5 为什么需要 contactCount 而非 bool？

```
场景：玩家同时踩在两块平台的边缘
  ┌─────┐  ┌─────┐
  │ PlatA│  │ PlatB│
  └──┬───┘  └───┬──┘
     │  Player  │
     └──────────┘

BeginContact: PlatA → count=1, grounded=true
BeginContact: PlatB → count=2, grounded=true
EndContact:   PlatA → count=1, grounded=true  ← 如果用 bool 就错了
EndContact:   PlatB → count=0, grounded=false
```

---

## 十七、精灵缩放与世界尺寸映射

### 17.1 核心公式：PIXEL_SIZE

**UrhoX 2D 精灵的默认世界尺寸由 `PIXEL_SIZE` 常量决定**：

```
PIXEL_SIZE = 0.01  (引擎内置常量)

默认世界尺寸 = 像素尺寸 × PIXEL_SIZE
```

| 贴图像素 | 默认世界宽 (米) | 默认世界高 (米) |
|---------|---------------|---------------|
| 64 × 64 | 0.64 | 0.64 |
| 128 × 128 | 1.28 | 1.28 |
| 256 × 256 | 2.56 | 2.56 |
| 100 × 200 | 1.00 | 2.00 |

### 17.2 控制精灵世界尺寸的三种方式

#### 方式 A: 节点缩放（最常用）

```lua
-- 目标：让 128×128 的贴图在世界中显示为 1×1 米
-- 默认大小 = 128 * 0.01 = 1.28 米
-- 需要缩放 = 1.0 / 1.28 = 0.78125
local targetSize = 1.0                   -- 目标世界尺寸（米）
local pixelSize = 128                    -- 贴图像素宽
local scale = targetSize / (pixelSize * PIXEL_SIZE)
node.scale2D = Vector2(scale, scale)     -- 等比缩放
```

#### 方式 B: drawRect（精确控制世界矩形）

```lua
-- 直接指定精灵在世界中的绘制矩形（米）
local sprite = node:CreateComponent("StaticSprite2D")
sprite.sprite = cache:GetResource("Sprite2D", "Sprites/player.png")
sprite.useDrawRect = true                -- bool: 启用自定义绘制矩形
sprite.drawRect = Rect(-0.5, -0.5, 0.5, 0.5)  -- Rect(minX, minY, maxX, maxY) 米
-- 上面表示：宽1米、高1米，中心在节点原点
```

#### 方式 C: hotSpot（改变锚点，不改尺寸）

```lua
sprite.useHotSpot = true                 -- bool: 启用自定义锚点
sprite.hotSpot = Vector2(0.5, 0.0)       -- 底部中心对齐
-- hotSpot 取值 (0,0)=左下 (0.5,0.5)=正中 (1,1)=右上
```

### 17.3 导出器缩放计算公式

```javascript
// 在导出器 TypeScript 中计算 node.scale
const PIXEL_SIZE = 0.01;

function calcScale(jsWidthPx, jsHeightPx, textureWidthPx, textureHeightPx) {
    // JS 世界中物体的目标世界宽高（米）
    const targetW = jsWidthPx / PIXELS_PER_UNIT;
    const targetH = jsHeightPx / PIXELS_PER_UNIT;

    // 贴图默认世界宽高（米）
    const defaultW = textureWidthPx * PIXEL_SIZE;
    const defaultH = textureHeightPx * PIXEL_SIZE;

    return {
        scaleX: targetW / defaultW,
        scaleY: targetH / defaultH,
    };
}
```

### 17.4 StaticSprite2D 显示相关属性汇总

| 属性 | 类型 | 说明 |
|------|------|------|
| `sprite` | `Sprite2D*` | 精灵资源（含贴图 + 矩形 + hotSpot） |
| `blendMode` | `BlendMode` | 混合模式：`BLEND_ALPHA` / `BLEND_ADD` / `BLEND_MULTIPLY` |
| `color` | `Color` | 着色（乘算） `Color(1,1,1,1)` = 无着色 |
| `alpha` | `float` | 透明度 0.0~1.0 |
| `flipX` | `bool` | 水平翻转 |
| `flipY` | `bool` | 垂直翻转 |
| `layer` | `int` | 渲染层（大的在前） |
| `orderInLayer` | `int` | 同层内排序 |
| `useDrawRect` | `bool` | 是否使用自定义绘制矩形 |
| `drawRect` | `Rect` | 自定义绘制矩形 Rect(minX, minY, maxX, maxY) 米 |
| `useHotSpot` | `bool` | 是否使用自定义锚点 |
| `hotSpot` | `Vector2` | 锚点 (0,0)=左下 (0.5,0.5)=中心 |
| `customMaterial` | `Material*` | 自定义材质（着色器特效用） |

---

## 十八、单向平台实现

### 18.1 原理

单向平台 = 角色从下方可穿过，从上方落下时站住。

**实现策略**：在碰撞回调中，根据角色相对平台的 Y 位置动态启用/禁用碰撞。

### 18.2 方式 A: PreSolve 回调（推荐）

```lua
-- 订阅 PreSolve 事件（碰撞求解前，可取消碰撞）
SubscribeToEvent("PhysicsPreSolve2D", "HandlePreSolve")

function HandlePreSolve(eventType, eventData)
    local shapeA = eventData["ShapeA"]:GetPtr("CollisionShape2D")
    local shapeB = eventData["ShapeB"]:GetPtr("CollisionShape2D")
    local nodeA = eventData["NodeA"]:GetPtr("Node")
    local nodeB = eventData["NodeB"]:GetPtr("Node")

    -- 找出哪个是单向平台
    local platformNode, playerNode_local = nil, nil
    if nodeA.name:find("OneWay") then
        platformNode = nodeA
        playerNode_local = nodeB
    elseif nodeB.name:find("OneWay") then
        platformNode = nodeB
        playerNode_local = nodeA
    end

    if platformNode and playerNode_local then
        local playerBottom = playerNode_local.position2D.y - 0.8  -- 玩家脚底 Y
        local platformTop = platformNode.position2D.y + 0.25      -- 平台顶部 Y

        -- 玩家脚底低于平台顶部 → 穿过（禁用此次碰撞）
        if playerBottom < platformTop - 0.05 then
            -- 设置 contact 为 disabled
            eventData["Enabled"]:SetBool(false)
        end
    end
end
```

### 18.3 方式 B: maskBits 动态切换

```lua
-- 配置
local CATEGORY_ONEWAY = 128              -- bit 7
local CATEGORY_PLAYER = 2

-- 平台设置
onewayShape.categoryBits = CATEGORY_ONEWAY
onewayShape.maskBits = 2                 -- 只碰玩家

-- 玩家 shape 默认碰所有（含单向平台）
playerShape.maskBits = 0xFF              -- 含 CATEGORY_ONEWAY

-- Update 中动态切换
function HandleUpdate(eventType, eventData)
    local vel = playerBody.linearVelocity
    if vel.y > 0 then
        -- 上升中 → 不碰单向平台
        playerShape.maskBits = playerShape.maskBits & (~CATEGORY_ONEWAY)
    else
        -- 下落/静止 → 碰单向平台
        playerShape.maskBits = playerShape.maskBits | CATEGORY_ONEWAY
    end
end
```

### 18.4 方式 C: 下跳（按下+跳跃穿过平台）

```lua
-- 玩家按下键时临时关闭单向平台碰撞
function DropThroughPlatform()
    playerShape.maskBits = playerShape.maskBits & (~CATEGORY_ONEWAY)
    -- 0.3 秒后恢复
    dropTimer = 0.3
end

-- Update 中计时恢复
if dropTimer > 0 then
    dropTimer = dropTimer - dt
    if dropTimer <= 0 then
        playerShape.maskBits = playerShape.maskBits | CATEGORY_ONEWAY
    end
end
```

### 18.5 导出器映射

| JS 属性 | UrhoX 映射 |
|---------|-----------|
| `platform.oneWay = true` | 节点名含 "OneWay" + categoryBits = 128 |
| `platform.dropThrough = true` | 额外生成下跳逻辑代码 |

---

## 十九、射线检测（Raycast）

### 19.1 API 签名

```lua
-- 获取 PhysicsWorld2D 组件
local physicsWorld = scene_:GetComponent("PhysicsWorld2D")

-- 多结果射线（返回所有命中）
---@param startPoint Vector2  起点（世界坐标，米）
---@param endPoint Vector2    终点（世界坐标，米）
---@param collisionMask unsigned  碰撞掩码（只检测 categoryBits & mask != 0 的形状）
---@return PhysicsRaycastResult2D[]
local results = physicsWorld:Raycast(startPoint, endPoint, collisionMask)

-- 单结果射线（返回最近命中）
---@return PhysicsRaycastResult2D
local result = physicsWorld:RaycastSingle(startPoint, endPoint, collisionMask)
```

### 19.2 PhysicsRaycastResult2D 结构

| 字段 | 类型 | 说明 |
|------|------|------|
| `position` | `Vector2` | 命中点世界坐标（米） |
| `normal` | `Vector2` | 命中表面法线方向 |
| `distance` | `float` | 起点到命中点的距离（米） |
| `body` | `RigidBody2D*` | 被命中的刚体 |

### 19.3 使用示例

```lua
-- 示例1: 地面检测（向下射线）
local start = playerNode:GetPosition2D()
local endPt = start + Vector2(0, -1.5)   -- 向下 1.5 米
local result = physicsWorld:RaycastSingle(start, endPt, 1)  -- mask=1 只检测地面

if result.body ~= nil then
    local groundY = result.position.y
    local dist = result.distance
    -- 可用于斜坡对齐、悬崖检测等
end

-- 示例2: 视线检测（敌人是否看到玩家）
local enemyPos = enemyNode:GetPosition2D()
local playerPos = playerNode:GetPosition2D()
local result = physicsWorld:RaycastSingle(enemyPos, playerPos, 1 | 2)
-- mask = GROUND | PLAYER

if result.body ~= nil then
    local hitNode = result.body.node
    if hitNode == playerNode then
        -- 直接看到玩家（中间无遮挡）
        alertState = true
    else
        -- 被墙壁/地面挡住
    end
end

-- 示例3: 获取鼠标点击处的刚体
local body = physicsWorld:GetRigidBody(screenX, screenY, 0xFFFF)
-- 参数: int screenX, int screenY, unsigned collisionMask
-- 返回: RigidBody2D* 或 nil
```

### 19.4 区域查询（AABB）

```lua
-- 获取矩形区域内的所有刚体
---@param aabb Rect  矩形区域 Rect(minX, minY, maxX, maxY) 世界坐标
---@param collisionMask unsigned
---@return RigidBody2D[]
local bodies = physicsWorld:GetRigidBodies(Rect(-5, -5, 5, 5), 0xFFFF)

for i = 1, #bodies do
    local body = bodies[i]
    local node = body.node
    -- 处理区域内的刚体...
end
```

---

## 二十、场景切换与关卡加载

### 20.1 完全重建场景

```lua
-- 切换关卡：销毁旧场景，创建新场景
function LoadLevel(levelName)
    -- 1. 停止旧的事件监听
    UnsubscribeFromAllEvents()

    -- 2. 销毁旧场景
    if scene_ then
        scene_:Remove()
        scene_ = nil
    end

    -- 3. 创建新场景
    scene_ = Scene()
    scene_:CreateComponent("Octree")
    scene_:CreateComponent("PhysicsWorld2D")

    -- 4. 根据关卡名加载内容
    local levelModule = require("Levels/" .. levelName)
    levelModule.Build(scene_)

    -- 5. 设置新的 viewport
    local cameraNode = scene_:GetChild("Camera2D")
    local camera = cameraNode:GetComponent("Camera")
    renderer:SetViewport(0, Viewport:new(scene_, camera))

    -- 6. 重新订阅事件
    SubscribeToEvent("Update", "HandleUpdate")
    SubscribeToEvent("PhysicsBeginContact2D", "HandleBeginContact")
    SubscribeToEvent("PhysicsEndContact2D", "HandleEndContact")
end
```

### 20.2 保留 UI 层切换场景

```lua
-- UI 层独立于 Scene，切换场景不影响 HUD
function LoadLevel(levelName)
    -- UI.SetRoot 不受影响
    -- 只重建 2D 场景部分

    if scene_ then scene_:Remove() end
    scene_ = Scene()
    -- ... 重建场景 ...

    -- 更新 HUD 显示
    levelLabel:SetText("关卡: " .. levelName)
end
```

### 20.3 从 TMX 文件加载关卡

```lua
function LoadLevelFromTMX(tmxPath)
    local scene_ = Scene()
    scene_:CreateComponent("Octree")
    scene_:CreateComponent("PhysicsWorld2D")

    -- 加载瓦片地图
    local mapNode = scene_:CreateChild("TileMap")
    local tileMap = mapNode:CreateComponent("TileMap2D")
    tileMap.tmxFile = cache:GetResource("TmxFile2D", tmxPath)

    -- 从对象层生成游戏对象
    for i = 0, tileMap.numLayers - 1 do
        local layer = tileMap:GetLayer(i)
        if layer.layerType == LT_OBJECT_GROUP then
            for j = 0, layer.numObjects - 1 do
                local obj = layer:GetObject(j)
                SpawnObjectFromTMX(scene_, obj)
            end
        end
    end

    return scene_
end

function SpawnObjectFromTMX(scene_, obj)
    local objType = obj.type                -- string: TMX 中设置的 type
    local pos = obj.position                -- Vector2: 位置（已转为世界坐标）
    local size = obj.size                   -- Vector2: 尺寸

    if objType == "player_spawn" then
        CreatePlayer(scene_, pos)
    elseif objType == "enemy" then
        local speed = tonumber(obj:GetProperty("speed")) or 2.0
        CreateEnemy(scene_, pos, speed)
    elseif objType == "pickup" then
        local pickupType = obj:GetProperty("pickup_type") or "coin"
        CreatePickup(scene_, pos, pickupType)
    end
end
```

### 20.4 导出器映射

| JS 概念 | UrhoX 映射 |
|---------|-----------|
| `SceneManager.loadScene("level2")` | `LoadLevel("level2")` 函数 |
| 关卡列表 | 每个关卡一个 `.lua` 模块或 `.tmx` 文件 |
| 场景间数据传递 | 模块级变量或全局 table 存储（分数、生命等） |

---

## 二十一、自定义属性透传

### 21.1 问题

JS 2D 编辑器中，节点上可挂载任意自定义属性（如 `damage=10`, `aiType="patrol"`, `speed=3.5`）。  
UrhoX Node 没有通用的 `userData` 字典，需要选择合适的传递方式。

### 21.2 方案 A: 节点名编码（简单场景）

```lua
-- 导出器在节点名中编码属性
local node = scene_:CreateChild("Enemy_patrol_speed3.5_damage10")

-- 运行时解析
local name = node.name
local aiType = name:match("_(%a+)_speed")    -- "patrol"
local speed = tonumber(name:match("speed([%d%.]+)"))  -- 3.5
local damage = tonumber(name:match("damage(%d+)"))    -- 10
```

### 21.3 方案 B: Lua table 注册表（推荐）

```lua
-- 导出器生成一个数据注册表模块
-- 文件: scripts/LevelData.lua
local LevelData = {}

LevelData.nodes = {
    ["Enemy_001"] = {
        aiType = "patrol",          -- string: AI 类型
        speed = 3.5,                -- float: 移动速度（米/秒）
        damage = 10,                -- int: 碰撞伤害
        patrolRange = 4.0,          -- float: 巡逻范围（米）
        dropItems = {"coin", "gem"},-- string[]: 掉落物
    },
    ["Pickup_001"] = {
        pickupType = "coin",        -- string: 拾取物类型
        value = 5,                  -- int: 奖励值
        respawnTime = 10.0,         -- float: 重生时间（秒），0=不重生
    },
    ["Trigger_boss"] = {
        eventName = "start_boss",   -- string: 触发的事件名
        oneShot = true,             -- bool: 是否只触发一次
    },
}

return LevelData
```

```lua
-- 运行时读取
local LevelData = require("LevelData")

function GetNodeData(node)
    return LevelData.nodes[node.name]
end

-- 碰撞回调中使用
function HandleBeginContact(eventType, eventData)
    local nodeA = eventData["NodeA"]:GetPtr("Node")
    local dataA = GetNodeData(nodeA)
    if dataA and dataA.damage then
        playerHP = playerHP - dataA.damage
    end
end
```

### 21.4 方案 C: Node Vars（引擎原生 key-value）

```lua
-- Node 支持 SetVar/GetVar 存储 Variant 类型数据
local enemyNode = scene_:CreateChild("Enemy")

-- 设置自定义变量
enemyNode:SetVar("speed", Variant(3.5))          -- float
enemyNode:SetVar("damage", Variant(10))          -- int
enemyNode:SetVar("aiType", Variant("patrol"))    -- string

-- 读取
local speed = enemyNode:GetVar("speed"):GetFloat()     -- float
local damage = enemyNode:GetVar("damage"):GetInt()     -- int
local aiType = enemyNode:GetVar("aiType"):GetString()  -- string
```

**Variant 支持的类型**：

| Lua 构造 | 存储类型 |
|---------|---------|
| `Variant(3.5)` | float |
| `Variant(10)` | int |
| `Variant("text")` | string |
| `Variant(true)` | bool |
| `Variant(Vector2(1,2))` | Vector2 |
| `Variant(Vector3(1,2,3))` | Vector3 |
| `Variant(Color(1,0,0))` | Color |

### 21.5 三种方案对比

| 方案 | 优点 | 缺点 | 适用场景 |
|------|------|------|---------|
| A: 节点名编码 | 零开销、无额外文件 | 可读性差、解析脆弱 | 简单的 1-2 个属性 |
| B: Lua table | 类型安全、IDE 补全、批量管理 | 需额外模块文件 | **推荐**：复杂属性、大量节点 |
| C: Node Vars | 引擎原生、与节点生命周期绑定 | 无 IDE 补全、类型需 Get 方法 | 运行时动态添加属性 |

---

## 二十二、调试可视化

### 22.1 PhysicsWorld2D 调试绘制

```lua
-- 启用物理调试绘制
local physicsWorld = scene_:GetComponent("PhysicsWorld2D")
physicsWorld.drawShape = true             -- bool: 绘制碰撞形状轮廓
physicsWorld.drawJoint = true             -- bool: 绘制关节连接线
physicsWorld.drawAabb = false             -- bool: 绘制 AABB 包围盒
physicsWorld.drawPair = false             -- bool: 绘制碰撞对
physicsWorld.drawCenterOfMass = false     -- bool: 绘制质心点

-- 需要场景中有 DebugRenderer 组件
scene_:CreateComponent("DebugRenderer")
```

### 22.2 手动绘制调试信息

```lua
-- 订阅 PostRenderUpdate 事件绘制调试图形
SubscribeToEvent("PostRenderUpdate", "HandleDebugDraw")

function HandleDebugDraw(eventType, eventData)
    local debug = scene_:GetComponent("DebugRenderer")
    if not debug then return end

    -- 绘制物理世界（碰撞体 + 关节）
    physicsWorld:DrawDebugGeometry()

    -- 自定义绘制：
    -- 绘制线段
    debug:AddLine(
        Vector3(0, 0, 0),                -- 起点 (注意是 Vector3，Z=0)
        Vector3(5, 3, 0),                -- 终点
        Color(1, 0, 0),                  -- 颜色
        false                            -- depthTest
    )

    -- 绘制十字（标记位置）
    debug:AddCross(
        Vector3(posX, posY, 0),          -- 位置
        0.3,                             -- 大小（米）
        Color(0, 1, 0),                  -- 颜色
        false
    )

    -- 绘制圆圈
    debug:AddCircle(
        Vector3(posX, posY, 0),          -- 圆心
        Vector3(0, 0, 1),                -- 法线方向（Z 轴 = 面向屏幕）
        0.5,                             -- 半径（米）
        Color(1, 1, 0),                  -- 颜色
        32,                              -- 段数
        false
    )

    -- 绘制包围盒
    debug:AddBoundingBox(
        BoundingBox(Vector3(-1, -1, 0), Vector3(1, 1, 0)),
        Color(0, 0.5, 1),
        false
    )
end
```

### 22.3 运行时切换调试显示

```lua
local debugEnabled = false

function HandleUpdate(eventType, eventData)
    -- 按 Z 键切换调试绘制
    if input:GetKeyPress(KEY_Z) then
        debugEnabled = not debugEnabled
        physicsWorld.drawShape = debugEnabled
        physicsWorld.drawJoint = debugEnabled
    end
end
```

### 22.4 PhysicsWorld2D 调试属性汇总

| 属性 | 类型 | 默认 | 说明 |
|------|------|------|------|
| `drawShape` | `bool` | `false` | 碰撞形状（绿=静态/蓝=动态/灰=休眠） |
| `drawJoint` | `bool` | `false` | 关节连接线 |
| `drawAabb` | `bool` | `false` | AABB 包围盒（紫色） |
| `drawPair` | `bool` | `false` | 碰撞对（当前接触中的形状对） |
| `drawCenterOfMass` | `bool` | `false` | 刚体质心位置 |

### 22.5 导出器建议

导出器可生成 debug 模式开关：

```lua
-- 生成的代码头部
local DEBUG_PHYSICS = false              -- 发布时改为 false

if DEBUG_PHYSICS then
    scene_:CreateComponent("DebugRenderer")
    physicsWorld.drawShape = true
    physicsWorld.drawJoint = true
end
```
