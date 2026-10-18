--[[
@module  ui_shell
@summary 主窗口外壳（exwin 窗口 + 顶栏 + 左侧导航 + 内容区 + 侧栏状态 + 视图切换）
@version 1.0.0
@date    2026.10.12
@usage
订阅 "OPEN_SOLAR_MAIN_WIN" 打开主窗口。
主窗口只负责「框架 + 视图切换」，各业务视图（监控/控制/曲线/记录/设置/系统）独立成模块。
数据通过订阅 "SOLAR_DATA" 获取，再转发给当前视图；toast 通过订阅 "SOLAR_TOAST" 触发。
]]

local W = require "ui_widgets"
local theme = require "theme"
local exwin = require "exwin"
local ui_boot = require "ui_boot"

local M = {}

-- 1024x600 设计布局常量
local SIDE_W = 92            -- 左侧栏宽
local TOPBAR_H = 56          -- 顶栏高
local PAD_L, PAD_R = 12, 16  -- 内容区左右内边距（对应设计稿 .page padding）
local PAD_T, PAD_B = 14, 14  -- 内容区上下内边距

local VIEWS = {
    { key = "dash",  label = "监控", mod = "ui_dash",  title = "系统监控", sub = "实时运行数据总览" },
    { key = "ctrl",  label = "控制", mod = "ui_ctrl",  title = "循环控制", sub = "集热循环 / 上水 / 加热策略" },
    { key = "chart", label = "曲线", mod = "ui_chart", title = "历史曲线", sub = "温度变化趋势分析" },
    { key = "alarm", label = "记录", mod = "ui_alarm", title = "报警记录", sub = "系统事件与故障追溯" },
    { key = "param", label = "设置", mod = "ui_param", title = "参数设置", sub = "运行参数与通讯配置" },
    { key = "sys",   label = "系统", mod = "ui_sys",   title = "系统信息", sub = "设备状态 / 通信 / 存储" },
}

local win_id = nil
local root = nil
local content = nil
local current_view = nil
local active_key = "dash"
local last_state = nil
local nav = {}
local top = {}
local side = {}
local screen_w, screen_h = 1024, 600
local current_key = nil
local view_cache = {}
local use_seq = 0
local nav_active = nil
local preload_stop = false

local function refresh_screen_size()
    if not display or not display.getSize then return end
    local ok, w, h = pcall(display.getSize)
    if ok and type(w) == "number" and w > 0 then screen_w, screen_h = w, h end
end

-- ================= 性能埋点 / 视图缓存 =================
local function dbg_cfg()
    return (require "config").debug or {}
end

local function now_ms()
    if mstime then return mstime() end
    if os.clock then return math.floor(os.clock() * 1000) end
    return 0
end

local function mem_text()
    if not (rtos and rtos.meminfo) then return "" end
    local ok, total, used = pcall(rtos.meminfo, "sys")
    if not ok or type(total) ~= "number" or type(used) ~= "number" then return "" end
    return string.format(" lua_mem=%d/%dKB", math.floor(used / 1024), math.floor(total / 1024))
end

local function comp_count()
    if not (airui and airui.debug) then return nil end
    local ok, st = pcall(airui.debug)
    if ok and type(st) == "table" then return tonumber(st.component_count) end
    return nil
end

local function perf_log(fmt, ...)
    if dbg_cfg().perf_log == false then return end
    log.info("perf", string.format(fmt, ...))
end

local function cache_count()
    local n = 0
    for _ in pairs(view_cache) do n = n + 1 end
    return n
end

-- 淘汰一个缓存视图：只调 mod.destroy()（各视图模块内部会销毁自己的 root 并清空 handles）
local function cache_drop(key)
    local s = view_cache[key]
    if not s then return end
    view_cache[key] = nil
    if s.mod and s.mod.destroy then s.mod.destroy() end
end

-- ================= 导航 =================
local function refresh_nav()
    local T = theme.get()
    for _, item in ipairs(VIEWS) do
        local n = nav[item.key]
        if n then
            local on = (item.key == active_key)
            -- 只更新「激活态发生变化」的那两项，其余项样式没变，避免白灌消息进渲染队列
            if on ~= (nav_active == item.key) then
                n.btn:set_color(on and T.nav_active_bg or T.navbar, 255)
                n.btn:set_border_color(on and T.cyan or T.navbar, 1)
                n.lbl:set_color(on and T.cyan or T.nav_item)
                n.ind:set_hidden(not on)
                if n.icon then
                    W.icon_set_color(n.icon, item.key, 21, on and T.cyan or T.nav_item)
                end
            end
        end
    end
    nav_active = active_key
end

-- ================= 视图切换 =================
-- 视图区几何（所有视图复用同一矩形，保证切页时失效区域最小）
local function view_rect()
    return SIDE_W + PAD_L, TOPBAR_H + PAD_T,
        screen_w - SIDE_W - PAD_L - PAD_R,
        screen_h - TOPBAR_H - PAD_T - PAD_B
end

local function create_view(item)
    local mod = require(item.mod)
    local vx, vy, vw, vh = view_rect()
    local view_root = mod.create(content, W.d(vx), W.d(vy), W.d(vw), W.d(vh), theme.get())
    return { mod = mod, root = view_root }
end

-- 超数量上限 / LVGL 内存水位偏高时按 LRU 淘汰（当前视图永不淘汰）
local function cache_evict(keep_key)
    local maxn = tonumber(dbg_cfg().view_cache_max) or 6
    local high = tonumber(dbg_cfg().view_cache_mem_high) or 0
    local function lru()
        local vk, best = nil, math.huge
        for k, s in pairs(view_cache) do
            if k ~= keep_key and (s.used or 0) < best then vk, best = k, s.used or 0 end
        end
        return vk
    end
    local function mem_high()
        if high <= 0 or not (airui and airui.debug) then return false end
        local ok, st = pcall(airui.debug)
        return ok and type(st) == "table" and (tonumber(st.mem_used_pct) or 0) >= high
    end
    while cache_count() > 1 and mem_high() do
        local vk = lru()
        if not vk then break end
        cache_drop(vk)
        perf_log("内存水位达到 %d%%，淘汰视图缓存 %s", high, vk)
    end
    while cache_count() > maxn do
        local vk = lru()
        if not vk then break end
        cache_drop(vk)
        perf_log("超出缓存上限 %d，淘汰视图缓存 %s", maxn, vk)
    end
end

local function set_view(key)
    if key == current_key and current_view then return end

    local item
    for _, v in ipairs(VIEWS) do
        if v.key == key then item = v; break end
    end
    if not item then return end

    local perf = dbg_cfg().perf_log ~= false
    local t0 = perf and now_ms() or 0
    local t1, t2, t3

    -- 1) 收起旧视图：缓存模式只隐藏（对象保留），非缓存模式销毁
    if current_view then
        local old = current_key and view_cache[current_key]
        if old and old.root then
            old.root:set_hidden(true)
        else
            current_view.destroy()
        end
        current_view, current_key = nil, nil
    end
    if perf then t1 = now_ms() end

    -- 2) 命中缓存直接用，否则新建
    local cached = dbg_cfg().view_cache ~= false
    local slot = cached and view_cache[key] or nil
    local built = false
    if not slot then
        slot = create_view(item)
        built = true
        if cached then view_cache[key] = slot end
    end
    slot.root:set_hidden(false)
    use_seq = use_seq + 1
    slot.used = use_seq
    current_view, current_key = slot.mod, key
    active_key = key

    -- 顶栏标题 / 副标题
    if top.title then top.title:set_text(item.title) end
    if top.sub then top.sub:set_text(item.sub) end
    if perf then t2 = now_ms() end

    -- 3) 首帧数据 + 导航态
    if last_state then slot.mod.update(last_state) end
    if perf then t3 = now_ms() end
    refresh_nav()

    -- 4) 超限/水位淘汰
    if built then cache_evict(key) end

    if perf then
        local t4 = now_ms()
        local cc = comp_count()
        perf_log("切换视图 %s(%s) 收起=%dms 建=%dms 刷数据=%dms 导航=%dms 总=%dms 组件=%s%s",
            key, built and "新建" or "缓存",
            t1 - t0, t2 - t1, t3 - t2, t4 - t3, t4 - t0,
            cc and tostring(cc) or "?", mem_text())
    end
end

-- 开机预热：把尚未建过的视图依次建好并隐藏，使首次点击也秒开
local function preload_views()
    if dbg_cfg().view_preload ~= true or dbg_cfg().view_cache == false then return end
    local delay = tonumber(dbg_cfg().view_preload_delay) or 2500
    local gap = tonumber(dbg_cfg().view_preload_gap) or 1200
    sys.wait(delay)
    for _, item in ipairs(VIEWS) do
        if preload_stop then
            perf_log("预热中止：用户已开始操作")
            return
        end
        if item.key ~= current_key and not view_cache[item.key] then
            local t0 = now_ms()
            local slot = create_view(item)
            slot.root:set_hidden(true)
            slot.used = 0
            view_cache[item.key] = slot
            perf_log("预热视图 %s 建=%dms 组件=%s%s", item.key, now_ms() - t0,
                tostring(comp_count() or "?"), mem_text())
        end
        sys.wait(gap)
    end
    cache_evict(current_key)
end

-- ================= 背景网格 =================
local function build_grid(parent, T)
    local items = {}
    local step = 26
    for x = step, screen_w - 1, step do
        items[#items + 1] = { type = "line", x1 = x, y1 = 0, x2 = x, y2 = screen_h,
            color = T.bg_grid, width = 1 }
    end
    for y = step, screen_h - 1, step do
        items[#items + 1] = { type = "line", x1 = 0, y1 = y, x2 = screen_w, y2 = y,
            color = T.bg_grid, width = 1 }
    end
    -- 背景网格内缩 4px，避免贴住根容器内容区边界
    airui.shape({ parent = parent, x = 0, y = 0, w = screen_w - 4, h = screen_h - 4, items = items })
end

-- ================= 顶栏 =================
local function build_topbar(T)
    airui.container({ parent = root, x = SIDE_W, y = 0, w = screen_w - SIDE_W - 4, h = TOPBAR_H, color = T.topbar })
    W.divider(root, SIDE_W, TOPBAR_H - 1, screen_w - SIDE_W - 4, T.ring)

    top.title = W.label(root, SIDE_W + 14, 6, 460, 24, "系统监控", 17, T.text_bright)
    top.sub = W.label(root, SIDE_W + 14, 36, 380, 18, "实时运行数据总览", 11, T.text_dim)

    -- 右侧：3 个状态芯片 + 时钟
    local right = screen_w - 16
    -- 时钟（带底色，内含可更新 label）
    local clock_box = airui.container({
        parent = root, x = W.d(right - 100), y = W.d(15), w = W.d(100), h = W.d(26),
        radius = W.d(9), color = T.accent_soft, border_color = T.cyan, border_width = 1,
    })
    top.clock_lbl = W.label(clock_box, 2, 3, 96, 20, "--:--:--", 12.5, T.text_bright, airui.TEXT_ALIGN_CENTER)
    right = right - 100 - 8
    side.chip_sd = W.chip(root, right - 64, 15, 64, "SD 8G", nil, T)
    right = right - 64 - 8
    side.chip_485 = W.chip(root, right - 92, 15, 92, "485 0x01", nil, T)
    right = right - 92 - 8
    side.chip_4g = W.chip(root, right - 88, 15, 88, "4G 在线", T.green, T)
end

-- ================= 左侧栏 =================
local function build_side(T)
    airui.container({ parent = root, x = 0, y = 0, w = SIDE_W, h = screen_h, color = T.navbar })
    -- 侧栏右侧竖分割线
    airui.container({ parent = root, x = SIDE_W - 1, y = 0, w = 1, h = screen_h, color = T.ring })

    -- 品牌
    local logo = airui.container({
        parent = root, x = W.d(25), y = W.d(14), w = W.d(42), h = W.d(42),
        radius = W.d(13), color = T.accent_soft, border_color = T.cyan, border_width = 1,
    })
    airui.shape({
        parent = logo, x = W.d(8), y = W.d(8), w = W.d(26), h = W.d(26),
        items = {
            { type = "circle", cx = 13, cy = 13, r = 5, color = T.cyan, width = 2 },
            { type = "line", x1 = 13, y1 = 1, x2 = 13, y2 = 5, color = T.cyan, width = 2 },
            { type = "line", x1 = 13, y1 = 21, x2 = 13, y2 = 25, color = T.cyan, width = 2 },
            { type = "line", x1 = 1, y1 = 13, x2 = 5, y2 = 13, color = T.cyan, width = 2 },
            { type = "line", x1 = 21, y1 = 13, x2 = 25, y2 = 13, color = T.cyan, width = 2 },
        },
    })
    W.label(root, 0, 62, SIDE_W, 14, "SOLAROS", 9, T.text_soft, airui.TEXT_ALIGN_CENTER)

    -- 导航项
    local nav_y0 = 91
    local pitch = 60
    for i, item in ipairs(VIEWS) do
        local by = nav_y0 + (i - 1) * pitch
        local btn = airui.container({
            parent = root, x = W.d(9), y = W.d(by), w = W.d(SIDE_W - 18), h = W.d(56),
            radius = W.d(13), color = T.navbar, border_color = T.navbar, border_width = 1,
            on_click = function()
                preload_stop = true   -- 用户开始操作，中止后台预热
                set_view(item.key)
            end,
        })
        local ic = W.icon(btn, item.key, 26, 8, 21, T.nav_item)
        -- 按钮有 1px 边框，内容区为 [1, w-1]：文字框四周再留 2px，否则出现滚动条
        local lbl = W.label(btn, 2, 33, SIDE_W - 18 - 4, 16, item.label, 10.5, T.nav_item, airui.TEXT_ALIGN_CENTER)
        local ind = airui.container({ parent = root, x = 0, y = W.d(by + 14),
            w = W.d(3), h = W.d(28), color = T.cyan, radius = W.d(2) })
        ind:set_hidden(true)
        nav[item.key] = { btn = btn, icon = ic, lbl = lbl, ind = ind }
    end

    -- 侧栏底部：信号条 + 时钟 + 联网标签
    local fx = 34
    for k = 1, 4 do
        local h = 5 + (k - 1) * 3
        airui.container({
            parent = root, x = W.d(fx + (k - 1) * 7), y = W.d(549 - h),
            w = W.d(4), h = W.d(h), radius = W.d(2),
            color = (k <= 3) and T.green or T.toggle_off,
        })
    end
    side.clock = W.label(root, 16, 556, 60, 16, "--:--", 11, T.text_soft, airui.TEXT_ALIGN_CENTER)
    W.label(root, 16, 576, 60, 12, "4G OK", 8.5, T.text_faint, airui.TEXT_ALIGN_CENTER)
end

-- ================= 内容区 =================
local function build_content(T)
    -- 视图直接挂在 root 上（不额外加不透明容器），使背景网格在面板间隙可见
    content = root
end

-- ================= toast（右下角，订阅触发）=================
local toast = {}

local function show_toast(color, title, sub)
    if not root then return end
    local T = theme.get()
    if not toast.box then
        toast.box = airui.container({
            parent = root, x = 0, y = 0, w = W.d(238), h = W.d(40),
            radius = W.d(12), color = T.panel, border_color = T.ring, border_width = 1,
        })
        toast.dot = airui.container({ parent = toast.box, x = W.d(12), y = W.d(17),
            w = W.d(7), h = W.d(7), radius = W.d(3), color = color })
        toast.t1 = W.label(toast.box, 26, 8, 200, 18, title, 11.5, T.text)
        toast.t2 = W.label(toast.box, 26, 25, 200, 14, sub or " ", 10, T.text_dim)
    end
    toast.dot:set_color(color, 255)
    toast.t1:set_text(title)
    toast.t2:set_text(sub or " ")
    toast.box:set_pos(W.d(screen_w - 16 - 238), W.d(screen_h - 16 - 40))
    toast.box:set_hidden(false)
    if toast.timer then sys.timerStop(toast.timer) end
    toast.timer = sys.timerStart(function()
        if toast.box then toast.box:set_hidden(true) end
    end, 2400)
end

-- ================= 数据刷新 / 时钟 =================
local function on_data(st)
    last_state = st
    if side.clock and st.hm then side.clock:set_text(st.hm) end
    if top.clock_lbl and st.clock then top.clock_lbl:set_text(st.clock) end
    if current_view and current_view.update then current_view.update(st) end
end

local function update_clock()
    if side.clock then side.clock:set_text(os.date("%H:%M")) end
    if top.clock_lbl then top.clock_lbl:set_text(os.date("%H:%M:%S")) end
end

-- ================= 构建 / 销毁 =================
local function build()
    if not airui or not airui.container then
        log.error("ui_shell", "airui 库不存在，无法构建界面（请使用带 LUAT_USE_GUI 的模拟器/固件）")
        return
    end
    refresh_screen_size()
    local T = theme.get()

    if dbg_cfg().airui_debug and airui and airui.debug then
        pcall(airui.debug, true)
    end

    root = airui.container({ parent = airui.screen, x = 0, y = 0, w = screen_w, h = screen_h, color = T.bg })
    build_grid(root, T)
    build_topbar(T)
    build_side(T)
    build_content(T)

    toast = {}
    set_view(active_key)
end

local function teardown()
    for key in pairs(view_cache) do cache_drop(key) end
    view_cache = {}
    current_view, current_key = nil, nil
    nav_active = nil
    preload_stop = false
    toast = {}
    if root then
        root:destroy()
        root = nil
    end
    nav, top, side = {}, {}, {}
    content = nil
end

local function rebuild()
    teardown()
    build()
    if last_state then on_data(last_state) end
end

-- 开机动画时序（进度步进 -> 延时销毁 -> 启动提示）
local function boot_sequence()
    for p = 10, 100, 10 do
        sys.wait(105)
        ui_boot.set_progress(p)
    end
    sys.wait(120)
    ui_boot.destroy()
    show_toast(theme.get().cyan, "系统启动完成", "采集 7 路 / 输出 6 路 / 4G 在线")
end

local function on_create()
    build()
    -- 开机动画覆盖层（在 root 之后创建，位于最上层）
    ui_boot.create(screen_w, screen_h, theme.get())
    sys.taskInit(boot_sequence)
end

local function on_destroy()
    ui_boot.destroy()
    teardown()
    win_id = nil
end

local function open()
    if not exwin.is_active(win_id) then
        win_id = exwin.open({ on_create = on_create, on_destroy = on_destroy })
        log.info("ui_shell", "主窗口打开成功", win_id)
        if dbg_cfg().view_preload == true then
            preload_stop = false
            sys.taskInit(preload_views)
        end
    end
end

local function on_toast(ev)
    show_toast(ev.color, ev.title, ev.sub)
end

local function clock_loop()
    while true do
        sys.wait(1000)
        if root then update_clock() end
    end
end

sys.subscribe("OPEN_SOLAR_MAIN_WIN", open)
sys.subscribe("SOLAR_DATA", on_data)
sys.subscribe("SOLAR_THEME_CHANGED", rebuild)
sys.subscribe("SOLAR_TOAST", on_toast)

sys.taskInit(clock_loop)

function M.open()
    open()
end

return M
