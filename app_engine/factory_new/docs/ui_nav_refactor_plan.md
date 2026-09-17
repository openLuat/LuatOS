# 应用工厂 UI 导航架构改造方案

## 一、现状问题

当前每个页面（设置、WiFi、应用商店等）都是独立的 exwin 全屏窗口。点击内置应用 → 新 exwin 覆盖在 idle_win 上 → 左侧 rail 被遮挡。返回 → exwin.close() 销毁窗口。

**问题：**
- 左侧导航栏只在桌面可见，进入任何页面后消失
- 每个 exwin 窗口持有独立 LVGL 屏缓冲（1024×600×2 ≈ 1.2MB），叠加多个页面内存迅速耗尽
- 页面间无结构化导航关系，跳转和返回逻辑分散在各模块

## 二、目标架构

```
┌──────────┬──────────────────────────────┐
│          │                              │
│  rail    │  content_area                │
│ (常驻)   │  ┌──────────────────────┐    │
│          │  │                      │    │
│  桌面  ● │  │  当前页面内容         │    │
│  设置    │  │                      │    │
│  WiFi   │  │  二级子页面可叠加     │    │
│  应用商店│  │                      │    │
│  ...    │  └──────────────────────┘    │
│          │  [返回按钮]                  │
└──────────┴──────────────────────────────┘
```

**导航规则：**
- 一级菜单切换（rail 点击不同应用）→ 销毁当前应用所有页面，创建新页面
- 二级菜单跳转（设置 → IoT）→ 在 content_area 叠加新组件，保留父页面
- 返回按钮 → 销毁最顶层组件，露出下一层
- 回到桌面 → 销毁所有页面，显示桌面内容

## 三、文件结构

```
ui/
├── ui_main.lua              -- 加载入口（改动小）
├── ui_shell.lua             -- 新增：全局骨架 exwin（rail + content_area + 返回按钮）
├── ui_desktop.lua           -- 新增：桌面内容（从 idle_win 抽出）
├── page_manager.lua         -- 新增：导航栈管理（纯逻辑）
├── idle_win.lua             -- 改造：瘦身为薄壳（订阅转发 + 调用 shell）
├── settings_win.lua         -- 改造：导出 create/destroy
├── settings_iot_win.lua     -- 改造：导出 create/destroy
├── settings_display_win.lua -- 改造：导出 create/destroy
├── settings_storage_win.lua -- 改造：导出 create/destroy
├── settings_sound_win.lua   -- 改造：导出 create/destroy
├── settings_fota_win.lua    -- 改造：导出 create/destroy
├── settings_about_win.lua   -- 改造：导出 create/destroy
├── settings_auto_win.lua    -- 改造：导出 create/destroy
├── storage_pri_win.lua      -- 改造：导出 create/destroy
├── app_store_win.lua        -- 改造：导出 create/destroy
├── wifi_list_win.lua        -- 改造：导出 create/destroy
├── file_manager_win.lua     -- 改造：导出 create/destroy
├── speedtest_win.lua        -- 改造：导出 create/destroy
├── factory_win.lua          -- 改造：导出 create/destroy
├── llm_chat_win.lua         -- 改造：导出 create/destroy
└── settings/
    └── settings_titlebar.lua -- 改造：返回按钮改为调 page_manager.pop_page()
```

## 四、新模块设计

### 4.1 page_manager.lua（导航栈）

```lua
local M = {}

-- 状态
local current_app = nil       -- 当前一级应用名
local page_stack = {}         -- 当前应用的页面栈 [{name, destroy_fn}]
local content_area = nil      -- 右侧内容区容器引用
local content_w, content_h = 0, 0
local back_btn = nil          -- 返回按钮引用
local app_registry = {}       -- 一级应用注册表
local desktop_module = nil    -- 桌面模块引用

--- 注册一级应用
function M.register_app(name, create_fn, destroy_fn)
    app_registry[name] = { create = create_fn, destroy = destroy_fn }
end

--- 注册桌面模块
function M.register_desktop(mod)
    desktop_module = mod
end

--- 初始化内容区（由 ui_shell 调用）
function M.init(area, w, h)
    content_area = area
    content_w, content_h = w, h
end

--- 切换一级应用
function M.open_app(name)
    if name == current_app then return end
    -- 销毁当前应用所有页面
    M._destroy_stack()
    -- 切换高亮
    current_app = name
    -- 创建新页面
    local app = app_registry[name]
    if app then
        local page = app.create(content_area, content_w, content_h)
        if page then
            table.insert(page_stack, { name = name, destroy_fn = page.destroy })
        end
    end
    M._update_back_btn()
end

--- 二级跳转（在同一应用内叠加页面）
function M.push_page(name, create_fn, destroy_fn)
    local page = create_fn(content_area, content_w, content_h)
    if page then
        table.insert(page_stack, { name = name, destroy_fn = page.destroy })
    end
    M._update_back_btn()
end

--- 返回（销毁栈顶页面）
function M.pop_page()
    if #page_stack <= 1 then
        -- 栈底是应用根页面，回到桌面
        M.go_home()
        return
    end
    local top = table.remove(page_stack)
    if top and top.destroy_fn then
        pcall(top.destroy_fn)
    end
    M._update_back_btn()
end

--- 回到桌面
function M.go_home()
    M._destroy_stack()
    current_app = nil
    if desktop_module then
        local page = desktop_module.create(content_area, content_w, content_h)
        if page then
            table.insert(page_stack, { name = "desktop", destroy_fn = page.destroy })
        end
    end
    M._update_back_btn()
end

--- 销毁整个栈
function M._destroy_stack()
    for i = #page_stack, 1, -1 do
        local p = page_stack[i]
        if p and p.destroy_fn then pcall(p.destroy_fn) end
    end
    page_stack = {}
end

--- 更新返回按钮可见性
function M._update_back_btn()
    if back_btn then
        back_btn:set_hidden(#page_stack <= 1)
    end
end

--- 获取当前应用名
function M.get_current_app()
    return current_app
end

return M
```

### 4.2 ui_shell.lua（全局骨架）

```lua
-- 唯一的 exwin 窗口，持有 rail + content_area + 返回按钮
local page_manager = require "page_manager"

local window_id = nil
local rail, content_area, back_btn
local rail_w = 104  -- dp

local function on_create()
    local base = theme.page_bg(airui.screen, screen_w, screen_h)

    -- 左侧 rail
    rail = build_rail(base)  -- 从 ui_desktop 抽出的 rail 构建逻辑

    -- 右侧内容区
    local cx = rail_w
    local cw = screen_w - rail_w
    content_area = airui.container({
        parent = base, x = cx, y = 0, w = cw, h = screen_h,
        color = theme.C.bg, color_opacity = 255,
    })

    -- 返回按钮（浮动在 content_area 右下角）
    back_btn = airui.button({
        parent = base, x = cx + 8, y = screen_h - 52, w = 40, h = 40,
        text = "<", style = { bg_color = theme.C.amber, text_color = theme.C.t1,
                              border_width = 0, radius = theme.R.sm },
        on_click = function() page_manager.pop_page() end,
    })

    page_manager.init(content_area, cw, screen_h)
    page_manager.go_home()  -- 初始显示桌面
end

local function on_destroy()
    page_manager._destroy_stack()
    window_id = nil
end

-- 订阅一级应用跳转
sys.subscribe("OPEN_SETTINGS_WIN", function() page_manager.open_app("settings") end)
sys.subscribe("OPEN_WIFI_WIN", function() page_manager.open_app("wifi") end)
sys.subscribe("OPEN_APP_STORE_WIN", function() page_manager.open_app("app_store") end)
-- ... 其他一级应用

sys.subscribe("OPEN_IDLE_WIN", function()
    if not window_id then
        window_id = exwin.open({ on_create = on_create, on_destroy = on_destroy })
    end
end)
```

### 4.3 ui_desktop.lua（桌面内容）

从 idle_win.lua 抽出以下函数：
- `build_clock_card()` → 时钟卡
- `build_weather_card()` → 天气卡
- `build_video_area()` → 视频区域
- `build_apps_card()` → 应用网格
- `build_dock()` → 底部 Dock
- 所有相关的状态变量和工具函数

导出接口：
```lua
local M = {}
function M.create(parent, w, h)
    -- 在 parent 容器内创建桌面 UI
    -- 返回 { destroy = function() ... end }
end
return M
```

### 4.4 页面模块改造模式（以 settings_win 为例）

**改造前：**
```lua
local window_id = nil
local main_container = nil

local function on_create()
    main_container = theme.page_bg(airui.screen, screen_w, screen_h)
    -- ... 构建 UI ...
end

local function on_destroy()
    -- ... 清理 ...
end

local function open_handler()
    window_id = exwin.open({ on_create = on_create, on_destroy = on_destroy })
end

sys.subscribe("OPEN_SETTINGS_WIN", open_handler)
```

**改造后：**
```lua
local M = {}
local main_container = nil

function M.create(parent, w, h)
    main_container = airui.container({
        parent = parent, x = 0, y = 0, w = w, h = h,
        color = theme.C.bg, color_opacity = 255,
    })
    -- ... 在 main_container 内构建 UI ...
    -- 子页面跳转改为调 page_manager.push_page()
    -- 返回按钮改为调 page_manager.pop_page()
    return { destroy = function()
        if main_container then main_container:destroy(); main_container = nil end
    end }
end

return M
```

**关键改动点：**
1. 去掉 `exwin.open` / `exwin.close` / `window_id`
2. `theme.page_bg(airui.screen, ...)` → 改为接收 parent 参数
3. 返回按钮：`exwin.close(window_id)` → `page_manager.pop_page()`
4. 子页面跳转：`sys.publish("OPEN_IOT_WIN")` → `page_manager.push_page("iot", iot.create, iot.destroy)`
5. 全局变量在 destroy 时清理

## 五、页面跳转关系（改造后）

```
桌面 (ui_desktop)
├── 点击「设置」     → page_manager.open_app("settings")
│   ├── 点击「IOT」     → page_manager.push_page("iot", ...)
│   ├── 点击「WiFi」    → page_manager.push_page("wifi", ...)
│   ├── 点击「显示」    → page_manager.push_page("display", ...)
│   └── 返回            → page_manager.pop_page()
├── 点击「WiFi」     → page_manager.open_app("wifi")
│   └── 返回            → page_manager.pop_page() → go_home()
├── 点击「应用商店」  → page_manager.open_app("app_store")
│   └── 返回            → page_manager.pop_page() → go_home()
└── 点击「文件管理」  → page_manager.open_app("file_manager")
    └── 返回            → page_manager.pop_page() → go_home()
```

## 六、实施步骤（建议顺序）

### 第一阶段：基础设施（不动现有页面）
1. 创建 `page_manager.lua`（导航栈逻辑）
2. 创建 `ui_shell.lua`（全局骨架 exwin）
3. 创建 `ui_desktop.lua`（从 idle_win 抽出桌面内容）
4. 改造 `idle_win.lua`（瘦身为薄壳，订阅转发给 shell）
5. 测试：桌面显示正常，rail 始终可见

### 第二阶段：改造第一个页面（settings_win）
6. 改造 `settings_win.lua`（去掉 exwin，导出 create/destroy）
7. 改造 `settings_titlebar.lua`（返回按钮改为调 page_manager）
8. 测试：从桌面进入设置 → 返回，rail 始终可见

### 第三阶段：改造设置子页面
9. 改造 `settings_iot_win.lua`、`settings_display_win.lua` 等
10. 测试：设置 → IoT → 返回 → 返回，导航栈正确

### 第四阶段：改造其他一级页面
11. 改造 `app_store_win.lua`、`wifi_list_win.lua`、`file_manager_win.lua`
12. 改造 `factory_win.lua`、`llm_chat_win.lua`、`speedtest_win.lua`
13. 全面测试

## 七、风险与缓解

| 风险 | 缓解措施 |
|------|----------|
| page_manager 状态管理出错 | 栈深度限制（最多10层），nil 检查，pcall 包裹 destroy |
| 页面 destroy 不彻底导致内存泄漏 | 统一 destroy 模式：先销毁 airui 容器（自动删除所有子控件），再清理定时器/订阅 |
| LVGL 渲染异常（多页面在同一容器） | 每个页面用独立 airui.container，destroy 时整个容器删除 |
| 现有页面改造遗漏 | 每改一个测试一个，不批量改 |
| rail 高亮状态不同步 | page_manager.open_app 时通知 ui_shell 更新高亮 |

## 八、预期效果

| 指标 | 改造前 | 改造后 |
|------|--------|--------|
| 左侧 rail | 仅桌面可见 | **始终可见** |
| 页面切换内存 | 每个页面 +1.2MB 屏缓冲 | **共享 1.2MB 屏缓冲** |
| 3个页面叠加内存 | ~3.6MB 屏缓冲 + 控件 | ~1.2MB 屏缓冲 + 控件 |
| 页面模块代码 | 含 exwin 样板 ~50行 | 纯 create/destroy ~30行 |
| 新增页面 | 复制 exwin 样板 + 订阅 | 实现 create/destroy + 注册 |
