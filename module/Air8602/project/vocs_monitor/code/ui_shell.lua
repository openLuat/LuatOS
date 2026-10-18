--[[
@module  ui_shell
@summary 主窗口外壳（exwin 窗口 + 顶栏 + 左侧导航 + 内容区 + 状态栏 + 视图切换）
@version 1.0.0
@date    2026.10.10
@usage
订阅 "OPEN_VOCS_MAIN_WIN" 打开主窗口。
主窗口只负责「框架 + 视图切换」，各业务视图（总览/色谱/质谱/数据/设置）独立成模块。
数据通过订阅 "VOCS_DATA" 获取，再转发给当前视图刷新。
]]

local W = require "ui_widgets"
local theme = require "theme"
local exwin = require "exwin"

local M = {}

-- 1024x600 设计布局常量
local TOPBAR_H = 58
local NAV_W = 70
local STATUS_H = 32
-- 内容区：x=NAV_W, y=TOPBAR_H, w=SW-NAV_W, h=SH-TOPBAR_H-STATUS_H
-- 视图区：内缩 10px
local VIEW_PAD = 10

local VIEWS = {
    { key = "overview", label = "总览", mod = "ui_overview" },
    { key = "chrom",    label = "色谱", mod = "ui_chrom" },
    { key = "ms",       label = "质谱", mod = "ui_ms" },
    { key = "data",     label = "数据", mod = "ui_data" },
    { key = "settings", label = "设置", mod = "ui_settings" },
}

local win_id = nil
local root = nil
local content = nil
local current_view = nil
local active_key = "overview"
local last_state = nil
local nav = {}
local top = {}
local status = {}
local screen_w, screen_h = 1024, 600
local current_key = nil    -- 当前视图 key（与 current_view 配对，用于查缓存）
local view_cache = {}      -- key -> { mod, root, used }：视图实例缓存
local use_seq = 0          -- LRU 计数
local nav_active = nil     -- 上一次的导航激活项（用于避免重复改图标）
local preload_stop = false -- 用户开始操作后置 true，预热立即停止，避免抢渲染队列

local function refresh_screen_size()
    if not display or not display.getSize then return end
    local ok, w, h = pcall(display.getSize)
    if ok and type(w) == "number" and w > 0 then screen_w, screen_h = w, h end
end

-- ================= 性能埋点 / 视图缓存 =================
local function dbg_cfg()
    return (require "config").debug or {}
end

-- 毫秒时间戳（个别环境无 mstime 时退化到 os.clock）
local function now_ms()
    if mstime then return mstime() end
    if os.clock then return math.floor(os.clock() * 1000) end
    return 0
end

-- Lua 侧内存（取不到就返回空串）
local function mem_text()
    if not (rtos and rtos.meminfo) then return "" end
    local ok, total, used = pcall(rtos.meminfo, "sys")
    if not ok or type(total) ~= "number" or type(used) ~= "number" then return "" end
    return string.format(" lua_mem=%d/%dKB", math.floor(used / 1024), math.floor(total / 1024))
end

-- AirUI 组件计数：该统计常开，不需要打开 debug 模式
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

-- 淘汰一个缓存视图：只调 mod.destroy()（各视图模块内部会销毁自己的 root 并清空 handles），
-- 不要额外再 destroy root —— 那会重复销毁同一个对象
local function cache_drop(key)
    local s = view_cache[key]
    if not s then return end
    view_cache[key] = nil
    if s.mod and s.mod.destroy then s.mod.destroy() end
end

-- 超数量上限 / LVGL 内存水位偏高时按 LRU 淘汰（当前视图永不淘汰）
local function cache_evict(keep_key)
    local maxn = tonumber(dbg_cfg().view_cache_max) or 5
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

-- ================= 导航 =================
local function refresh_nav()
    local T = theme.get()
    for _, item in ipairs(VIEWS) do
        local n = nav[item.key]
        if n then
            local on = (item.key == active_key)
            -- 只更新「激活态发生变化」的那两项（旧的激活项 + 新的激活项）：
            -- 其余项样式没变，重复 set_color/set_items 只会白灌消息进渲染队列
            if on ~= (nav_active == item.key) then
                n.btn:set_color(on and T.nav_active_bg or T.navbar, 255)
                n.btn:set_border_color(on and T.ring or T.navbar, 1)
                n.lbl:set_color(on and T.cyan or T.nav_item)
                n.ind:set_hidden(not on)
                W.icon_set_color(n.icon, item.key, 19, on and T.cyan or T.nav_item)
            end
        end
    end
    nav_active = active_key
end

-- 视图区几何
local function view_rect()
    return NAV_W + VIEW_PAD, TOPBAR_H + VIEW_PAD,
        screen_w - NAV_W - VIEW_PAD * 2,
        screen_h - TOPBAR_H - STATUS_H - VIEW_PAD * 2
end

-- 建一个视图（不显示），供首次进入与开机预热复用
local function create_view(item)
    local mod = require(item.mod)
    local vx, vy, vw, vh = view_rect()
    local view_root = mod.create(content, W.d(vx), W.d(vy), W.d(vw), W.d(vh), theme.get())
    return { mod = mod, root = view_root }
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
    if perf then t2 = now_ms() end

    -- 3) 首帧数据 + 导航态
    if last_state then slot.mod.update(last_state) end
    if perf then t3 = now_ms() end
    refresh_nav()

    -- 4) 超限/水位淘汰
    if built then cache_evict(key) end

    -- 计时全部结束后再取组件数：airui.debug() 要跨任务取数，放在区间内会污染测量
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
    -- 等首屏稳定再开始，避免预热与开机首帧抢 CPU
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
        -- 间隔留足，让 LVGL 把上一批创建消息消化完，避免积压后 Lua 侧被迫等待
        sys.wait(gap)
    end
    cache_evict(current_key)
end

-- ================= 背景网格 =================
local function build_grid(parent, T)
    local items = {}
    local step = 40
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
    airui.container({ parent = root, x = 0, y = 0, w = screen_w - 4, h = TOPBAR_H, color = T.topbar })
    W.divider(root, 0, TOPBAR_H - 1, screen_w - 4, T.ring)

    -- 品牌
    airui.image({ parent = root, x = W.d(16), y = W.d(13), w = W.d(32), h = W.d(32),
        src = "/luadb/logo.png", fit = "contain" })
    W.label(root, 59, 6, 220, 20, "上海合宙", 14, T.text_bright)
    W.label(root, 59, 31, 220, 16, "智能大屏方案", 11, T.text_dim)

    -- 居中标题（两侧装饰横线已按需求删除）
    W.label(root, 0, 19, screen_w - 4, 22, "VOCs在线环境监测系统", 16, T.text_bright, airui.TEXT_ALIGN_CENTER)

    -- 右侧：状态芯片 + 方法芯片 + 时钟
    -- 右侧：状态芯片 + 方法芯片 + 时钟（宽度按放大后的字号留足，避免裁切/换行）
    top.clock = W.label(root, screen_w - 116, 18, 100, 22, "--:--:--", 15.5, T.text_bright,
        airui.TEXT_ALIGN_RIGHT)
    top.chip_method = W.chip(root, screen_w - 256, 16, 126, "方法 VOC-58", false, T)
    -- 「运行中」状态组件：点击进入窗口深度测试的第 1 级窗口（ui_depth）
    top.chip_run = W.chip(root, screen_w - 354, 16, 84, "运行中", true, T, function()
        -- 日志保持短 ASCII：Air8602 日志口会把单行截断，中文日志基本只剩前缀
        log.info("ui_shell", "click depth")
        sys.publish("OPEN_VOCS_DEPTH_WIN")
    end)
end

-- ================= 左侧导航 =================
local function build_nav(T)
    airui.container({ parent = root, x = 0, y = TOPBAR_H, w = NAV_W, h = screen_h - TOPBAR_H - STATUS_H,
        color = T.navbar })
    -- 导航右侧竖分割线
    airui.container({ parent = root, x = NAV_W - 1, y = TOPBAR_H, w = 1,
        h = screen_h - TOPBAR_H - STATUS_H, color = T.ring })

    for i, item in ipairs(VIEWS) do
        local by = 12 + (i - 1) * 66
        local btn = airui.container({
            parent = root, x = W.d(5), y = W.d(TOPBAR_H + by), w = W.d(60), h = W.d(58),
            radius = W.d(9), color = T.navbar, border_color = T.navbar, border_width = 1,
            on_click = function()
                preload_stop = true   -- 用户开始操作，中止后台预热，别和用户抢渲染队列
                set_view(item.key)
            end,
        })
        local icon = W.icon(btn, item.key, 19, 7, 22, T.nav_item)
        -- 按钮有 1px 边框，内容区为 [1,59]：文字框四周再留 2px，否则出现滚动条
        local lbl = W.label(btn, 2, 34, 55, 18, item.label, 11, T.nav_item, airui.TEXT_ALIGN_CENTER)
        local ind = airui.container({ parent = root, x = 0, y = W.d(TOPBAR_H + by + 18),
            w = W.d(3), h = W.d(22), color = T.cyan })
        ind:set_hidden(true)
        nav[item.key] = { btn = btn, icon = icon, lbl = lbl, ind = ind }
    end
end

-- ================= 状态栏 =================
local function build_statusbar(T)
    local sy = screen_h - STATUS_H
    -- 宽度与高度都留 2~4px 余量，避免状态栏贴住根容器内容区边界
    airui.container({ parent = root, x = 0, y = sy, w = screen_w - 4, h = STATUS_H - 2, color = T.statusbar })
    W.divider(root, 0, sy, screen_w - 4, T.ring)

    airui.container({ parent = root, x = W.d(16), y = W.d(sy + 13), w = W.d(6), h = W.d(6),
        radius = W.d(3), color = T.cyan })
    W.label(root, 28, sy + 6, 90, 20, "系统正常", 11.5, T.cyan)
    status.temp = W.label(root, 140, sy + 6, 140, 20, "柱温 -- °C", 11.5, T.text_dim)
    status.vac = W.label(root, 290, sy + 6, 180, 20, "真空 --", 11.5, T.text_dim)
    status.eth = W.label(root, screen_w - 320, sy + 6, 140, 20, "ETH --", 11.5, T.text_dim,
        airui.TEXT_ALIGN_RIGHT)
    status.fw = W.label(root, screen_w - 170, sy + 6, 154, 20, "固件 --", 11.5, T.text_dim,
        airui.TEXT_ALIGN_RIGHT)
end

-- ================= 数据刷新 =================
local function on_data(st)
    last_state = st
    if top.clock then top.clock:set_text(st.clock) end
    if status.temp then status.temp:set_text(string.format("柱温 %.1f °C", st.temp)) end
    if status.vac then status.vac:set_text("真空 " .. st.vacuum) end
    if status.eth then status.eth:set_text("ETH " .. st.eth) end
    if status.fw then status.fw:set_text("固件 " .. st.firmware) end
    if current_view and current_view.update then current_view.update(st) end
end

-- ================= 构建 / 销毁 =================
local function build()
    if not airui or not airui.container then
        log.error("ui_shell", "airui 库不存在，无法构建界面（请使用带 LUAT_USE_GUI 的模拟器/固件）")
        return
    end
    refresh_screen_size()
    local T = theme.get()

    -- 可选的 AirUI 内置统计（每秒打印 FPS/内存/组件数；组件级日志较多，仅排查用）
    if dbg_cfg().airui_debug and airui and airui.debug then
        pcall(airui.debug, true)
    end

    root = airui.container({ parent = airui.screen, x = 0, y = 0, w = screen_w, h = screen_h, color = T.bg })
    build_grid(root, T)
    build_topbar(T)
    build_nav(T)
    build_statusbar(T)

    -- 视图直接挂在 root 上（不额外加不透明容器），使背景网格在面板间隙可见
    content = root

    set_view(active_key)
end

local function teardown()
    -- 先清空视图缓存（各模块内部会销毁自己的 root 并清空 handles），再销毁外壳
    for key in pairs(view_cache) do cache_drop(key) end
    view_cache = {}
    current_view, current_key = nil, nil
    nav_active = nil      -- 导航图标会随外壳一起重建，激活态记录一并复位
    preload_stop = false
    if root then
        root:destroy()
        root = nil
    end
    nav, top, status = {}, {}, {}
    content = nil
end

local function rebuild()
    teardown()
    build()
    if last_state then on_data(last_state) end
end

local function on_create()
    build()
end

local function on_destroy()
    teardown()
    win_id = nil
end

local function open()
    if not exwin.is_active(win_id) then
        win_id = exwin.open({ on_create = on_create, on_destroy = on_destroy })
        log.info("ui_shell", "主窗口打开成功", win_id)
        -- 可选：后台预热其余视图（默认打开；打开后首次点击也秒开）
        if dbg_cfg().view_preload == true then
            preload_stop = false   -- 上面 build 时的 set_view 会把它置 true，这里显式放行
            sys.taskInit(preload_views)
        end
    end
end

sys.subscribe("OPEN_VOCS_MAIN_WIN", open)
sys.subscribe("VOCS_DATA", on_data)
sys.subscribe("VOCS_THEME_CHANGED", rebuild)

return M
