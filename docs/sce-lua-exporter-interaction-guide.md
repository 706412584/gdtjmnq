# SCE Lua 导出器 — UrhoX UI 事件/交互/动画/生命周期参考

> 定位相关见 `sce-lua-exporter-positioning-guide.md`。
> 样式相关见 `sce-lua-exporter-styling-guide.md`。
> 本文档覆盖事件绑定、手势识别、过渡动画、关键帧动画和组件生命周期。

---

## 一、事件系统总览

### 1.1 事件分类

| 类别 | 事件 | 触发时机 |
|------|------|---------|
| 指针事件 | `onPointerEnter/Leave/Down/Up/Move/Cancel` | 鼠标/触摸原始事件 |
| 手势事件 | `onTap/DoubleTap/LongPress/Swipe/Pan/Pinch` | 手势识别器判定后 |
| 焦点事件 | `onFocus/onBlur` | 获得/失去键盘焦点 |
| 组件专属 | `onClick/onChange/onSubmit/onScroll` 等 | 特定组件的交互事件 |

### 1.2 事件传播

- 事件沿 widget 树**从子向父冒泡**
- 调用 `event:StopPropagation()` 可阻止冒泡
- 调用 `event:PreventDefault()` 可阻止默认行为

---

## 二、通用指针事件（所有 Widget）

所有 UI 组件（Panel、Label、Button、Image 等）均支持以下指针事件：

```lua
UI.Panel {
    onPointerEnter  = function(event, widget) end,   -- 指针进入命中区域
    onPointerLeave  = function(event, widget) end,   -- 指针离开命中区域
    onPointerDown   = function(event, widget) end,   -- 按下（鼠标/触摸）
    onPointerUp     = function(event, widget) end,   -- 释放
    onPointerMove   = function(event, widget) end,   -- 移动（追踪中）
    onPointerCancel = function(event, widget) end,   -- 指针序列被取消
}
```

### 2.1 PointerEvent 字段

| 字段 | 类型 | 说明 |
|------|------|------|
| `type` | string | `"PointerDown"`, `"PointerUp"`, `"PointerMove"`, `"PointerEnter"`, `"PointerLeave"`, `"PointerCancel"` |
| `pointerId` | number | 每个触摸手指/鼠标的唯一 ID |
| `pointerType` | string | `"mouse"`, `"touch"`, `"pen"` |
| `x`, `y` | number | **widget 局部坐标系**中的位置 |
| `button` | number | 哪个鼠标按钮（仅鼠标） |
| `buttons` | number | 当前按住的所有按钮位掩码 |
| `pressure` | number | 0.0–1.0 压力值 |
| `isPrimary` | boolean | 是否是主指针（第一个触摸或鼠标左键） |
| `deltaX`, `deltaY` | number | 距上次事件的移动量 |
| `timestamp` | number | 事件时间（ms） |
| `target` | Widget | 接收事件的原始 widget |
| `currentTarget` | Widget | 当前正在执行回调的 widget |

### 2.2 PointerEvent 方法

```lua
event:IsPrimaryAction()    -- 触摸: 始终 true；鼠标: 仅左键为 true
event:StopPropagation()    -- 阻止冒泡
event:PreventDefault()     -- 阻止默认行为
```

---

## 三、手势事件（所有 Widget）

手势识别器在指针事件基础上判定手势类型，识别后触发回调。

```lua
UI.Panel {
    -- 点击
    onClick          = function(widget, event) end,   -- ⚠️ 参数顺序相反！
    onTap            = function(event, widget) end,
    onDoubleTap      = function(event, widget) end,

    -- 长按
    onLongPress      = function(event, widget) end,   -- 到达阈值时触发
    onLongPressStart = function(event, widget) end,   -- 同 onLongPress
    onLongPressEnd   = function(event, widget) end,   -- 手指抬起时触发

    -- 滑动（快速划过）
    onSwipe          = function(event, widget) end,   -- 任意方向
    onSwipeLeft      = function(event, widget) end,
    onSwipeRight     = function(event, widget) end,
    onSwipeUp        = function(event, widget) end,
    onSwipeDown      = function(event, widget) end,

    -- 拖拽（持续移动）
    onPan            = function(event, widget) end,   -- 等同 onPanMove
    onPanStart       = function(event, widget) end,
    onPanMove        = function(event, widget) end,
    onPanEnd         = function(event, widget) end,

    -- 捏合缩放（多指）
    onPinch          = function(event, widget) end,   -- 等同 onPinchMove
    onPinchStart     = function(event, widget) end,
    onPinchMove      = function(event, widget) end,
    onPinchEnd       = function(event, widget) end,
}
```

### 3.1 onClick 的特殊参数顺序

```lua
-- ⚠️ onClick 参数顺序是 (widget, event?)，与其他手势回调 (event, widget) 相反！
onClick = function(widget, event)
    -- widget: 被点击的组件实例
    -- event: 可能为 nil
end

-- 其他所有手势回调的参数顺序为：
onTap = function(event, widget)
    -- event: GestureEvent 对象
    -- widget: 触发的组件实例
end
```

### 3.2 GestureEvent 字段

| 字段 | 类型 | 适用手势 | 说明 |
|------|------|---------|------|
| `type` | string | 所有 | 手势类型名 |
| `x`, `y` | number | 所有 | 手势发生位置 |
| `target` | Widget | 所有 | 命中测试的目标 widget |
| `pointerId` | number | 所有 | |
| `pointerType` | string | 所有 | `"mouse"` 或 `"touch"` |
| `timestamp` | number | 所有 | ms |
| `tapCount` | number | Tap/DoubleTap | 1 或 2 |
| `direction` | string | Swipe/Pan | `"Left"`, `"Right"`, `"Up"`, `"Down"`, `"None"` |
| `velocity` | number | Swipe | px/ms |
| `distance` | number | Swipe/Pan | 总距离 |
| `deltaX`, `deltaY` | number | Pan | 帧间增量 |
| `totalDeltaX`, `totalDeltaY` | number | Pan | 从起始点的累计增量 |
| `scale` | number | Pinch | 相对于起始的缩放比 |
| `centerX`, `centerY` | number | Pinch | 双指中点 |
| `duration` | number | LongPress | 已按住的时间（ms） |

### 3.3 GestureEvent 方法

```lua
event:StopPropagation()         -- 阻止冒泡
event:IsPropagationStopped()    -- 是否已阻止
event:IsTap()                   -- 是否为 Tap 类型
event:IsSwipe()                 -- 是否为 Swipe 类型
event:IsPan()                   -- 是否为 Pan 类型
event:IsLongPress()             -- 是否为长按类型
event:IsPinch()                 -- 是否为捏合类型
event:IsHorizontalSwipe()       -- 水平滑动
event:IsVerticalSwipe()         -- 垂直滑动
```

### 3.4 手势识别阈值

| 参数 | 默认值 | 说明 |
|------|--------|------|
| `tapMaxDuration` | 300 ms | 超过则不算 Tap |
| `tapMaxDistance` | 10 px | 移动超过则不算 Tap |
| `doubleTapMaxInterval` | 300 ms | 两次 Tap 间隔上限 |
| `doubleTapMaxDistance` | 30 px | 两次 Tap 位置容差 |
| `longPressMinDuration` | 500 ms | 长按最低时长 |
| `longPressMaxDistance` | 10 px | 移动超过则取消长按 |
| `swipeMinDistance` | 50 px | 滑动最小距离 |
| `swipeMaxDuration` | 500 ms | 滑动必须在此时间内完成 |
| `swipeMinVelocity` | 0.3 px/ms | 滑动最低速度 |
| `panMinDistance` | 5 px | 拖拽启动阈值 |
| `pinchMinDistance` | 10 px | 捏合启动阈值 |

---

## 四、焦点事件

```lua
UI.Panel {
    onFocus = function(widget) end,   -- 获得键盘焦点
    onBlur  = function(widget) end,   -- 失去键盘焦点
}
```

注意：`onFocus`/`onBlur` 的回调只接收 `widget` 一个参数，不包含 event 对象。

---

## 五、组件专属事件

### 5.1 Button

```lua
UI.Button {
    onClick  = function(widget, event) end,   -- ⚠️ widget 在前，event 在后
    disabled = false,                         -- true 时 onClick 不触发
}
```

Button 状态相关的 props（用于自动过渡）：
- `hoverBackgroundColor` — 悬停时的背景色（自动由 `backgroundColor` 加亮 15% 派生）
- `pressedBackgroundColor` — 按下时的背景色（自动由 `backgroundColor` 加深 20% 派生）
- `disabledBackgroundColor` — 禁用时的背景色
- `hoverBackgroundImage` / `pressedBackgroundImage` / `disabledBackgroundImage`
- `hoverBackgroundGradient` / `pressedBackgroundGradient`

### 5.2 Slider

```lua
UI.Slider {
    onChange    = function(self, value) end,   -- 拖拽过程中每次值变化触发
    onChangeEnd = function(self, value) end,  -- 拖拽结束时触发一次
    value = 0,
    min   = 0,
    max   = 100,
    step  = 1,
}
```

### 5.3 TextField（文本输入）

```lua
UI.TextField {
    onChange = function(self, value) end,   -- 每次按键/粘贴时触发
    onSubmit = function(self, value) end,   -- 按下 Enter 键触发
    onFocus  = function(self) end,          -- 获得焦点（覆盖通用 onFocus）
    onBlur   = function(self) end,          -- 失去焦点（覆盖通用 onBlur）
    value       = "",
    placeholder = "",
    maxLength   = nil,
    password    = false,
    multiline   = false,
    readOnly    = false,
    autoFocus   = false,
}
```

### 5.4 Toggle（开关）

```lua
UI.Toggle {
    onChange = function(self, value) end,   -- value: boolean
    value    = false,
    disabled = false,
}
```

### 5.5 Checkbox（复选框）

```lua
UI.Checkbox {
    onChange = function(self, checked) end,   -- checked: boolean
    checked  = false,
    disabled = false,
}
```

### 5.6 Dropdown（下拉菜单）

```lua
UI.Dropdown {
    onChange = function(self, value, option) end,
    options = {
        { value = "a", label = "选项 A" },
        { value = "b", label = "选项 B", disabled = true },
    },
    value       = nil,
    placeholder = "请选择...",
}
-- option 参数是选中的 { value, label, disabled } 表
```

### 5.7 ScrollView（滚动容器）

```lua
UI.ScrollView {
    onScroll = function(self, scrollX, scrollY) end,
    scrollX             = false,    -- 启用水平滚动
    scrollY             = true,     -- 启用垂直滚动
    showScrollbar       = true,
    scrollbarInteractive = false,   -- 可拖拽滚动条
    bounces             = true,     -- iOS 风格弹性回弹
    scrollSnapType      = nil,      -- "y mandatory"|"y proximity"|"x mandatory"|"x proximity"
}
```

ScrollView 公开方法：
```lua
sv:ScrollBy(dx, dy)        -- 相对滚动
sv:SetScroll(x, y)         -- 绝对滚动
sv:GetScroll()             -- 返回 scrollX, scrollY
sv:ScrollToTop()
sv:ScrollToBottom()
sv:GetContentSize()        -- 返回内容 width, height
```

子元素的 ScrollSnap：
```lua
UI.Panel {
    scrollSnapAlign = "start",   -- "start"|"center"|"end"
}
```

粘性头部：
```lua
UI.Panel {
    position     = "sticky",
    stickyOffset = 0,   -- 距容器顶部的偏移量
}
```

---

## 六、动态事件绑定（OnEvent / OffEvent）

除了在构造时通过 props 声明事件回调外，也可以在运行时动态添加/移除事件监听：

```lua
-- 添加事件监听
widget:OnEvent("click", function(widget, event) end)
widget:OnEvent("pointerenter", function(event, widget) end)
widget:OnEvent("swipeleft", function(event, widget) end)

-- 移除特定监听器
widget:OffEvent("click", specificHandler)

-- 移除某事件的所有监听器
widget:OffEvent("click")
```

### 6.1 所有支持的事件名称

```
pointerenter, pointerleave, pointerdown, pointerup, pointermove, pointercancel,
click, tap, doubletap,
longpressstart, longpressend,
swipe, swipeleft, swiperight, swipeup, swipedown,
panstart, panmove, panend,
pinchstart, pinchmove, pinchend,
focus, blur
```

### 6.2 导出器建议

对于布局编辑器导出，事件绑定建议使用 props 声明式写法：

```lua
-- ✅ 推荐：声明式（导出器易生成）
UI.Button {
    id = "btn_start",
    onClick = function(widget) end,
}

-- ✅ 也可以：运行时绑定（适合动态场景）
local btn = root:FindById("btn_start")
btn:OnEvent("click", function(widget, event) end)
```

---

## 七、过渡动画（Transition）

### 7.1 transition 属性

任何 widget 都可通过 `transition` 属性声明属性变化时的过渡动画：

```lua
UI.Panel {
    opacity = 1,
    transition = "opacity 0.3s easeOut",
}

-- 之后通过 SetStyle 改变 opacity，会自动过渡动画
panel:SetStyle({ opacity = 0 })   -- 0.3s 从 1 淡出到 0
```

### 7.2 transition 格式

```lua
-- 单属性字符串
transition = "opacity 0.3s easeOut"

-- 多属性逗号分隔
transition = "backgroundColor 0.8s easeInOut, scale 0.3s easeOutBack, opacity 0.5s linear"

-- "all" 关键字（所有可过渡属性共用配置）
transition = "all 0.5s easeInOut"

-- Table 格式
transition = {
    properties = { "opacity", "scale" },   -- 或 "all"
    duration   = 0.3,                       -- 秒
    easing     = "easeOut",
}

-- 时长格式："0.3s"（秒）、"300ms"（毫秒）、0.3（数字=秒）
```

### 7.3 可过渡属性列表

**只有以下属性可以通过 transition 产生动画，其他属性变化时立即生效**：

| 类别 | 属性 |
|------|------|
| 数值型 | `opacity`, `scale`, `rotate`, `translateX`, `translateY`, `borderRadius`, `borderWidth`, `shadowBlur`, `shadowOffsetX`, `shadowOffsetY` |
| 颜色型（RGBA 插值） | `backgroundColor`, `borderColor`, `shadowColor`, `fontColor` |

⚠️ `width`, `height`, `padding`, `margin`, `flexGrow`, `left`, `top` 等**布局属性不可过渡**，改变时会立即生效。

### 7.4 特殊：ProgressBar 的 value 过渡

ProgressBar 扩展了可过渡属性，支持 `value` 平滑动画：

```lua
UI.ProgressBar {
    value = 0.7,
    transition = "value 0.3s easeOut",
}
-- 更新 value 时会平滑过渡
progressBar:SetValue(0.9)   -- 从 0.7 动画到 0.9
```

### 7.5 缓动函数列表

| 名称 | 特点 |
|------|------|
| `linear` | 匀速 |
| `easeIn` | 慢启动（二次） |
| `easeOut` | 慢结束（二次） |
| `easeInOut` | 慢启慢停（二次） |
| `easeInCubic` | 三次入 |
| `easeOutCubic` | 三次出 |
| `easeInOutCubic` | 三次双向 |
| `easeInExpo` | 指数入 |
| `easeOutExpo` | 指数出 |
| `easeInBack` | 起始回弹 |
| `easeOutBack` | 结束回弹 |
| `easeInOutBack` | 双向回弹 |
| `spring` | 物理弹簧（会超调） |

⚠️ `spring` 可能使数值超出 0~1 范围。**不要对颜色属性使用 spring**，会产生无效 RGBA 值。

### 7.6 SetStyle 触发过渡

```lua
-- 有过渡效果（默认）
widget:SetStyle({ opacity = 0, scale = 0.8 })

-- 跳过过渡，立即生效
widget:SetStyle({ opacity = 1, scale = 1 }, true)   -- 第二个参数 = skipTransition
```

**重要规则**：
- 构造期间（`Init()`/`Build()` 内）的 `SetStyle` 不会触发过渡，始终立即生效
- 只有 `initialized_ = true` 后（即构造完成后）才会触发过渡动画

---

## 八、关键帧动画（Keyframe Animation）

### 8.1 widget:Animate()

```lua
widget:Animate({
    keyframes = {
        [0]   = { opacity = 0, translateY = 20 },
        [0.5] = { opacity = 1, translateY = 5 },
        [1]   = { opacity = 1, translateY = 0 },
    },
    duration   = 0.5,           -- 秒（必填）
    easing     = "easeOut",     -- 全局进度曲线
    loop       = false,         -- true = 无限循环，数字 = 循环次数
    direction  = "normal",      -- "normal" | "reverse" | "alternate"
    fillMode   = "forwards",    -- "none" | "forwards" | "backwards" | "both"
    onComplete = function() end,  -- 动画完成回调
})
```

### 8.2 keyframes 格式

- key 为 0~1 之间的进度值（0 = 起始，1 = 结束）
- value 为属性表，只能使用可过渡属性（见 7.3）
- 中间帧会按线性插值

```lua
keyframes = {
    [0]    = { opacity = 0, scale = 0.5 },     -- 起始
    [0.3]  = { opacity = 1, scale = 1.1 },     -- 30% 时
    [0.6]  = { scale = 0.95 },                  -- 60% 时（opacity 不变）
    [1]    = { opacity = 1, scale = 1.0 },     -- 结束
}
```

### 8.3 fillMode 说明

| 值 | 行为 |
|----|------|
| `"none"` | 动画结束后恢复到原始 props 值 |
| `"forwards"` | 动画结束后保持最终帧的属性值（写入 props） |
| `"backwards"` | 调用 Animate 时立即应用第一帧（避免第一帧闪烁） |
| `"both"` | 同时应用 forwards + backwards |

### 8.4 direction 说明

| 值 | 行为 |
|----|------|
| `"normal"` | 正序播放 0→1 |
| `"reverse"` | 倒序播放 1→0 |
| `"alternate"` | 正→反→正... 交替播放（配合 loop 使用） |

### 8.5 停止动画

```lua
widget:StopAnimation()            -- 立即停止
widget:HasActiveTransitions()     -- 检查是否有活跃的过渡或动画
```

---

## 九、组件生命周期

### 9.1 生命周期阶段

| 阶段 | 方法 | 时机 |
|------|------|------|
| 构造 | `Widget.new(props)` | 创建 widget 实例 |
| 初始化 | `Init()` | 设置内部状态（此时 SetStyle 不触发过渡） |
| 组合 | `Build()` | 声明式构建子 widget 树（类似 React render） |
| 就绪 | `initialized_ = true` | 构造完成，此后 SetStyle 可触发过渡 |
| 每帧更新 | `Update(dt)` | 有活跃动画/过渡时每帧调用 |
| 销毁 | `Destroy()` | 显式销毁，取消所有动画，释放资源 |

### 9.2 没有 onMount/onUnmount 回调

**UrhoX UI 系统没有暴露 `onMount`、`onUnmount`、`onLayout`、`onResize` 等生命周期回调。**

生命周期由引擎内部管理，外部代码的切入点：

```lua
-- ✅ "挂载后"逻辑：在 UI.SetRoot() 之后直接执行
local root = UI.Panel { ... }
UI.SetRoot(root)
-- 此处即为"挂载完成"，可以安全调用 SetStyle/Animate
root:FindById("welcome"):Animate({ ... })

-- ✅ "卸载前"逻辑：在切换页面前手动清理
function switchPage(newPage)
    -- 卸载前的清理工作
    saveScrollPosition()
    -- 设置新页面
    UI.SetRoot(newPage)
end

-- ✅ 可见性控制（不触发回调）
widget:SetVisible(false)   -- 隐藏，从布局中移除
widget:SetVisible(true)    -- 显示
widget:Show()              -- 等同 SetVisible(true)
widget:Hide()              -- 等同 SetVisible(false)
widget:IsVisible()         -- 查询
```

### 9.3 销毁

```lua
widget:Destroy()
-- 1. 取消所有活跃的过渡和动画
-- 2. 递归销毁所有子 widget
-- 3. 从父 widget 移除
-- 4. 释放 Yoga 布局节点
```

---

## 十、Button 状态过渡（自动行为）

Button 组件内部自动管理 hover/pressed/disabled 状态的背景色过渡：

```lua
UI.Button {
    backgroundColor = "#E94560",
    transition = "backgroundColor 0.2s easeOut",   -- 启用状态过渡

    -- 可选：显式指定各状态颜色（不指定则自动派生）
    hoverBackgroundColor    = "#FF5E7A",    -- 默认: Lighten(bg, 0.15)
    pressedBackgroundColor  = "#BA3750",    -- 默认: Darken(bg, 0.20)
    disabledBackgroundColor = "#666666",
}
```

**自动行为**：
- 鼠标进入 → 过渡到 hoverBackgroundColor
- 按下 → 过渡到 pressedBackgroundColor
- 释放 → 过渡回 hover 或 normal
- `disabled = true` → 过渡到 disabledBackgroundColor，且不响应点击

---

## 十一、常用组件方法（运行时更新）

### 11.1 通用方法（所有 Widget）

```lua
widget:SetStyle({ prop = value })              -- 更新样式（可触发过渡）
widget:SetStyle({ prop = value }, true)        -- 更新样式（跳过过渡）
widget:Animate({ keyframes, duration, ... })   -- 关键帧动画
widget:StopAnimation()                         -- 停止动画
widget:HasActiveTransitions()                  -- 是否有活跃动画
widget:GetRenderProp(propName)                 -- 获取当前渲染值（过渡中间值）

widget:SetVisible(bool)                        -- 设置可见性
widget:Show() / widget:Hide()                  -- 显示/隐藏
widget:IsVisible()                             -- 查询可见性
widget:Destroy()                               -- 销毁

widget:FindById("id")                          -- 递归查找子 widget
widget:OnEvent("eventName", handler)           -- 动态添加事件
widget:OffEvent("eventName", handler?)         -- 移除事件（不传 handler 则移除全部）
```

### 11.2 特定组件方法

| 组件 | 方法 | 说明 |
|------|------|------|
| Button | `:SetDisabled(bool)` | 设置禁用状态 |
| Slider | `:SetValue(n)` | 设置值 |
| TextField | `:SetValue(str)` | 设置文本 |
| Toggle | `:SetValue(bool)` | 设置开关 |
| Checkbox | `:SetChecked(bool)` | 设置选中 |
| ProgressBar | `:SetValue(n)` | 设置进度（可过渡） |
| ScrollView | `:ScrollTo(x, y)` | 滚动到指定位置 |
| ScrollView | `:ScrollBy(dx, dy)` | 相对滚动 |
| ScrollView | `:ScrollToTop()` | 滚动到顶部 |
| ScrollView | `:ScrollToBottom()` | 滚动到底部 |
| ScrollView | `:GetScroll()` | 获取当前滚动位置 |
| ScrollView | `:GetContentSize()` | 获取内容尺寸 |
| 所有 | `.text = "..."` | 直接修改 text 属性 |

---

## 十二、导出器实践建议

### 12.1 事件导出策略

```lua
-- 布局编辑器为可交互组件生成占位回调：
UI.Button {
    id = "btn_forge",
    text = "开始锻造",
    onClick = function(widget)
        -- [EVENT:btn_forge:click]
        -- 由游戏逻辑代码填充
    end,
}

-- 或导出空回调，由逻辑代码通过 FindById 绑定：
-- （推荐用于交互逻辑复杂的场景）
local btn = root:FindById("btn_forge")
btn:OnEvent("click", GameLogic.onForgeStart)
```

### 12.2 动画导出策略

```lua
-- 入场动画
UI.Panel {
    id = "modal",
    opacity = 0,
    translateY = 50,
    transition = "opacity 0.3s easeOut, translateY 0.3s easeOut",
}
-- 挂载后触发入场
local modal = root:FindById("modal")
modal:SetStyle({ opacity = 1, translateY = 0 })

-- 或使用关键帧动画
modal:Animate({
    keyframes = {
        [0] = { opacity = 0, translateY = 50, scale = 0.9 },
        [1] = { opacity = 1, translateY = 0, scale = 1.0 },
    },
    duration = 0.4,
    easing = "easeOutBack",
    fillMode = "forwards",
})
```

### 12.3 Slider/ScrollView 在容器中的冲突处理

- Slider 在 ScrollView 内部时，拖拽 Slider 不会触发滚动（引擎自动处理）
- TextField 获得焦点时同理，Pan 事件被文本选择消费
- **无需导出额外配置**

### 12.4 Button 状态色自动派生

如果只导出 `backgroundColor`，Button 会自动计算：
- hover = Lighten(bg, 15%)
- pressed = Darken(bg, 20%)

如果需要精确控制，显式导出 `hoverBackgroundColor` / `pressedBackgroundColor`。

---

## 十三、事件汇总表

| 组件 | 专属事件 | 回调签名 |
|------|---------|---------|
| **所有** | `onPointerEnter/Leave/Down/Up/Move/Cancel` | `(event: PointerEvent, widget)` |
| **所有** | `onTap/DoubleTap/LongPress/LongPressStart/End` | `(event: GestureEvent, widget)` |
| **所有** | `onSwipe/SwipeLeft/Right/Up/Down` | `(event: GestureEvent, widget)` |
| **所有** | `onPan/PanStart/PanMove/PanEnd` | `(event: GestureEvent, widget)` |
| **所有** | `onPinch/PinchStart/PinchMove/PinchEnd` | `(event: GestureEvent, widget)` |
| **所有** | `onFocus/onBlur` | `(widget)` |
| **Button** | `onClick` | `(widget, event?)` ⚠️ 顺序相反 |
| **Slider** | `onChange` | `(self, value: number)` |
| **Slider** | `onChangeEnd` | `(self, value: number)` |
| **TextField** | `onChange` | `(self, value: string)` |
| **TextField** | `onSubmit` | `(self, value: string)` |
| **TextField** | `onFocus/onBlur` | `(self)` |
| **Toggle** | `onChange` | `(self, value: boolean)` |
| **Checkbox** | `onChange` | `(self, checked: boolean)` |
| **Dropdown** | `onChange` | `(self, value, option)` |
| **ScrollView** | `onScroll` | `(self, scrollX, scrollY)` |

---

## 十四、注意事项

1. **`onClick` 参数顺序相反** — `(widget, event?)` 而非 `(event, widget)`，这是唯一的例外
2. **没有生命周期回调** — 没有 onMount/onUnmount/onLayout，在 `UI.SetRoot()` 后直接执行"挂载后"逻辑
3. **构造期间 SetStyle 不触发过渡** — 防止入场时的无意义动画
4. **只有列出的属性可过渡** — width/height/padding 等布局属性立即生效
5. **spring 缓动会超调** — 不要用在颜色属性上
6. **Swipe 同时触发方向和通用** — `onSwipeLeft` 触发时 `onSwipe` 也会触发
7. **动态事件监听零开销** — `eventListeners_` 在首次 `OnEvent()` 调用时才分配内存
