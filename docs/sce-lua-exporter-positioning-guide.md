# SCE Lua 导出器 — UrhoX UI 定位字段参考

> 给布局器/导出器开发者的引擎定位能力文档。
> 基于 `urhox-libs/UI/Core/Widget.lua` 源码实测确认。

---

## 一、定位字段完整支持表

### 1.1 Yoga 布局字段（影响布局计算）

| Props 字段 | Yoga API | 支持百分比 | 说明 |
|-----------|----------|-----------|------|
| `position` | `SetPositionType` | — | `"relative"` / `"absolute"` / `"fixed"` |
| `left` | `SetPosition(EdgeLeft, v)` | ✅ `"50%"` | 距父容器左边 |
| `top` | `SetPosition(EdgeTop, v)` | ✅ | 距父容器顶部 |
| `right` | `SetPosition(EdgeRight, v)` | ✅ | 距父容器右边 |
| `bottom` | `SetPosition(EdgeBottom, v)` | ✅ | 距父容器底部 |
| `width` | `SetWidth(v)` / `SetWidthAuto` | ✅ | 也支持 `"auto"` |
| `height` | `SetHeight(v)` / `SetHeightAuto` | ✅ | 也支持 `"auto"` |
| `minWidth` / `maxWidth` | `SetMinWidth` / `SetMaxWidth` | ✅ | |
| `minHeight` / `maxHeight` | `SetMinHeight` / `SetMaxHeight` | ✅ | |
| `margin` / `marginTop` 等 | `SetMargin(Edge, v)` | ✅ | 支持 per-side |
| `padding` / `paddingTop` 等 | `SetPadding(Edge, v)` | ✅ | 支持 per-side |
| `flexBasis` | `SetFlexBasis(v)` | ✅ | |
| `flexGrow` | `SetFlexGrow(v)` | — | |
| `flexShrink` | `SetFlexShrink(v)` | — | 默认 0 |
| `alignSelf` | `SetAlignSelf(v)` | — | 覆盖父的 alignItems |
| `gap` / `rowGap` / `columnGap` | `SetGap(v)` | ✅ | |
| `overflow` | `SetOverflow(v)` | — | `"visible"` / `"hidden"` / `"scroll"` |

### 1.2 Flexbox 容器字段（父容器控制子节点）

| 字段 | 可选值 |
|------|--------|
| `flexDirection` | `"row"`, `"column"`, `"row-reverse"`, `"column-reverse"` |
| `justifyContent` | `"flex-start"`, `"center"`, `"flex-end"`, `"space-between"`, `"space-around"`, `"space-evenly"` |
| `alignItems` | `"flex-start"`, `"center"`, `"flex-end"`, `"stretch"`, `"baseline"` |
| `flexWrap` | `"nowrap"`, `"wrap"`, `"wrap-reverse"` |

### 1.3 视觉变换字段（不影响布局）

| 字段 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `translateX` | number | 0 | X 位移（基础像素，受 UI scale 缩放） |
| `translateY` | number | 0 | Y 位移 |
| `scale` | number | 1.0 | 等比缩放 |
| `rotate` | number | 0 | 旋转角度（度） |
| `transformOrigin` | string / table | `"center"` | `"center"`, `"top-left"`, `"top"`, `"bottom"`, `"left"`, `"right"`, `{x, y}` |
| `opacity` | number | 1.0 | 透明度 0~1，影响子树 |

---

## 二、三种 position 模式

### `position = "relative"`（默认）

- 参与父容器 Flexbox 布局流
- `left`/`top`/`right`/`bottom` 作为相对偏移（offset）

### `position = "absolute"`

- 脱离流，相对于最近的**父容器**定位
- 支持 `left` + `top`（左上锚定）
- 支持 `right` + `bottom`（右下锚定）
- 支持百分比 `left = "50%"`
- ⚠️ 同时设置 `left` + `right` 时，Yoga 会计算隐含宽度（类似 CSS）

### `position = "fixed"`

- 脱离整棵 UI 树，相对于**视口**定位
- `right`/`bottom` 由引擎手动计算为 `viewport - size - value`
- ⚠️ **fixed 模式不支持百分比**，只接受数值
- 适用于：全局浮动按钮、Toast、常驻 HUD

---

## 三、象限锚定映射方案

导出器根据子节点在设计画布中的位置，判定锚定象限后，输出对应字段：

| 象限 | 判定条件（示例：1920×1080 画布） | 导出字段 |
|------|-------------------------------|---------|
| 左上 | x < 1920×0.3, y < 1080×0.3 | `left` + `top` |
| 右上 | x > 1920×0.7, y < 1080×0.3 | `right` + `top`（right = 画布宽 - x - width） |
| 左下 | x < 1920×0.3, y > 1080×0.7 | `left` + `bottom`（bottom = 画布高 - y - height） |
| 右下 | x > 1920×0.7, y > 1080×0.7 | `right` + `bottom` |
| 水平居中 | abs(x + width/2 - 960) < 阈值 | `left = "50%"` + `translateX = -width/2` |
| 垂直居中 | abs(y + height/2 - 540) < 阈值 | `top = "50%"` + `translateY = -height/2` |
| 正中央 | 水平 + 垂直均居中 | 父容器 `justifyContent="center", alignItems="center"` |
| 默认/中间区 | 不满足任何边缘条件 | 保持 `left` + `top`（安全回退） |

### 根容器导出

```lua
-- 响应式根容器（替代固定 1920×1080）
UI.Panel {
    width = "100%",
    height = "100%",
    backgroundColor = PAGE_BG_COLOR,
}
```

### 居中子节点

```lua
-- 方案 A：absolute + 百分比 + translate
UI.Panel {
    position = "absolute",
    left = "50%",
    top = "50%",
    translateX = -width / 2,
    translateY = -height / 2,
    width = width,
    height = height,
}

-- 方案 B：父容器 flex 居中（更简洁，适合单个居中子节点）
UI.Panel {
    width = "100%",
    height = "100%",
    justifyContent = "center",
    alignItems = "center",
    children = { child }
}
```

### 右下角浮动按钮

```lua
-- absolute 方式（相对父容器）
UI.Panel {
    position = "absolute",
    right = 40,
    bottom = 40,
    width = 120,
    height = 48,
}

-- fixed 方式（相对视口，不受父容器滚动影响）
UI.Panel {
    position = "fixed",
    right = 40,
    bottom = 40,
    width = 120,
    height = 48,
}
```

---

## 四、缩放适配策略

导出器应根据用户选择的适配模式，生成对应的 `scale` 函数：

| 选项 | scale 函数 | 适用场景 |
|------|-----------|---------|
| 完整显示 (Contain) | `math.min(W/designW, H/designH)` | 不裁切，可能有边距 |
| 填满裁切 (Cover) | `math.max(W/designW, H/designH)` | 填满，溢出裁切 |
| 横向铺满 (MatchWidth) | `W / designW` | 横版游戏，高度可能不足 |
| 纵向铺满 (MatchHeight) | `H / designH` | 竖版游戏，宽度可能不足 |

**Contain 模式建议搭配居中 wrapper**：

```lua
UI.Init({
    scale = function()
        return math.min(graphics.width / DESIGN_W, graphics.height / DESIGN_H)
    end,
})

-- 根节点用全屏背景居中内容
UI.SetRoot(UI.Panel {
    width = "100%",
    height = "100%",
    backgroundColor = PAGE_BG_COLOR,
    justifyContent = "center",
    alignItems = "center",
    children = { pageContent }
})
```

---

## 五、已知问题与导出建议

### 5.1 ShapeLine placeholder 溢出

- **问题**：placeholder Label 放在 5.62px 高容器内，文字溢出覆盖内容
- **建议**：不生成 placeholder children，或加 `overflow = "hidden"`

### 5.2 lineHeight 单位错误

- **问题**：CSS `line-height: 101px` 直接除以 fontSize 输出为 `lineHeight = 5.539`
- **引擎行为**：lineHeight 是倍数，5.539 × fontSize = 行高远超容器
- **建议**：
  - 识别 CSS 垂直居中 hack（line-height ≈ container-height）→ 输出 `verticalAlign = "middle"`
  - 真实行距需求 → 限制在 1.0~3.0 范围

### 5.3 多行文本高度不足

- **问题**：含 `\n` 的文本，height 只按单行计算
- **建议**：`height = lineCount × fontSize × lineHeight`，或不输出 height 让引擎自动撑高

### 5.4 screen_orientation 不匹配

- **问题**：横版设计导出 portrait
- **建议**：根据画布宽高比自动判定（width > height → landscape）

---

## 六、引擎不支持的字段（导出器应跳过）

| CSS 属性 | 引擎状态 | 替代方案 |
|---------|---------|---------|
| `transform: translateX(...)` CSS 字符串 | ❌ 不解析 CSS transform 字符串 | 用结构化 `translateX` / `translateY` 数值字段 |
| `box-shadow` CSS 字符串 | ❌ 崩溃 | 用结构化 `boxShadow = { {x,y,blur,spread,color,inset} }` |
| `linear-gradient(...)` CSS 字符串 | ❌ 不解析 | 用结构化 `backgroundGradient = {type,direction,from,to}` |
| `text-shadow` | ❌ 不支持 | 无替代 |
| `filter: blur(...)` | ❌ 不支持 | 无替代 |
| `z-index` | ❌ 不支持 | 调整 children 顺序（后面的在上面） |
| `cursor` | ❌ 不支持 | — |
| `transition` CSS 字符串 | ❌ 不解析 | 用结构化 `transition = { property, duration, easing }` |

---

*最后更新: 2025-05-30*
*基于: urhox-libs/UI/Core/Widget.lua, Style.lua, UI.lua 源码*
