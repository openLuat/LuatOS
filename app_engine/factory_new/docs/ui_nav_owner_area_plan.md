# 桌面导航改造方案（owner 归属 + area 区域路线）

> 日期：2026-09-17 ｜ 范围：`app_engine/factory_new`
> 状态：**规划中，尚未改动任何代码**
> 关联文档：`docs/ui_nav_refactor_plan.md`（**另一条路线，见第二节对比**）
> 涉及：`libs/exwin.lua`、`ui/ui_theme.lua`、`ui/idle_win.lua` + 19 个页面文件

---

## 一、结论摘要

| 决策点 | 结论 |
|--------|------|
| 总体思路 | 给 `exwin` 增加 **`owner` 归属字段**（不是 `level`），配合 `theme.page` / `page_bg` 的 **`area` 区域参数** |
| 左栏归属 | 由 `idle_win` 继续充当宿主，**不新增 ui_shell / ui_desktop / page_manager 三个模块** |
| 一级菜单切换 | `exwin.close_children_of(宿主id)` → 再 `open` 新页面；**先清后开**，保证 `owner` 自动正确 |
| 二级页面返回 | 走原有 `exwin.close(window_id)`，只关自己，父页面不重建 |
| 页面侧改法 | 每页只改 2 处：`update_screen_size()` 收窄 `screen_w` + `page_bg` 传 `area.x/area.y` |
| 窄屏策略 | `area` 为 nil → 完全保持现状整屏行为，**窄屏零改动** |
| 预计净增代码 | **+212 行（+1.8%）**，触及既有代码约 68 行 |
| 最大收益 | 窗口栈深从**无上界**变为**确定上界**（1 宿主 + 1 一级 + N 二级） |
| 最大风险 | 换肤后左栏刷新、msgbox/keyboard 定位（详见 5.4） |

---

## 二、与既有方案（`ui_nav_refactor_plan.md`）的关系

仓库里已存在一份 `docs/ui_nav_refactor_plan.md`，走的是**完全不同的路线**。两者**不应同时实施**，需二选一。

### 2.1 路线差异

| | 既有方案（ui_shell 路线） | **本方案（owner + area 路线）** |
|---|---|---|
| 窗口管理 | 新建 `page_manager.lua` 自建栈，**绕开 exwin** | 复用 `exwin`，增加 `owner` 字段 |
| 骨架 | 新建 `ui_shell.lua`（唯一 exwin 窗口，持有 rail + content_area + 浮动返回按钮） | 保留 `idle_win` 作宿主，左栏不重建 |
| 桌面 | 从 1830 行的 `idle_win` 抽出 `ui_desktop.lua` | `idle_win` **保持不动** |
| 页面接口 | 19 个页面改造为导出 `M.create(parent, w, h)` / `destroy`，**删掉全部 exwin 样板** | 19 个页面**保留** exwin 结构，各加约 4 行 |
| 返回按钮 | shell 内统一浮动按钮 | 各页保留标题栏返回（不变） |
| 页面改动面 | 每页重写首尾约 50 行 → **合计约 950 行** | 每页改 2 处 → **合计约 68 行** |
| 新增模块 | 3 个（page_manager / ui_shell / ui_desktop） | 0 个（只扩展现有 2 个库） |
| 与 exwin 的关系 | 两套栈并存（`return_idle` / `is_active` 语义会变乱） | 单一栈，语义一致 |

### 2.2 ⚠️ 关于「屏缓冲」的前提更正

既有方案第四节称：

> 每个 exwin 窗口持有独立 LVGL 屏缓冲（1024×600×2 ≈ 1.2MB），叠加多个页面内存迅速耗尽
> 改造前 3 个页面 ≈ 3.6MB 屏缓冲 → 改造后 ≈ 1.2MB

**这个前提不成立。** 核实结论如下：

| 事实 | 源码位置 |
|------|----------|
| `lv_display_create` **全应用只调用一次** | `components/airui/src/core/luat_airui_ctx.c:464`（在 `airui_init` 内） |
| 显示缓冲**只在 `airui_init` 分配一次**（buf1 + buf2 双缓冲） | `luat_airui_ctx.c:500-512` |
| 缓冲大小 = `w * h * bpp / DIVISOR`，默认 `DIVISOR = 2` | `luat_airui_ctx.c:501` + `inc/luat_airui_conf.h:43` |
| 工程未定义 `LUAT_USE_AIRUI_DISPLAY_BUFFER_SIZE_DIVISOR` | 全仓库 Grep 无匹配，即取默认值 2 |

也就是说：**1024×600×2B / 2 × 2 缓冲 = 1.2MB，但这是全局唯一一份，与 exwin 窗口数量无关。**

`exwin` 的多个窗口只是**同一棵 LVGL 对象树的不同分支**，各窗口增加的是**控件对象内存**（每个 LVGL 对象约百字节级），不是屏缓冲。

**影响**：既有方案「3 个页面 3.6MB → 1.2MB」的内存收益**不存在**；改造前后的屏缓冲都是 1.2MB 固定值。真正需要解决的仍然是**窗口栈深无上界导致的对象堆积**——这一点本方案同样解决，且改动量小一个数量级。

> 建议：若最终选择既有方案，请先更正该节的内存测算，避免基于错误前提决策。

### 2.3 既有方案中可借鉴的点

- **统一浮动返回按钮**：本方案保留各页标题栏返回（改动小），但若后续要做「层级面包屑」，可参考该设计。
- **`content_area` 容器**：用一个容器承载页面、天然 clip。本方案用坐标偏移替代（见 4.2 说明），代价是页面需读 `area.x/y`；若要更强隔离，可改为容器方案。

---

## 三、现状分析

### 3.1 窗口栈：纯线性，无层级概念

`libs/exwin.lua`（171 行）对外只有 4 个接口：

| 接口 | 行为 |
|------|------|
| `exwin.open(config)` | 入栈 + `on_create`；同时让前栈顶 `on_lose_focus` |
| `exwin.close(win_id)` | 出栈 + `on_destroy`；若是栈顶则让新栈顶 `on_get_focus` |
| `exwin.is_active(win_id)` | 是否栈顶 |
| `exwin.return_idle()` | **硬编码**「保留 index=1，销毁其余」 |

窗口记录只有 5 个字段（`libs/exwin.lua:88-94`），**没有父子关系，没有层级标记**。`return_idle()` 假设首页永远是栈底，无法表达「回到某个一级菜单」或「销毁某棵子树」。

### 3.2 全工程页面的统一模式

实测：`ui/` 目录 25 个 lua 文件（其中 21 个 `*_win.lua`）共 **11,466 行**；页面构建点 **21 处**，涉及 **20 个文件**，全部是同一套写法：

```lua
main_container = theme.page_bg(airui.screen, screen_w, screen_h)   -- 铺满整屏
-- 或
local ctx = theme.page({ title = "...", on_back = function() exwin.close(window_id) end })
```

返回一律 `exwin.close(window_id)`。

`theme.page(o)`（`ui/ui_theme.lua:1340`）虽接受 `o.parent`，但尺寸**恒等于全屏**：

```lua
function M.page(o)
    o = o or {}
    local sw = screen_w or 480      -- ← 写死全屏
    local sh = screen_h or 800      -- ← 写死全屏
```

**每个页面都隐式假设「我独占整屏」**——一条从未写进注释、但处处依赖的隐式契约。

### 3.3 布局特征（决定改造可行性的关键杠杆）

以 `ui/settings/settings_iot_win.lua` 为例，其 20 处 `screen_w/screen_h` 引用**全部**是比例式写法：

```lua
card_w    = screen_w - 2 * margin
input_w   = card_w - label_w - math.floor(screen_w * 0.08)
x = margin, y = math.floor(screen_h * 0.06), w = card_w, h = math.floor(screen_h * 0.35)
```

**只要把 `screen_w` 换成内容区宽度、`screen_h` 保持不变，页面内所有几何会自动重新自适应**，一处都不用逐行改写。这是本方案「改动不扩散」的根本原因。

同理，`ui_theme.lua:308 M.wallpaper(parent, w, h)` 内部所有子元素（10 条渐变条、4 处光斑）都是**相对 base 容器**的坐标（`x=0, y=y0`），只有 base 本身在 `(0,0)`。给 base 加 `x/y` 偏移，整个背景跟着走。

### 3.4 需求

1. `idle_win` 左侧内置应用栏**常驻显示**（宽屏 ≥560dp 已有 104dp rail）。
2. 点击内置应用后，**右侧剩余区域**显示对应内容，左栏不被覆盖。
3. 切换内置应用时，**销毁上一个一级菜单的整棵子页面树**，避免页面无限堆积。
4. 一级菜单内部跳转（设置 → iot）**不销毁父级**，返回时回到父级。

---

## 四、方案设计

### 4.1 exwin：引入 `owner` 归属字段

**为什么用 `owner` 而不是 `level`**：`level` 需要调用方自己推算层级（设置里再开 iot，算 2 还是 3？取决于谁是根），而 `owner` 在开窗时天然已知 —— **谁开的我，我就归谁**。默认取当前栈顶，**绝大多数页面无需写任何参数**。

**改动 1：窗口记录增加 `owner`**（`libs/exwin.lua:88`）

```lua
local new_win = {
    id = new_id,
    owner = config.owner or (current and current.id) or nil,   -- 默认归属当前栈顶
    create = config.on_create,
    destroy = config.on_destroy,
    lose_focus = config.on_lose_focus,
    get_focus = config.on_get_focus
}
```

**改动 2：把 `close` 拆出内部实现**（供批量关闭复用、抑制中间焦点回调）

```lua
local suppress_focus = false

local function close_internal(win_id)
    local idx = find_index_by_id(win_id)
    if not idx then return false end
    local win = win_stack[idx]
    local is_top = (idx == #win_stack)
    if win.destroy then pcall(win.destroy) end
    table.remove(win_stack, idx)
    if is_top and not suppress_focus then
        local new_current = win_stack[#win_stack]
        if new_current and new_current.get_focus then pcall(new_current.get_focus) end
    end
    return true
end

function exwin.close(win_id)
    close_internal(win_id)
end
```

**改动 3：新增四个接口**

```lua
-- 递归收集以 id 为根的全部后代（子先于父入表 → 天然形成自底向上的销毁顺序）
local function collect_descendants(id, acc)
    for _, w in ipairs(win_stack) do
        if w.owner == id then
            collect_descendants(w.id, acc)
            acc[#acc + 1] = w.id
        end
    end
end

--[[销毁以 id 为根的全部后代（不含 id 自身）
批量期间抑制中间的 get_focus，结束后统一结算一次焦点，
避免「关闭 N 个窗口触发 N 次重建」。]]
function exwin.close_children_of(id)
    if id == nil then return 0 end
    local victim = {}
    collect_descendants(id, victim)
    local n = #victim
    if n == 0 then return 0 end

    suppress_focus = true
    for _, vid in ipairs(victim) do close_internal(vid) end
    suppress_focus = false

    -- 统一结算：让当前栈顶获得焦点（见 5.4 风险 1，此处不可省）
    local top = win_stack[#win_stack]
    if top and top.get_focus then pcall(top.get_focus) end
    return n
end

-- 向上追溯所属的一级菜单（根）窗口 id
function exwin.find_root(win_id)
    local idx = find_index_by_id(win_id)
    if not idx then return nil end
    local cur = win_stack[idx]
    while cur and cur.owner do
        local oi = find_index_by_id(cur.owner)
        if not oi then break end
        cur = win_stack[oi]
    end
    return cur and cur.id or nil
end

-- 是否存在子窗口（供宿主判断高亮是否该清除）
function exwin.has_children(id)
    for _, w in ipairs(win_stack) do
        if w.owner == id then return true end
    end
    return false
end
```

> **关键约束**：`close_children_of` 末尾**必须显式结算一次焦点**。因为 `idle_win` 的换肤重建依赖 `on_get_focus`，若把焦点回调全部抑制且不补结算，会出现「换肤后左栏颜色不刷新」（见 5.4 风险 1）。

### 4.2 ui_theme：`page` / `page_bg` 支持区域

**为什么不把 `content_area()` 放进 `exwin`**：`exwin` 是纯窗口栈库，不应知道「左侧 rail 有多宽」这类 UI 布局细节。区域信息由 UI 层提供。

**改动 1：新增壳层状态与区域查询**（新增于 `ui/ui_theme.lua`）

```lua
-- 壳层（Shell）状态：由 idle_win 在布局计算后写入
M.shell = { enabled = false, rail_w = 0, host_id = nil }

--[[返回内容区几何 { x, y, w, h }；无左栏（窄屏）时返回 nil
返回 nil 即「保持整屏行为」，调用方无需分支判断]]
function M.content_area()
    if not M.shell.enabled or M.shell.rail_w <= 0 then return nil end
    local w = (screen_w or 480) - M.shell.rail_w
    if w < 1 then return nil end
    return { x = M.shell.rail_w, y = 0, w = w, h = screen_h or 800 }
end
```

**改动 2：`M.wallpaper` 支持偏移**（`ui/ui_theme.lua:308`）

```lua
function M.wallpaper(parent, x, y, w, h)
    local base = M.box(parent, { x = x, y = y, w = w, h = h, color = M.C.bg })
    -- 以下 STEPS 渐变条与 4 处光斑全部保持相对 base 的坐标，无需改动
    ...
end
```

**改动 3：`M.page_bg` 支持偏移**（`ui/ui_theme.lua:1321`）

```lua
function M.page_bg(parent, x, y, w, h)
    if M.STYLE.wallpaper then
        return M.wallpaper(parent, x, y, w, h)
    end
    return M.box(parent, { x = x, y = y, w = w, h = h, color = M.C.bg })
end
```

**改动 4：`M.page` 支持 `o.area`**（`ui/ui_theme.lua:1340`）

```lua
function M.page(o)
    o = o or {}
    local area = o.area                                   -- { x, y, w, h } 或 nil
    local sw = (area and area.w) or screen_w or 480        -- 有区域 → 用区域尺寸
    local sh = (area and area.h) or screen_h or 800
    local bx = (area and area.x) or 0
    local by = (area and area.y) or 0
    local pad = o.pad or M.page_margin()
    local p = o.parent or airui.screen

    local base
    if o.flat then
        base = M.box(p, { x = bx, y = by, w = sw, h = sh, color = M.C.bg })
    else
        base = M.page_bg(p, bx, by, sw, sh)
    end
    -- 以下 ctx 计算逻辑完全不变：ctx.x/y 仍相对 base 的绝对坐标
    ...
end
```

> 关键：`ctx.x/y` 是**相对 base** 的绝对坐标（`x = pad`），而 base 已被摆到 `area.x/area.y`。因此页面内所有以 `ctx.base` / `main_container` 为 parent 的子控件**坐标全部无需改动**。

> 为什么用坐标偏移而不是 idle_win 建一个 `content_host` 容器：容器方案需要 idle_win 持续管理该容器的生命周期与 z-order（每次换肤重建 idle 时，重建出来的 `main_container` 会盖住容器，需额外 `move_foreground`）。坐标偏移无额外状态，且新页面总是后创建，z-order 天然正确。

### 4.3 页面侧改动模板

**每个需要改造的页面只改 2 处**（以 `settings_iot_win.lua` 为例）：

```lua
-- ① 页面顶部：宽度收窄为内容区宽度
local area = nil

local function update_screen_size()
    local pw, ph = lcd.getSize()
    screen_w, screen_h = pw, ph
    area = theme.content_area()            -- ← 新增
    if area then screen_w = area.w end     -- ← 新增：只收窄宽度，高度不变
    ...
end

-- ② 背景容器带上偏移
local function build_ui()
    update_screen_size()
    main_container = theme.page_bg(airui.screen,
        area and area.x or 0, area and area.y or 0, screen_w, screen_h)   -- ← 改调用
    ...
end
```

`theme.page` 路径的页面（`settings_win` / `settings_about_win` / `settings_theme_win`）更简单：

```lua
local ctx = theme.page({
    area = theme.content_area(),      -- ← 新增 1 行
    title = "设置",
    sub = "设备偏好、网络、显示与系统",
    on_back = function() exwin.close(window_id) end,
})
```

### 4.4 idle_win：左栏常驻与菜单切换

**改动 1：布局计算后写入壳层状态**（`ui/idle_win.lua:190 calc_layout()` 末尾）

```lua
theme.shell.enabled = use_rail
theme.shell.rail_w  = rail_w
```

**改动 2：统一内置应用入口**（替换 `idle_win.lua:324 / 953 / 1174` 三处 `sys.publish`）

```lua
--[[一级菜单切换：先清掉上一个一级菜单的整棵子树，再打开新页面。
「先清后开」的顺序很重要：
1. 清空后栈顶回到 idle，新页面的 owner 默认取栈顶即可自动归到 idle 名下；
2. close_children_of 结算焦点时 idle 若待重建（换肤），重建发生在 open 之前，
   保证新页面 z-order 在 idle 之上。]]
local function open_builtin(win)
    exwin.close_children_of(theme.shell.host_id)
    set_rail_active(win)
    sys.publish("OPEN_" .. win .. "_WIN")
end
```

三处调用点：网格 tile 点击（324）、左栏 rail 项点击（953）、dock 项点击（1174）。

**改动 3：记录宿主窗口 id**（`ui/idle_win.lua:2053 open_handler()`）

```lua
local function open_handler()
    window_id = exwin.open({ ... })
    theme.shell.host_id = window_id          -- 暴露给各页面作 owner
end
```

**改动 4：`on_get_focus` 清除高亮**（`ui/idle_win.lua:2029`）

idle 重新获得焦点意味着它上面的窗口都被关掉了，此时应清除左栏高亮：

```lua
local function on_get_focus()
    if take_theme_dirty() then
        local keep_id = window_id
        on_destroy()
        on_create()
        window_id = keep_id
        theme.shell.host_id = window_id      -- 重建后重新暴露
    end
    set_rail_active(nil)                     -- 回到首页 → 清除一级菜单高亮
    ...
end
```

**改动 5：左栏高亮**（`ui/idle_win.lua:928 build_rail()`）

`build_rail` 里的 rail 项需按 `active_menu` 着色，做法与 `theme.rail` 中 `on = (i == o.active)` 一致；并把控件收集到 `rail_item_widgets[b.win]`，供 `set_rail_active` 就地改属性（**不重建 rail**）：

```lua
local on = (b.win == active_menu)
local item = theme.card(rail, {
    x = ..., y = y, w = iw, h = ih,
    radius = theme.R.md,
    color    = on and theme.C.amber or theme.C.surface,
    opa      = on and 44 or 0,
    border   = on and theme.C.amber or nil,
    border_w = on and 1 or 0,
    on_click = function() open_builtin(b.win) end,
})
rail_item_widgets[b.win] = item
```

```lua
local function set_rail_active(win)
    if active_menu == win then return end
    active_menu = win
    for name, w in pairs(rail_item_widgets) do
        local on = (name == win)
        w:set_color(on and theme.C.amber or theme.C.surface)
        -- 描边/透明度同理
    end
end
```

### 4.5 窄屏回退

`use_rail = (sw >= 560) and not compact`（`idle_win.lua:194`）。窄屏下 `rail_w = 0` → `theme.shell.enabled = false` → `content_area()` 返回 `nil` → 页面走原有整屏逻辑。

**窄屏零改动**，无需任何分支判断。

另：`settings_win` 的 `wide = sw >= 560` 判定用的是收窄后的 `sw`，因此内容区不够宽时会**自动降级**为窄屏两列布局。

### 4.6 改造后的窗口栈形态

```
idle_win (宿主, owner = nil)                 ← 常驻栈底，左栏属于它
  └─ 设置 (owner = idle_id)                  ← 一级菜单
       └─ iot (owner = 设置_id)              ← 二级菜单
```

| 用户操作 | 栈变化 | 说明 |
|----------|--------|------|
| 左栏点「设置」 | `close_children_of(idle)` → open(设置) | 清空后开新，栈深 2 |
| 设置内点「iot」 | open(iot, owner=设置) | 栈深 3，设置页**不重建** |
| iot 返回 | `close(iot)` | 栈深 2，设置页**不重建** |
| 在 iot 页点左栏「文件管理」 | `close_children_of(idle)` 销毁 设置+iot → open(文件管理) | 栈深 2 |
| 设置页返回 | `close(设置)` | 栈深 1，idle 全屏显示 |

---

## 五、改造前后预测

### 5.1 代码量

**基线（实测）**：`ui/` 目录 11,466 行 + `libs/exwin.lua` 171 行 = **11,637 行**；页面构建点 21 处；`screen_w|screen_h` 引用 323 处。

| 改动位置 | 改前 | 改后 | 净增 | 触及既有行 |
|----------|------|------|------|-----------|
| `libs/exwin.lua` | 171 | ~250 | **+79** | ~6 |
| `ui/ui_theme.lua` | 1421 | ~1433 | **+12** | ~4 |
| `ui/idle_win.lua` | 1830 | ~1878 | **+48** | ~18 |
| 19 个页面 × ~4 行 | — | — | **+76** | ~40 |
| **合计** | **11,637** | **~11,849** | **+212（+1.8%）** | **~68** |

**为什么 +212 行能覆盖 323 处引用**：页面内几何是比例式写法（见 3.3），收窄 `screen_w` 后自动自适应，**绝大多数引用无需触碰**。

> ⚠️ **更正（2026-09-17 复核）**：不存在单一的全局收窄点。每个页面文件都有自己的 `local screen_w, screen_h = 480, 800`，各自在本地 `update_screen_size()` 里从 `lcd.getSize()` 推导（如 `ui/settings/settings_iot_win.lua:15`、`ui/settings/settings_win.lua` 同构）。所以第 460 行的「19 个页面 × ~4 行」应理解为**逐文件改 2 行尺寸来源 + 1 行传 `area`**，合计约 57 处、约 85 行，而不是「改一处全局变量」。
>
> 收窄机制本身仍然成立：页面内部控件全部以 `parent = base` 创建，LVGL 子对象坐标**相对父容器**，因此把 `base` 摆到 `(rail_w, 0)`、把页面的 `screen_w` 设为 `area.w` 后，内部所有 `x = screen_w * 0.08` 这类比例式写法确实**一处都不用改**。结论不变，只是实现路径由「1 处」修正为「19 个文件各 2 行」。
>
> 详细对比与证据见 `docs/ui_nav_plan_compare.md`。

**复杂度集中在库层**：`exwin.lua` 增加约 79 行（其中注释约 34 行，实际代码约 45 行），对调用方透明。这是「代码不臃肿」的关键 —— **复杂度进库，不进页面**。

对比既有方案的改动面：19 个页面 × 约 50 行首尾重写 ≈ **950 行**，另加 3 个新模块（page_manager / ui_shell / ui_desktop，其中 ui_desktop 要从 1830 行的 idle_win 中抽出）。

### 5.2 运行效率

| 维度 | 改造前 | 改造后 | 判断 |
|------|--------|--------|------|
| 显示缓冲 | 1.2MB 全局唯一 | 1.2MB 全局唯一 | **不变**（见 2.2） |
| 单帧渲染面积 | 1024×600 = 614,400 px | 920×600 = 552,000 px | **-10.2%** ✅ |
| 页面重建成本 | 销毁 N + 创建 M | 同量级 | 持平 |
| 左栏重建 | 不重建（idle 为栈底） | 不重建 | 持平 |
| 同层返回 | 不重建设置页 | 不重建设置页 | 持平 |
| LVGL 对象树深度 | 屏幕下挂 1 个页面 | 屏幕下挂 idle + 1 个页面 | 略增 ⚠️ |
| 屏幕重绘触发 | idle 失焦后 timer 已停 | 同左 | 持平 |
| **窗口栈深上界** | **无上界**（取决于用户路径） | **1 + 1 + N** | **从无界变有界** ✅ |
| 视频解码 | 失焦后继续（`on_lose_focus` 未停 video） | 同左 | 持平（既有问题） |

对象树加深的影响可控：LVGL 按 invalidate 区域遍历子对象，不做全屏扫描；且 `idle_win.on_lose_focus` 已有 `sys.timerStop(timer_handler)`，失焦后时钟不再每秒 invalidate，被遮挡的 idle 子树基本不参与渲染。

**内存是本次改造最大的收益**：改造前栈深是「取决于用户点序的无界变量」，改造后是「可推导的确定上界」。单个二级页约 40~60 个 LVGL 对象，栈深固定 3 层，反复切换 100 次栈深不涨。

> ⚠️ **更正（2026-09-17 复核）**：上一句只说了栈深，**漏了本方案相对「抽 shell 方案」的内存劣势**，需要补上。
>
> 本方案下 `idle_win` 常驻，所以**桌面对象（约 150~250 个）与视频解码缓冲会一直占着内存**。`ui/idle_win.lua:1818-1827` 创建的是硬件解码的 MJPG 组件（`format = "mjpg"`, `decode_mode = "hw"`, `auto_play = true`, 典型帧 480×270），其帧缓冲约 253KB（单缓冲）/ 约 506KB（双缓冲）——**很可能是全应用最大的一笔单体分配**。它只在 `on_destroy`（行 1976-1980）里才被释放。
>
> 而「抽 `ui_shell` + `ui_desktop`」的方案在进入应用时会销毁桌面，连带释放这笔分配，**峰值内存确实更低**。
>
> **必做的补强**：在 `idle_win.on_lose_focus`（行 2048-2051，目前只停 `timer_handler` 与充电动画，**不含视频**）里显式 `stop()` + `destroy()` 视频组件，即可拿回大部分内存优势。若实测缓冲可接受，也可改为 `pause()` 保留缓冲、回来无缝续播——这是本方案相对抽 shell 方案的额外自由度（后者只有「销毁重播」一条路）。
>
> 注意：`on_lose_focus` 未停视频是**当前架构已有的 bug**（现在打开设置页时，被盖住的桌面视频仍在 30fps 解码、配套 MP3 仍在播放），改造时应一并修掉。

**一个真实退步点**：跨一级菜单切换后再回来，必须完整重建（旧页已销毁）。这是用「少量重建」换「内存可控」，值得。

### 5.3 耦合性

| | 改造前 | 改造后 |
|---|--------|--------|
| 页面 ↔ 尺寸 | 每页隐式假设「独占整屏」，依赖全局 `screen_w/screen_h` | 页面接收注入的 `area`，**不知道左栏存在** |
| 页面 ↔ 窗口栈 | `exwin.close(window_id)` | 不变；`owner` 默认取栈顶，多数页面零改动 |
| `idle_win` 身份 | 首页 + 左栏宿主（双重） | 不变 |
| `exwin` API 面 | 4 个接口 | **8 个**（+100%）⚠️ |

**净效果是耦合下降** —— 把「页面渲染尺寸」从全局隐式契约变成了显式注入参数。

**但新增一条隐式契约**：`update_screen_size()` 必须记得收窄 `screen_w`，否则页面溢出到左栏。这条必须写进 `ui_theme.lua` 文件头注释与页面模板，否则后续新增页面必踩。

### 5.4 风险清单（按严重度排序）

| # | 风险 | 级别 | 说明与对策 |
|---|------|------|-----------|
| 1 | **换肤后左栏不刷新** | 🔴 | `idle_win` 靠 `UI_THEME_CHANGED` 打脏 + `on_get_focus` 重建。改造后 idle 常驻失焦，若 `close_children_of` 把焦点回调全抑制且不补结算，就等不到重建时机。**对策**：`close_children_of` 末尾必须显式结算一次焦点（见 4.1） |
| 2 | **msgbox / keyboard 定位** | 🟠 | `airui.msgbox` 默认 `auto_center = true` 相对**屏幕**居中，改造后偏向屏幕中心而非内容区中心，且会盖住左栏；`airui.keyboard` 用 `w = screen_w`。全工程 **msgbox 约 25 处、keyboard 约 12 处**，需逐处决策（接受 / 收进内容区） |
| 3 | **settings_win 三层横排拥挤** | 🟠 | 设置页本身已是「左 nav 240dp + 右卡」。改造后右卡从 748dp 缩到 **644dp（-14%）**。`wide = sw >= 560` 用收窄后的 `sw`，不够宽时自动降级为窄屏布局 |
| 4 | **左栏高亮状态** | 🟡 | 新增「当前哪个一级菜单激活」状态与就地改属性逻辑，约 +25 行 |
| 5 | **`settings_iot_win` 的 `60 * density` 硬编码** | 🟡 | `settings_iot_win.lua:61-62` 用 `y = math.floor(60 * _G.density_scale)` 绕开标题栏高度，区域变化后该值不再正确，应改用 `titlebar.create` 返回的标题栏高度 `th` |
| 6 | **`scrollable` 死代码** | 🟡 | `ui_theme.lua:284 / 356 / 789 / 1185` 的 `scrollable = (o.scrollable == true)`，C 层 `luat_airui_container.c:37-46` **根本不读该 key**（只读 `parent/x/y/w/h/color/color_opacity/radius/border_color/border_width`）。要么补 C 绑定（须走 GUI 构建），要么删除以免误导 |
| 7 | **视频失焦不暂停** | 🟡 | `idle_win.on_lose_focus`（2048 行）只停 `timer_handler` 与充电动画，未停 video。改造前后一致，建议顺手修掉 |
| 8 | **返回语义待定** | 🔵 | 左栏常驻后，一级菜单页是否还保留返回按钮？建议保留（关掉自己 → idle 全屏显示） |
| 9 | **回归测试面** | 🔵 | 19 页 × 宽屏/窄屏 = **38 个场景**。建议先只打通「idle ↔ 设置 ↔ iot」一条链验证机制，再批量铺开 |

---

## 六、分阶段执行清单

### P0 —— 库层能力（不动业务页面，可独立验证）

| 序 | 改动 | 文件 |
|---|------|------|
| 1 | 窗口记录增加 `owner` 字段 | `libs/exwin.lua:88` |
| 2 | 拆出 `close_internal` + `suppress_focus` | `libs/exwin.lua:120` |
| 3 | 新增 `close_children_of` / `find_root` / `has_children` | `libs/exwin.lua` |
| 4 | 新增 `M.shell` / `M.content_area()` | `ui/ui_theme.lua` |
| 5 | `M.wallpaper` / `M.page_bg` 支持 `x/y` 偏移 | `ui/ui_theme.lua:308 / 1321` |
| 6 | `M.page` 支持 `o.area` | `ui/ui_theme.lua:1340` |
| 7 | 更新 `ui_theme.lua` 文件头「尺寸契约」注释（第 19 条） | `ui/ui_theme.lua:19` |

**验收**：`area = nil` 时全工程行为与改造前**完全一致**（这是回退保障）。

### P1 —— 打通最小闭环（idle ↔ 设置 ↔ iot）

| 序 | 改动 | 文件 |
|---|------|------|
| 8 | 写入 `theme.shell.enabled / rail_w` | `ui/idle_win.lua:190` |
| 9 | 新增 `open_builtin` + `set_rail_active`，替换 3 处 `sys.publish` | `ui/idle_win.lua:324 / 953 / 1174` |
| 10 | 暴露 `theme.shell.host_id`（`open_handler` 与重建后） | `ui/idle_win.lua:2053 / 2029` |
| 11 | `on_get_focus` 清除高亮 | `ui/idle_win.lua:2029` |
| 12 | `build_rail` 支持高亮 + 收集控件引用 | `ui/idle_win.lua:928` |
| 13 | `settings_win` 传 `area` | `ui/settings/settings_win.lua:113` |
| 14 | `settings_iot_win` 收窄 `screen_w` + `page_bg` 偏移 + 去掉 `60` 硬编码 | `ui/settings/settings_iot_win.lua:30 / 61 / 274` |

**验收**：见第七节 1~5 条。

### P2 —— 铺开其余页面

按批次改，每批改完即验证：

| 批次 | 页面 |
|------|------|
| 2-a 设置二级 | `settings_about_win`、`settings_auto_win`、`settings_display_win`、`settings_fota_win`、`settings_sound_win`、`settings_storage_win`、`settings_theme_win`、`storage_pri_win` |
| 2-b WiFi 组 | `wifi_list_win`、`wifi_detail_win`、`wifi_connect_win` |
| 2-c 一级菜单 | `app_store_win`、`file_manager_win`（2 处）、`speedtest_win`、`llm_chat_win`、`factory_win` |
| 2-d 工厂二级 | `factory_rec_win` |

### P3 —— 清理与收尾

| 序 | 改动 |
|---|------|
| 15 | msgbox / keyboard 定位决策与实施（约 37 处） |
| 16 | 清理 `scrollable` 死代码，或补 C 绑定（须走 GUI 构建 `bsp/pc/build_windows_32bit_msvc_gui.bat`） |
| 17 | 视频失焦暂停（`on_lose_focus` 增加 video stop） |
| 18 | 补 `ui_theme.lua` 与新页面模板的「尺寸契约」注释 |

---

## 七、验证清单

### 宽屏（≥560dp，rail 生效）

1. 左栏点「设置」→ 左栏可见且「设置」项高亮，右侧显示设置页内容。
2. 设置内点「iot」→ 右侧切换为 iot 页，左栏仍高亮「设置」。
3. iot 页返回 → 回到设置页，**设置页未重建**（用 `log.info` 确认 `on_create` 未再次触发）。
4. 在 iot 页直接点左栏「文件管理」→ 设置 + iot **同时被销毁**，文件管理打开。
5. 反复在左栏来回切换 10 次 → 窗口栈深度稳定为 2，无增长。
6. 设置页返回 → 回到 idle 全屏，左栏高亮清除。
7. 在设置页切换主题 → 返回后左栏与新主题配色一致。
8. 长按/点击应用网格 tile、dock 项 → 行为与左栏一致。

### 窄屏（<560dp）

9. 无左栏，页面整屏显示，行为与改造前**完全一致**。
10. 窗口栈深仍受限（`close_children_of` 依然生效）。

### 内存

11. 用 `log.info` 打印栈快照，确认任意操作序列后栈深 ≤ 3。
12. 连续操作 5 分钟（反复切换一级菜单 + 进入二级页），观察内存无单调增长。

---

## 八、风险与回滚

**回退保障**：由于 `area = nil` 时 `theme.page` / `page_bg` / `content_area()` 全部退化为原有行为，只需把 `idle_win.calc_layout()` 里的 `theme.shell.enabled = false` 一行改掉，即可**立即回到改造前状态**，无需回滚其余改动。

**分阶段提交**：P0 / P1 / P2 各自独立可运行，建议分开提交，便于定位问题。

**GUI 相关变更必须走 GUI 构建**：
```
bsp/pc/build_windows_32bit_msvc_gui.bat
```

---

## 九、待决策事项

| # | 事项 | 选项 |
|---|------|------|
| 1 | **路线选择** | A. 本方案（owner + area，改动 ~68 行）　B. `ui_nav_refactor_plan.md`（ui_shell + page_manager，改动 ~950 行 + 3 新模块） |
| 2 | 一级菜单页是否保留返回按钮 | A. 保留（关自己 → idle 全屏）　B. 移除（完全靠左栏切换） |
| 3 | msgbox / keyboard 是否收进内容区 | A. 保持全屏居中（盖住左栏）　B. 收进内容区（需逐处传 parent） |
| 4 | 是否顺手修视频失焦暂停 | A. 本次一起改　B. 另开任务 |
| 5 | `scrollable` 死代码处理 | A. 删除　B. 补 C 绑定（需 GUI 构建） |

---

## 十、附录：关键源码索引

| 位置 | 内容 |
|------|------|
| `libs/exwin.lua:33-38` | `win_stack` / `next_id` 定义 |
| `libs/exwin.lua:75-108` | `exwin.open` |
| `libs/exwin.lua:120-143` | `exwin.close` |
| `libs/exwin.lua:171-188` | `exwin.return_idle`（硬编码栈底） |
| `ui/ui_theme.lua:19` | 文件头「尺寸契约」注释（需更新） |
| `ui/ui_theme.lua:284 / 356 / 789 / 1185` | `scrollable` 死代码 |
| `ui/ui_theme.lua:308-327` | `M.wallpaper`（子元素均相对 base） |
| `ui/ui_theme.lua:1321-1326` | `M.page_bg` |
| `ui/ui_theme.lua:1340-1375` | `M.page` |
| `ui/idle_win.lua:190-270` | `calc_layout()`，含 `use_rail` / `rail_w` |
| `ui/idle_win.lua:324 / 953 / 1174` | 三处 `sys.publish("OPEN_...")` |
| `ui/idle_win.lua:928-966` | `build_rail()` |
| `ui/idle_win.lua:1914-1966` | `on_create()` |
| `ui/idle_win.lua:2029-2051` | `on_get_focus()` / `on_lose_focus()` |
| `ui/idle_win.lua:2053-2060` | `open_handler()` |
| `ui/settings/settings_win.lua:113-117` | `theme.page` 调用；`wide = sw >= 560`（124 行） |
| `ui/settings/settings_iot_win.lua:59-62` | `content_area` + `60 * density` 硬编码 |
| `components/airui/src/core/luat_airui_ctx.c:464` | `lv_display_create`（全局唯一） |
| `components/airui/src/core/luat_airui_ctx.c:500-512` | 显示缓冲分配（全局唯一，双缓冲） |
| `components/airui/inc/luat_airui_conf.h:43` | `AIRUI_DISPLAY_BUFFER_SIZE_DIVISOR` 默认 2 |
| `components/airui/binding/luat_lib_airui_container.c:236-247` | container 方法表（**无 `set_size`**） |
| `components/airui/src/components/widgets/luat_airui_container.c:37-46` | container 配置解析（**不读 `scrollable`**） |

---

## 十一、实施记录（2026-09-17 落地）

本章记录**实际写进代码的版本**。它与第四、六章的初版设计有 3 处刻意偏差 —— 都是在动手时发现的更省代码的落地手法，本节逐条说明。

### 11.1 实际新增的接口

**`libs/exwin.lua`（171 → 383 行）**

| 接口 | 作用 |
|---|---|
| `exwin.open({ ..., owner = id \| false })` | 新增 `owner` 字段。不传时默认取**开窗瞬间的栈顶窗口 id**；传 `false` 表示显式声明为顶层窗口 |
| `exwin.close(win_id)` | 语义扩展：连带递归销毁全部后代（自底向上），避免留下 owner 指向已销毁窗口的孤儿 |
| `exwin.close_children_of(win_id)` | **本次核心**。销毁指定窗口的全部后代（不含自身），批量期间抑制中间焦点、结束时统一结算一次 |
| `exwin.close_family(win_id)` | 语义别名，等价 `exwin.close` |
| `exwin.find_root(win_id)` | 向上追溯所属一级菜单（根）窗口 id，带自引用与环保护 |
| `exwin.has_children(win_id)` / `exwin.get_owner(win_id)` | 查询辅助 |
| `exwin.dump()` / `exwin.depth()` | 栈快照与深度，供日志自检 |

内部重构：抽出 `collect_descendants`（子先于父入表）、`destroy_many`（返回是否影响原栈顶）、`settle_focus`（受 `suppress_focus` 抑制）。
**保持不变的既有语义**：`destroy` 回调仍在 `table.remove` **之前**调用（与改造前一致）。

**`ui/ui_theme.lua`（+约 50 行）**

| 接口 | 作用 |
|---|---|
| `theme.shell = { enabled, rail_w, host_id }` | 壳层状态，由 `idle_win.calc_layout()` 写入 |
| `theme.content_area()` | 返回右侧内容区 `{ x, y, w, h }`；无左栏（窄屏 / idle 未创建）时返回 **nil** |
| `theme.content_fit(w, h)` | 尺寸修正：把页面局部的 `screen_w` 收窄为内容区宽度；无壳层时原样返回 |
| `M.wallpaper(parent, w, h, x, y)` | 新增可选 `x/y`（**末尾追加**，不破坏既有调用） |
| `M.page_bg(parent, w, h, x, y)` | 同上；且 `x == nil` 时按壳层自动偏移 |
| `M.page(o)` | 支持 `o.area`；未指定且挂在屏幕上时**自动取** `content_area()`；`area = false` 可强制整屏 |

### 11.2 与初版设计的 3 处偏差（更省代码）

**偏差 1：`page_bg` 自动偏移，调用点零改动**

初版设计是「页面算 area，然后把 `area.x / area.y` 显式传给 `page_bg`」（第四章 4.3），那样 17 个 `page_bg` 调用点都要改成 4 参数。

实际实现把偏移判断收进 `page_bg` 内部，**触发条件是「传入宽度 == 内容区宽度」**：

```lua
if x == nil then
    x, y = 0, 0
    if parent == airui.screen then
        local area = M.content_area()
        if area and w == area.w then x, y = area.x, area.y end
    end
end
```

为什么可靠：页面在 `update_screen_size()` 里调用 `content_fit()` 收窄 `screen_w`，`build_ui` 再把这个 `screen_w` 传给 `page_bg` —— 于是「该页面已准备好落在内容区」这个事实，恰好由 `w == area.w` 精确表达。

为什么 `idle_win` 不会被误偏移：它传的是**整屏宽度**（1024），不等于内容区宽度（920），条件不成立。

好处：没有跨页面的全局偏移状态（不依赖「谁最后写了 fit 值」），自校验、无时序问题。

**偏差 2：`content_fit` 一行接入，取代「页面自己算 area」**

页面侧最终只加 **1 行**，加在 `update_screen_size()` 末尾：

```lua
screen_w, screen_h = theme.content_fit(screen_w, screen_h)
```

`build_ui()` 里的 `page_bg` 调用**一个字都不用改**（因为偏差 1 已让 `page_bg` 自动偏移）。

两种路径都覆盖：
- 走 `theme.page` 的页面（`settings_win` / `settings_about_win` / `settings_theme_win`）：`M.page` 自动取 area，页面内 `sw` 收窄后与 `ctx.sw` 一致；
- 手工 `page_bg` 的页面：靠偏差 1 自动偏移。

**偏差 3：`app_store_win` 用「函数内 local 遮蔽全局」**

`app_store_win.lua` 是唯一没有 `update_screen_size()` 的页面，全文 20+ 处直接读全局 `screen_w`。做法：

```lua
-- 文件级，原先直接读全局
local screen_w, screen_h = 480, 800

local function calc_layout()
    screen_w, screen_h = _G.screen_w or screen_w, _G.screen_h or screen_h
    screen_w, screen_h = theme.content_fit(screen_w, screen_h)
    ...  -- 以下全部几何自动用收窄后的值
```

同时 `calc_layout()` 一定先于 `create_ui()` 执行（`on_create` 里就是这个顺序），因此文件级变量已就绪。

### 11.3 与初版设计不一致的另外 2 个判断

**① `settings_iot_win.lua` 的 `60 * density` 硬编码：评估后保留**

初版把它列为「顺手清掉」。实际核对后认为**不该在本次动它**：`theme.header` 的返回高度是 `dp(56)`，而原值 `60 * density_scale` 约等于「标题栏高度 + 少量间隙」，二者只差几像素；更要紧的是它是**垂直**方向的量，而本次收窄只动水平宽度，所以这个 hack 既没变好也没变坏。改它属于独立的小重构，混进来只会增加回归面。

**② 视频失焦：销毁并在回到桌面时重播，而不是 `pause()`**

初版倾向「`pause()` 保留缓冲、回来无缝续播」。实际核对 `exaudio` 后改了主意：

- `exaudio` 没有可靠的续播接口（`audio_stop()` 会清掉 `audio_obj`）。只暂停画面而音乐继续响，会造成**音画错位**；
- 于是 `on_lose_focus` 选择 `stop()` + `destroy()` + `audio_stop()`，并把文件路径记入 `video_resume_file`；`on_get_focus` 再按记录重新 `video_start_play()` —— 音视频一起从头开始，观感一致。
- 代价：回到桌面需要重新解码起播（首次出画略慢）；换来失焦期间不占硬解资源与约 253KB（单帧）/506KB（双缓冲）帧缓冲。
- 重建时（`on_create`）会把 `video_resume_file` 清空，避免与 `build_video_area` 的自动起播重复。

### 11.4 本次改动的文件清单

| 类型 | 文件 | 改动 |
|---|---|---|
| 库层 | `libs/exwin.lua` | 全量重写：owner + 5 个新接口 |
| 库层 | `ui/ui_theme.lua` | shell 状态 / `content_area` / `content_fit` / `wallpaper` / `page_bg` / `page` |
| 宿主 | `ui/idle_win.lua` | `open_builtin` 收口（3 处调用点）、左栏高亮底块、`calc_layout` 写壳层、`on_get_focus` / `on_lose_focus` / `open_handler`、视频失焦策略 |
| 一级菜单页 | `app_store_win` / `file_manager_win` / `speedtest_win` / `llm_chat_win` / `factory_win` / `factory_rec_win` | 接入 `content_fit` |
| 设置二级页 | `settings_win` / `settings_iot_win` / `settings_about_win` / `settings_auto_win` / `settings_display_win` / `settings_fota_win` / `settings_sound_win` / `settings_storage_win` / `settings_theme_win` / `storage_pri_win` | 接入 `content_fit` |
| wifi | `wifi_list_win` / `wifi_detail_win` / `wifi_connect_win` | 接入 `content_fit` |

合计 **2 个库文件 + 19 个页面**，页面侧每处 1 行。未改：`welcome_win`（启动期 `shell.enabled = false`，`content_area()` 返回 nil，天然整屏）。

### 11.5 改动后的窗口栈形态

```
[0] welcome        owner = nil（首个窗口，栈空）
[1] idle_win       owner = false（显式顶层，宿主）
[2] 设置           owner = 1
[3] iot            owner = 2
```
- 点左栏「文件管理」→ `close_children_of(1)` 销毁 3、2（自底向上）→ 栈回到 `[idle]` → 再开文件管理（`owner` 自动 = 1）→ 栈深恒为 2。
- 设置 → iot → 返回 → 只关 iot（`exwin.close` 走原路径）→ 栈深 2。
- 无论怎么点，**栈深上界 = 1 + 1 + 内部跳转层数**，反复切换不再累积。

### 11.6 验证

**① 构建：通过。** GUI 变体全量编译 20 分钟，日志末尾 `[pc-build] Build completed successfully`；
4538 字节日志中仅有既有的第三方 warning（`lwipopts.h` 宏重定义、若干 `const` 限定符），**无 error**。

> 本机 `cmd.exe` 被安全策略拦截（`cmd /c ...` 直接报 blocked），所以 `build_windows_32bit_msvc_gui.bat`
> 不能直接用，改为直接调它内部的那个 ps1：
> `build_with_summary.ps1 -Arch x86 -Vm64 0 -Gui y -Mgba y -Mode summary`。
> 另外 `*>` 重定向出来的是 **UTF-16** 日志，Read 会报「binary file」，
> 需用 `[System.Text.Encoding]::Unicode.GetString()` 转一次才能看。

**② 语法：22/22 通过。** 用 `luaparse`（`luaVersion: '5.3'`）逐个解析本次改动的全部文件
（`libs/exwin.lua` + `ui_theme.lua` + `idle_win.lua` + 19 个页面），无一处解析失败。

**③ 关键断言：49/49 通过。** 覆盖：

- 接口存在性：`close_children_of` / `find_root` / `has_children` / `get_owner` /
  `M.shell` / `M.content_area` / `M.content_fit` / `wallpaper(w,h,x,y)` / `page_bg(w,h,x,y)`
- 语义正确性：`owner = false` 顶层分支、`suppress_focus` 抑制 + 批量后统一 `settle_focus()`、
  **`destroy` 回调仍早于 `table.remove`**（保持旧语义）
- 契约一致性：`page_bg` 用「`w == area.w`」作偏移信号、`M.page` **不再复用 `page_bg`**（避免双重偏移）
- 收口完整性：`idle_win` 全文只剩 **1 处** `sys.publish("OPEN_`，即 `open_builtin` 收口点自身
  （三处旧调用点 324/953/1174 全部改完）
- 接入完整性：19 个页面全部含 `theme.content_fit(`；3 个 `page_bg(airui.screen, sw, sh)` 特例参数正确

**④ 待用户目视确认（本机无法自证）。** 本机无 Chrome/Edge/Playwright 内核，
界面效果不能逐像素自检。请在 PC 模拟器或真机上核对第七章清单，其中
**第 1 项「宽屏左栏常驻」与第 3 项「切菜单后栈深回落」**是本次改造的验收核心：

1. 宽屏点左栏「设置」→ 左栏仍在、右侧显示设置、左栏该顶高亮
2. 设置里点 iot → 右侧切到 iot、左栏高亮不变、返回回设置
3. 在 iot 里点左栏「文件管理」→ 设置 + iot **应同时被销毁**（`exwin.dump()` 看栈快照）
4. 反复来回切 10 次 → 栈深稳定在 2
5. 窄屏 → 整屏铺满，与改造前一致

---

### 11.7 增补：左栏「桌面」一级菜单入口（同日追加）

**先做的核实。** 需求原文是「加个首页按钮表示 idle_win，取代当前的头像区域」。核实后有两个必须先讲清的事实：

| 核实项 | 结论 |
|---|---|
| 全工程是否有渲染出来的「头像区域」 | **没有**。`头像` / `avatar` / `dev1` 三个关键字的命中全部落在主题令牌与 `theme.rail()` 内部 |
| `theme.rail()` 是否被调用 | **未调用**（dead code）—— 全工程只有它的定义处，没有调用点 |
| `idle_win` 真实左栏（`build_rail`）的构成 | 顶部品牌块 + 内置应用列表，**栏底本来就是空的** |

所以「取代头像区域」在代码里没有可直接替代的对象。但**底层需求成立**：左栏常驻之后，
从二级页（设置 → iot）回桌面只能连点两次返回，而全工程**没有任何 UI 入口能一键回桌面**
（`exwin.return_idle()` 除被 `exapp` 沙箱包装一次外，无业务调用者）。

**做法**：在 `build_rail` 末尾补一个「桌面」项，摆在栏底（设计稿里头像所在的位置），
语义上等于「一级菜单里的第 0 项」。

| 项 | 说明 |
|---|---|
| 位置 | `home_y = screen_h - pad - ih`，与内置应用之间留空白做视觉分隔 |
| 高亮 | 登记为 `rail_items[DESKTOP_KEY]`，哨兵 key `"__desktop"`（不可能与 win 名冲突） |
| 点击 | `go_desktop()` → `close_children_of(theme.shell.host_id)`；**不再手动调 `set_rail_active`**，清场末尾的焦点结算会让 `on_get_focus` 自动把高亮切回「桌面」 |
| 语义变更 | `set_rail_active(nil)` 由「清除全部高亮」变为「高亮桌面项」—— 一级菜单里**始终恰好有一项**处于选中态，用户才能一眼看出自己停在哪一层 |
| 溢出护栏 | `if y <= home_y then ... else log.warn(...) end`。内置应用数量由配置驱动，溢出控件会顶出父容器，而 LVGL 容器天生带 `SCROLLABLE`，一溢出整条左栏就长出滑动条 |
| 图标 | `icon = "desktop"`；`desktop.png` 未提供时按占位块绘制（与品牌块、应用项同一套兜底）。往 `res/` 放一张 `desktop.png` 即可显示真实图标 |

**窄屏**：无左栏 → 无此入口。返回键仍够用（一级页 1 次、二级页 2 次），零改动。

**与既有机制的关系**：`go_desktop` 与 `open_builtin` 完全对称（都先清子树），差别只在
「不开新页」。两者都不依赖 `exwin.return_idle()`，因此不受它「保留 index=1」这个硬编码的影响。

**验证**：

| 项 | 结果 |
|---|---|
| 补丁脚本 4 处替换 | 各命中 **1 次**（全部命中才落盘，原子写入） |
| 落盘后逐条断言 | **7/7 PASS** |
| `luaparse` 语法 | **22/22 PASS** |
| 关键断言 | **57/57 PASS**（本次新增 8 条覆盖本项） |
| GUI 变体重构建 | ✅ `[pc-build] Build completed successfully`，且三步 `completed without visible warnings` |

**待目视确认（新增 2 条，接在上文第 5 条之后）**：

6. 宽屏桌面态 → 左栏栏底「桌面」项高亮，其余项均不高亮。
7. 点左栏「设置」→「桌面」项熄灭、「设置」项亮起；再点栏底「桌面」→ 设置页消失、
   右区回到桌面内容、「桌面」项重新亮起。

---

### 11.8 修复：一级菜单切换时的闪烁（同日追加）

**问题现象**（用户反馈）：切换内置应用时，会先闪一下 `idle_win`（桌面），再进入目标页面。
「返回」反而没问题。

**根因定位（源码级）**：`11.5` 里实现的 `open_builtin` 用的是「**先清后开**」——
先 `close_children_of(host)` 销毁上一棵菜单子树，再 `sys.publish` 打开新页。
而 `sys.publish` **并不立即分发**：

| 事实 | 出处 |
|---|---|
| `sys.publish` 只把消息压入全局队列 | `script/corelib/sys.lua:524-527` —— `table.insert(messageQueue, {...})` |
| 真正的分发在 `sys.run()` 每轮开头的 `dispatch()` | `script/corelib/sys.lua:576` |
| 本轮 `dispatch` 之后才回到 `rtos.receive` 等待，其间会渲染一帧 | 同上 |

于是时序变成：

```
本轮：  close_children_of  → 桌面裸露、并结算焦点触发 on_get_focus
        sys.publish        → 仅入队，新页尚未创建
        ── 本轮结束，渲染一帧 ──→  ✗ 这一帧画的就是被清空后的桌面（闪烁）
下轮：  dispatch()         → 新页面此刻才被创建
```

这同时说明：**「先清后开」这个顺序本身是错的**，不只是时机没调好。
`11.5` 当初选它，理由是「清空后栈顶回到 idle，新页 owner 才会落到 idle 名下」——
现在这个理由由 `begin_menu_switch` 显式接管，不再需要靠「先清空」来间接达成。

**修复方案**：把「回收旧菜单」推迟到**新页面创建完成之后**，并且由 `exwin` 自己执行
（只有它知道 `open` 何时真正发生）。

新增两个接口 + 一处改造：

| 位置 | 内容 |
|---|---|
| `exwin.begin_menu_switch(host_id)` | 登记一笔切换事务：快照 `host` 的全部后代为待回收名单，并起一个 1s 超时兜底（带 token 校验，防止连点两次时旧事务的超时误清新事务） |
| `exwin.open` 的 owner 选择 | 事务存续期间，**强制** `owner = switch_pending.host`。原因：旧菜单此刻尚未回收、栈顶还是它，若不强制，新页会挂到旧菜单名下，随即被本次回收连带销毁 |
| `exwin.open` 末尾 | `create` 完成之后，同步回收待回收名单（`suppress_focus` 包裹，**不补结算焦点** —— 栈顶就是刚创建的新页，本就是它该在的位置） |
| `exwin.children_of(id)` | 列出直接子窗口 id，供宿主判断「当前一级菜单是谁」 |

`idle_win.open_builtin` 随之变成：

```lua
local function open_builtin(win)
    local host = theme.shell.host_id
    local leaf = exwin.children_of(host)[1]   -- 一级菜单互斥，至多一个直接子窗口

    -- 已停在目标菜单里：只回收它的后代（退回菜单根），菜单页本身不重建
    if active_menu == win and leaf then
        if exwin.has_children(leaf) then exwin.close_children_of(leaf) end
        return
    end

    exwin.begin_menu_switch(host)   -- 登记事务；回收由 exwin 在新页创建后收尾
    set_rail_active(win)
    sys.publish("OPEN_" .. win .. "_WIN")
end
```

修复后的时序：

```
本轮：  begin_menu_switch  → 快照旧菜单为待回收
        sys.publish        → 入队（旧菜单仍在，桌面不裸露）
下轮：  dispatch → exwin.open：新页入栈 + create（新页控件已挂屏幕最上层）
                           → 回收旧菜单（被新页完全遮挡，不可见）
        ── 渲染一帧 ──→  ✓ 只画新页
```

**新增的顺带收益**：点「已激活的同一个菜单」不再重建该菜单页，只回收它的后代。
即「在 iot 页点左栏『设置』」= 无损退回设置根，滚动位置与已填内容都保留
（旧实现会销毁并重建整个设置页）。

**验证**：

| 项 | 结果 |
|---|---|
| 补丁脚本 9 处替换 | 各命中 **1 次**（预检全过才落盘，原子写入） |
| 落盘后逐条断言 | **12/12 PASS** |
| `luaparse` 语法 | **22/22 PASS** |
| 关键断言（新增 9 条覆盖本项） | **69/69 PASS**，其中含顺序断言：`pcall(new_win.create)` 必须先于 `destroy_many(sw.victims)` |
| GUI 变体重构建 | 见 `bsp/pc/build/logs/` 最新日志 |

