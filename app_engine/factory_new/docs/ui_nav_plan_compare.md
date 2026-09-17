# 两个 UI 导航改造方案对比分析

对比对象：

- **方案 A**：`docs/ui_nav_owner_area_plan.md`（exwin 增加 `owner` 字段 + `theme.page` 支持 `area` 收窄渲染区域）
- **方案 B**：`docs/ui_nav_refactor_plan.md`（新增 `ui_shell` + `ui_desktop` + `page_manager`，绕开 exwin）

两份文档解决的问题相同（左侧 rail 常驻、右侧显示页面内容、窗口栈深无上界），但技术路线完全不同。

---

## 零、结论

**方案 A 整体更好，但不是完胜。** 九个维度里 A 占优 6 项、B 占优 2 项、1 项持平。

B 的两个真实优势是：

1. **内存峰值更低** —— 进入应用就销毁桌面，桌面对象和视频解码缓冲全部释放；
2. **结构语义更干净** —— rail 归 shell 所有，桌面重建不可能盖住 rail。

这两个优势都可以用很小的代价在 A 里补齐（见第六节），而 B 的劣势（改动面 10 倍、exapp 被阻断、三个既有机制失效）无法用小代价补齐。

**一句话差异**：A 是「给现有 exwin 加一个归属字段，让页面知道自己该画在哪儿」；B 是「把 exwin 从页面路径上摘掉，另建一套页面栈」。A 把复杂度放进库里（`exwin` 171 → 约 250 行），B 把复杂度摊到 19 个页面 + 3 个新模块 + 一次 1830 行文件拆解上。

---

## 一、事实核查：方案 B 中的 5 处错误

写本文档时逐条去源码核实了 B 的关键论据，其中 5 处不成立。

### 1.1 ❌「每个 exwin 窗口持有独立 LVGL 屏缓冲（1024×600×2 ≈ 1.2MB）」

B 的第一条问题描述和第八节预期效果表都建立在这个前提上（「3 个页面叠加 ≈ 3.6MB → 1.2MB」）。

| 核实项 | 源码证据 | 结论 |
|---|---|---|
| `lv_display_create` 调用次数 | `components/airui/src/core/luat_airui_ctx.c:464`，位于 `airui_init` 内 | **全应用只执行一次** |
| 显示缓冲分配 | `luat_airui_ctx.c:500-512`，buf1 / buf2 双缓冲 | **只分配一次** |
| 缓冲大小 | `w * h * bpp / AIRUI_DISPLAY_BUFFER_SIZE_DIVISOR`，默认除数 2（`airui/include/luat_airui_conf.h:43`），本工程未覆盖 | 1024×600 下约 1.2MB |

**1.2MB 是全局唯一一份，与开几个 exwin 窗口无关。** exwin 多窗口只增加 LVGL 控件对象（每个百字节量级）。所以 B 宣称的「3.6MB → 1.2MB」收益不存在，改造前后屏缓冲都固定 1.2MB。

### 1.2 ❌「页面模块代码：含 exwin 样板 ~50 行 → 纯 create/destroy ~30 行」

实测 `ui/settings/settings_iot_win.lua`（二级页代表）的 exwin 样板只有约 14 行：

```lua
local window_id = nil                                     -- 行 9
local function on_get_focus() end                         -- 行 299
local function on_lose_focus() end                        -- 行 300
local function open_handler()                             -- 行 302-309
    window_id = exwin.open({ on_create = on_create, on_destroy = on_destroy,
                             on_lose_focus = on_lose_focus, on_get_focus = on_get_focus })
end
sys.subscribe("OPEN_IOT_WIN", open_handler)               -- 行 311
```

改造后需要 `local M = {}` + `function M.create(parent, w, h)` + `return { destroy = function() ... end }` + `return M`，约 15 行。**这是打平，不是节省 20 行。** 「代码量更少」这个卖点不成立。

### 1.3 ❌ `back_btn:set_hidden(...)` —— 该 API 在 button 上不存在

B 的 `page_manager._update_back_btn()` 写了：

```lua
back_btn:set_hidden(#page_stack <= 1)
```

而 `back_btn` 由 `airui.button` 创建。核实 `components/airui/binding/luat_lib_airui_button.c:294-311`，button 的方法表只有：

```
set_text / get_text / set_disabled / set_style / set_stype /
set_on_click / set_on_pressed / set_on_released / set_on_long_press /
get_pos / set_pos / move / focus / destroy / is_destroyed
```

**没有 `set_hidden`。** 全仓 `set_hidden` 只在 container 上实现（`luat_lib_airui_container.c:240`），另有 keyboard 的 `hide`、msgbox 的 `hide`。所以这段代码一执行就会抛 `attempt to call a nil value (method 'set_hidden')`。

### 1.4 ❌ 文件清单不全，漏 6 个使用 exwin 的文件

B 第三节列了 18 个文件。实际使用 `exwin.open` / `exwin.close` 的文件（grep `exwin\.(open|close|is_active|return_idle)` 结果）还包括：

| 漏项 | 位置 | 说明 |
|---|---|---|
| `ui/welcome_win.lua` | 168 / 75 | 开机动画，栈底之上的第一层窗口 |
| `ui/factory_rec_win.lua` | 381 / 255 | 双窗口（含 `on_get_focus`/`on_lose_focus`） |
| `ui/settings/settings_theme_win.lua` | 219 / 68 | 主题切换页 |
| `ui/wifi/wifi_connect_win.lua` | 534 / 373 / 460 / 533 | **含 `exwin.is_active` 守卫** |
| `ui/wifi/wifi_detail_win.lua` | 307 / 259 / 306 | **含 `exwin.is_active` 守卫** |
| `app/settings/settings_auto_app.lua` | 234 / 170 | 用 exwin 开弹窗，不属于 `ui/` 目录 |

漏掉 `welcome_win` 意味着改造后的启动时序没有被评估过。

### 1.5 ⚠️ `scrollable` 参数是死参数（两份文档都该记的技术债）

`ui_theme.lua` 有 4 处 `scrollable = (o.scrollable == true)`（行 284 / 356 / 789 / 1185），`idle_win.lua:1773` 也直接用了 `airui.container({ ..., scrollable = true })`。

核实 `components/airui/src/components/widgets/luat_airui_container.c:36-46`，container 创建时只解析：`parent / x / y / w / h / color / color_opacity / radius / border_color / border_width`。**`scrollable` 不在其中。**

但代码「看起来能用」是有原因的：`components/airui/lvgl9/src/core/lv_obj.c:578` 里 `obj->flags |= LV_OBJ_FLAG_SCROLLABLE;` —— LVGL 基础对象**默认就带 SCROLLABLE**。

所以真实情况是：

- `scrollable = true` → 无效但恰好与默认值一致，看不出问题；
- `scrollable = false` → **静默失效**，容器照样能滚。这是潜在的坑。

建议在 `ui_theme.lua` 注释里标注该参数当前未生效，或补上 C 绑定（改 C 必须走 GUI 构建 `bsp/pc/build_windows_32bit_msvc_gui.bat`）。

---

## 二、九个维度逐项对比

### 2.1 代码量 · 改动面 —— A 明显更优

关键指标不是「净增行数」，而是**被改写的既有行数**，因为改写才是出 bug 的地方。

| | 方案 A | 方案 B |
|---|---|---|
| 新增模块 | 0 个 | 3 个（`ui_shell` / `page_manager` / `ui_desktop`） |
| 库内改动 | `exwin.lua` +约 79 行 | 不动 exwin，但 exwin 从页面路径上被摘除 |
| 单页改动 | 约 5 行（改本地尺寸来源 + 传 `area`） | 约 30~60 行（首尾接口重写 + 子页跳转改法） |
| 19 页合计改写 | **约 85 行** | **约 600~1100 行** |
| 最重文件 | `idle_win.lua` 只改 3 处 publish | `idle_win.lua` 1830 行需拆成 `ui_desktop` + rail，并改造为可重复 `create`/`destroy` |
| 改写倍数 | 1× | **约 7~13×** |

B 最危险的一项不是行数，而是**把 `idle_win` 拆成可重建组件**。桌面是全应用最重的一页：硬件解码 MJPG 视频 + 配套 MP3 音频、天气卡、应用网格、翻页器、充电动画、外部应用扫描，还有一堆定时器与订阅。把这些从「只创建一次」改造成「可反复创建销毁」是全新引入的生命周期风险，而收益只是「名字更干净」。

> **更正我自己上一版文档**：`ui_nav_owner_area_plan.md` 里写「只需在 `update_screen_size()` 里把 `screen_w` 收窄为 `area.w`，323 处引用自动免改」。机制是对的，但**不存在单一的全局收窄点** —— 每个页面文件都有自己的 `local screen_w, screen_h = 480, 800`（如 `settings_iot_win.lua:15`、`settings_win.lua` 同构），各自从 `lcd.getSize()` 推导。所以要改的是 **19 个文件各 2 行**，不是 1 处。总体改动量仍然很小，但表述需要纠正。
>
> 好消息是收窄机制本身成立：页面内部所有控件都以 `parent = base` 创建，LVGL 子对象坐标**相对父容器**，所以把 `base` 摆到 `(rail_w, 0)`、把页面的 `screen_w` 设为 `area.w`，内部所有 `x = screen_w * 0.08` 这类比例式写法**一处都不用改**。

### 2.2 稳态运行效率 —— A 更优

| 维度 | 方案 A | 方案 B |
|---|---|---|
| 单帧渲染面积 | 920×600（-10.2%） | 920×600（-10.2%） |
| 左栏 rail | 不重建（idle 常驻） | 不重建（shell 常驻） |
| 回桌面 | **零重建** | **整页重建** |
| 回桌面重建内容 | — | 视频首帧重解 + MP3 重起、外部应用重扫、网格 N 个 tile 重建 |
| 进应用 | 新页创建 | 新页创建 + 桌面销毁 |
| 栈深上界 | 1 + N | shell + 内容栈 |

B 的代价在于**桌面是全应用最重的页面**，而它每次回桌面都要完整走一遍「销毁 → 创建」。反复点 rail 来回切换 = 反复付这笔钱。A 因为桌面常驻，回桌面是瞬时的。

### 2.3 内存峰值 —— B 更优（这是 B 最硬的优点）

**这一点需要更正我上一版文档的结论。** 我之前写「内存是这次改造最大的收益，两方案的栈深上界一致」，把内存当成持平项。核实 `idle_win` 后，这个判断不准确。

`idle_win.lua` 持有硬件解码的 MJPG 播放组件：

```lua
-- idle_win.lua:1818-1827
video_obj = airui.video({
    parent = video_card, w = vw, h = vh,     -- vw/vh 取自 MJPG 文件头，典型 480×270
    src = video_current_file,                -- /luatos_boot.mjpg
    format = "mjpg", decode_mode = "hw",
    interval = 33, loop = video_is_loop, auto_play = true,
})
```

- `airui_video_videoplayer_ctx_t` 持有解码后端上下文与帧缓冲。480×270 一帧 RGB565 = 约 253KB，若后端双缓冲则约 506KB。**这很可能是全应用最大的一笔单体分配**，远超「1.2MB 屏缓冲」之外的所有控件对象。
- 该组件在 `idle_win.on_destroy` 里才被释放（行 1976-1980：`video_obj:stop()` + `video_obj:destroy()`）。

于是：

| | 进入应用后的常驻内存 |
|---|---|
| 方案 A（idle 常驻） | 桌面控件（约 150~250 个对象）+ **视频解码缓冲** |
| 方案 B（桌面销毁） | 仅当前页 |

所以 **B 的峰值内存确实更低**，这是它真实的优势。

**但 A 可以花 2 行拿到大部分收益** —— 见第六节第 1 项：在 `idle_win.on_lose_focus` 里显式释放视频。而且 A 保留了选择权：`pause`（停 CPU、保缓冲、回来无缝续播）还是 `destroy`（释放缓冲、回来从第 0 帧重播），B 只有后者。

### 2.4 耦合性 —— A 更优

| | 方案 A | 方案 B |
|---|---|---|
| 窗口栈数量 | **1**（`exwin.win_stack`） | **2**（exwin + `page_manager.page_stack`） |
| 新增模块 | 0 | 3 |
| 页面间通信 | 保留事件总线（`sys.publish("OPEN_IOT_WIN")`） | 改为**直接 require**：`page_manager.push_page("iot", iot.create, iot.destroy)` |
| 可测试性 | 页面需 `exwin` | 页面需 `page_manager`（换了个依赖而已） |

B 的 `push_page` 要求调用方持有子页面的 `create`/`destroy` 函数，所以 `settings_win` 必须 `require "settings_iot_win"`。这**把消息总线换成了模块直接依赖**：原来设置页不知道、也不需要知道 iot 页的存在，现在两者强绑定，还形成一个跨页面的依赖图。同时 `ui_main.lua` 里按 `project_config.features` 集中门控可选窗口的做法，会随着直接 require 被分散到各页面。

另外，双栈并存意味着「屏幕上有什么」有两个事实来源。`exwin.is_active` / `exwin.return_idle` / `exapp` 的窗口计数都指向那个**不再代表 UI 的栈**，语义会静默偏移。

### 2.5 既有语义兼容 —— A 完全兼容，B 三处失效

**（1）`exwin.is_active` 防重开守卫失效**

三个页面用它作为「已经开着就别再开」的守卫：

```lua
-- ui/wifi/wifi_list_win.lua:542
if not exwin.is_active(window_id) then
    window_id = exwin.open({ ... })
end
-- ui/wifi/wifi_detail_win.lua:306、ui/wifi/wifi_connect_win.lua:533 同构
```

迁移到 B 后这些页面不再是 exwin 窗口，`is_active` 恒为 false → **守卫失效，可重复创建**。B 的页面改造模板没有覆盖这一点。

**（2）`exwin.return_idle()` 不再回桌面**

`libs/exwin.lua:171-188` 的 `return_idle()` 逻辑是「销毁 index 2..N，保留 index 1」。

- 方案 A：index 1 就是 `idle_win` → **行为完全正确，一行不改** ✅
- 方案 B：index 1 变成 `ui_shell` → 它销毁的是 shell 之上的窗口（welcome、三方应用窗口），**页面栈里的页面一个都不动** → 「返回首页」对内置页面失效 ❌

**（3）`exapp` 的三方应用窗口机制被阻断**

`libs/exapp.lua` 为三方应用包了一层 exwin，并用**窗口数量**驱动应用生命周期：

```lua
-- exapp.lua:2806-2812
local function check_windows()
    if #win_ids == 0 then
        my_env.log.info("exapp_window", "window count is 0, auto exit app")
        my_env.exapp.close()          -- 窗口清零 → 自动退出应用
    end
end

-- exapp.lua:2817-2824
my_env.exwin.open = function(config)
    local win_id = glob_exwin.open(config)
    if win_id then table.insert(win_ids, win_id) end
    return win_id
end

-- exapp.lua:2827-2835
my_env.exwin.close = function(win_id)
    local locked = (fskv.get("app_autostart_locked") or "0") == "1"
    if locked and #win_ids <= 1 then
        glob_sys.publish("AUTOSTART_REQUEST_EXIT_PASSWORD")   -- 自启锁：拦关闭
        return
    end
    ...
```

- 若三方应用的页面被迁移到 `page_manager`，`win_ids` 永远为空 → `check_windows()` 判定窗口数为 0 → **应用一进去就自动退出**；
- 若不迁移（三方应用继续用 exwin 全屏），那它打开时仍会盖住 rail，**与本次改造目标不一致**，形成内置页/三方页两套行为。

方案 A 下这个机制**完全不受影响**：内置页仍是 exwin 窗口，与三方应用同构，`win_ids` 语义照旧。**这是 A 相对 B 最决定性的一项。**

### 2.6 增量交付 / 回滚 —— A 更优

| | 方案 A | 方案 B |
|---|---|---|
| 能否逐页灰度 | **能** —— 未改的页面走 `area = nil`，行为与现在完全一致 | **不能** —— 页面接口从 `exwin` 换成 `create/destroy`，必须一次性切完 |
| 回滚成本 | `theme.shell.enabled = false` 一行 | 无（19 页接口已改） |
| 首个可验证节点 | idle ↔ 设置 ↔ iot 一条链 | 需先完成 shell + page_manager + ui_desktop 三个模块 |

A 允许「新旧页面共存」这一点，对 21 个窗口文件的工程非常关键。

### 2.7 结构清晰度 —— B 略优（真实优点）

B 把 rail 放进 `ui_shell`、页面放进步 `content_area`，于是**桌面/页面的重建不可能盖住 rail**——它们在结构上不是兄弟节点。

方案 A 下 rail 和桌面内容都在 `idle_win.main_container` 里，页面是 `airui.screen` 下的另一个兄弟节点。这会引出一个我在上一版文档里**没有写到的具体风险**：

> `idle_win.on_get_focus` 里有「主题脏则 `on_destroy()` + `on_create()`」的重建逻辑。重建时新容器会成为 `airui.screen` 的**最后一个子节点**，在 LVGL 里就是 z 序最上层 —— 如果此页面在重建瞬间恰好有子页面在栈上，**重建后的桌面会盖住子页面**。
>
> 而 `airui.container` 只有 `set_pos / move / set_hidden / hide / open / destroy`，**没有 `move_to_background`**，没法事后调整 z 序。

好消息是 A 只要遵守「成为栈顶时才重建」即可规避：`close_children_of` 末尾结算一次焦点（让 idle 在子页面全部关闭后重建），重建就发生在没有上层页面的时候。这一点已写在 `ui_nav_owner_area_plan.md` 的 `open_builtin` / `close_children_of` 设计里（先清后开）。

**但这个 z 序风险是 B 从结构上天然免疫的，属于 B 的真实优势。**

### 2.8 其他差异

| 项 | 方案 A | 方案 B |
|---|---|---|
| 启动时序 | 不变（welcome 先 `publish OPEN_IDLE_WIN` 再 `exwin.close`，与现在一致） | `OPEN_IDLE_WIN` 会立即触发 `shell.on_create → go_home()`，在 welcome 尚未关闭时就建桌面并起视频 |
| 返回按钮 | 沿用各页自带标题栏返回 | shell 额外加一个浮动返回按钮（`content_area` 右下角），与页面自带标题栏返回**功能重复** |
| 页面归属判定 | 声明式：`owner = 当前 window_id`，由 exwin 自动记录 | 由 `page_manager.open_app` 的 `current_app` 变量维护 |
| 新增 API 面 | exwin 从 4 → 7 个接口 | exwin 不变；新增 `page_manager` 约 10 个接口 |

---

## 三、两个方案各自的独有风险

### 3.1 方案 B 独有

| # | 风险 | 级别 | 依据 |
|---|---|---|---|
| 1 | `exapp` 窗口数判定导致三方应用进入即自退；自启解锁保护失效 | 🔴 阻断 | `exapp.lua:2806-2856` |
| 2 | `back_btn:set_hidden` 不存在，一行代码直接抛错 | 🔴 运行时报错 | `luat_lib_airui_button.c:294-311` |
| 3 | `exwin.return_idle()` 不再回桌面 | 🟠 功能退化 | `exwin.lua:171-188` + shell 成为 index 1 |
| 4 | `exwin.is_active` 守卫失效，wifi 三页可重复创建 | 🟠 功能退化 | `wifi_list_win.lua:542` 等 |
| 5 | 拆解 `idle_win`（视频/定时器/订阅/天气/网格）为可重建组件 | 🟠 高工作量高风险 | `idle_win.lua` 1830 行 |
| 6 | 页面改 `require` 子页，破坏总线解耦与 features 集中门控 | 🟡 耦合上升 | `settings_win.lua` 现用 `sys.publish(event)` |
| 7 | 文件清单漏 6 个文件，含 `welcome_win` | 🟡 遗漏 | 见 1.4 |
| 8 | 内存收益论据错误（屏缓冲全局一份） | 🟡 决策依据失真 | 见 1.1 |
| 9 | 回桌面整页重建（视频重解、外部应用重扫） | 🟡 效率退化 | `ui_desktop.create` 每次全建 |

### 3.2 方案 A 独有

| # | 风险 | 级别 | 依据 / 对策 |
|---|---|---|---|
| 1 | **桌面视频在失焦后继续解码、音频继续播放** | 🔴 必须在改造中一并修掉 | `idle_win.on_lose_focus`（行 2048-2051）只停 `timer_handler` 与 `stop_charge_anim()`，**不含视频**；`luat_airui_video.c:564` 的唯一门控是 `data->playing`，无任何可见性/遮挡判断。**注意这是当前架构已有的 bug**，不是 A 引入的。对策见 6.1 |
| 2 | 主题重建的 z 序可能盖住上层页面 | 🟠 | 见 2.7；靠「先清后开 + 成为栈顶才重建」规避 |
| 3 | 19 个文件各有独立的 `local screen_w`，需逐文件改 2 行 | 🟡 | 见 2.1 的更正说明 |
| 4 | 窄屏无 rail，需 `area = nil` 回退到整屏 | 🟡 | `idle_win.lua:206` 起 `use_rail = (sw >= 560)`；`exwin.content_area()` 内部判断后返回 `nil` |
| 5 | `idle_win` 职责未减（仍兼任 rail 宿主 + 桌面），仍是最重文件 | 🟡 | 可后期只抽出 rail（约 150 行）改善，不需要动桌面 |

---

## 四、三个决定性差异

如果只记三条，记这三条：

**1. 方案 B 会阻断 `exapp` 三方应用机制。**
它不是「多花点工」的问题，而是「迁移后三方应用进不去」的硬阻断，除非同时改造 `exapp.lua` 的窗口计数逻辑——而 B 的文档完全没提。方案 A 因内置页仍是 exwin 窗口，天然零冲突。

**2. 方案 B 的改动面是 A 的 7~13 倍，且集中在最难的地方。**
A 改的是「页面的尺寸来源」（19 × 2 行）和「谁来清子页面」（`exwin` 一个函数）。B 改的是每个页面的**公共接口**，还要把 1830 行 `idle_win` 拆成可反复创建销毁的组件——而这块代码里跑着硬件解码视频、音频、定时器和一堆订阅。

**3. 方案 B 唯一的硬优势是内存峰值，而这个优势 A 用 2 行就能拿到大部分。**
B 靠「销毁桌面」释放桌面对象与视频解码缓冲；A 只需在 `idle_win.on_lose_focus` 里显式停掉视频，即可释放最大的那一笔分配。且 A 还能选择 `pause`（保缓冲、无缝续播）而非只能 `destroy`。

---

## 五、我上一版文档需要更正的两处

诚实标注，避免后续按错误前提实施：

| # | 原表述 | 更正 |
|---|---|---|
| 1 | 「内存是这次改造最大的收益……栈深上界一致，内存表现持平」 | **不准确。** 方案 A 因桌面常驻，峰值内存高于方案 B（B 会释放桌面对象与视频解码缓冲）。A 必须补上「失焦释放视频」，否则改造后峰值内存比 B 差。 |
| 2 | 「只需在 `update_screen_size()` 里收窄 `screen_w`，323 处引用自动免改」 | **机制对、表述错。** 不存在单一全局收窄点；19 个文件各有独立 `local screen_w`，需逐文件改 2 行。但收窄后页面内部所有比例式几何确实免改（子坐标相对父容器）。 |

---

## 六、推荐路线：方案 A + 3 项补强

采纳 A 的骨架，把 B 的两个真实优势补进来：

### 6.1 补强 1：失焦释放视频（拿到 B 的内存优势）

```lua
-- idle_win.lua，替换现有 on_lose_focus（行 2048-2051）
local function on_lose_focus()
    if timer_handler then sys.timerStop(timer_handler); timer_handler = nil end
    stop_charge_anim()
    -- 新增：桌面被覆盖时释放最大的单体分配（硬件解码缓冲）
    if video_obj then
        pcall(function() video_obj:stop() end)
        pcall(function() video_obj:destroy() end)
        video_obj = nil
    end
    audio_stop()
end

-- on_get_focus 里按需重建（现有 on_get_focus 已具备重建能力，挂上即可）
```

若实测缓冲常驻内存可接受，也可改为 `video_obj:pause()` 保留缓冲，回来时无缝续播、不重解首帧 —— 这是 A 相对 B 的额外自由度。

### 6.2 补强 2：只抽 rail，不抽桌面（拿到 B 的结构优势）

从 `idle_win` 抽出 **rail 构建逻辑（约 150 行）** 到一个 `ui_rail.lua`，由 idle 持有。这样 rail 与桌面内容在代码上分离，主题重建的 z 序风险被结构性消除，且**不需要触碰桌面的任何布局代码**（对比 B 要动 1500 行）。

### 6.3 补强 3：给 `airui.container` 补 `move_to_background`（或确认可不需要）

如果 6.2 之后仍需在运行时调整 z 序，需要新增一个 C 绑定（container 目前只有 `set_pos / move`，无 z 序操作）。建议先不做，靠「先清后开」规避；若实测出现桌面盖住子页面的情况再补，补时须走 GUI 构建。

### 6.4 顺手清掉的技术债

| 项 | 位置 | 动作 |
|---|---|---|
| `scrollable` 死参数 | `ui_theme.lua:284 / 356 / 789 / 1185`、`idle_win.lua:1773` | 补 C 绑定或加注释标注未生效；否则 `scrollable = false` 会静默失效 |
| `60 * density_scale` 硬编码 | `settings_iot_win.lua:303` 附近（绕开标题栏高度） | 改用 `theme.page` 的 `ctx.y`，区域变化后 60 不再正确 |
| `return_idle()` 硬编码 index=1 | `libs/exwin.lua:171-188` | 语义上标注「回到栈底一级页面」，避免误以为能回任意一级菜单 |

---

## 七、源码索引

| 主题 | 位置 |
|---|---|
| 窗口栈实现 | `libs/exwin.lua:75-188` |
| `exapp` 三方应用窗口计数 / 自启锁 | `libs/exapp.lua:2806-2856` |
| 全局唯一屏缓冲 | `components/airui/src/core/luat_airui_ctx.c:464, 500-512` |
| 缓冲除数配置 | `components/airui/include/luat_airui_conf.h:43` |
| container 创建时解析的 key | `components/airui/src/components/widgets/luat_airui_container.c:36-46` |
| container 方法表（有 set_hidden） | `components/airui/binding/luat_lib_airui_container.c:236-247` |
| button 方法表（无 set_hidden） | `components/airui/binding/luat_lib_airui_button.c:294-311` |
| LVGL 默认 SCROLLABLE | `components/airui/lvgl9/src/core/lv_obj.c:578` |
| 视频组件门控（仅 playing） | `components/airui/src/components/widgets/luat_airui_video.c:563-576, 848-871` |
| idle_win 视频资源与释放 | `ui/idle_win.lua:1779-1908`（构建）、`1966-1981`（销毁） |
| idle_win 失焦逻辑（未停视频） | `ui/idle_win.lua:2048-2051` |
| rail 与宽屏判定 | `ui/idle_win.lua:203-206` |
| `is_active` 守卫 | `ui/wifi/wifi_list_win.lua:542`、`ui/wifi/wifi_detail_win.lua:306`、`ui/wifi/wifi_connect_win.lua:533` |
| 页面本地尺寸推导样例 | `ui/settings/settings_iot_win.lua:15, 27-41` |
| 页面 exwin 样板样例 | `ui/settings/settings_iot_win.lua:9, 299-311` |
| 启动时序 | `ui/welcome_win.lua:65-77`、`ui/ui_main.lua` |
