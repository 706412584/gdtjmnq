---
name: spriteflow
description: 2D 像素角色动作图集生成与切帧流水线。用户要做 sprite sheet、角色待机/行走/攻击/死亡动作、像素动画、AI 生成动作帧、抠背景、切帧、导出 UrhoX Sprite2D XML、把 SpriteFlow/网页插件转成可运行工具时必须使用。适合 “生成角色动画图集”“切 spritesheet”“去背景”“导入 2D 像素角色动画”“gpt-iamge2 生成精灵帧” 等需求。
---

# SpriteFlow — UrhoX 2D 像素动作图集流水线

这个 skill 把 SpriteFlow 的网页/React 原型转换成项目可运行流程：

1. 用统一提示词生成 spritesheet。
2. 对整张图做抠背景 / chroma key。
3. 按网格切成单帧 PNG。
4. 生成 UrhoX 可读取的 `Sprite2D` XML。
5. 输出诊断信息，检查帧占用率、空帧、偏移和网格一致性。

当前项目内原 TS/TSX 文件可作为插件参考；可运行能力优先使用 `scripts/spriteflow_cli.py`。

## 触发后先做

1. 读取 `PROJECT_RULES.md`：图片生成统一使用 `gpt-iamge2`。
2. 如要生成图片，优先调用项目提供的图片生成工具，并显式选择 `model="gpt"`。
3. 如用户已有 spritesheet，只运行本 skill 的 CLI 进行抠背景、切帧、导出 XML。
4. 输出文件放到 `assets/image/Sprites/<name>/` 或用户指定目录。
5. 修改项目 Lua 后按规则 LSP + build + Git；仅切图/生成资源时无需改 Lua，但仍建议提交 Git。

## 推荐输出结构

```text
assets/image/Sprites/<name>/
  sheet.png                 -- 原图或处理后图集
  frames/
    <name>_idle_01.png
    <name>_idle_02.png
  <name>_Idle.xml           -- Sprite2D XML
  diagnostic.json           -- 切帧诊断
```

## 生成提示词原则

项目图片统一用 `gpt-iamge2`。提示词包含：

- pixel art / strict grid aligned
- transparent background 或 chroma key background
- no anti-aliasing, no blur, no shadows
- same character every frame
- fixed camera and consistent scale
- clear action phases
- 方向：right / left / front / back / isometric
- 网格：row 1×N 或 square N×N

动作约束：

- idle：身体/肩膀/呼吸有微变化，相邻帧不能完全相同。
- walk/run：腿脚接地点必须交替，不用速度线、尘土、影子伪装运动。
- attack：蓄力、主击、跟随、收招清晰，特效必须贴附武器或身体。
- death：重心逐帧下降，不用漂浮符号。

## CLI 用法

```bash
python3 .agent/skills/spriteflow/scripts/spriteflow_cli.py \
  --input assets/image/Sprites/farmer_sheet.png \
  --output assets/image/Sprites/farmer \
  --name Farmer \
  --action Walk \
  --layout row \
  --cols 8 \
  --rows 1 \
  --key-color '#00FF00' \
  --tolerance 48 \
  --make-xml
```

常用参数：

| 参数 | 说明 |
|---|---|
| `--input` | 输入 spritesheet PNG |
| `--output` | 输出目录 |
| `--name` | 角色/资源名 |
| `--action` | 动作名，如 Idle/Walk/Attack |
| `--layout` | `row` 或 `square` |
| `--cols` / `--rows` | 网格列数/行数 |
| `--frame-count` | 只导出前 N 帧 |
| `--key-color` | 抠背景颜色，如 `#00FF00` |
| `--tolerance` | 抠色容差，默认 36 |
| `--content-band` | 对单行图集先检测内容带再切帧 |
| `--make-xml` | 生成 UrhoX Sprite2D XML |

## 质量诊断

CLI 会输出：

- 每帧非透明像素占比 `occupancy`
- 内容中心偏移 `centerOffsetX/Y`
- 空帧 / 极低占用警告
- 帧尺寸和切片矩形

处理建议：

- 空帧：重新生成图集或检查网格参数。
- 占用率过低：角色太小，提示词加 “character fills 70% of each cell”。
- 中心偏移大：提示词加 “feet aligned to same baseline, centered in every cell”。
- 抠色破坏角色：换 key color 或降低 tolerance；避免角色使用接近 key color 的颜色。

## UrhoX 导入规则

- 资源路径从 ResourceCache 根开始，不加 `assets/` 前缀。
- Lua 中加载 Sprite2D 示例：

```lua
local sprite = cache:GetResource("Sprite2D", "image/Sprites/Farmer/Farmer_Walk.xml")
local spr = node:CreateComponent("StaticSprite2D")
spr:SetSprite(sprite)
```

- 如果用单张 sheet + `textureRect` 动画，也可只导出 frames，按 `urhox-2d-pixel-tile` 的 spritesheet 分帧方式播放。

## 与 2D 瓦片 skill 配合

- 本 skill 负责角色/怪物/特效图集资源。
- `urhox-2d-pixel-tile` 负责 2D Scene、相机、碰撞、瓦片、HUD。
- 角色碰撞体尺寸不要直接按 PNG 像素猜，导入后在米制世界里设置 `CollisionBox2D`。

## 插件化说明

`.agent/skills/spriteflow/*.tsx` 是网页面板/编辑器插件参考，不直接在 UrhoX 运行时执行。若用户要求“做编辑器插件”，再基于这些 TSX 文件接入对应编辑器构建系统；若只是要生成游戏资源，使用本 skill 的 CLI 更稳定。

## 验证清单

- [ ] 输入图存在且能被 PIL 打开。
- [ ] 网格参数与图集一致。
- [ ] 输出 frames 数量正确。
- [ ] 抠背景后 alpha 正常。
- [ ] diagnostic 没有空帧或严重偏移。
- [ ] XML 资源路径不包含 `assets/` 前缀。
- [ ] 如资源被 Lua 引用，运行 LSP 和官方 build。
