# 布局器导出 vs 实际运行修复 — 对比与导出器改进建议

> **目的**：对比布局器原始导出代码（`docs/2d像素瓦片/sce-lua/scripts/`）和实际可正确运行的代码（`scripts/`），
> 列出每一处必要的运行时修正，并给出导出器侧应如何修改的建议。

---

## 一、文件对照总览

| 文件 | 导出原始版本 | 运行修正版本 | 主要差异 |
|------|-------------|-------------|---------|
| `main.lua` | 109 行 | 118 行 | 相机 orthoSize 改为动态计算 |
| `scene2d_2D瓦片庭院.lua` | 223 行 | 252 行 | +Props 渲染、+边界墙、碰撞体缩小 |
| `logic_2D瓦片庭院.lua` | 465 行 | 467 行 | 几乎无差异（仅注释微调） |

---

## 二、逐项修正对比

---

### 2.1 相机 orthoSize：固定值 → 动态计算

**问题**：导出器输出固定 `orthoSize = 4.16`（= mapH），在横屏设备上若 aspect > mapW/mapH，
两侧会出现黑边（相机视野高度锁定，但宽度不够覆盖地图）。

#### 导出器原始代码（main.lua:68）

```lua
camera.orthoSize = 4.16
```

#### 运行修正代码（main.lua:68-70）

```lua
local mapW, mapH = 6.4, 4.16
local aspect = graphics.width / graphics.height
camera.orthoSize = math.min(mapH, mapW / aspect)
```

#### 修正原理

- `mapW / aspect` = 让地图宽度恰好填满视口所需的 orthoSize
- `math.min(mapH, mapW / aspect)` = 取两者较小值，保证地图在任何 aspect 下都不会出现黑边
- 窄屏（手机竖屏）→ `mapW/aspect > mapH` → 用 `mapH`（高度锁定，宽度自然够）
- 宽屏（PC/平板横屏）→ `mapW/aspect < mapH` → 用更小值（宽度锁定，高度可能裁切顶底少量草地）

#### 导出器改进建议

导出器在生成 main.lua 的相机初始化段时：

```lua
-- 导出器应生成以下模板：
local mapW, mapH = ${sceneWidth}, ${sceneHeight}  -- 从场景配置读取
local aspect = graphics.width / graphics.height
camera.orthoSize = math.min(mapH, mapW / aspect)
```

其中 `sceneWidth` / `sceneHeight` 从瓦片地图的 `cols * tileW * PIXEL_SIZE` 和 `rows * tileW * PIXEL_SIZE` 计算得出。

---

### 2.2 Props（装饰道具）渲染 — 导出器完全缺失

**问题**：布局器中放置了 14 个 Props（植物、道具、建筑装饰），但导出器没有生成任何 Props 渲染代码。
原因是这些素材没有预制 `.xml` SpriteSheet，只能通过 `textureRect` UV 裁剪从图集中提取。

#### 导出器原始代码

**无**（完全缺失 Props 段）

#### 运行修正代码（scene2d:81-138）

```lua
-- Props（植物/道具/建筑）— textureRect UV 裁剪
do
    local props = {
        -- {id, w(px), h(px), left(px), top(px), tex, bgSizePx, bgPosX(CSS负), bgPosY(CSS负)}
        { "panel_gep19dky", 82.95, 102.41, 36.87, 40.96, "image/topdown-basic/TX_Plant.png", 369, -17, -10 },
        -- ... 共 14 个 props
    }

    local ORIGIN_Y = 4.16
    local TEX_NATIVE = 512

    for _, p in ipairs(props) do
        local id, pw, ph, pleft, ptop, texPath, bgSize, bgPosX, bgPosY = ...

        -- 1. CSS 像素坐标 → 世界坐标（中心点）
        local worldX = pleft * 0.01 + pw * 0.005
        local worldY = ORIGIN_Y - (ptop * 0.01 + ph * 0.005)

        -- 2. CSS background-size/position → 源纹理 IntRect
        local scale = TEX_NATIVE / bgSize
        local srcX = (-bgPosX) * scale
        local srcY = (-bgPosY) * scale
        local srcW = pw * scale
        local srcH = ph * scale

        -- 3. StaticSprite2D + drawRect + textureRect
        local spr = n:CreateComponent("StaticSprite2D")
        spr.useDrawRect = true
        spr.drawRect = Rect(-pw * 0.005, -ph * 0.005, pw * 0.005, ph * 0.005)
        spr.useTextureRect = true
        -- UV 计算（引擎约定：V=0 图片顶部，V=1 图片底部）
        local u0 = srcX / TEX_NATIVE
        local u1 = (srcX + srcW) / TEX_NATIVE
        local vForTop = srcY / TEX_NATIVE
        local vForBot = (srcY + srcH) / TEX_NATIVE
        spr.textureRect = Rect(u0, vForBot, u1, vForTop)  -- Rect(left, vBot, right, vTop)
    end
end
```

#### 修正原理

1. **坐标转换**：CSS 左上角原点 → UrhoX 左下角原点，Y 需翻转
2. **UV 裁剪**：CSS `background-size` + `background-position` 的负值 → 纹理像素偏移
3. **V 轴翻转**：UrhoX Rect 的 V 坐标系与 CSS 相反，`Rect(u0, v_bottom, u1, v_top)`

#### 导出器改进建议

导出器需要新增一个 **Props 渲染段生成器**，处理流程：

```
对每个 Props 元素:
  1. 检查是否有对应 .xml SpriteSheet
     ├─ 有 → 使用 .xml 方案（与角色相同）
     └─ 无 → 使用 textureRect UV 裁剪方案

textureRect 方案需要导出器提供：
  - id: 节点唯一标识
  - width/height (CSS px): 元素可视尺寸
  - left/top (CSS px): 元素在画布中的位置
  - texturePath: 源图集路径
  - bgSize (CSS px): background-size 值（控制缩放比）
  - bgPosX/bgPosY (CSS px, 负值): background-position 偏移

UV 计算公式（写入模板）:
  scale = TEX_NATIVE / bgSize
  srcX = (-bgPosX) * scale
  srcY = (-bgPosY) * scale
  srcW = width * scale
  srcH = height * scale
  u0 = srcX / TEX_NATIVE
  u1 = (srcX + srcW) / TEX_NATIVE
  vTop = srcY / TEX_NATIVE
  vBot = (srcY + srcH) / TEX_NATIVE
  textureRect = Rect(u0, vBot, u1, vTop)   -- V 翻转！
```

**注意**：`TEX_NATIVE` 应从实际纹理文件读取（可能不是 512），或导出器在编辑时记录纹理原始尺寸。

---

### 2.3 角色/敌人碰撞体 — 尺寸过大需缩小

**问题**：导出器生成的碰撞体尺寸等于角色 drawRect 的视觉大小，导致：
- 玩家感觉"还没碰到就被打了"
- 走廊过窄、无法通过明显有空间的缝隙
- 碰撞手感差，不符合 2D 俯视角游戏惯例

#### 导出器原始代码

```lua
-- 敌人碰撞体（scene2d:172）
shape:SetSize(0.5735, 0.6964)   -- 接近 drawRect 全尺寸

-- 玩家碰撞体（scene2d:189）
shape:SetSize(0.8193, 0.8193)   -- 等于 drawRect 全尺寸
```

#### 运行修正代码

```lua
-- 敌人碰撞体（scene2d:213）
shape:SetSize(0.35, 0.35)       -- 约 50% 视觉尺寸
shape:SetCenter(0, -0.10)       -- 向下偏移（碰撞判定对准脚部）

-- 玩家碰撞体（scene2d:228）
shape:SetSize(0.40, 0.40)       -- 约 49% 视觉尺寸
shape:SetCenter(0, -0.12)       -- 向下偏移（碰撞判定对准脚部）
```

#### 修正原理

俯视角 2D 游戏的标准做法：
1. **碰撞体 = 视觉尺寸的 40%~60%**：给玩家"擦边"的感觉，提升操作手感
2. **center 向下偏移**：角色精灵通常以中心为锚点，但"脚底"才是实际占地位置。碰撞体下移让判定更符合直觉

#### 导出器改进建议

导出器应提供碰撞体缩放系数配置（而非直接使用 drawRect 尺寸）：

```javascript
// 导出器内部配置（建议可在 UI 中暴露给用户调整）
const COLLISION_SCALE = {
    player: 0.49,    // 玩家碰撞体 = drawRect * 0.49
    enemy:  0.43,    // 敌人碰撞体 = drawRect * 0.43
    npc:    0.50,    // NPC 碰撞体 = drawRect * 0.50
}
const COLLISION_CENTER_OFFSET_Y = -0.12  // 所有角色碰撞体向下偏移（占 drawRect 高度的比例）
```

导出器生成代码模板：

```lua
-- 替代原来的: shape:SetSize(drawW, drawH)
local collisionScale = ${COLLISION_SCALE}
local offsetY = ${CENTER_OFFSET_Y}
shape:SetSize(drawW * collisionScale, drawH * collisionScale)
shape:SetCenter(0, offsetY)
```

---

### 2.4 地图边界墙 — 导出器缺失

**问题**：玩家/敌人可以走出地图可视范围（瓦片地图外围是草地装饰，无物理阻挡）。

#### 导出器原始代码

**无**（完全缺失边界墙）

#### 运行修正代码（scene2d:169-189）

```lua
-- 地图边界碰撞墙
do
    local wallThick = 0.4
    local mapW, mapH = 6.4, 4.16
    -- 可行走区域边界（= 石墙内侧边缘）
    local minX, maxX = 0.96, 5.44
    local minY, maxY = 0.32, 3.84
    local walls = {
        { (minX - wallThick / 2), mapH / 2, wallThick, mapH },   -- 左墙
        { (maxX + wallThick / 2), mapH / 2, wallThick, mapH },   -- 右墙
        { mapW / 2, (maxY + wallThick / 2), mapW, wallThick },   -- 上墙
        { mapW / 2, (minY - wallThick / 2), mapW, wallThick },   -- 下墙
    }
    for i, w in ipairs(walls) do
        local n = scene_:CreateChild("boundary_wall_" .. i)
        n:SetPosition2D(w[1], w[2])
        local body = n:CreateComponent("RigidBody2D")
        body.bodyType = BT_STATIC
        local shape = n:CreateComponent("CollisionBox2D")
        shape:SetSize(w[3], w[4])
        shape.categoryBits = 1
        shape.maskBits = 65535
        n:SetVar("tag", Variant("wall"))
    end
end
```

#### 导出器改进建议

导出器应在识别到瓦片地图的"墙壁层"或"边界"时自动生成 4 面边界碰撞墙：

```
逻辑：
1. 从瓦片数据中分析可行走区域范围（非墙壁瓦片的 AABB）
2. 或从用户在编辑器中标记的"可行走区域"矩形读取 minX/maxX/minY/maxY
3. 在四边生成 BT_STATIC + CollisionBox2D 的隐形墙节点

参数：
- wallThick: 0.4（固定，或可配置）
- categoryBits: 1（与障碍物同类）
- maskBits: 65535（阻挡一切）
- tag: "wall"
```

如果编辑器暂不支持自动检测可行走区域，至少应提供一个"边界矩形"配置项让用户手动指定。

---

### 2.5 Props Colliders — 独立碰撞节点循环生成（代码整洁度）

**问题**：导出器为每个 Props 碰撞体生成了独立的 `do...end` 块，共 8 个块、每块 12 行代码 = 96 行重复代码。

#### 导出器原始代码（scene2d:72-152，共 80 行）

```lua
do
    local n = scene_:CreateChild("collider2d_vxld7di3")
    n:SetPosition2D(0.7886, 2.8595)
    nodes["collider2d_vxld7di3"] = n
    local body = n:CreateComponent("RigidBody2D")
    body.bodyType = BT_STATIC
    local shape = n:CreateComponent("CollisionBox2D")
    shape:SetSize(0.2253, 0.1843)
    shape.categoryBits = 1
    shape.maskBits = 65535
    shape.density = 1.0
    n:SetVar("tag", Variant("obstacle"))
end
-- 重复 8 次...
```

#### 运行修正代码（scene2d:141-163，共 22 行）

```lua
do
    local colliders = {
        { "collider2d_vxld7di3", 0.7886, 2.8595, 0.2253, 0.1843 },
        { "collider2d_qq438qgo", 5.6735, 2.8799, 0.2048, 0.1843 },
        -- ... 共 8 条
    }
    for _, c in ipairs(colliders) do
        local cid, cx, cy, cw, ch = c[1], c[2], c[3], c[4], c[5]
        local n = scene_:CreateChild(cid)
        n:SetPosition2D(cx, cy)
        nodes[cid] = n
        local body = n:CreateComponent("RigidBody2D")
        body.bodyType = BT_STATIC
        local shape = n:CreateComponent("CollisionBox2D")
        shape:SetSize(cw, ch)
        shape.categoryBits = 1
        shape.maskBits = 65535
        shape.density = 1.0
        n:SetVar("tag", Variant("obstacle"))
    end
end
```

#### 导出器改进建议

对于同类型的批量节点（Colliders、Pickups、Portals 等），导出器应生成**数据表 + 循环**的紧凑形式，而非逐个展开。

好处：
- 代码量减少 70%+
- 新增/删除碰撞体只改数据行，不改模板逻辑
- 方便运行时动态查询

---

## 三、不需要修正的部分（导出器已正确处理）

| 功能 | 状态 | 说明 |
|------|------|------|
| 角色 .xml SpriteSheet 引用 | ✅ 正确 | `cache:GetResource("SpriteSheet2D", "image/Sprites/Orc_Idle.xml")` |
| 瓦片 data 编码 (tsetIdx*65536 + tileIdx) | ✅ 正确 | 紧凑高效 |
| PhysicsWorld2D gravity=0 (俯视角) | ✅ 正确 | topdown 模式无重力 |
| logic.lua 完整游戏循环 | ✅ 正确 | 玩家/敌人/子弹/计时/碰撞/动画 全流程 |
| GameHUD 集成（摇杆+按钮） | ✅ 正确 | 已正确传递 joystick/jumpButton/shootButton |

### ⚠️ 重要修正：瓦片渲染方案

| 功能 | 状态 | 说明 |
|------|------|------|
| TileMap2D `SpriteSheet2D:new()` | ❌ **不可用** | 引擎不暴露此构造函数，运行时报 `nil value` |
| TileMap2D `SpriteSheet2D()` | ❌ **不可用** | 报 `Attempt to call a non-callable object` |

**正确方案**：瓦片也使用 `Sprite2D + textureRect UV 裁剪`（与 Props 相同方式），详见 2.6 节。

---

## 四、改进优先级建议

| 优先级 | 修正项 | 影响 | 工作量 |
|--------|--------|------|--------|
| **P0** | **瓦片渲染方案替换** | **崩溃！SpriteSheet2D:new() 不存在** | 中（替换为 textureRect） |
| P0 | Props textureRect 渲染 | 场景缺少装饰，视觉不完整 | 中（需新增模板段） |
| P0 | 动态 orthoSize | 横屏黑边，不可接受 | 小（改一行模板） |
| P1 | 碰撞体缩放 + center 偏移 | 手感差，但能玩 | 小（加缩放系数） |
| P1 | 边界墙生成 | 角色可走出地图 | 小（加 4 面墙模板） |
| P2 | Collider 数据表紧凑化 | 代码可读性 | 小（改生成模板） |

---

---

### 2.6 瓦片渲染 — SpriteSheet2D:new() 不存在，必须替换

**问题**：导出器生成 `SpriteSheet2D:new()` 程序化创建 SpriteSheet，但 UrhoX Lua 绑定**不暴露此构造函数**。
运行时直接崩溃：`attempt to call a nil value (method 'new')`。
尝试 `SpriteSheet2D()` 也不行：`Attempt to call a non-callable object`。

> **注意**：`cache:GetResource("SpriteSheet2D", "xxx.xml")` 加载已有的 .xml 文件是可以的（角色用的就是这个），
> 但程序化创建新的 SpriteSheet2D 实例不可能。

#### 导出器原始代码（崩溃）

```lua
local sheet = SpriteSheet2D:new()       -- ❌ nil!
sheet:SetTexture(tex)
sheet:DefineSprite(name, IntRect(...))
return sheet:GetSprite(name)
```

#### 运行修正代码（textureRect 方案）

```lua
-- 预加载纹理信息
local tilesetInfo = {}
for idx, path in ipairs(tilesets) do
    local tex = cache:GetResource("Texture2D", path)
    local spr = cache:GetResource("Sprite2D", path)
    if tex and spr then
        tilesetInfo[idx] = {
            sprite = spr,
            texW = tex:GetWidth(),
            texH = tex:GetHeight(),
            tileCols = math.max(1, math.floor(tex:GetWidth() / tileSize))
        }
    end
end

-- 渲染每个瓦片
local info = tilesetInfo[tsetIdx]
local sx = (tileIdx % info.tileCols) * tileSize
local sy = math.floor(tileIdx / info.tileCols) * tileSize

local u0 = sx / info.texW
local u1 = (sx + tileSize) / info.texW
local vForTop = sy / info.texH
local vForBot = (sy + tileSize) / info.texH

local s = t:CreateComponent("StaticSprite2D")
s:SetSprite(info.sprite)
s.useDrawRect = true
s.drawRect = Rect(-halfTile, -halfTile, halfTile, halfTile)
s.useTextureRect = true
s.textureRect = Rect(u0, vForBot, u1, vForTop)  -- V: bottom 在前，top 在后
```

#### 修正原理

与 Props 完全相同的 textureRect UV 裁剪方案：
1. 加载完整纹理为 `Sprite2D`（通过 cache，共享同一实例）
2. 同时加载 `Texture2D` 获取纹理像素尺寸
3. 对每个瓦片计算其在图集中的像素位置，转换为归一化 UV
4. 用 `useDrawRect + useTextureRect` 控制显示区域和 UV 区域

#### 导出器改进建议

导出器应**废弃 `SpriteSheet2D:new()` 方案**，改为生成以下模板：

```lua
-- 导出器模板：瓦片渲染
local tilesetInfo = {}
for idx, path in ipairs(tilesets) do
    local tex = cache:GetResource("Texture2D", path)
    local spr = cache:GetResource("Sprite2D", path)
    if tex and spr then
        tilesetInfo[idx] = {
            sprite = spr,
            texW = tex:GetWidth(),
            texH = tex:GetHeight(),
            tileCols = math.max(1, math.floor(tex:GetWidth() / ${tileSize}))
        }
    end
end

-- 每个瓦片：
local info = tilesetInfo[tsetIdx]
local sx = (tileIdx % info.tileCols) * ${tileSize}
local sy = math.floor(tileIdx / info.tileCols) * ${tileSize}
s:SetSprite(info.sprite)
s.useDrawRect = true
s.drawRect = Rect(-${halfTile}, -${halfTile}, ${halfTile}, ${halfTile})
s.useTextureRect = true
s.textureRect = Rect(sx/info.texW, (sy+${tileSize})/info.texH, (sx+${tileSize})/info.texW, sy/info.texH)
```

**UV 约定**：`Rect(u_left, v_bottom, u_right, v_top)` — 引擎中 V=0 对应图片顶部，V=1 对应图片底部，
Rect 第2参数（较大V值）放 bottom，第4参数（较小V值）放 top。

---

## 五、textureRect UV 公式速查（供导出器开发者参考）

```
输入（来自 CSS/编辑器）:
  - element.width, element.height     (CSS px, 元素可视尺寸)
  - element.left, element.top         (CSS px, 画布位置)
  - background-image                   (纹理路径)
  - background-size                    (CSS px, 通常 < TEX_NATIVE 表示缩小显示)
  - background-position-x/y            (CSS px, 负值表示向左/上偏移)

常量:
  - PIXEL_SIZE = 0.01                  (1 CSS px = 0.01 世界米)
  - TEX_NATIVE                         (纹理原始宽高，通常 512px)
  - ORIGIN_Y = mapHeight               (地图高度，Y 翻转锚点)

坐标转换:
  worldX = left * 0.01 + width * 0.005           (中心 X)
  worldY = ORIGIN_Y - (top * 0.01 + height * 0.005)  (中心 Y, 翻转)

UV 计算:
  scale = TEX_NATIVE / bgSize
  srcX = (-bgPosX) * scale
  srcY = (-bgPosY) * scale
  srcW = width * scale
  srcH = height * scale

  u0 = srcX / TEX_NATIVE
  u1 = (srcX + srcW) / TEX_NATIVE
  vTop = srcY / TEX_NATIVE              (纹理空间顶部 V)
  vBot = (srcY + srcH) / TEX_NATIVE     (纹理空间底部 V)

UrhoX StaticSprite2D 设置:
  spr.useDrawRect = true
  spr.drawRect = Rect(-width*0.005, -height*0.005, width*0.005, height*0.005)
  spr.useTextureRect = true
  spr.textureRect = Rect(u0, vBot, u1, vTop)     -- ⚠️ V 翻转: bottom 在前！
  spr.blendMode = BLEND_ALPHA
  spr.layer = 5                                   -- Props 在 tiles(0) 之上、角色(10) 之下
```

---

*文档版本: v1.0 | 生成日期: 2026-06-02*
