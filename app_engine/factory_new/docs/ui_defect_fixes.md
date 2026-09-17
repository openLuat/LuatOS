# 本轮缺陷修复 —— 遮罩 / 沙箱心跳 / 圆角裁剪 / 玻璃主题左栏

> 版本 1.0 · 2026.09.17
> 涉及文件：`ui/app_store_win.lua`、`libs/exapp.lua`、`ui/idle_win.lua`、`ui/ui_theme.lua`、
> `ui/ui_theme_themes.lua`、`components/airui/src/components/widgets/luat_airui_container.c`
> 关联文档：[`ui_theme_v2.md`](./ui_theme_v2.md)（第四条修复的主题体系背景）、
> [`ui_nav_owner_area_plan.md`](./ui_nav_owner_area_plan.md)（左栏常驻的由来）

四条用户反馈，逐条定位到源码级成因。**其中第 2 条与左栏常驻无关，是既有的 PC 模拟器缺陷**。

| # | 现象 | 根因归属 | 是否本轮引入 |
|---|---|---|---|
| 1 | 下载应用的遮罩不是全屏，右侧缺一条左栏宽度的区域 | 导航改造（`content_fit` 把 `screen_w` 收窄）与遮罩的全屏假设冲突 | 既有代码 + 改造后暴露 |
| 2 | 打开安装的应用再关闭 → 哪里也点击不了 | `exapp.sandbox_cleanup` 停了 LVGL 心跳却从不恢复 | **既有缺陷**（仅 PC 模拟器） |
| 3 | 播放器按钮栏外部露出两个方角 | 圆角卡片没有裁剪贴边的方形子组件 | 既有缺陷 |
| 4 | 琥珀夜空 / 青竹幽谷主题左栏没变化 | 两套玻璃主题的 `rail_bg` 与 `OPA.rail` 完全相同 | 主题 v2 的设计漏洞 |

---

## 一、下载遮罩不是全屏（右侧缺一条左栏）

### 根因

```lua
-- ui/app_store_win.lua · show_progress_dialog（修复前）
local msk = airui.container({
    parent = airui.screen,          -- ← 挂在屏幕上，坐标从 (0,0) 起
    x = 0, y = 0,
    w = screen_w, h = screen_h,     -- ← 但这是 content_fit 收窄后的「内容区」尺寸
    color = theme.C.black, color_opacity = 180,
})
```

本页的 `screen_w / screen_h` 在 `calc_layout()` 里被 `theme.content_fit()` 改成内容区尺寸
（宽屏下 = 整屏宽 − 左栏宽）。遮罩的父节点是 `airui.screen`、起点是 `(0,0)`，
于是它只覆盖 `x ∈ [0, area.w]`，**右侧正好漏出一条左栏宽度的区域**没被压暗。

对照：`exapp` 的 UI 沙箱容器用的是 `ctx.screen_w`（真全屏），同一个界面里两套坐标混用。

### 修法

取全局的全屏尺寸，遮罩与弹窗几何都用它：

```lua
local full_w = _G.screen_w or screen_w
local full_h = _G.screen_h or screen_h
```

`_G.screen_w / _G.screen_h` 是未收窄的全局值（本页 `calc_layout()` 开头就是从这里同步的）。
遮罩盖满整屏同时也带来正确的模态语义：下载/安装期间左栏也不可点，不会中途切菜单。

---

## 二、打开安装的应用再关闭 → 哪里也点击不了

### 根因：LVGL 心跳被停掉后没有再恢复

```lua
-- libs/exapp.lua · sandbox_cleanup（修复前）
if lvgltimer and lvgltimer.stop then
    local ok, err = pcall(lvgltimer.stop)     -- ← 停了
end
-- ...销毁沙箱容器...
-- 之后没有任何 lvgltimer.start()
```

`lvgltimer` 是 **PC 模拟器专属模块**（`bsp/pc/src/main_mini.c:243-253` 注册；
真机没有这个模块，`lvgltimer` 为 `nil`，所以只有模拟器会中招）。它的语义是：

| API | 作用 |
|---|---|
| `lvgltimer.stop()` | `lvgl_timer_enabled = 0` → 定时器回调直接 return，**不再调用 `lv_tick_inc` + `lv_task_handler`** |
| `lvgltimer.start()` | 恢复为 1 |

停跳之后：LVGL 不再打 tick、不再跑 task handler → **输入不再被处理、界面不再重绘**。
画面停在最后一帧上，看起来像「界面还在、就是点不动」，而不是崩溃 ——
用户的原话就是「哪里也点击不了」。

停跳的动机是对的（注释写着：防止控件销毁过程中 timer 回调访问已释放内存导致 C0000005），
缺的是配对的恢复。**任何「已安装应用」退出都会走 `sandbox_cleanup`**：
`exapp.open` → 沙箱容器 → 应用窗口 `exwin.close` → 包装层 `check_windows()`
（`#win_ids == 0`）→ `my_env.exapp.close()` → 应用协程 `sys.waitUntil` 返回 →
`sandbox_cleanup`。于是「打开一个已安装的应用再关掉」必然触发。

### 修法

在沙箱容器销毁之后、退订/清模块/GC 之前恢复心跳：

```lua
if sandbox_container then
    local ok, err = pcall(sandbox_container.destroy, sandbox_container)
    ...
end

-- 恢复 LVGL timer（必须与上面的 stop 配对）
if lvgltimer and lvgltimer.start then
    local ok, err = pcall(lvgltimer.start)
    ...
end
```

位置选择：`sandbox_container.destroy` 是唯一需要保护的销毁动作（它是所有应用控件的根），
销毁完就可以恢复；后面只剩 `unsubscribe_all` / 清 `package.loaded` / `collectgarbage`，
都不碰 LVGL 控件。

> ⚠️ 同一份代码在 `script/libs/exapp.lua` 还有一份拷贝，**本轮未同步修改**。
> 若其他工程也用那份，需要同样处理。

---

## 三、播放器按钮栏外部露出两个方角

### 根因

`idle_win.build_video_area()` 的结构：

```
video_card        圆角卡片（radius = theme.R.md，黑色实底）
 └── airui.video  画面（居中，不贴边）
 └── video_ctrl_bar  控制栏：等宽、贴底、radius = 0（方形）
```

LVGL 默认**不把子组件裁到父对象的圆角里** —— 只有父对象打开了 `clip_corner`
（等价 CSS 的 `overflow:hidden`）才会裁。于是控制栏的两个直角正好盖在卡片的
左下 / 右下圆角上，卡片边缘就冒出两个方角；控制栏底色取 `theme.C.panel`，
在浅色主题下 panel 是白色，所以用户看到的是「两个白色的方角」。

AirUI 的容器创建只解析 `radius` 等少数键，`lv_obj_set_style_clip_corner` 没有暴露出来。

### 修法：给容器补上 `clip_corner`

**C 侧**（`components/airui/src/components/widgets/luat_airui_container.c`，纯增量、默认 false）：

```c
bool clip_corner = airui_marshal_bool(L, idx, "clip_corner", false);
...
if (clip_corner) {
    lv_obj_set_style_clip_corner(container, true, main_default);
}
```

**Lua 侧**：`theme.box` / `theme.card` 透传 `clip_corner`，
`build_video_area` 的视频卡片传 `clip_corner = true`。

这是通用能力：任何「圆角卡片 + 贴边方形子组件」的组合都能用它消除同样的方角
（应用网格卡、时钟卡等如出现同类现象可直接传参）。本轮只改视频卡片，不扩大回归面。

---

## 四、琥珀夜空 / 青竹幽谷主题左栏没变化

### 根因

两套主题同属**深色玻璃档**，`rail_bg` 都是 `0xFFFFFF`、`OPA.rail` 都是 `26`：

| 主题 | 底色 | `rail_bg` | `OPA.rail` | 左栏合成色 | 栏上 `t2` |
|---|---|---|---|---|---|
| amber 琥珀夜空 | `0x0D131C` | `0xFFFFFF` | 26 | `0x2D2E31` | `0x95A0AE` |
| forest 青竹幽谷 | `0x0E2619` | `0xFFFFFF` | 26 | `0x273C30` | `0x94B3A4` |

合成色只差 ΔE **5.6**，`t2` 文字色也几乎一样 —— 左栏 100px 宽、对比又低，
「细看可分」在实际观感上就是「没变」。**两套主题的差异全在内容区，唯独左栏相同。**

### 修法

把「是哪一套主题」交给各主题自己的 `rail_bg` 色相，并把玻璃档 `rail` 从 26 提到 40：

| 主题 | `rail_bg` | 左栏合成色 | 栏上 `t2` 对比度 |
|---|---|---|---|
| amber | `0xFFD9A0`（暖琥珀） | `0x333231` | 4.8 |
| forest | `0xBFF2DA`（竹青） | `0x2A4637` | 4.6 |

| 指标 | 修复前 | 修复后 |
|---|---|---|
| amber ↔ forest 左栏 ΔE | 5.6 | **16.8** |
| 深色档内左栏最接近对 | amber ↔ forest 5.6 | amber ↔ forest 16.8 |

玻璃的通透感保留（40/255 ≈ 16%，桌面光斑仍能透上来），只是左栏颜色现在跟着主题走。

---

## 五、设置里的屏幕分辨率显示不正确

> 用户反馈：「设置里面的屏幕分辨率显示不正确」。

### 根因：又一处「收窄后的 `screen_w` 被当成整屏用」

与第一条遮罩缺陷**同源**。桌面导航改造后，页面的 `update_screen_size()` 会把局部的
`screen_w / screen_h` 交给 `theme.content_fit()` 收窄：

```lua
-- ui_theme.lua
function M.content_fit(w, h)
    local area = M.content_area()   -- { x = rail_w, y = 0, w = screen_w - rail_w, h = screen_h }
    if not area then return w, h end
    return area.w, h                -- ⚠ 宽度变成「内容区宽度」
end
```

而 `settings_win.lua` 收窄之后，**设备信息卡又拿同一对 `sw / sh` 去显示「屏幕分辨率」**：

```lua
{ "屏幕分辨率", string.format("%d × %d", sw, sh) },   -- sw 此时已是内容区宽度
```

于是 1024×600 的屏上显示成 `824 × 600` —— **少掉的正好是一条左栏宽度**，
与第一条遮罩缺陷的现象完全一致。

### 修法：把「整屏」与「内容区」两个尺寸分开存

```lua
local sw, sh = 480, 800
-- scr_w/scr_h 是「整屏」尺寸，sw/sh 会被 content_fit 收窄成内容区宽度（全屏 − 左栏），
-- 展示「屏幕分辨率」必须用前者，否则宽屏下会少写一条左栏宽度。
local scr_w, scr_h = 480, 800

local function update_screen_size()
    scr_w, scr_h = screen_w or 480, screen_h or 800
    sw, sh = scr_w, scr_h
    -- 宽屏有左栏时收窄到右侧内容区（窄屏原样返回）
    sw, sh = theme.content_fit(sw, sh)
    ...
end
```

展示行改用 `scr_w / scr_h`，**布局仍旧全部走 `sw / sh`**。
分辨率是「设备的属性」，不是「当前页面的可用宽度」，两者不该共用一个变量。

### 这类缺陷的共同识别方法

凡是**挂在 `airui.screen` 上、或者描述设备本身**的量
（遮罩、弹窗居中基准、屏幕分辨率、全屏截图范围），都不能用页面里收窄后的 `screen_w`。
取整屏尺寸一律走 `_G.screen_w / _G.screen_h`（或像本页这样单独留存一份 `scr_w / scr_h`）。

---

## 六、验证

| 项 | 结果（截至 v3 主题批改） |
|---|---|
| 补丁落盘 | `patch_glass_rail.py` 4 / 4；`patch_theme_v3.py`（分辨率 + 主题集）、`patch_theme_v3b/c.py`（注释与判据收口）逐条 count 断言通过 |
| 源码级只读复核 `verify_theme_v3.py` | ✅ **29 / 29**（主题 9 套 / order 1..9 / 无 blob 残留 / 分辨率取整屏 / 上一轮成果未回退） |
| `theme_audit_v2.py` | ✅ **12 / 12**（新增：主题数恰为 9 套、同档位内左栏 ΔE ≥ 8） |
| `parse_check.js` | ✅ 语法 **24 / 24**、断言 **114 / 114** |
| GUI 变体构建 | 见构建日志 `[pc-build] Build completed successfully` |

### 审计脚本本轮新增的判据

**「同档位内左栏底色 ΔE ≥ 8」** —— 为什么是这个范围：

- 只在**同档位**内要求：跨档位时整屏明度差得远，左栏差 ΔE 6 也不影响「换了一套主题」的
  判断（用户报的正是两套深色玻璃之间）。
- **浅色档豁免**并写明理由：那三套的设计就是「近白面板 + 微色偏」
  （`ui_theme_themes.lua` 文件头），靠品牌块 / 选中块的强调色区分，
  强行拉开到 ΔE 8 反而破坏设计。

原判据「左栏无 ΔE<3 的不可分对」保留 —— 它太松（ΔE 5.6 也过），
正是它让第四条缺陷溜过了上一轮审计。

### 需用户目视确认

1. 宽屏下下载/安装时的遮罩是否盖满整屏（含左栏区域）。
2. 打开任意已安装应用并关闭后，界面是否仍可点击（模拟器上验证）。
3. 播放器控制栏下方的两个方角是否消失。
4. 主题页切换「琥珀夜空 ↔ 青竹幽谷」时左栏是否明显变色（暖 → 绿）。

---

## 七、遗留与未做

| 项 | 说明 |
|---|---|
| `script/libs/exapp.lua` 的同名拷贝 | 仍带着「停心跳不恢复」的缺陷，本轮未同步（不在本工程加载路径上） |
| `clip_corner` 的推广 | 已在 AirUI 容器层通用可用；其他圆角卡片如出现同类方角，传参即可，本轮未全量套用 |
| 浅色档左栏的色相 | 三套仍是「近白微色偏」（ΔE 4.2~5.9，设计如此）；若希望浅色档左栏也能一眼看出色相，需要重新设计这三套的 rail 基调 |
| 其他 `content_fit` 收窄值与「全屏」假设的冲突 | 已修两处：app_store 的进度遮罩（第一条）、settings_win 的屏幕分辨率（第五条）。同一模式（用收窄后的 `screen_w` 去画挂在 `airui.screen` 上的东西，或去描述设备本身）如再出现，按这两条的写法取 `_G.screen_w` / 单独留存整屏尺寸 |
