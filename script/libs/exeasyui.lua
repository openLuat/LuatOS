--[[
exEasyUI v1.7.5
作者：曾帅、江访
日期：2026-01-26
================================
结构说明：
1. 常量定义 - UI颜色常量和调试配置
2. 硬件依赖 - LCD/TP 初始化、字体后端装配
3. 核心部分
   3.1 渲染子系统
   3.2 运行时与事件系统
   3.3 调试模块
   3.4 Widget 基类
4. 工具函数 - 绘图工具、字体工具、文本处理工具
5. 组件部分 - 组件按名称拼音排序，组件列表：
    button、
    check_box、
    combo_box、
    input、
    keyboard、
    label、
    message_box、
    picture、
    progress_bar、
    window、
6. 对外接口导出
]]

local ui                              = {
    version = "1.7.5",
    hw = {},
    runtime = {},
    render = {},
    widget = {},
    debug = {}
}

-- 依赖模块（由 LuatOS 侧提供）
local exlcd                           = require "exlcd"
local extp                            = require "extp"
local lcd                             = lcd
local spi                             = spi
local gtfont                          = gtfont
local hzfont                          = hzfont or rawget(_G, "hzfont")

-- 前置声明（便于分段组织）
local clamp
local now_ms
local fill_rect
local stroke_rect
local font_line_height
local font_measure
local font_draw
local Canvas
local canvas
local handle_debug_stats

local render_state
local sleep_flag                      = false -- 休眠标志，默认false（非休眠状态）
local sleep_config                    = {}

-- 运行时表提前声明，便于硬件模块引用
local runtime                         = {
    roots = {},
    pointer_capture = nil,
    input_bound = false,
    last_pointer = { x = 0, y = 0 },
    touch_anchor_x = 0,
    touch_anchor_y = 0
}
ui.runtime                            = runtime

-- 调试状态表提前声明
local debug_state                     = {
    enabled = false,
    last_stats = nil,
    last_log_ms = 0,
    accum_frame_ms = 0,
    accum_start_ms = 0,
    timer_id = nil
}

-- ================================
-- 1. 常量定义
-- ================================

local COLOR_WHITE                     = 0xFFFF
local COLOR_BLACK                     = 0x0000
local COLOR_GRAY                      = 0x8410
local COLOR_BLUE                      = 0x001F
local COLOR_RED                       = 0xF800
local COLOR_GREEN                     = 0x07E0
local COLOR_YELLOW                    = 0xFFE0
local COLOR_CYAN                      = 0x07FF
local COLOR_MAGENTA                   = 0xF81F
local COLOR_ORANGE                    = 0xFC00
local COLOR_PINK                      = 0xF81F
local COLOR_SKY_BLUE                  = 0x65BE
local COLOR_WIN11_LIGHT_DIALOG_BG     = 0xF79E
local COLOR_WIN11_LIGHT_BUTTON_BG     = 0xFFDF
local COLOR_WIN11_LIGHT_BUTTON_BORDER = 0xE73C
local COLOR_WIN11_DARK_DIALOG_BG      = 0x2104
local COLOR_WIN11_DARK_BUTTON_BG      = 0x3186
local COLOR_WIN11_DARK_BUTTON_BORDER  = 0x4A69

ui.COLOR_WHITE                        = COLOR_WHITE
ui.COLOR_BLACK                        = COLOR_BLACK
ui.COLOR_GRAY                         = COLOR_GRAY
ui.COLOR_BLUE                         = COLOR_BLUE
ui.COLOR_RED                          = COLOR_RED
ui.COLOR_GREEN                        = COLOR_GREEN
ui.COLOR_YELLOW                       = COLOR_YELLOW
ui.COLOR_CYAN                         = COLOR_CYAN
ui.COLOR_MAGENTA                      = COLOR_MAGENTA
ui.COLOR_ORANGE                       = COLOR_ORANGE
ui.COLOR_PINK                         = COLOR_PINK
ui.COLOR_SKY_BLUE                     = COLOR_SKY_BLUE
ui.COLOR_WIN11_LIGHT_DIALOG_BG        = COLOR_WIN11_LIGHT_DIALOG_BG
ui.COLOR_WIN11_LIGHT_BUTTON_BG        = COLOR_WIN11_LIGHT_BUTTON_BG
ui.COLOR_WIN11_LIGHT_BUTTON_BORDER    = COLOR_WIN11_LIGHT_BUTTON_BORDER
ui.COLOR_WIN11_DARK_DIALOG_BG         = COLOR_WIN11_DARK_DIALOG_BG
ui.COLOR_WIN11_DARK_BUTTON_BG         = COLOR_WIN11_DARK_BUTTON_BG
ui.COLOR_WIN11_DARK_BUTTON_BORDER     = COLOR_WIN11_DARK_BUTTON_BORDER

local DEBUG_LOG_INTERVAL_MS           = 1000
local current_theme                   = "light"
gtfont_dev                            = gtfont_dev or nil

local FontAdapter                     = {
    _backend = "default",
    _size = 12,
    _gray = false,
    _name = nil,
    _hz_antialias = -1
}

-- ================================
-- 2. 硬件依赖
-- ================================

local function configure_font_backend(opts)
    opts = opts or {}
    local function fallback_default()
        FontAdapter._backend = "default"
        FontAdapter._size = 12
        FontAdapter._gray = false
        FontAdapter._name = opts.name
        FontAdapter._hz_antialias = -1
        if lcd and lcd.setFont and lcd.font_opposansm12_chinese then
            lcd.setFont(lcd.font_opposansm12_chinese)
            log.info("exEasyUI", "使用默认的font_opposansm12_chinese字体")
        else
            log.warn("exEasyUI", "该固件不支持默认的font_opposansm12_chinese字体，将没有中文支持，请更换支持该字体的固件 ")
        end
    end

    if opts.type == "gtfont" and gtfont and spi then
        local spi_id = (opts.spi and opts.spi.id) or 0
        local spi_cs = (opts.spi and opts.spi.cs) or 8
        local spi_clk = 20 * 1000 * 1000
        gtfont_dev = spi.deviceSetup(spi_id, spi_cs, 0, 0, 8, spi_clk, spi.MSB, 1, 0)
        local ok = gtfont_dev and gtfont.init(gtfont_dev)
        if ok then
            FontAdapter._backend = "gtfont"
            FontAdapter._size = tonumber(opts.size or 16)
            FontAdapter._gray = false
            log.info("exEasyUI", "gtfont enabled", spi_id, spi_cs, FontAdapter._size)
            return
        else
            log.warn("exEasyUI", "gtfont init failed, fallback")
        end
    elseif opts.type == "hzfont" and hzfont then
        local cache_size = tonumber(opts.cache_size) or 256
        cache_size = (cache_size == 128 or cache_size == 256 or cache_size == 512 or cache_size == 1024 or cache_size == 2048) and
            cache_size or 256
        local to_psram = opts.to_psram or false
        local ok

        if to_psram then
            -- 使用3个参数初始化：ttf_path, cache_size, load_to_psram
            ok = hzfont.init(opts.path, nil, true)
            log.info("exEasyUI", "hzfont enabled with PSRAM", opts.path or "builtin", FontAdapter._size, "to_psram=true")
        else
            -- 使用2个参数初始化：ttf_path, cache_size
            ok = hzfont.init(opts.path, cache_size)
            log.info("exEasyUI", "hzfont enabled", opts.path or "builtin", FontAdapter._size, "to_psram=false")
        end

        if ok then
            FontAdapter._backend = "hzfont"
            FontAdapter._size = tonumber(opts.size or 16)
            local aa = tonumber(opts.antialias or -1) or -1
            if not (aa == -1 or aa == 1 or aa == 2 or aa == 4) then
                aa = -1
            end
            FontAdapter._hz_antialias = aa
            return
        else
            log.warn("exEasyUI", "hzfont init failed, fallback")
        end
    end

    fallback_default()
end

function ui.hw_init(opts)
    if not opts then
        log.error("ui.hw_init", "opts is nil")
        return false
    end
    local lcd_ok = exlcd.init(opts.lcd_config)
    if not lcd_ok then
        log.error("exEasyUI", "LCD init failed")
        return false
    end
    if opts.enable_buffer ~= false and lcd and lcd.setupBuff then
        lcd.setupBuff(nil, true)
        log.info("exEasyUI", "framebuffer enabled")
    end
    if lcd and lcd.autoFlush then
        lcd.autoFlush(false)
    end
    if lcd and lcd.setAcchw and lcd.ACC_HW_JPEG then
        lcd.setAcchw(lcd.ACC_HW_JPEG, opts.enable_hardware_decode and true or false)
    end

    -- 初始化触摸IC
    -- 使用配置表中的参数初始化触摸
    local tp_config = opts.tp_config
    extp.init(tp_config)

    -- 设置消息发布状态
    if tp_config and tp_config.message_enabled then
        if type(tp_config.message_enabled) == "table" then
            sleep_config = tp_config.message_enabled
            for msg_type, enabled in pairs(tp_config.message_enabled) do
                if type(msg_type) == "string" and type(enabled) == "boolean" then
                    local success = extp.set_publish_enabled(msg_type, enabled)
                    if not success then
                        log.warn("exEasyUI", "设置消息发布状态失败:", msg_type, enabled)
                    end
                end
            end
        elseif type(tp_config.message_enabled) == "string" then
            local success = extp.set_publish_enabled(tp_config.message_enabled, true)
            sleep_config = extp.get_publish_enable("ALL")
            if not success then
                log.warn("exEasyUI", "设置消息发布状态失败:", tp_config.message_enabled)
            end
        end
    end

    -- 设置滑动阈值
    if tp_config and tp_config.swipe_threshold then
        if type(tp_config.swipe_threshold) == "number" and tp_config.swipe_threshold > 0 then
            extp.set_swipe_threshold(tp_config.swipe_threshold)
        end
    end

    -- 设置长按阈值
    if tp_config and tp_config.long_press_threshold then
        if type(tp_config.long_press_threshold) == "number" and tp_config.long_press_threshold > 0 then
            extp.set_long_press_threshold(tp_config.long_press_threshold)
        end
    end

    runtime.bindInput()

    local width, height

    if opts.lcd_config and opts.lcd_config.w then
        width = (opts.lcd_config and opts.lcd_config.w) or (render_state and render_state.viewport_w)
        height = (opts.lcd_config and opts.lcd_config.h) or (render_state and render_state.viewport_h)
    else
        width, height = lcd.getSize()
    end

    -- 设定字体依赖
    configure_font_backend(opts.font_config or {})
    ui.render.set_viewport(width, height)
    return true
end

-- ================================
-- 3. 核心部分
-- ================================

-- 3.1 渲染子系统

--[[ 刷新机制说明：
exEasyUI 当前的画面刷新机制采用了“脏区收集 + 延迟批量渲染”策略：

1. 脏区收集：当 UI 组件需要刷新时（即 invalidate），会将脏区域 push 到 render_state.dirty_regions，或者标记全屏需刷新，而不会立刻调用渲染。
2. 延迟批量定时：每次有新的脏区加入时，如果刷新定时器未启动，则会启动一个 30ms 的延时定时器（render_state.batch_timer），多次 invalidate 会聚合在一起，定时器回调时统一刷新。
3. 批量渲染：定时器触发后，统一执行一次渲染（如 render_dirty_regions_once 或 request_render），根据脏区列表/全屏标志渲染这些区域，并调用 lcd.flush()。渲染后清空脏区和定时器标记，准备下一轮。
4. 优势：这样能有效合并多组件的刷屏操作（如一次事件引发多个区域变化），大幅减少无谓的重复渲染和屏幕刷新调用，提高性能并减少闪烁。

总之，easyui 刷新机制通过“脏区收集 + 延迟批量+合并”实现了响应灵活且高效的 UI 更新，有利于复杂交互场景下的性能优化和体验提升。
]]

render_state = {
    dirty_regions = {},         -- 当前帧需要刷新的区域列表（数组）
    full_refresh = true,        -- 是否需要全屏刷新
    need_present = false,       -- 是否需要LCD重新显示
    viewport_w = 320,           -- 渲染视口宽度，默认320
    viewport_h = 240,           -- 渲染视口高度，默认240
    clear_color = COLOR_BLACK,  -- 清屏颜色
    render_in_progress = false, -- 是否正在渲染
    render_pending = false,     -- 是否有待渲染请求
    batch_timer_id = nil,       -- 批量刷新定时器ID
    batch_delay_ms = 30         -- 批量刷新延迟（单位ms）
}

-- 计算当前脏区的纵向范围，返回 min_y/max_y（用于局部刷新优化）
local function accumulate_dirty_y_range()
    if render_state.full_refresh then
        return 0, render_state.viewport_h - 1
    end
    if #render_state.dirty_regions == 0 then
        return nil, nil
    end
    local min_y = render_state.viewport_h
    local max_y = 0
    for i = 1, #render_state.dirty_regions do
        local r = render_state.dirty_regions[i]
        local rmin = clamp(r.y, 0, render_state.viewport_h - 1)
        local rmax = clamp(r.y + r.h - 1, 0, render_state.viewport_h - 1)
        if rmin < min_y then min_y = rmin end
        if rmax > max_y then max_y = rmax end
    end
    if min_y > max_y then
        return nil, nil
    end
    return min_y, max_y
end

-- 重置脏区状态，使下一帧从空白状态开始
local function reset_dirty_state()
    render_state.dirty_regions = {}
    render_state.full_refresh = false
    render_state.need_present = false
end

-- 递归绘制整个 widget 树，传入脏区范围用于局部渲染
local function draw_widget_tree(widget, dirty, stats)
    if not widget.visible then return end
    if stats then stats.widgets = stats.widgets + 1 end
    if widget.draw then
        widget:draw(canvas, dirty)
    end
    if widget.children then
        for i = 1, #widget.children do
            draw_widget_tree(widget.children[i], dirty, stats)
        end
    end
end

-- 执行一次脏区渲染：只在确实有脏区时才调用，绘制后立即重置脏区
-- 渲染器核心：根据当前积累的 dirty_regions 渲染整个 widget 树
-- 如果没脏区直接返回，避免无谓的绘制
local function render_dirty_regions_once()
    if not render_state.need_present then
        if not sleep_flag and lcd and lcd.flush then
            lcd.flush()
        end
        return false
    end
    local start_ms = now_ms()
    local y_min, y_max = accumulate_dirty_y_range()
    if not y_min then
        reset_dirty_state()
        return false
    end
    if render_state.full_refresh and canvas and canvas.clear then
        canvas:clear(render_state.clear_color)
    end
    local stats = {
        widgets = 0,
        dirty_span = (y_max and y_min) and (y_max - y_min + 1) or 0,
        full_refresh = render_state.full_refresh
    }
    local dirty_span = { y_min = y_min, y_max = y_max }
    for i = 1, #runtime.roots do
        draw_widget_tree(runtime.roots[i], dirty_span, stats)
    end
    stats.frame_ms = now_ms() - start_ms
    handle_debug_stats(stats)
    if not sleep_flag and lcd and lcd.flush then
        lcd.flush()
    end
    reset_dirty_state()
    return true
end

-- 请求一次渲染：设置 need_present 并串行调用 render_frame，确保当前渲染完成前不会再次启动
-- 用于 `invalidate`/`background` 等接口
-- 请求一次脏区渲染：只有在当前没有正在渲染的情况下才执行，否则设置 pending 让当前帧结束后继续渲染
local function cancel_batch_timer()
    if render_state.batch_timer_id and sys and sys.timerStop then
        sys.timerStop(render_state.batch_timer_id)
    end
    render_state.batch_timer_id = nil
end

local function request_render()
    cancel_batch_timer()
    render_state.need_present = true
    if render_state.render_in_progress then
        render_state.render_pending = true
        return false
    end
    local result = false
    repeat
        -- 每轮先清除 pending 标记再执行
        render_state.render_pending = false
        render_state.render_in_progress = true
        result = render_dirty_regions_once()
        render_state.render_in_progress = false
        -- 如果在 render_dirty_regions_once 中又产生新的 invalidate，就继续渲染
    until not render_state.render_pending
    return result
end

-- 批量渲染调度函数：合并短时间内多次渲染请求，只调度一次定时渲染
local function schedule_batched_render()
    render_state.need_present = true -- 标记需要渲染
    -- 如果不支持 sys.timerStart 或未设置批量延迟，或批量延迟为0，则直接渲染
    if not sys or not sys.timerStart or (render_state.batch_delay_ms or 0) <= 0 then
        return request_render()
    end
    -- 已有定时器任务在排队，不重复调度
    if render_state.batch_timer_id then
        return
    end
    -- 启动一次定时器，到期后执行渲染并清除计时器ID
    render_state.batch_timer_id = sys.timerStart(function()
        render_state.batch_timer_id = nil
        request_render()
    end, render_state.batch_delay_ms)
end

-- 设置逻辑分辨率（主要由硬件初始化时调用）
ui.render.set_viewport = function(w, h)
    if w then render_state.viewport_w = w end
    if h then render_state.viewport_h = h end
end

-- 直接填充背景色并强制标记全屏脏区
ui.render.background = function(color)
    render_state.clear_color = color or COLOR_BLACK
    render_state.full_refresh = true
    schedule_batched_render()
end

-- 标记一个脏区并触发渲染；传入 nil 意味着全屏刷新
ui.render.invalidate = function(rect)
    if not rect then
        render_state.full_refresh = true
    else
        render_state.dirty_regions[#render_state.dirty_regions + 1] = rect
    end
    schedule_batched_render()
end

-- 设置批量渲染延迟（单位：毫秒），用于合并多次刷新请求，减少刷新次数
ui.render.set_batch_delay = function(ms)
    local delay = tonumber(ms)
    if delay and delay >= 0 then
        render_state.batch_delay_ms = delay
    else
        render_state.batch_delay_ms = 0
    end
end

ui.render.present = request_render

-- 3.1.1 图片缓存管理器
local image_cache = {
    _zbuff_cache = {}, -- 路径 -> zbuff 映射
    _loading = {},     -- 正在加载的路径集合（防止重复加载）
    _failed = {}       -- 加载失败的路径集合（避免重复尝试）
}

-- 获取图片 zbuff（按需加载）
function image_cache.get_zbuff(path)
    if not path or type(path) ~= "string" or path == "" then
        return nil
    end

    -- 检查是否已缓存
    if image_cache._zbuff_cache[path] then
        return image_cache._zbuff_cache[path]
    end

    -- 检查是否正在加载（防止重复加载）
    if image_cache._loading[path] then
        return nil
    end

    -- 检查是否已失败
    if image_cache._failed[path] then
        return nil
    end

    -- 检查文件是否存在
    if io and io.exists then
        if not io.exists(path) then
            image_cache._failed[path] = true
            log.warn("image_cache", "图片文件不存在", path)
            return nil
        end
    end

    -- 检查 lcd.image2raw 是否可用
    if not lcd or not lcd.image2raw then
        return nil
    end

    -- 标记为正在加载
    image_cache._loading[path] = true

    -- 解码图片
    local ok, zbuff = pcall(lcd.image2raw, path)
    image_cache._loading[path] = false

    if ok and zbuff then
        -- 缓存成功
        image_cache._zbuff_cache[path] = zbuff
        return zbuff
    else
        -- 解码失败
        image_cache._failed[path] = true
        log.warn("image_cache", "图片解码失败", path)
        return nil
    end
end

-- 预加载图片
function image_cache.preload(path)
    if not path or type(path) ~= "string" or path == "" then
        return false
    end

    -- 如果已缓存，直接返回
    if image_cache._zbuff_cache[path] then
        return true
    end

    -- 尝试加载
    local zbuff = image_cache.get_zbuff(path)
    return zbuff ~= nil
end

-- 清除缓存
function image_cache.clear(path)
    if path then
        -- 清除指定路径
        image_cache._zbuff_cache[path] = nil
        image_cache._loading[path] = nil
        image_cache._failed[path] = nil
    else
        -- 清除所有缓存
        image_cache._zbuff_cache = {}
        image_cache._loading = {}
        image_cache._failed = {}
    end
end

-- 检查缓存状态
function image_cache.is_cached(path)
    if not path then return false end
    return image_cache._zbuff_cache[path] ~= nil
end

ui.image_cache = image_cache

-- 3.2 运行时与事件系统
local function dispatch_pointer(evt, a, b)
    for i = #runtime.roots, 1, -1 do
        local root = runtime.roots[i]
        if root:dispatch_pointer(evt, a, b) then
            return true
        end
    end
    return false
end

local function debug_touch_log(evt, rawA, rawB, cursorX, cursorY)
    if not debug_state.enabled then return end
    local function sval(v)
        if v == nil then return "nil" end
        return tostring(v)
    end
    -- log.info("exEasyUI.debug.tp", string.format("evt=%s raw=(%s,%s) cursor=(%s,%s)",
    --     tostring(evt or ""), sval(rawA), sval(rawB), sval(cursorX), sval(cursorY)))
end

local function handle_touch_event(evt, a, b)
    local rawA = a
    local rawB = b
    if evt == "TOUCH_DOWN" or evt == "SINGLE_TAP" or evt == "LONG_PRESS" then
        runtime.last_pointer.x = tonumber(a) or 0
        runtime.last_pointer.y = tonumber(b) or 0
        runtime.touch_anchor_x = runtime.last_pointer.x
        runtime.touch_anchor_y = runtime.last_pointer.y
        debug_touch_log(evt, rawA, rawB, runtime.last_pointer.x, runtime.last_pointer.y)
        return dispatch_pointer(evt, runtime.last_pointer.x, runtime.last_pointer.y)
    end
    if evt == "MOVE_X" then
        local delta = tonumber(a) or 0
        if runtime.touch_anchor_x == nil then
            runtime.touch_anchor_x = runtime.last_pointer.x
        end
        runtime.last_pointer.x = (runtime.touch_anchor_x or 0) + delta
        debug_touch_log(evt, rawA, rawB, runtime.last_pointer.x, runtime.last_pointer.y)
        return dispatch_pointer(evt, runtime.last_pointer.x, runtime.last_pointer.y)
    elseif evt == "MOVE_Y" then
        local delta = tonumber(b) or 0
        if runtime.touch_anchor_y == nil then
            runtime.touch_anchor_y = runtime.last_pointer.y
        end
        runtime.last_pointer.y = (runtime.touch_anchor_y or 0) + delta
        debug_touch_log(evt, rawA, rawB, runtime.last_pointer.x, runtime.last_pointer.y)
        return dispatch_pointer(evt, runtime.last_pointer.x, runtime.last_pointer.y)
    else
        local ax = tonumber(a)
        local ay = tonumber(b)
        debug_touch_log(evt, rawA, rawB, ax, ay)
        return dispatch_pointer(evt, ax, ay)
    end
end

function runtime.bindInput()
    if runtime.input_bound then return end
    sys.subscribe("BASE_TOUCH_EVENT", handle_touch_event)
    runtime.input_bound = true
end

function runtime.add(widget)
    runtime.roots[#runtime.roots + 1] = widget
    widget.root = true
    if widget.on_mount then widget:on_mount() end
    widget:invalidate()
    return widget
end

function runtime.remove(widget)
    for i = #runtime.roots, 1, -1 do
        if runtime.roots[i] == widget then
            table.remove(runtime.roots, i)
            if widget.on_unmount then widget:on_unmount() end
            render_state.full_refresh = true
            request_render()
            return true
        end
    end
    return false
end

local function debug_emit_summary()
    local total = debug_state.accum_frame_ms or 0
    local usage = (total / DEBUG_LOG_INTERVAL_MS) * 100
    log.info("exEasyUI.debug", string.format("最近1s绘制耗时=%.1fms  耗时占比=%.1f%%", total, usage))
    debug_state.accum_frame_ms = 0
    debug_state.accum_start_ms = now_ms()
end

local function debug_timer_tick()
    if not debug_state.enabled then return end
    debug_emit_summary()
end

handle_debug_stats = function(stats)
    debug_state.last_stats = stats
    if not debug_state.enabled then return end
    if stats and stats.frame_ms then
        log.info("exEasyUI.debug", string.format("单次绘制耗时=%.1fms  绘制组件=%d  脏区高度=%dpx  绘制方式=%s",
            stats.frame_ms or 0,
            stats.widgets or 0,
            stats.dirty_span or 0,
            stats.full_refresh and "全屏" or "局部"))
        debug_state.accum_frame_ms = (debug_state.accum_frame_ms or 0) + (stats.frame_ms or 0)
    end
    if not debug_state.timer_id then
        local now = now_ms()
        if debug_state.accum_start_ms == 0 then
            debug_state.accum_start_ms = now
        end
        local window_ms = DEBUG_LOG_INTERVAL_MS
        if now - debug_state.accum_start_ms >= window_ms then
            debug_emit_summary()
        end
    end
end

function ui.debug.enable(enabled)
    enabled = not not enabled
    if enabled and not debug_state.enabled then
        debug_state.enabled = true
        debug_state.accum_frame_ms = 0
        debug_state.accum_start_ms = now_ms()
        if sys and sys.timerLoopStart then
            debug_state.timer_id = sys.timerLoopStart(debug_timer_tick, DEBUG_LOG_INTERVAL_MS)
        end
    elseif (not enabled) and debug_state.enabled then
        debug_state.enabled = false
        if debug_state.timer_id and sys and sys.timerStop then
            sys.timerStop(debug_state.timer_id)
        end
        debug_state.timer_id = nil
        debug_state.accum_frame_ms = 0
        debug_state.accum_start_ms = 0
    end
end

function ui.debug.set_level(level)
    if level == "off" then
        ui.debug.enable(false)
    else
        ui.debug.enable(true)
    end
end

function ui.debug.get_stats()
    return debug_state.last_stats
end

setmetatable(ui.debug, {
    __call = function(_, enabled)
        ui.debug.enable(enabled)
    end
})

-- 3.4 Widget 基类
local BaseWidget = {}
BaseWidget.__index = BaseWidget

function BaseWidget:new(opts)
    opts = opts or {}
    local o = setmetatable({}, self)
    o.x = opts.x or 0
    o.y = opts.y or 0
    o.w = opts.w or 0
    o.h = opts.h or 0
    o.visible = opts.visible ~= false
    o.enabled = opts.enabled ~= false
    o.children = {}
    o.theme = opts.theme
    return o
end

function BaseWidget:get_absolute_position()
    local x = self.x or 0
    local y = self.y or 0
    local parent = self.parent
    while parent do
        x = x + (parent.x or 0)
        y = y + (parent.y or 0)
        if parent._scroll then
            x = x + (parent._scroll.offset_x or 0)
            y = y + (parent._scroll.offset_y or 0)
        end
        parent = parent.parent
    end
    return x, y
end

function BaseWidget:add(child)
    self.children[#self.children + 1] = child
    child.parent = self
    child:invalidate()
    return child
end

function BaseWidget:get_bounds()
    local ax, ay = self:get_absolute_position()
    return { x = ax, y = ay, w = self.w, h = self.h }
end

function BaseWidget:invalidate(rect)
    local bounds = rect or self:get_bounds()
    ui.render.invalidate(bounds)
end

function BaseWidget:contains_point(px, py)
    local bounds = self:get_bounds()
    return px >= bounds.x and py >= bounds.y and
        px <= (bounds.x + bounds.w) and py <= (bounds.y + bounds.h)
end

function BaseWidget:handle_event()
    return false
end

function BaseWidget:dispatch_pointer(evt, x, y)
    if not self.visible or not self.enabled then
        return false
    end
    if self.children then
        for i = #self.children, 1, -1 do
            if self.children[i]:dispatch_pointer(evt, x, y) then
                return true
            end
        end
    end
    if self.handle_event ~= BaseWidget.handle_event then
        return self:handle_event(evt, x, y)
    end
    return false
end

ui.widget.Base = BaseWidget

-- ================================
-- 4. 工具函数
-- ================================

clamp = function(v, minv, maxv)
    if v < minv then return minv end
    if v > maxv then return maxv end
    return v
end

now_ms = function()
    if mcu and mcu.ticks then
        return mcu.ticks()
    end
    if sys and sys.tick then
        return sys.tick()
    end
    return (os.time() or 0) * 1000
end

fill_rect = function(x1, y1, x2, y2, color)
    if not lcd or not lcd.fill then return end
    lcd.fill(x1, y1, x2, y2 + 1, color)
end

stroke_rect = function(x1, y1, x2, y2, color)
    if not lcd then return end
    if lcd.drawLine then
        lcd.drawLine(x1, y1, x2, y1, color)
        lcd.drawLine(x2, y1, x2, y2, color)
        lcd.drawLine(x2, y2, x1, y2, color)
        lcd.drawLine(x1, y2, x1, y1, color)
    end
end

font_line_height = function(style)
    if FontAdapter._backend == "gtfont" or FontAdapter._backend == "hzfont" then
        return tonumber(style and style.size or FontAdapter._size or 16)
    end
    if lcd and style and style.size then
        local guess = "font_opposansm" .. tostring(style.size) .. "_chinese"
        if lcd[guess] then
            return tonumber(style.size)
        end
    end
    return FontAdapter._size or 12
end

font_measure = function(text, style)
    if not text or text == "" then return 0 end
    style = style or {}
    if FontAdapter._backend == "gtfont" and lcd and lcd.getGtfontStrWidth then
        return lcd.getGtfontStrWidth(text, tonumber(style.size or FontAdapter._size or 16))
    end
    if FontAdapter._backend == "hzfont" and lcd and lcd.getHzFontStrWidth then
        return lcd.getHzFontStrWidth(text, tonumber(style.size or FontAdapter._size or 16))
    end
    if lcd and lcd.getStrWidth then
        return lcd.getStrWidth(text)
    end
    local width = 0
    local i = 1
    local size = tonumber(style.size) or FontAdapter._size or 12
    while i <= #text do
        local byte = string.byte(text, i)
        if byte < 128 then
            width = width + math.ceil(size / 2)
            i = i + 1
        else
            width = width + size
            i = i + 3
        end
    end
    return width
end

font_draw = function(text, x, y, color, style)
    if not lcd then return end
    style = style or {}
    color = color or COLOR_WHITE
    if FontAdapter._backend == "gtfont" and lcd.drawGtfontUtf8 then
        local sz = tonumber(style.size or FontAdapter._size or 16)
        if FontAdapter._gray and lcd.drawGtfontUtf8Gray then
            lcd.drawGtfontUtf8Gray(text, sz, 4, x, y, color)
            return
        end
        lcd.drawGtfontUtf8(text, sz, x, y, color)
        return
    end
    if FontAdapter._backend == "hzfont" and lcd.drawHzfontUtf8 then
        local sz = tonumber(style.size or FontAdapter._size or 16)
        local lh = font_line_height(style)
        lcd.drawHzfontUtf8(x, y + lh, text, sz, color, FontAdapter._hz_antialias or -1)
        return
    end
    if lcd.setFont then
        if FontAdapter._name and lcd["font_" .. FontAdapter._name] then
            lcd.setFont(lcd["font_" .. FontAdapter._name])
        elseif style.size then
            local guess = "font_opposansm" .. tostring(style.size) .. "_chinese"
            if lcd[guess] then
                lcd.setFont(lcd[guess])
            elseif lcd.font_opposansm12_chinese then
                lcd.setFont(lcd.font_opposansm12_chinese)
            end
        elseif lcd.font_opposansm12_chinese then
            lcd.setFont(lcd.font_opposansm12_chinese)
        end
    end
    local lh = font_line_height(style)
    if lcd.drawStr then
        lcd.drawStr(x, y + lh, text, color)
    end
end

Canvas = {}
Canvas.__index = Canvas

function Canvas:new()
    return setmetatable({}, Canvas)
end

function Canvas:clear(color)
    if lcd and lcd.clear then
        lcd.clear(color or COLOR_BLACK)
    end
end

function Canvas:fill_rect(x, y, w, h, color)
    if w <= 0 or h <= 0 then return end
    fill_rect(x, y, x + w - 1, y + h - 1, color)
end

function Canvas:stroke_rect(x, y, w, h, color)
    if w <= 0 or h <= 0 then return end
    stroke_rect(x, y, x + w - 1, y + h - 1, color)
end

function Canvas:draw_text(text, x, y, color, style)
    font_draw(text, x, y, color, style)
end

function Canvas:text_width(text, style)
    return font_measure(text, style)
end

function Canvas:line_height(style)
    return font_line_height(style)
end

function Canvas:draw_text_in_rect_centered(x, y, w, h, text, opts)
    opts = opts or {}
    local padding = opts.padding or 0
    local style = opts.style or {}
    local color = opts.color or COLOR_WHITE
    local tw = self:text_width(text or "", style)
    local lh = self:line_height(style)
    local inner_w = math.max(0, w - padding * 2)
    local inner_h = math.max(0, h - padding * 2)
    local tx = x + padding + (inner_w - tw) // 2
    local ty = y + padding + (inner_h - lh) // 2
    self:draw_text(text or "", tx, ty, color, style)
end

canvas = Canvas:new()

local function get_utf8_char(text, i)
    if not text or i > #text then return "", 0 end
    local byte = string.byte(text, i)
    if not byte then return "", 0 end
    if byte < 128 then
        return string.sub(text, i, i), 1
    elseif byte >= 224 and byte < 240 then
        if i + 2 <= #text then
            return string.sub(text, i, i + 2), 3
        else
            return string.sub(text, i, i), 1
        end
    elseif byte >= 192 and byte < 224 then
        if i + 1 <= #text then
            return string.sub(text, i, i + 1), 2
        else
            return string.sub(text, i, i), 1
        end
    elseif byte >= 240 then
        if i + 3 <= #text then
            return string.sub(text, i, i + 3), 4
        else
            return string.sub(text, i, i), 1
        end
    end
    return string.sub(text, i, i), 1
end

local function wrap_text_lines(text, maxWidth, style)
    if not text or text == "" then return { "" } end
    if not maxWidth or maxWidth <= 0 then return { text } end
    local lines = {}
    local currentLine = ""
    local currentWidth = 0
    local wordBuffer = ""
    local wordWidth = 0
    local i = 1
    while i <= #text do
        local char, charLen = get_utf8_char(text, i)
        local charWidth = font_measure(char, style)
        local byte = string.byte(text, i)
        local isAlphaNum = (byte and ((byte >= 48 and byte <= 57) or (byte >= 65 and byte <= 90) or (byte >= 97 and byte <= 122)))
        if isAlphaNum then
            wordBuffer = wordBuffer .. char
            wordWidth = wordWidth + charWidth
            i = i + charLen
        else
            if wordBuffer ~= "" then
                if currentWidth + wordWidth > maxWidth then
                    if currentLine ~= "" then
                        table.insert(lines, currentLine)
                        currentLine = wordBuffer
                        currentWidth = wordWidth
                    else
                        currentLine = wordBuffer
                        currentWidth = wordWidth
                    end
                else
                    currentLine = currentLine .. wordBuffer
                    currentWidth = currentWidth + wordWidth
                end
                wordBuffer = ""
                wordWidth = 0
            end
            if char == " " then
                if currentWidth + charWidth <= maxWidth then
                    currentLine = currentLine .. char
                    currentWidth = currentWidth + charWidth
                else
                    if currentLine ~= "" then
                        table.insert(lines, currentLine)
                    end
                    currentLine = ""
                    currentWidth = 0
                end
            else
                if currentWidth + charWidth > maxWidth then
                    if currentLine ~= "" then
                        table.insert(lines, currentLine)
                    end
                    currentLine = char
                    currentWidth = charWidth
                else
                    currentLine = currentLine .. char
                    currentWidth = currentWidth + charWidth
                end
            end
            i = i + charLen
        end
    end
    if wordBuffer ~= "" then
        if currentWidth + wordWidth > maxWidth and currentLine ~= "" then
            table.insert(lines, currentLine)
            currentLine = wordBuffer
        else
            currentLine = currentLine .. wordBuffer
        end
    end
    if currentLine ~= "" then
        table.insert(lines, currentLine)
    end
    if #lines == 0 then
        lines = { "" }
    end
    return lines
end

local function fit_text_to_width(text, maxWidth, style, opts)
    opts = opts or {}
    if not text then return "" end
    if not maxWidth or maxWidth <= 0 then return text end
    if font_measure(text, style) <= maxWidth then
        return text
    end
    local ellipsis = opts.ellipsis and "..." or ""
    local reserve = opts.ellipsis and font_measure("...", style) or 0
    local limit = maxWidth - reserve
    if limit <= 0 then
        return opts.ellipsis and "..." or ""
    end
    local truncated = ""
    local used = 0
    local i = 1
    while i <= #text do
        local char, len = get_utf8_char(text, i)
        local cw = font_measure(char, style)
        if used + cw > limit then
            break
        end
        truncated = truncated .. char
        used = used + cw
        i = i + len
    end
    if opts.ellipsis then
        return truncated .. "..."
    end
    return truncated
end

local function draw_text_direct(x, y, text, opts)
    opts = opts or {}
    font_draw(text or "", x, y, opts.color or COLOR_WHITE, opts.style or {})
end

local function draw_text_in_rect_centered(x, y, w, h, text, opts)
    opts = opts or {}
    local padding = opts.padding or 0
    local style = opts.style or {}
    local color = opts.color or COLOR_WHITE
    local tw = font_measure(text or "", style)
    local lh = font_line_height(style)
    local inner_w = math.max(0, w - padding * 2)
    local inner_h = math.max(0, h - padding * 2)
    local tx = x + padding + (inner_w - tw) // 2
    local ty = y + padding + (inner_h - lh) // 2
    font_draw(text or "", tx, ty, color, style)
end

local function draw_image_placeholder(x, y, w, h, bg_color, border_color)
    bg_color = bg_color or COLOR_GRAY
    border_color = border_color or COLOR_WHITE
    fill_rect(x, y, x + w - 1, y + h - 1, bg_color)
    stroke_rect(x, y, x + w - 1, y + h - 1, border_color)
    if lcd and lcd.drawLine then
        lcd.drawLine(x, y, x + w - 1, y + h - 1, border_color)
        lcd.drawLine(x + w - 1, y, x, y + h - 1, border_color)
        if w >= 20 and h >= 20 then
            local margin = math.min(w, h) // 8
            lcd.drawLine(x + margin, y + margin, x + w - 1 - margin, y + h - 1 - margin, border_color)
            lcd.drawLine(x + w - 1 - margin, y + margin, x + margin, y + h - 1 - margin, border_color)
        end
    end
end

-- 箭头绘制工具（在给定矩形内绘制上下左右箭头）
local function draw_arrow_icon(x, y, w, h, direction, color)
    local cx = x + w // 2
    local cy = y + h // 2
    -- 控制箭头尺寸（增大内边距，整体缩短约 1/3）
    local padX = math.max(1, w // 3)
    local padY = math.max(1, h // 3)
    local leftX = x + padX
    local rightX = x + w - padX
    local topY = y + padY
    local bottomY = y + h - padY

    if direction == "up" then
        lcd.drawLine(leftX, bottomY, cx, topY, color)
        lcd.drawLine(rightX, bottomY, cx, topY, color)
    elseif direction == "down" then
        lcd.drawLine(leftX, topY, cx, bottomY, color)
        lcd.drawLine(rightX, topY, cx, bottomY, color)
    elseif direction == "left" then
        -- 左侧中点 -> 右上/右下（<）
        lcd.drawLine(leftX, cy, rightX, topY, color)
        lcd.drawLine(leftX, cy, rightX, bottomY, color)
    elseif direction == "right" then
        -- 右侧中点 -> 左上/左下（>）
        lcd.drawLine(rightX, cy, leftX, topY, color)
        lcd.drawLine(rightX, cy, leftX, bottomY, color)
    end
end
-- ================================
-- 5. 组件部分（按拼音排序）
-- 组件列表：button、check_box、combo_box、input、keyboard、label、message_box、picture、progress_bar、window
-- ================================

-- 5.1 button
local button = setmetatable({}, { __index = BaseWidget })
button.__index = button

function button:new(opts)
    opts = opts or {}
    opts.w = opts.w or opts.width or 100
    opts.h = opts.h or opts.height or 36
    local o = BaseWidget.new(self, opts)
    local dark = (current_theme == "dark")
    o.text = opts.text or "Button"
    o.text_style = { size = opts.text_size or opts.size or opts.font_size or 12 }
    o.colors = {
        bg = opts.bg_color or (dark and COLOR_GRAY or COLOR_WHITE),
        pressed = opts.pressed_color or COLOR_SKY_BLUE,
        border = opts.border_color or (dark and COLOR_WHITE or COLOR_BLACK),
        text = opts.text_color or (dark and COLOR_WHITE or COLOR_BLACK)
    }
    o.src = opts.src
    o.src_pressed = opts.src_pressed
    o.src_toggled = opts.src_toggled
    o.toggle = opts.toggle or false
    o.toggled = opts.toggled or false
    o.on_toggle = opts.on_toggle
    o.on_click = opts.on_click
    o.pressed = false
    o._imageCache = {}
    return o
end

local function button_resolve_image(self)
    if not self.src then return nil end
    if self.toggle and self.toggled then
        return self.src_toggled or self.src
    elseif self.pressed then
        return self.src_pressed or self.src
    end
    return self.src
end

function button:draw(ctx)
    if not self.visible then return end
    local ax, ay = self:get_absolute_position()
    local img = button_resolve_image(self)

    -- 优先使用图片缓存（lcd.image2raw + lcd.draw）
    if img and lcd and lcd.image2raw and lcd.draw then
        local zbuff = ui.image_cache.get_zbuff(img)
        if zbuff then
            -- 使用 zbuff 绘制，lcd.draw 会自动使用 zbuff 内部的 width 和 height
            lcd.draw(ax, ay, nil, nil, zbuff)
            return
        end
    end

    -- 绘制按钮背景和文本
    local bg = self.pressed and self.colors.pressed or self.colors.bg
    ctx:fill_rect(ax, ay, self.w, self.h, bg)
    ctx:stroke_rect(ax, ay, self.w, self.h, self.colors.border)
    local text_w = ctx:text_width(self.text or "", self.text_style)
    local text_h = ctx:line_height(self.text_style)
    local tx = ax + math.max(0, (self.w - text_w) // 2)
    local ty = ay + math.max(0, (self.h - text_h) // 2)
    ctx:draw_text(self.text or "", tx, ty, self.colors.text, self.text_style)
end

function button:set_text(new_text)
    self.text = tostring(new_text or "")
    self:invalidate()
end

function button:handle_event(evt, x, y)
    if not self.enabled then return false end
    local inside = self:contains_point(x or 0, y or 0)
    if evt == "TOUCH_DOWN" and inside then
        self.pressed = true
        self._capture = true
        self:invalidate()
        return true
    elseif (evt == "MOVE_X" or evt == "MOVE_Y") and self._capture then
        local new_pressed = inside
        if new_pressed ~= self.pressed then
            self.pressed = new_pressed
            self:invalidate()
        end
        return true
    elseif evt == "SINGLE_TAP" then
        local was_pressed = self.pressed
        self.pressed = false
        self._capture = false
        if was_pressed and inside then
            if self.toggle then
                self.toggled = not self.toggled
                if self.on_toggle then
                    pcall(self.on_toggle, self.toggled, self)
                end
            end
            if self.on_click then
                pcall(self.on_click, self)
            end
            self:invalidate()
            return true
        end
        self:invalidate()
        return was_pressed
    elseif evt == "LONG_PRESS" or evt == "SWIPE_LEFT" or evt == "SWIPE_RIGHT" or evt == "SWIPE_UP" or evt == "SWIPE_DOWN" then
        if self._capture then
            self.pressed = false
            self._capture = false
            self:invalidate()
            return true
        end
    end
    return false
end

ui.button = function(opts)
    return button:new(opts)
end

-- 5.2 CheckBox
local check_box = setmetatable({}, { __index = BaseWidget })
check_box.__index = check_box

function check_box:new(opts)
    opts = opts or {}
    opts.box_size = opts.box_size or 20
    local text_style = { size = opts.text_size or 12 }
    local text_width = opts.text and font_measure(opts.text, text_style) or 0
    opts.w = math.max(opts.w or 0, opts.box_size + (opts.text and (10 + text_width) or 0))
    opts.h = math.max(opts.h or 0, opts.box_size, font_line_height(text_style))
    local o = BaseWidget.new(self, opts)
    o.text = opts.text or ""
    o.text_style = text_style
    o.box_size = opts.box_size
    o.checked = opts.checked or false
    o.on_change = opts.on_change
    local dark = (current_theme == "dark")
    o.colors = {
        border = opts.border_color or (dark and COLOR_WHITE or COLOR_BLACK),
        bg = opts.bg_color or (dark and COLOR_BLACK or COLOR_WHITE),
        tick = opts.tick_color or COLOR_SKY_BLUE,
        text = opts.text_color or (dark and COLOR_WHITE or COLOR_BLACK)
    }
    return o
end

function check_box:set_checked(v)
    local nv = not not v
    if nv == self.checked then return end
    self.checked = nv
    self:invalidate()
    if self.on_change then
        pcall(self.on_change, self.checked, self)
    end
end

function check_box:toggle()
    self:set_checked(not self.checked)
end

function check_box:draw(ctx)
    local ax, ay = self:get_absolute_position()
    local size = self.box_size
    ctx:stroke_rect(ax, ay, size, size, self.colors.border)
    ctx:fill_rect(ax + 2, ay + 2, size - 4, size - 4, self.colors.bg)
    if self.checked then
        ctx:fill_rect(ax + 4, ay + 4, size - 8, size - 8, self.colors.tick)
    end
    if self.text and self.text ~= "" then
        local lh = ctx:line_height(self.text_style)
        local ty = ay + (self.h - lh) // 2
        ctx:draw_text(self.text, ax + size + 10, ty, self.colors.text, self.text_style)
    end
end

function check_box:handle_event(evt, x, y)
    if evt == "SINGLE_TAP" then
        if x and y and self:contains_point(x, y) then
            self:toggle()
            return true
        end
    elseif evt == "TOUCH_DOWN" then
        return self:contains_point(x or 0, y or 0)
    end
    return false
end

ui.check_box = function(opts)
    return check_box:new(opts)
end

-- 5.3 ComboBox
local dropdown_panel = setmetatable({}, { __index = BaseWidget })
dropdown_panel.__index = dropdown_panel

function dropdown_panel:new(owner)
    local o = BaseWidget.new(self, { x = 0, y = 0, w = 0, h = 0 })
    o.owner = owner
    o.visible = false
    o.item_height = (owner and owner.dropdown_item_height) or 32
    o.padding = 4
    o.scroll_offset = 0
    o.max_scroll_offset = 0
    o.hovered_index = -1
    o.pressed_index = -1
    o.scroll_threshold = 10
    o.drag_start_y = 0
    o.scroll_base_offset = 0
    o.is_dragging = false
    o._host_is_window = false
    return o
end

function dropdown_panel:update_layout()
    local owner = self.owner
    if not owner then return end
    self.w = owner.w
    local itemCount = #(owner.options or {})
    local maxVisible = math.max(1, math.min(itemCount, owner.max_visible_items or 5))
    self.visible_count = maxVisible
    self.h = maxVisible * self.item_height + self.padding * 2
    self.max_scroll_offset = math.max(0, itemCount - maxVisible)
    self.scroll_offset = clamp(self.scroll_offset, 0, self.max_scroll_offset)
    if self._host_is_window and owner._parentWindow then
        self.x = owner.x
        self.y = owner.y + owner.h
    else
        local ax, ay = owner:get_absolute_position()
        self.x = ax
        self.y = ay + owner.h
    end
end

function dropdown_panel:draw(ctx)
    if not self.visible then return end
    local owner = self.owner
    if not owner then return end
    local ax, ay       = self:get_absolute_position()
    local dark         = (current_theme == "dark")
    local bg_color     = dark and COLOR_WIN11_DARK_BUTTON_BG or COLOR_WIN11_LIGHT_BUTTON_BG
    local border_color = dark and COLOR_WIN11_DARK_BUTTON_BORDER or COLOR_WIN11_LIGHT_BUTTON_BORDER
    ctx:fill_rect(ax, ay, self.w, self.h, bg_color)
    ctx:stroke_rect(ax, ay, self.w, self.h, border_color)
    local startIdx = self.scroll_offset + 1
    local endIdx = math.min(#owner.options, startIdx + (self.visible_count or owner.max_visible_items or 5) - 1)
    local textStyle = owner.text_style
    local lh = ctx:line_height(textStyle)
    for i = startIdx, endIdx do
        local itemY = ay + self.padding + (i - startIdx) * self.item_height
        local isHovered = (i == self.hovered_index)
        local isPressed = (i == self.pressed_index)
        local isSelected = (i == owner.selected_index)
        if isPressed then
            ctx:fill_rect(ax + self.padding, itemY, self.w - self.padding * 2, self.item_height, COLOR_GRAY)
        elseif isHovered then
            ctx:fill_rect(ax + self.padding, itemY, self.w - self.padding * 2, self.item_height, COLOR_SKY_BLUE)
        end
        local labelColor = owner.colors.text
        if isHovered then
            labelColor = COLOR_WHITE
        end
        local text = owner:_normalize_option_text(owner.options[i])
        local textX = ax + self.padding + 6
        local textY = itemY + (self.item_height - lh) // 2
        if isSelected then
            ctx:draw_text("*", textX, textY, labelColor, textStyle)
            textX = textX + ctx:text_width("*", textStyle) + 4
        end
        ctx:draw_text(text, textX, textY, labelColor, textStyle)
    end

    -- 绘制滚动指示器（如果需要滚动）
    if self.max_scroll_offset > 0 then
        local scrollBarWidth = 4
        local scrollBarX = ax + self.w - scrollBarWidth - 2
        local scrollBarHeight = self.h - 4
        local scrollBarY = ay + 2

        -- 滚动条背景
        ctx:fill_rect(scrollBarX, scrollBarY, scrollBarWidth, scrollBarHeight, COLOR_WHITE)

        -- 滚动条滑块（基于滚动偏移计算）
        local maxVisibleItems = self.visible_count or owner.max_visible_items or 5
        local totalItems = #owner.options
        local thumbHeight = math.max(10, math.floor(scrollBarHeight * maxVisibleItems / totalItems))

        -- 计算滑块位置：基于当前滚动偏移量
        local thumbY
        if self.max_scroll_offset > 0 then
            thumbY = scrollBarY +
                math.floor((self.scroll_offset / self.max_scroll_offset) * (scrollBarHeight - thumbHeight))
        else
            thumbY = scrollBarY
        end

        ctx:fill_rect(scrollBarX, thumbY, scrollBarWidth, thumbHeight, border_color)
    end
end

function dropdown_panel:handle_event(evt, x, y)
    if not (self.visible and self.owner and self.owner.enabled) then return false end
    local inside = self:contains_point(x, y)
    if not inside then
        if evt == "SINGLE_TAP" or evt == "LONG_PRESS" then
            self:hide()
            return true
        end
        return false
    end
    local owner = self.owner
    local ax, ay = self:get_absolute_position()
    if evt == "TOUCH_DOWN" then
        self.drag_start_y = y
        self.scroll_base_offset = self.scroll_offset
        self.is_dragging = false
        local relativeY = y - ay - self.padding
        local pressedIndex = math.floor(relativeY / self.item_height) + self.scroll_offset + 1
        if pressedIndex >= 1 and pressedIndex <= #owner.options then
            self.pressed_index = pressedIndex
        else
            self.pressed_index = -1
        end
        self._capture = true
        self:invalidate()
        return true
    elseif (evt == "MOVE_X" or evt == "MOVE_Y") and self._capture then
        local dy = y - self.drag_start_y
        if not self.is_dragging and math.abs(dy) >= self.scroll_threshold then
            self.is_dragging = true
            self.pressed_index = -1
            self.hovered_index = -1
            self:invalidate()
        end
        if self.is_dragging then
            local newOffset = self.scroll_base_offset + math.floor(-dy / self.item_height)
            newOffset = clamp(newOffset, 0, self.max_scroll_offset)
            if newOffset ~= self.scroll_offset then
                self.scroll_offset = newOffset
                self:invalidate()
            end
        else
            local relativeY = y - ay - self.padding
            local hoverIndex = math.floor(relativeY / self.item_height) + self.scroll_offset + 1
            if hoverIndex >= 1 and hoverIndex <= #owner.options then
                if hoverIndex ~= self.hovered_index then
                    self.hovered_index = hoverIndex
                    self:invalidate()
                end
            else
                if self.hovered_index ~= -1 then
                    self.hovered_index = -1
                    self:invalidate()
                end
            end
        end
        return true
    elseif evt == "SINGLE_TAP" and self._capture then
        self._capture = false
        local relativeY = y - ay - self.padding
        local clickedIndex = math.floor(relativeY / self.item_height) + self.scroll_offset + 1
        self.pressed_index = -1
        if self.hovered_index ~= -1 then
            self.hovered_index = -1
            self:invalidate()
        end
        if not self.is_dragging and clickedIndex >= 1 and clickedIndex <= #owner.options then
            owner:set_selected(clickedIndex)
            self:hide()
            return true
        end
        self.is_dragging = false
        return true
    elseif evt == "LONG_PRESS" or evt == "SWIPE_LEFT" or evt == "SWIPE_RIGHT" or evt == "SWIPE_UP" or evt == "SWIPE_DOWN" then
        self._capture = false
        if self.pressed_index ~= -1 or self.hovered_index ~= -1 then
            self.pressed_index = -1
            self.hovered_index = -1
            self:invalidate()
        end
        self.is_dragging = false
        return true
    end
    return false
end

function dropdown_panel:show()
    local owner = self.owner
    if not owner then return end
    if self.visible then return end
    self._host_is_window = owner._parentWindow ~= nil
    if self._host_is_window and owner._parentWindow then
        owner._parentWindow:add(self)
    else
        runtime.add(self)
    end
    self:update_layout()
    self.visible = true
    self.hovered_index = owner.selected_index or -1
    self.pressed_index = -1
    self.is_dragging = false
    self:invalidate()
end

function dropdown_panel:hide()
    if not self.visible then return end
    self.visible = false
    self.hovered_index = -1
    self.pressed_index = -1
    self.is_dragging = false
    self._capture = false
    if self._host_is_window and self.parent then
        self.parent:remove(self)
    else
        runtime.remove(self)
    end
    self._host_is_window = false
end

local combo_box = setmetatable({}, { __index = BaseWidget })
combo_box.__index = combo_box

function combo_box:new(opts)
    opts = opts or {}
    opts.w = opts.width or opts.w or 200
    opts.h = opts.height or opts.h or 36
    local o = BaseWidget.new(self, opts)
    o.options = opts.options or {}
    o.selected_index = clamp(opts.selected or 1, 1, math.max(1, #o.options))
    o.placeholder = opts.placeholder or "请选择"
    o.max_visible_items = opts.max_visible_items or 5
    o.dropdown_item_height = opts.item_height or 32
    o.text_style = { size = opts.text_size or opts.size or 12 }
    local dark = (current_theme == "dark")
    o.colors = {
        bg = opts.bg_color or (dark and COLOR_WIN11_DARK_BUTTON_BG or COLOR_WIN11_LIGHT_BUTTON_BG),
        border = opts.border_color or (dark and COLOR_WIN11_DARK_BUTTON_BORDER or COLOR_WIN11_LIGHT_BUTTON_BORDER),
        text = opts.text_color or (dark and COLOR_WHITE or COLOR_BLACK),
        arrow = opts.arrow_color or COLOR_SKY_BLUE
    }
    o.on_select = opts.on_select
    o.pressed = false
    o._dropdown = dropdown_panel:new(o)
    return o
end

function combo_box:_normalize_option_text(item)
    if type(item) == "table" then
        return tostring(item.text or item.value or "")
    end
    return tostring(item or "")
end

function combo_box:set_options(options)
    self.options = options or {}
    if self.selected_index > #self.options then
        self.selected_index = #self.options > 0 and #self.options or 1
    end
    self:invalidate()
end

function combo_box:set_selected(index)
    if index < 1 or index > #self.options then return end
    self.selected_index = index
    self:invalidate()
    if self.on_select then
        local ok, err = pcall(self.on_select, self:get_selected_value(), index, self:get_selected_text())
        if not ok then
            log.warn("ComboBox", "on_select error", err)
        end
    end
end

function combo_box:get_selected_index()
    return self.selected_index or 0
end

function combo_box:get_selected_text()
    if not self.options or #self.options == 0 then
        return self.placeholder
    end
    return self:_normalize_option_text(self.options[self.selected_index])
end

function combo_box:get_selected_value()
    if not self.options or #self.options == 0 then
        return nil
    end
    local item = self.options[self.selected_index]
    if type(item) == "table" then
        return item.value
    end
    return item
end

function combo_box:draw(ctx)
    if not self.visible then return end
    local ax, ay   = self:get_absolute_position()
    local bg_color = self.pressed and COLOR_GRAY or self.colors.bg
    ctx:fill_rect(ax, ay, self.w, self.h, bg_color)
    ctx:stroke_rect(ax, ay, self.w, self.h, self.colors.border)
    local textPadding = 8
    local arrowSpace = 20
    local style = self.text_style
    local maxTextWidth = math.max(0, self.w - textPadding * 2 - arrowSpace)
    local text = self:get_selected_text()
    text = fit_text_to_width(text, maxTextWidth, style, { ellipsis = true })
    local textY = ay + (self.h - ctx:line_height(style)) // 2
    ctx:draw_text(text, ax + textPadding, textY, self.colors.text, style)
    if lcd and lcd.drawLine then
        local arrowX = ax + self.w - arrowSpace // 2 - 4
        local arrowY = ay + self.h // 2
        if self._dropdown.visible then
            lcd.drawLine(arrowX - 5, arrowY + 2, arrowX, arrowY - 2, self.colors.arrow)
            lcd.drawLine(arrowX, arrowY - 2, arrowX + 5, arrowY + 2, self.colors.arrow)
        else
            lcd.drawLine(arrowX - 5, arrowY - 2, arrowX, arrowY + 2, self.colors.arrow)
            lcd.drawLine(arrowX, arrowY + 2, arrowX + 5, arrowY - 2, self.colors.arrow)
        end
    end
end

function combo_box:handle_event(evt, x, y)
    if not self.enabled then return false end
    local inside = self:contains_point(x or 0, y or 0)
    if evt == "TOUCH_DOWN" and inside then
        self.pressed = true
        return true
    elseif (evt == "MOVE_X" or evt == "MOVE_Y") and self.pressed then
        self.pressed = inside
        return true
    elseif evt == "SINGLE_TAP" then
        local was_pressed = self.pressed
        self.pressed = false
        if was_pressed and inside then
            if self._dropdown.visible then
                self._dropdown:hide()
            else
                self._dropdown:show()
            end
            return true
        end
    elseif evt == "LONG_PRESS" or evt == "SWIPE_LEFT" or evt == "SWIPE_RIGHT" or evt == "SWIPE_UP" or evt == "SWIPE_DOWN" then
        self.pressed = false
    end
    return false
end

function combo_box:on_unmount()
    if self._dropdown and self._dropdown.visible then
        self._dropdown:hide()
    end
end

ui.combo_box = function(opts)
    return combo_box:new(opts)
end

-- 5.4 Label
local label = setmetatable({}, { __index = BaseWidget })
label.__index = label

function label:new(opts)
    opts = opts or {}
    local o = BaseWidget.new(self, opts)
    o.text = tostring(opts.text or "")
    o.text_style = { size = opts.size or opts.text_size }
    local dark = (current_theme == "dark")
    o.color = opts.color or (dark and COLOR_WHITE or COLOR_BLACK)
    o.word_wrap = not not opts.word_wrap
    o._autoWidth = not opts.w
    o:_reflow()
    return o
end

function label:_reflow()
    local style = self.text_style
    if self.word_wrap and not self._autoWidth and self.w and self.w > 0 then
        self._lines = wrap_text_lines(self.text, self.w, style)
        local lh = font_line_height(style)
        self.h = math.max(self.h or 0, #self._lines * lh)
    else
        self._lines = nil
        if self._autoWidth then
            self.w = font_measure(self.text, style)
        end
        self.h = font_line_height(style)
    end
end

function label:set_text(text)
    self.text = tostring(text or "")
    self:_reflow()
    self:invalidate()
end

function label:set_size(sz)
    self.text_style.size = tonumber(sz) or self.text_style.size
    self:_reflow()
    self:invalidate()
end

function label:draw(ctx)
    if not self.visible then return end
    local ax, ay = self:get_absolute_position()
    local style = self.text_style
    if self.word_wrap and self._lines then
        local lh = ctx:line_height(style)
        for i = 1, #self._lines do
            ctx:draw_text(self._lines[i], ax, ay + (i - 1) * lh, self.color, style)
        end
    else
        local text = self.text
        if not self._autoWidth and self.w and self.w > 0 then
            text = fit_text_to_width(text, self.w, style, { ellipsis = false })
        end
        ctx:draw_text(text, ax, ay, self.color, style)
    end
end

function label:handle_event()
    return false
end

ui.label = function(opts)
    return label:new(opts)
end

-- 5.5 Input
local input = setmetatable({}, { __index = BaseWidget })
input.__index = input

function input:new(opts)
    opts = opts or {}
    opts.w = opts.w or opts.width or 200
    opts.h = opts.h or opts.height or 36
    local o = BaseWidget.new(self, opts)

    -- 文本属性
    o.text = opts.text or ""
    o.placeholder = opts.placeholder or "请输入文本"
    o.max_length = opts.max_length

    -- 输入类型
    o.input_type = opts.input_type or "text" -- text/number/password/email

    -- 外观属性
    local dark = (current_theme == "dark")
    o.bg_color = opts.bg_color or (dark and COLOR_WIN11_DARK_BUTTON_BG or COLOR_WIN11_LIGHT_BUTTON_BG)
    o.text_color = opts.text_color or (dark and COLOR_WHITE or COLOR_BLACK)
    o.placeholder_color = opts.placeholder_color or COLOR_GRAY
    o.border_color = opts.border_color or (dark and COLOR_WIN11_DARK_BUTTON_BORDER or COLOR_WIN11_LIGHT_BUTTON_BORDER)
    o.focused_border_color = opts.focused_border_color or COLOR_SKY_BLUE
    o.text_style = { size = opts.text_size or opts.size or 12 }

    -- 状态属性
    o.focused = false
    o.keyboard = nil -- 关联的键盘实例

    -- 回调函数
    o.on_text_changed = opts.on_text_changed
    o.on_focus_changed = opts.on_focus_changed
    o.on_confirm = opts.on_confirm

    -- 内部状态
    o._textOffset = 0  -- 文本滚动偏移（用于长文本显示）
    o._pressed = false -- TOUCH_DOWN 时的视觉反馈

    -- 键盘配置
    o.keyboard_click_effect = opts.keyboard_click_effect ~= false

    return o
end

-- 文本操作方法
function input:set_text(text)
    local newText = tostring(text or "")
    if self.max_length and #newText > self.max_length then
        newText = string.sub(newText, 1, self.max_length)
    end

    if self.text ~= newText then
        self.text = newText
        self:invalidate()
        if self.on_text_changed then
            pcall(self.on_text_changed, self.text, self)
        end
    end
end

function input:get_text()
    return self.text
end

-- 别名方法（兼容驼峰命名）
function input:getText()
    return self:get_text()
end

function input:setText(text)
    return self:set_text(text)
end

function input:set_placeholder(text)
    self.placeholder = tostring(text or "")
    self:invalidate()
end

function input:insert_text(text)
    if not text or text == "" then return end
    local newText = self.text .. text
    self:set_text(newText)
end

function input:delete_text(start_pos, length)
    if not self.text or self.text == "" then return end

    length = length or 1
    start_pos = math.max(1, math.min(start_pos, #self.text + 1))
    local end_pos = math.min(start_pos + length - 1, #self.text)

    if start_pos > end_pos then return end

    local beforeText = string.sub(self.text, 1, start_pos - 1)
    local afterText = string.sub(self.text, end_pos + 1)
    self:set_text(beforeText .. afterText)
end

-- 焦点管理
function input:focus()
    if self.focused then return end

    -- 隐藏其他 Input 的键盘（确保同时只有一个 Input 有焦点）
    for i = 1, #runtime.roots do
        local root = runtime.roots[i]
        if root and root._isKeyboard and root ~= self.keyboard then
            root:hide()
        end
    end

    self.focused = true

    -- 创建键盘实例（每个 Input 拥有自己的 keyboard 实例）
    if not self.keyboard then
        -- 通过 ui.keyboard 访问（keyboard 组件在后面定义）
        if ui.keyboard then
            self.keyboard = ui.keyboard({
                input = self,
                enable_click_effect = self.keyboard_click_effect
            })
            self.keyboard._isKeyboard = true -- 标记为键盘组件
        end
    end

    -- 显示键盘
    if self.keyboard then
        self.keyboard:show() -- 键盘位置在 show() 内部计算（屏幕中下对齐底边）
        self.keyboard:set_input_type(self.input_type)
    end

    -- 触发焦点变化回调
    if self.on_focus_changed then
        pcall(self.on_focus_changed, true, self)
    end
end

function input:blur()
    if not self.focused then return end

    self.focused = false

    -- 隐藏键盘
    if self.keyboard and self.keyboard:is_visible() then
        self.keyboard:hide()
    end

    -- 触发焦点变化回调
    if self.on_focus_changed then
        pcall(self.on_focus_changed, false, self)
    end

    self:invalidate()
end

function input:is_focused()
    return self.focused
end

-- 绘制方法
function input:draw(ctx)
    if not self.visible then return end

    local ax, ay = self:get_absolute_position()

    -- 绘制背景
    ctx:fill_rect(ax, ay, self.w, self.h, self.bg_color)

    -- 绘制边框
    local border_color = (self.focused or self._pressed) and self.focused_border_color or self.border_color
    ctx:stroke_rect(ax, ay, self.w, self.h, border_color)

    -- 文本绘制区域
    local textPadding = 8
    local textX = ax + textPadding
    local textY = ay + (self.h - ctx:line_height(self.text_style)) // 2
    local maxTextWidth = self.w - textPadding * 2

    -- 确定要显示的文本
    local displayText = self.text
    local text_color = self.text_color

    if not displayText or displayText == "" then
        displayText = self.placeholder
        text_color = self.placeholder_color
    elseif self.input_type == "password" then
        displayText = string.rep("*", #self.text)
    end

    -- 处理长文本滚动显示
    local textWidth = ctx:text_width(displayText, self.text_style)
    if textWidth > maxTextWidth then
        -- 使用 fit_text_to_width 工具函数截断文本
        displayText = fit_text_to_width(displayText, maxTextWidth, self.text_style, { ellipsis = false })
    end

    -- 绘制文本
    if displayText and displayText ~= "" then
        ctx:draw_text(displayText, textX, textY, text_color, self.text_style)
    end
end

-- 事件处理
function input:handle_event(evt, x, y)
    if not self.enabled then return false end

    local inside = self:contains_point(x or 0, y or 0)

    if evt == "TOUCH_DOWN" then
        if inside then
            self._pressed = true
            self:invalidate()
            return true
        end
    elseif evt == "SINGLE_TAP" then
        if inside then
            self._pressed = false
            self:focus()
            self:invalidate()
            return true
        end
        return false
    end

    return false
end

ui.input = function(opts)
    return input:new(opts)
end

-- 5.6 Keyboard
local keyboard = setmetatable({}, { __index = BaseWidget })
keyboard.__index = keyboard

function keyboard:new(opts)
    opts = opts or {}
    local o = BaseWidget.new(self, {
        x = 0,
        y = 0,
        w = opts.width or 300,
        h = opts.height or 450,
        visible = false
    })

    -- 关联的 Input 组件
    o.input = opts.input

    -- 是否启用点击变色效果
    o.enable_click_effect = opts.enable_click_effect ~= false

    -- 键盘布局参数
    o.keySize = 90
    o.keyGap = 0

    -- 输入模式
    o.isNumberMode = false
    o.isPinyin9KeyMode = false

    -- 字母键盘按键映射
    o.letterMappings = {
        { text = "ABC", chars = { "a", "b", "c", "A", "B", "C" }, type = "letters", keyId = 1 },
        { text = "DEF", chars = { "d", "e", "f", "D", "E", "F" }, type = "letters", keyId = 2 },
        { text = "GHI", chars = { "g", "h", "i", "G", "H", "I" }, type = "letters", keyId = 3 },
        { text = "JKL", chars = { "j", "k", "l", "J", "K", "L" }, type = "letters", keyId = 4 },
        { text = "MNO", chars = { "m", "n", "o", "M", "N", "O" }, type = "letters", keyId = 5 },
        { text = "PQRS", chars = { "p", "q", "r", "s", "P", "Q", "R", "S" }, type = "letters", keyId = 6 },
        { text = "TUV", chars = { "t", "u", "v", "T", "U", "V" }, type = "letters", keyId = 7 },
        { text = "WXYZ", chars = { "w", "x", "y", "z", "W", "X", "Y", "Z" }, type = "letters", keyId = 8 },
        { text = "空格", chars = { " " }, type = "space" },
        { text = "delete", chars = {}, type = "delete" },
        { text = "NUM", chars = {}, type = "num" },
        { text = "中/EN", chars = {}, type = "lang" }
    }

    -- 数字键盘按键映射
    o.numberMappings = {
        { text = "1",      chars = { "1" }, type = "number" },
        { text = "2",      chars = { "2" }, type = "number" },
        { text = "3",      chars = { "3" }, type = "number" },
        { text = "4",      chars = { "4" }, type = "number" },
        { text = "5",      chars = { "5" }, type = "number" },
        { text = "6",      chars = { "6" }, type = "number" },
        { text = "7",      chars = { "7" }, type = "number" },
        { text = "8",      chars = { "8" }, type = "number" },
        { text = "9",      chars = { "9" }, type = "number" },
        { text = "delete", chars = {},      type = "delete" },
        { text = "0",      chars = { "0" }, type = "number" },
        { text = "EN",     chars = {},      type = "letter" }
    }

    -- 根据模式设置按键映射
    o.keyMappings = o.letterMappings

    -- 按键布局
    o.keyLayout = {}
    o:build_key_layout()

    -- 候选字符相关状态
    o.selectedKey = nil
    o.currentCandidates = {}
    o._pressedCandidateIndex = nil

    -- 9键拼音输入模式相关属性
    o.keySequence = {}           -- 当前按键序列（存储按键ID：1-8）
    o.syllableCandidates = {}    -- 音节候选列表
    o.selectedSyllableIndex = 1  -- 当前选中的音节索引
    o.currentSyllable = ""       -- 当前选中的音节（已确认）
    o.pinyinCandidates = {}      -- 候选字列表（UTF-8字符串数组）
    o.selectedCandidateIndex = 1 -- 当前选中的候选字索引
    o.syllablePageIndex = 1      -- 音节列表当前页索引
    o.candidatePageIndex = 1     -- 候选字列表当前页索引（每页8个候选字）
    o.pinyinModule = nil         -- pinyin模块缓存

    -- 候选区显示状态
    o.displayStartIndex = 1       -- 预览框显示的起始字符位置
    o._pressedSyllableIndex = nil -- 当前按下的音节索引
    o._backButtonPressed = false  -- 返回按钮按下状态

    return o
end

function keyboard:build_key_layout()
    local start_x = self.x + 30 -- 左侧预留30px（用于未来音节选择区）
    local start_y = self.y + 95 -- 顶部控制栏50px + 候选区50px
    local keySize = self.keySize
    local keyGap = self.keyGap

    -- 构建3×4按键布局
    self.keyLayout = {}
    local keyIndex = 1

    for row = 0, 3 do
        for col = 0, 2 do
            if keyIndex <= #self.keyMappings then
                local key = {
                    x = start_x + col * (keySize + keyGap),
                    y = start_y + row * (keySize + keyGap),
                    w = keySize,
                    h = keySize,
                    text = self.keyMappings[keyIndex].text,
                    chars = self.keyMappings[keyIndex].chars,
                    type = self.keyMappings[keyIndex].type,
                    keyId = self.keyMappings[keyIndex].keyId, -- 用于拼音输入
                    pressed = false
                }
                table.insert(self.keyLayout, key)
                keyIndex = keyIndex + 1
            end
        end
    end
end

function keyboard:show()
    -- 计算键盘位置（屏幕中下对齐底边）
    local sw = render_state.viewport_w
    local sh = render_state.viewport_h
    self.x = (sw - self.w) // 2 -- 水平居中
    self.y = sh - self.h        -- 底部对齐

    -- 重新构建按键布局
    self:build_key_layout()

    self.visible = true
    self.enabled = true

    -- 重置状态
    self.selectedKey = nil
    self.currentCandidates = {}
    self.displayStartIndex = 1

    -- 重置拼音输入状态
    self.keySequence = {}
    self.syllableCandidates = {}
    self.selectedSyllableIndex = 1
    self.currentSyllable = ""
    self.pinyinCandidates = {}
    self.selectedCandidateIndex = 1
    self.syllablePageIndex = 1
    self.candidatePageIndex = 1
    self._pressedSyllableIndex = nil
    self._pressedCandidateIndex = nil

    -- 添加到运行时根组件列表（顶层显示）
    runtime.add(self)
end

function keyboard:hide()
    self.visible = false
    self.enabled = false

    -- 从运行时根组件列表移除
    runtime.remove(self)

    -- 通知 Input 组件失去焦点
    if self.input and self.input.focused then
        self.input:blur()
    end
end

function keyboard:is_visible()
    return self.visible
end

function keyboard:set_input_type(inputType)
    -- 根据输入类型切换键盘模式
    if inputType == "number" then
        self:switch_to_number_mode()
    else
        self:switch_to_letter_mode()
    end
end

function keyboard:switch_to_number_mode()
    if not self.isNumberMode then
        self.isNumberMode = true
        self.isPinyin9KeyMode = false -- 切换到数字模式时关闭拼音模式
        self.keyMappings = self.numberMappings
        self:build_key_layout()
        -- 清除候选字符状态
        self.selectedKey = nil
        self.currentCandidates = {}
        self._pressedCandidateIndex = nil
        -- 清除拼音输入状态
        self.keySequence = {}
        self.syllableCandidates = {}
        self.currentSyllable = ""
        self.pinyinCandidates = {}
        self:invalidate()
    end
end

function keyboard:switch_to_letter_mode()
    if self.isNumberMode then
        self.isNumberMode = false
        -- 切换到字母模式时不清除拼音模式（保持当前状态）
        self.keyMappings = self.letterMappings
        self:build_key_layout()
        -- 清除候选字符状态
        self.selectedKey = nil
        self.currentCandidates = {}
        self._pressedCandidateIndex = nil
        self:invalidate()
    end
end

-- 切换到9键拼音模式
function keyboard:switch_to_pinyin_9key_mode()
    self.isPinyin9KeyMode = true
    self.keySequence = {}
    self.syllableCandidates = {}
    self.selectedSyllableIndex = 1
    self.currentSyllable = ""
    self.pinyinCandidates = {}
    self.selectedCandidateIndex = 1
    self.syllablePageIndex = 1
    self.candidatePageIndex = 1
    self._pressedSyllableIndex = nil

    -- 加载pinyin模块（模组自带的核心库，不需要require）
    if not self.pinyinModule then
        self.pinyinModule = pinyin
        if not self.pinyinModule then
            log.warn("Keyboard", "pinyin模块不可用")
            self.isPinyin9KeyMode = false
            return false
        end
    end

    self:invalidate()
    return true
end

-- 处理9键输入
function keyboard:on_pinyin_9key_input(keyId)
    -- keyId: 1-8 对应 ABC-WXYZ
    if not self.isPinyin9KeyMode then
        return
    end

    -- 限制按键序列最大长度为5（中文最多5个音节拼音）
    if #self.keySequence >= 5 then
        log.warn("Keyboard", "按键序列已达最大长度5")
        return
    end

    -- 如果已经有选中的音节，先清除候选字状态
    if self.currentSyllable ~= "" then
        self.currentSyllable = ""
        self.pinyinCandidates = {}
        self.selectedCandidateIndex = 1
        self.candidatePageIndex = 1
    end

    -- 追加到按键序列
    table.insert(self.keySequence, keyId)

    -- 查询可能的音节（输入第一个按键后即开始显示）
    if self.pinyinModule and self.pinyinModule.querySyllables then
        local syllables = self.pinyinModule.querySyllables(self.keySequence)
        self.syllableCandidates = syllables or {}
        self.selectedSyllableIndex = 1
        self.syllablePageIndex = 1
        log.info("Keyboard", "按键序列:", table.concat(self.keySequence, ","),
            "音节数:", #self.syllableCandidates)
    else
        self.syllableCandidates = {}
    end

    self:invalidate()
end

-- 选择音节
function keyboard:select_syllable(syllable)
    if not self.isPinyin9KeyMode or not syllable then
        return false
    end

    -- 确认选中的音节
    self.currentSyllable = syllable

    -- 查询该音节对应的候选字（使用queryUtf8直接返回UTF-8字符串数组）
    if self.pinyinModule and self.pinyinModule.queryUtf8 then
        local chars = self.pinyinModule.queryUtf8(syllable)
        self.pinyinCandidates = chars or {}
        self.selectedCandidateIndex = 1
        self.candidatePageIndex = 1
        log.info("Keyboard", "选中音节:", syllable, "候选字数:", #self.pinyinCandidates)
    else
        self.pinyinCandidates = {}
    end

    -- 清空按键序列（准备输入下一个字）
    self.keySequence = {}
    self.syllableCandidates = {}
    self.selectedSyllableIndex = 1
    self.syllablePageIndex = 1

    self:invalidate()
    return true
end

-- 选择候选字
function keyboard:select_candidate(index)
    if not self.isPinyin9KeyMode then
        return false
    end

    -- index 是相对索引（1-8），需要计算实际索引（考虑分页）
    local actualIndex = (self.candidatePageIndex - 1) * 8 + index

    if actualIndex >= 1 and actualIndex <= #self.pinyinCandidates then
        local char = self.pinyinCandidates[actualIndex] -- 直接使用UTF-8字符串

        -- 插入到输入框
        if self.input then
            self.input:insert_text(char)
        end

        -- 重置状态，准备输入下一个字
        self.currentSyllable = ""
        self.pinyinCandidates = {}
        self.selectedCandidateIndex = 1
        self.candidatePageIndex = 1

        self:invalidate()
        return true
    end

    return false
end

-- 删除键处理（9键模式）
function keyboard:on_pinyin_9key_delete()
    if not self.isPinyin9KeyMode then
        return
    end

    -- 如果正在选择音节（有按键序列未确认）
    if #self.keySequence > 0 then
        -- 删除最后一个按键，并根据剩余按键序列重新查询音节
        table.remove(self.keySequence, #self.keySequence)
        if #self.keySequence > 0 then
            if self.pinyinModule and self.pinyinModule.querySyllables then
                local syllables = self.pinyinModule.querySyllables(self.keySequence)
                self.syllableCandidates = syllables or {}
                self.selectedSyllableIndex = 1
                self.syllablePageIndex = 1
            else
                self.syllableCandidates = {}
                self.selectedSyllableIndex = 1
                self.syllablePageIndex = 1
            end
        else
            -- 没有按键了，清空音节候选
            self.syllableCandidates = {}
            self.selectedSyllableIndex = 1
            self.syllablePageIndex = 1
        end
        log.info("Keyboard", "删除一位按键，当前序列:", table.concat(self.keySequence, ","))
        self:invalidate()
        return
    end

    -- 如果已选中音节并在选择候选汉字阶段，删除应清空音节并回到按键输入
    if self.currentSyllable ~= "" then
        self.currentSyllable = ""
        self.pinyinCandidates = {}
        self.selectedCandidateIndex = 1
        self.candidatePageIndex = 1
        log.info("Keyboard", "清空已选音节，返回按键输入阶段")
        self:invalidate()
        return
    else
        -- 没有选择音节，删除输入框中的最后一个字符
        if self.input then
            local currentText = self.input:get_text()
            if currentText and #currentText > 0 then
                -- 按 UTF-8 字符删除最后一个字符，避免残留半个字节导致 "�"
                local lastStart = 1
                local i = 1
                while i <= #currentText do
                    local _, charLen = get_utf8_char(currentText, i)
                    lastStart = i
                    i = i + math.max(charLen, 1)
                end
                local deleteLen = #currentText - lastStart + 1
                self.input:delete_text(lastStart, deleteLen)
            end
        end
    end
end

-- 绘制方法
function keyboard:draw(ctx)
    if not self.visible then return end

    local ax, ay       = self:get_absolute_position()
    local dark         = (current_theme == "dark")
    local bg_color     = dark and COLOR_WIN11_DARK_BUTTON_BG or COLOR_WIN11_LIGHT_BUTTON_BG
    local border_color = dark and COLOR_WIN11_DARK_BUTTON_BORDER or COLOR_WIN11_LIGHT_BUTTON_BORDER

    -- 绘制键盘背景
    ctx:fill_rect(ax, ay, self.w, self.h, bg_color)
    ctx:stroke_rect(ax, ay, self.w, self.h, border_color)

    -- 绘制顶部控制栏（返回按钮和预览区）
    self:draw_top_bar(ctx, ax, ay)

    -- 绘制候选区（音节或候选字）
    if self.isPinyin9KeyMode then
        -- 显示候选字选择区（始终显示）
        self:draw_pinyin_candidates(ctx, ax, ay)
    else
        -- 显示预览区（英文模式）
        self:draw_preview_area(ctx, ax, ay)
        -- 绘制候选字符区（英文模式）
        self:draw_candidate_area(ctx, ax, ay)
    end

    -- 绘制左侧音节选择区（9键拼音模式）
    if self.isPinyin9KeyMode then
        self:draw_left_syllable_panel(ctx, ax, ay)
    end

    -- 绘制按键
    for i = 1, #self.keyLayout do
        self:draw_key(ctx, self.keyLayout[i])
    end
end

function keyboard:draw_top_bar(ctx, ax, ay)
    local dark            = (current_theme == "dark")
    local bg_color        = dark and COLOR_WIN11_DARK_BUTTON_BG or COLOR_WIN11_LIGHT_BUTTON_BG
    local border_color    = dark and COLOR_WIN11_DARK_BUTTON_BORDER or COLOR_WIN11_LIGHT_BUTTON_BORDER
    local text_color      = dark and COLOR_WHITE or COLOR_BLACK
    local button_bg_color = bg_color

    -- 返回按钮
    local backBtnX        = ax + 10
    local backBtnY        = ay + 5
    local backBtnW        = 60
    local backBtnH        = 35
    -- 检查返回按钮是否被按下
    local backBtnbg_color = (self.enable_click_effect and self._backButtonPressed) and COLOR_GRAY or button_bg_color
    ctx:fill_rect(backBtnX, backBtnY, backBtnW, backBtnH, backBtnbg_color)
    ctx:stroke_rect(backBtnX, backBtnY, backBtnW, backBtnH, border_color)
    local back_text = "返回"
    local back_style = { size = 12 }
    ctx:draw_text_in_rect_centered(backBtnX, backBtnY, backBtnW, backBtnH, back_text, {
        color = text_color,
        style = back_style
    })

    -- 输入预览区
    if self.input then
        local previewX = backBtnX + backBtnW + 10 -- 预览框起始位置
        local previewW = self.w - 90              -- 预览框宽度：300px - 90px = 210px
        local previewText = self.input:get_text()

        -- 处理预览文本显示（上方仅预览已输入的汉字/文本，不再显示音节）
        local displayText = previewText
        if displayText == "" then
            displayText = "输入预览"
        else
            local style = { size = 12 }
            local textWidth = ctx:text_width(displayText, style)
            local maxTextWidth = previewW - 20 -- 左右各留10像素
            if textWidth > maxTextWidth then
                displayText = fit_text_to_width(displayText, maxTextWidth, style, { ellipsis = false })
            end
        end

        -- 输入预览区：有边框，高35px
        local previewAreaY = backBtnY
        local previewAreaH = backBtnH
        ctx:fill_rect(previewX, previewAreaY, previewW, previewAreaH, button_bg_color)
        ctx:stroke_rect(previewX, previewAreaY, previewW, previewAreaH, border_color)
        -- 左对齐绘制，左边距10px
        local previewtext_color = (previewText == "") and COLOR_GRAY or text_color
        ctx:draw_text(displayText, previewX + 10, previewAreaY + (previewAreaH - ctx:line_height({ size = 12 })) // 2,
            previewtext_color, { size = 12 })

        -- 新增：音节预览区（位于预览区下方5px，高20px，无边框）
        if self.isPinyin9KeyMode then
            local syllablePreviewY = previewAreaY + previewAreaH
            local syllableText = ""
            if #self.keySequence > 0 then
                -- 显示按键序列（如：abc+mno）
                local keyToLetters = {
                    [1] = "abc",
                    [2] = "def",
                    [3] = "ghi",
                    [4] = "jkl",
                    [5] = "mno",
                    [6] = "pqrs",
                    [7] = "tuv",
                    [8] = "wxyz"
                }
                local keyPreview = {}
                for _, keyId in ipairs(self.keySequence) do
                    table.insert(keyPreview, keyToLetters[keyId] or "")
                end
                syllableText = table.concat(keyPreview, "+")
            elseif self.currentSyllable ~= "" then
                -- 显示已选中的音节
                syllableText = self.currentSyllable
            end
            if syllableText ~= "" then
                ctx:draw_text(syllableText, previewX + 10,
                    syllablePreviewY + (20 - ctx:line_height({ size = 12 })) // 2,
                    text_color, { size = 12 })
            end
        end
    end
end

function keyboard:draw_preview_area(ctx, ax, ay)
    if not self.input then return end

    local previewY      = ay + 5      -- 和返回按键平行
    local previewHeight = 35          -- 和返回按键高度一致
    local previewX      = ax + 80     -- 预览框起始位置（返回键后）
    local previewW      = self.w - 90 -- 预览框宽度

    local dark          = (current_theme == "dark")
    local bg_color      = dark and COLOR_WIN11_DARK_BUTTON_BG or COLOR_WIN11_LIGHT_BUTTON_BG
    local border_color  = dark and COLOR_WIN11_DARK_BUTTON_BORDER or COLOR_WIN11_LIGHT_BUTTON_BORDER
    local text_color    = dark and COLOR_WHITE or COLOR_BLACK

    -- 绘制预览区背景
    ctx:fill_rect(previewX, previewY, previewW, previewHeight, bg_color)
    ctx:stroke_rect(previewX, previewY, previewW, previewHeight, border_color)

    -- 绘制预览文本
    local previewText = self.input:get_text() or ""
    if previewText == "" then
        previewText = "输入预览"
        text_color = COLOR_GRAY
    end

    -- 处理长文本
    local previewStyle = { size = 12 }
    local textWidth = ctx:text_width(previewText, previewStyle)
    local maxTextWidth = previewW - 20 -- 左右各留10像素
    if textWidth > maxTextWidth then
        previewText = fit_text_to_width(previewText, maxTextWidth, previewStyle, { ellipsis = false })
    end

    local textHeight = ctx:line_height(previewStyle)
    local textX = previewX + 10
    local textY = previewY + (previewHeight - textHeight) // 2
    ctx:draw_text(previewText, textX, textY, text_color, previewStyle)
end

function keyboard:draw_key(ctx, key)
    local dark             = (current_theme == "dark")
    local bg_color         = dark and COLOR_WIN11_DARK_BUTTON_BG or COLOR_WIN11_LIGHT_BUTTON_BG
    local border_color     = dark and COLOR_WIN11_DARK_BUTTON_BORDER or COLOR_WIN11_LIGHT_BUTTON_BORDER
    local text_color       = dark and COLOR_WHITE or COLOR_BLACK
    local presse_dbg_color = COLOR_GRAY

    local btnbg_color      = (self.enable_click_effect and key.pressed) and presse_dbg_color or bg_color

    ctx:fill_rect(key.x, key.y, key.w, key.h, btnbg_color)
    ctx:stroke_rect(key.x, key.y, key.w, key.h, border_color)

    -- -- 绘制按键文本
    local displayText = key.text

    local textStyle = { size = 12 }
    local textWidth = ctx:text_width(displayText, textStyle)
    local textHeight = ctx:line_height(textStyle)
    local textX = key.x + (key.w - textWidth) // 2
    local textY = key.y + (key.h - textHeight) // 2
    ctx:draw_text(displayText, textX, textY, text_color, textStyle)
end

-- 事件处理
function keyboard:handle_event(evt, x, y)
    if not self.visible or not self.enabled then
        return false
    end

    local inside = self:contains_point(x or 0, y or 0)

    -- 检查是否点击了返回按钮
    local backBtnX = self.x + 10
    local backBtnY = self.y + 5
    local backBtnW = 60
    local backBtnH = 40
    if x >= backBtnX and x < backBtnX + backBtnW and
        y >= backBtnY and y < backBtnY + backBtnH then
        if evt == "TOUCH_DOWN" then
            self._backButtonPressed = true
            self:invalidate()
            return true
        elseif evt == "SINGLE_TAP" then
            self._backButtonPressed = false
            self:hide()
            return true
        elseif evt == "MOVE_X" or evt == "MOVE_Y" then
            self._backButtonPressed = false
            self:invalidate()
            return true
        end
    end

    -- 处理候选字左右翻页按键（9键拼音模式）
    if self.isPinyin9KeyMode and #self.pinyinCandidates > 0 then
        if self:handle_candidate_arrow_touch(evt, x, y) then
            return true
        end
    end

    -- 处理候选字选择区触摸（9键拼音模式）
    if self.isPinyin9KeyMode and #self.pinyinCandidates > 0 then
        if self:handle_candidate_panel_touch(evt, x, y) then
            return true
        end
    end

    -- 处理音节选择区触摸（9键拼音模式）
    if self.isPinyin9KeyMode and #self.syllableCandidates > 0 and self.currentSyllable == "" then
        if self:handle_syllable_panel_touch(evt, x, y) then
            return true
        end
    end

    -- 处理候选字符选择（英文模式）
    if not self.isPinyin9KeyMode and #self.currentCandidates > 0 then
        local candidateY = self.y + 50
        local candidateHeight = 50
        local candidateBtnSize = 30

        for i = 1, 10 do
            local btnX = self.x + (i - 1) * candidateBtnSize
            local btnY = candidateY + (candidateHeight - candidateBtnSize) // 2

            if i <= #self.currentCandidates and
                x >= btnX and x < btnX + candidateBtnSize and
                y >= btnY and y < btnY + candidateBtnSize then
                if evt == "TOUCH_DOWN" then
                    self._pressedCandidateIndex = i
                    self:invalidate()
                    return true
                elseif evt == "SINGLE_TAP" then
                    local char = self.currentCandidates[i]
                    self:on_candidate_selected(char)
                    return true
                elseif evt == "MOVE_X" or evt == "MOVE_Y" then
                    if self._pressedCandidateIndex ~= i then
                        self._pressedCandidateIndex = nil
                        self:invalidate()
                    end
                    return true
                end
            end
        end
    end

    -- 处理按键点击
    if evt == "TOUCH_DOWN" and inside then
        -- 检查是否点击了按键
        for i = 1, #self.keyLayout do
            local key = self.keyLayout[i]
            if x >= key.x and x < key.x + key.w and
                y >= key.y and y < key.y + key.h then
                key.pressed = true
                self._capture = true
                self:invalidate()
                return true
            end
        end
        return true
    elseif evt == "SINGLE_TAP" and self._capture then
        -- 处理按键释放
        for i = 1, #self.keyLayout do
            local key = self.keyLayout[i]
            if key.pressed then
                key.pressed = false
                self:on_key_pressed(key)
                self:invalidate()
                break
            end
        end

        self._capture = false
        return true
    elseif (evt == "MOVE_X" or evt == "MOVE_Y") and self._capture then
        -- 更新按键按下状态
        for i = 1, #self.keyLayout do
            local key = self.keyLayout[i]
            local wasPressed = key.pressed
            key.pressed = (x >= key.x and x < key.x + key.w and
                y >= key.y and y < key.y + key.h)
            if wasPressed ~= key.pressed then
                self:invalidate()
            end
        end
        return true
    end

    return false
end

-- 处理按键按下
function keyboard:on_key_pressed(key)
    if not key then return end

    -- 删除键处理
    if key.type == "delete" then
        -- 9键拼音模式下的删除键处理
        if self.isPinyin9KeyMode then
            self:on_pinyin_9key_delete()
            return
        end

        -- 清除候选字符状态
        self.selectedKey = nil
        self.currentCandidates = {}
        self._pressedCandidateIndex = nil

        if self.input then
            local currentText = self.input:get_text()
            if currentText and #currentText > 0 then
                -- 按 UTF-8 字符删除最后一个字符
                local lastStart = 1
                local i = 1
                while i <= #currentText do
                    local _, charLen = get_utf8_char(currentText, i)
                    lastStart = i
                    i = i + math.max(charLen, 1)
                end
                local deleteLen = #currentText - lastStart + 1
                self.input:delete_text(lastStart, deleteLen)
            end
        end
        self:invalidate()
        return
    end

    -- 数字/字母模式切换
    if key.type == "num" then
        self:switch_to_number_mode()
        return
    elseif key.type == "letter" then
        self:switch_to_letter_mode()
        return
    end

    -- 9键拼音模式下的字母键处理
    if self.isPinyin9KeyMode and key.type == "letters" and key.keyId then
        self:on_pinyin_9key_input(key.keyId)
        return
    end


    -- 9键拼音模式下的空格键处理
    if self.isPinyin9KeyMode and key.type == "space" then
        if self.input then
            self.input:insert_text(" ")
        end
        return
    end

    -- 语言切换键（中/EN）
    if key.type == "lang" then
        if self.isPinyin9KeyMode then
            -- 关闭拼音模式，切换到英文模式
            self.isPinyin9KeyMode = false
            -- 清除拼音输入状态
            self.keySequence = {}
            self.syllableCandidates = {}
            self.currentSyllable = ""
            self.pinyinCandidates = {}
            self.selectedCandidateIndex = 1
            self.syllablePageIndex = 1
            self.candidatePageIndex = 1
            self._pressedSyllableIndex = nil
            -- 如果当前是数字模式，需要先切换到字母模式
            if self.isNumberMode then
                self:switch_to_letter_mode()
            end
        else
            -- 切换到拼音模式
            -- 如果当前是数字模式，需要先切换到字母模式
            if self.isNumberMode then
                self:switch_to_letter_mode()
            end
            -- 尝试切换到拼音模式
            local success = self:switch_to_pinyin_9key_mode()
            if not success then
                log.warn("Keyboard", "切换到拼音模式失败，pinyin模块不可用")
            end
        end
        self:invalidate()
        return
    end

    -- 数字/字母模式切换
    if key.type == "num" then
        self:switch_to_number_mode()
        return
    elseif key.type == "letter" then
        self:switch_to_letter_mode()
        return
    end

    -- 普通按键处理（字母/数字）
    if key.chars and #key.chars > 0 then
        -- 清除之前的候选字符状态
        self.selectedKey = nil
        self.currentCandidates = {}
        self._pressedCandidateIndex = nil

        -- 处理数字直接输入
        if key.type == "number" then
            local char = key.chars[1]
            if self.input then
                self.input:insert_text(char)
            end
            -- 处理空格键
        elseif key.type == "space" then
            if self.input then
                self.input:insert_text(" ")
            end
        else
            -- 字母键：显示候选字符，让用户选择
            self.selectedKey = key
            self.currentCandidates = key.chars
            self:invalidate()
        end
    end
end

-- 处理候选字符选择
function keyboard:on_candidate_selected(char)
    if char and char ~= "" then
        if self.input then
            self.input:insert_text(char)
        end
    end
    -- 清除候选状态和按键状态
    self.selectedKey = nil
    self.currentCandidates = {}
    self._pressedCandidateIndex = nil

    -- 清除所有按键状态
    for i = 1, #self.keyLayout do
        self.keyLayout[i].pressed = false
    end

    self:invalidate()
end

-- 绘制候选字符区
function keyboard:draw_candidate_area(ctx, ax, ay)
    local candidateY       = ay + 50 -- 候选区Y坐标（预览区下方10px）
    local candidateHeight  = 50
    local candidateBtnSize = 30

    local dark             = (current_theme == "dark")
    local bg_color         = dark and COLOR_WIN11_DARK_BUTTON_BG or COLOR_WIN11_LIGHT_BUTTON_BG
    local border_color     = dark and COLOR_WIN11_DARK_BUTTON_BORDER or COLOR_WIN11_LIGHT_BUTTON_BORDER
    local text_color       = dark and COLOR_WHITE or COLOR_BLACK
    local presse_dbg_color = COLOR_GRAY

    -- 候选按键固定10个，从左到右排列
    for i = 1, 10 do
        local btnX = ax + (i - 1) * candidateBtnSize
        local btnY = candidateY + (candidateHeight - candidateBtnSize) // 2

        -- 根据是否有候选字符决定显示内容
        if i <= #self.currentCandidates then
            local char        = self.currentCandidates[i]
            -- 检查候选按键是否被按下
            local isPressed   = (self._pressedCandidateIndex == i)
            local btnbg_color = (self.enable_click_effect and isPressed) and presse_dbg_color or bg_color

            ctx:fill_rect(btnX, btnY, candidateBtnSize, candidateBtnSize, btnbg_color)
            ctx:stroke_rect(btnX, btnY, candidateBtnSize, candidateBtnSize, border_color)

            -- 绘制候选字符文本
            local textStyle = { size = 12 }
            local textWidth = ctx:text_width(char, textStyle)
            local textHeight = ctx:line_height(textStyle)
            local textX = btnX + (candidateBtnSize - textWidth) // 2
            local textY = btnY + (candidateBtnSize - textHeight) // 2
            ctx:draw_text(char, textX, textY, text_color, textStyle)
        else
            -- 没有候选字符时显示空按钮
            ctx:fill_rect(btnX, btnY, candidateBtnSize, candidateBtnSize, bg_color)
            ctx:stroke_rect(btnX, btnY, candidateBtnSize, candidateBtnSize, border_color)
        end
    end
end

-- 处理候选字左右翻页按键
function keyboard:handle_candidate_arrow_touch(evt, x, y)
    local candidateY = self.y + 50
    local candidateHeight = 50
    local candidateBtnSize = 30
    local arrowW = candidateBtnSize

    -- 左侧翻页按键（←）
    local leftArrowX = self.x
    local leftArrowY = candidateY + (candidateHeight - candidateBtnSize) // 2
    if x >= leftArrowX and x < leftArrowX + arrowW and
        y >= leftArrowY and y < leftArrowY + candidateBtnSize then
        if evt == "SINGLE_TAP" then
            if self.candidatePageIndex > 1 then
                self.candidatePageIndex = self.candidatePageIndex - 1
                self.selectedCandidateIndex = (self.candidatePageIndex - 1) * 8 + 1
                self:invalidate()
            end
            return true
        end
    end

    -- 右侧翻页按键（→）
    local rightArrowX = self.x + self.w - arrowW
    local rightArrowY = leftArrowY
    if x >= rightArrowX and x < rightArrowX + arrowW and
        y >= rightArrowY and y < rightArrowY + candidateBtnSize then
        if evt == "SINGLE_TAP" then
            local maxPage = math.ceil(#self.pinyinCandidates / 8)
            if self.candidatePageIndex < maxPage then
                self.candidatePageIndex = self.candidatePageIndex + 1
                self.selectedCandidateIndex = (self.candidatePageIndex - 1) * 8 + 1
                self:invalidate()
            end
            return true
        end
    end

    return false
end

-- 处理候选字选择区触摸
function keyboard:handle_candidate_panel_touch(evt, x, y)
    local candidateY = self.y + 50
    local candidateHeight = 50
    local candidateBtnSize = 30
    local arrowW = candidateBtnSize
    local candidatestart_x = self.x + arrowW

    for i = 1, 8 do
        local idx = (self.candidatePageIndex - 1) * 8 + i
        local btnX = candidatestart_x + (i - 1) * candidateBtnSize
        local btnY = candidateY + (candidateHeight - candidateBtnSize) // 2

        if idx <= #self.pinyinCandidates and
            x >= btnX and x < btnX + candidateBtnSize and
            y >= btnY and y < btnY + candidateBtnSize then
            if evt == "TOUCH_DOWN" then
                self._pressedCandidateIndex = idx
                self:invalidate()
                return true
            elseif evt == "SINGLE_TAP" then
                self:select_candidate(i) -- 传入相对索引（1-8）
                self._pressedCandidateIndex = nil
                return true
            elseif evt == "MOVE_X" or evt == "MOVE_Y" then
                if self._pressedCandidateIndex ~= idx then
                    self._pressedCandidateIndex = nil
                    self:invalidate()
                end
                return true
            end
        end
    end

    return false
end

-- 处理音节选择区触摸
function keyboard:handle_syllable_panel_touch(evt, x, y)
    local syllableBtnSize = 30
    local syllableAreaX = self.x
    local syllableAreaY = self.y + 95
    local start_y = syllableAreaY

    -- 上一页按钮（第一个小格子）
    local topBtnY = start_y
    if x >= syllableAreaX and x < syllableAreaX + syllableBtnSize and
        y >= topBtnY and y < topBtnY + syllableBtnSize then
        if evt == "SINGLE_TAP" then
            if self.syllablePageIndex > 1 then
                self.syllablePageIndex = self.syllablePageIndex - 1
                self.selectedSyllableIndex = (self.syllablePageIndex - 1) * 10 + 1
                self:invalidate()
            end
            return true
        end
    end

    -- 中间10个音节按钮（从第二个小格子开始）
    local syllablestart_y = start_y + syllableBtnSize
    for i = 1, 10 do
        local idx = (self.syllablePageIndex - 1) * 10 + i
        local btnY = syllablestart_y + (i - 1) * syllableBtnSize

        if idx <= #self.syllableCandidates and
            x >= syllableAreaX and x < syllableAreaX + syllableBtnSize and
            y >= btnY and y < btnY + syllableBtnSize then
            if evt == "TOUCH_DOWN" then
                self._pressedSyllableIndex = idx
                self:invalidate()
                return true
            elseif evt == "SINGLE_TAP" then
                local syllable = self.syllableCandidates[idx]
                self.selectedSyllableIndex = idx
                self:select_syllable(syllable)
                self._pressedSyllableIndex = nil
                return true
            elseif evt == "MOVE_X" or evt == "MOVE_Y" then
                if self._pressedSyllableIndex ~= idx then
                    self._pressedSyllableIndex = nil
                    self:invalidate()
                end
                return true
            end
        end
    end

    -- 下一页按钮（第12个小格子）
    local bottomBtnY = start_y + 11 * syllableBtnSize
    if x >= syllableAreaX and x < syllableAreaX + syllableBtnSize and
        y >= bottomBtnY and y < bottomBtnY + syllableBtnSize then
        if evt == "SINGLE_TAP" then
            local maxPage = math.ceil(#self.syllableCandidates / 10)
            if self.syllablePageIndex < maxPage then
                self.syllablePageIndex = self.syllablePageIndex + 1
                self.selectedSyllableIndex = (self.syllablePageIndex - 1) * 10 + 1
                self:invalidate()
            end
            return true
        end
    end

    return false
end

-- 绘制左侧音节选择区
function keyboard:draw_left_syllable_panel(ctx, ax, ay)
    local syllableBtnSize     = 30      -- 每个音节按钮大小（30x30）
    local syllableAreaX       = ax      -- 左侧预留区域X坐标
    local syllableAreaY       = ay + 95 -- 从按键区域上方开始（与大格子对齐）

    -- 大格子高度是90px，4个大格子总高度360px
    -- 12个小格子，每个30px，总共360px，正好对齐
    -- 每3个小格子对齐一个大格子（90px = 3 * 30px）
    local keySize             = 90          -- 大格子高度
    local totalHeight         = 4 * keySize -- 4个大格子的总高度 = 360px

    local dark                = (current_theme == "dark")
    local bg_color            = dark and COLOR_WIN11_DARK_BUTTON_BG or COLOR_WIN11_LIGHT_BUTTON_BG
    local border_color        = dark and COLOR_WIN11_DARK_BUTTON_BORDER or COLOR_WIN11_LIGHT_BUTTON_BORDER
    local text_color          = dark and COLOR_WHITE or COLOR_BLACK
    local selecte_dbg_color   = COLOR_SKY_BLUE
    local selected_text_color = COLOR_WHITE
    local presse_dbg_color    = COLOR_GRAY

    -- 12个小格子，每个30px，总共360px，正好等于4个大格子的高度
    local start_y             = syllableAreaY

    -- 1. 最上面的上一页切换按键（↑）- 第一个大格子的第一个小格子位置
    local topBtnY             = start_y
    ctx:fill_rect(syllableAreaX, topBtnY, syllableBtnSize, syllableBtnSize, bg_color)
    ctx:stroke_rect(syllableAreaX, topBtnY, syllableBtnSize, syllableBtnSize, border_color)
    -- 使用 draw_arrow_icon 绘制箭头图标
    draw_arrow_icon(syllableAreaX, topBtnY, syllableBtnSize, syllableBtnSize, "up", text_color)

    -- 2. 中间10个音节选择按键
    -- 从第二个小格子开始，每3个小格子对应一个大格子
    -- 索引1是上一页，索引2-11是10个音节，索引12是下一页
    local syllablestart_y = start_y + syllableBtnSize -- 从第二个小格子开始
    for i = 1, 10 do
        local idx = (self.syllablePageIndex - 1) * 10 + i
        local btnY = syllablestart_y + (i - 1) * syllableBtnSize

        if idx <= #self.syllableCandidates then
            local syllable = self.syllableCandidates[idx]
            local isSelected = (idx == self.selectedSyllableIndex)
            local isPressed = (self._pressedSyllableIndex == idx)
            local btnbg_color
            if self.enable_click_effect and isPressed then
                btnbg_color = presse_dbg_color
            elseif isSelected then
                btnbg_color = selecte_dbg_color
            else
                btnbg_color = bg_color
            end
            local btntext_color = (isSelected or (self.enable_click_effect and isPressed)) and selected_text_color or
                text_color

            ctx:fill_rect(syllableAreaX, btnY, syllableBtnSize, syllableBtnSize, btnbg_color)
            ctx:stroke_rect(syllableAreaX, btnY, syllableBtnSize, syllableBtnSize, border_color)
            ctx:draw_text_in_rect_centered(syllableAreaX, btnY, syllableBtnSize, syllableBtnSize, syllable, {
                color = btntext_color,
                style = { size = 10 }
            })
        else
            -- 空按钮
            ctx:fill_rect(syllableAreaX, btnY, syllableBtnSize, syllableBtnSize, bg_color)
            ctx:stroke_rect(syllableAreaX, btnY, syllableBtnSize, syllableBtnSize, border_color)
        end
    end

    -- 3. 最下面的下一页切换按键（↓）- 第4个大格子的第3个小格子位置（最后一个）
    local bottomBtnY = start_y + 11 * syllableBtnSize -- 第12个小格子（索引12）
    ctx:fill_rect(syllableAreaX, bottomBtnY, syllableBtnSize, syllableBtnSize, bg_color)
    ctx:stroke_rect(syllableAreaX, bottomBtnY, syllableBtnSize, syllableBtnSize, border_color)
    draw_arrow_icon(syllableAreaX, bottomBtnY, syllableBtnSize, syllableBtnSize, "down", text_color)
end

-- 绘制候选字选择区
function keyboard:draw_pinyin_candidates(ctx, ax, ay)
    local candidateY          = ay + 50 -- 候选区Y坐标
    local candidateHeight     = 50
    -- 中文候选带左右翻页：左右各占1格(30px)，中间8格候选
    local candidateBtnSize    = 30 -- 每个候选按钮大小（30x30）

    local dark                = (current_theme == "dark")
    local bg_color            = dark and COLOR_WIN11_DARK_BUTTON_BG or COLOR_WIN11_LIGHT_BUTTON_BG
    local border_color        = dark and COLOR_WIN11_DARK_BUTTON_BORDER or COLOR_WIN11_LIGHT_BUTTON_BORDER
    local text_color          = dark and COLOR_WHITE or COLOR_BLACK
    local selecte_dbg_color   = COLOR_SKY_BLUE
    local selected_text_color = COLOR_WHITE
    local presse_dbg_color    = COLOR_GRAY

    -- 左侧分页按键（←）
    local arrowW              = candidateBtnSize
    local leftArrowX          = ax
    local leftArrowY          = candidateY + (candidateHeight - candidateBtnSize) // 2
    ctx:fill_rect(leftArrowX, leftArrowY, arrowW, candidateBtnSize, bg_color)
    ctx:stroke_rect(leftArrowX, leftArrowY, arrowW, candidateBtnSize, border_color)
    draw_arrow_icon(leftArrowX, leftArrowY, arrowW, candidateBtnSize, "left", text_color)

    -- 右侧分页按键（→）
    local rightArrowX = ax + self.w - arrowW
    local rightArrowY = leftArrowY
    ctx:fill_rect(rightArrowX, rightArrowY, arrowW, candidateBtnSize, bg_color)
    ctx:stroke_rect(rightArrowX, rightArrowY, arrowW, candidateBtnSize, border_color)
    draw_arrow_icon(rightArrowX, rightArrowY, arrowW, candidateBtnSize, "right", text_color)

    -- 候选按键固定8个（居中区域，从 ax + arrowW 开始）
    local candidatestart_x = ax + arrowW
    for i = 1, 8 do
        local idx = (self.candidatePageIndex - 1) * 8 + i
        local btnX = candidatestart_x + (i - 1) * candidateBtnSize
        local btnY = candidateY + (candidateHeight - candidateBtnSize) // 2

        if idx <= #self.pinyinCandidates then
            local char = self.pinyinCandidates[idx] -- 直接使用UTF-8字符串
            local isSelected = (idx == self.selectedCandidateIndex)
            local isPressed = (self._pressedCandidateIndex == idx)
            local btnbg_color
            if self.enable_click_effect and isPressed then
                btnbg_color = presse_dbg_color
            elseif isSelected then
                btnbg_color = selecte_dbg_color
            else
                btnbg_color = bg_color
            end
            local btntext_color = (isSelected or (self.enable_click_effect and isPressed)) and selected_text_color or
                text_color

            ctx:fill_rect(btnX, btnY, candidateBtnSize, candidateBtnSize, btnbg_color)
            ctx:stroke_rect(btnX, btnY, candidateBtnSize, candidateBtnSize, border_color)

            -- 使用字体渲染候选字（优先使用hzfont，如果不可用则降级到其他字体后端）
            -- 通过 ctx:draw_text 统一接口，字体后端在 ui.init() 中配置
            local textStyle = { size = 12 }
            ctx:draw_text_in_rect_centered(btnX, btnY, candidateBtnSize, candidateBtnSize, char, {
                color = btntext_color,
                style = textStyle
            })
        else
            -- 空按钮
            ctx:fill_rect(btnX, btnY, candidateBtnSize, candidateBtnSize, bg_color)
            ctx:stroke_rect(btnX, btnY, candidateBtnSize, candidateBtnSize, border_color)
        end
    end
end

-- 绘制音节候选区（显示在候选字选择区的位置，但内容不同）
function keyboard:draw_syllable_candidates(ctx, ax, ay)
    -- 音节候选区暂时不单独绘制，由左侧音节选择区处理
    -- 这里可以预留，如果需要显示音节预览可以在这里实现
end

ui.keyboard = function(opts)
    return keyboard:new(opts)
end

-- 5.7 MessageBox
local message_box = setmetatable({}, { __index = BaseWidget })
message_box.__index = message_box

function message_box:new(opts)
    opts = opts or {}
    opts.w = opts.width or opts.w or 280
    opts.h = opts.height or opts.h or 160
    opts.x = opts.x or 20
    opts.y = opts.y or 40
    local o = BaseWidget.new(self, opts)
    o.title = opts.title or "Info"
    o.message = opts.message or ""
    o.word_wrap = opts.word_wrap ~= false
    local dark = (current_theme == "dark")
    o.border_color = opts.border_color or (dark and COLOR_WHITE or COLOR_BLACK)
    o.text_color = opts.text_color or (dark and COLOR_WHITE or COLOR_BLACK)
    o.bg_color = opts.bg_color or (dark and COLOR_WIN11_DARK_DIALOG_BG or COLOR_WIN11_LIGHT_DIALOG_BG)
    o.buttons = opts.buttons or { "OK" }
    o.on_result = opts.on_result
    o.text_style = { size = opts.text_size or opts.size or 12 }
    o._buttons = {}
    o:_layout_buttons()
    o:_layout_message()
    return o
end

function message_box:_layout_buttons()
    self._buttons = {}
    local count = #self.buttons
    if count == 0 then return end
    local btnW = 80
    local gap = 12
    local total = count * btnW + (count - 1) * gap
    local start_x = (self.w - total) // 2
    local btnY = self.h - 12 - 36
    for i = 1, count do
        local label = tostring(self.buttons[i])
        local btn = button:new({ x = start_x, y = btnY, w = btnW, h = 36, text = label })
        btn.on_click = function()
            if self.on_result then
                local ok, err = pcall(self.on_result, label, self)
                if not ok then
                    log.warn("MessageBox", "on_result error", err)
                end
            end
            self.visible = false
        end
        self:add(btn)
        self._buttons[#self._buttons + 1] = btn
        start_x = start_x + btnW + gap
    end
end

function message_box:_layout_message()
    self._msgPadding = 10
    self._msgstart_y = 36
    local reserved = (#self.buttons > 0) and (12 + 36) or 10
    self._msgHeight = self.h - reserved - self._msgstart_y
    self._msgWidth = self.w - self._msgPadding * 2
    if self.word_wrap then
        self._messageLines = wrap_text_lines(self.message, self._msgWidth, self.text_style)
        local lh = font_line_height(self.text_style)
        self._maxLines = math.max(1, math.floor(self._msgHeight / lh))
    else
        self._messageLines = nil
    end
end

function message_box:set_message(message)
    self.message = tostring(message or "")
    self:_layout_message()
    self:invalidate()
end

function message_box:set_title(title)
    self.title = tostring(title or "")
    self:invalidate()
end

function message_box:show()
    self.visible = true
    self.enabled = true
    self:invalidate()
end

function message_box:hide()
    self.visible = false
    self:invalidate()
end

function message_box:draw(ctx)
    if not self.visible then return end
    local ax, ay = self:get_absolute_position()
    ctx:fill_rect(ax, ay, self.w, self.h, self.bg_color)
    ctx:stroke_rect(ax, ay, self.w, self.h, self.border_color)
    ctx:draw_text(self.title, ax + 10, ay + 8, self.text_color, self.text_style)
    local style = self.text_style
    local lh = ctx:line_height(style)
    local start_y = ay + self._msgstart_y
    if self.word_wrap then
        local lines = self._messageLines or wrap_text_lines(self.message, self._msgWidth, style)
        local limit = math.min(#lines, self._maxLines or #lines)
        for i = 1, limit do
            ctx:draw_text(lines[i], ax + self._msgPadding, start_y + (i - 1) * lh, self.text_color, style)
        end
    else
        local text = fit_text_to_width(self.message, self._msgWidth, style, { ellipsis = true })
        ctx:draw_text(text, ax + self._msgPadding, start_y, self.text_color, style)
    end
end

function message_box:handle_event()
    if not (self.visible and self.enabled) then return false end
    return true
end

ui.message_box = function(opts)
    return message_box:new(opts)
end

-- 5.6 Picture
local picture = setmetatable({}, { __index = BaseWidget })
picture.__index = picture

function picture:new(opts)
    opts = opts or {}
    local o = BaseWidget.new(self, opts)
    o.src = opts.src
    o.sources = opts.sources
    o.index = opts.index or 1
    o.autoplay = not not opts.autoplay
    o.interval = opts.interval or 1000
    o._last_switch = now_ms()
    o._imageCache = {}
    o._timer_id = nil
    if o.w == 0 then o.w = 80 end
    if o.h == 0 then o.h = 80 end
    -- 如果启用自动播放，启动定时器
    if o.autoplay and o.sources and #o.sources > 1 then
        o:_start_autoplay_timer()
    end
    return o
end

function picture:set_sources(list)
    self.sources = list
    self.index = 1
    -- 如果启用自动播放且有多个图片，重启定时器
    if self.autoplay and list and #list > 1 then
        self:_stop_autoplay_timer()
        self:_start_autoplay_timer()
    elseif not list or #list <= 1 then
        self:_stop_autoplay_timer()
    end
end

function picture:next()
    if not self.sources or #self.sources == 0 then return end
    self.index = (self.index % #self.sources) + 1
end

function picture:prev()
    if not self.sources or #self.sources == 0 then return end
    self.index = (self.index - 2) % #self.sources + 1
end

function picture:_start_autoplay_timer()
    if self._timer_id then return end
    if not (self.sources and #self.sources > 1) then return end

    -- 使用定时器定期触发切换
    local function autoplay_tick()
        if not self.autoplay or not self.visible then
            self:_stop_autoplay_timer()
            return
        end
        if not self.sources or #self.sources <= 1 then
            self:_stop_autoplay_timer()
            return
        end

        local t = now_ms()
        if (t - self._last_switch) >= self.interval then
            self:next()
            self._last_switch = t
            self:invalidate()
        end
    end

    -- 尝试使用 sys.timerLoopStart（如果可用）
    if sys and sys.timerLoopStart then
        -- 使用较短的检查间隔（100ms），确保及时响应
        self._timer_id = sys.timerLoopStart(autoplay_tick, math.min(100, self.interval))
    else
        -- 如果没有定时器 API，回退到原来的方式（在 draw 中检查）
        -- 这种情况下需要确保 ui.render() 被定期调用
        self._timer_id = true -- 标记为已启用，但使用 draw() 中的逻辑
    end
end

function picture:_stop_autoplay_timer()
    if self._timer_id and sys and sys.timerStop then
        sys.timerStop(self._timer_id)
    end
    self._timer_id = nil
end

function picture:play()
    self.autoplay = true
    if not self._timer_id then
        self:_start_autoplay_timer()
    end
end

function picture:pause()
    self.autoplay = false
    self:_stop_autoplay_timer()
end

function picture:draw()
    if not self.visible then return end
    local ax, ay = self:get_absolute_position()
    local path = self.src
    if self.sources and #self.sources > 0 then
        path = self.sources[self.index]
    end

    if type(path) == "string" and path ~= "" then
        -- 优先使用图片缓存（lcd.image2raw + lcd.draw）
        if lcd and lcd.image2raw and lcd.draw then
            local zbuff = ui.image_cache.get_zbuff(path)
            if zbuff then
                -- 使用 zbuff 绘制，lcd.draw 会自动使用 zbuff 内部的 width 和 height
                lcd.draw(ax, ay, nil, nil, zbuff)
                return
            end
        end
    end

    -- 绘制占位符
    draw_image_placeholder(ax, ay, self.w, self.h, COLOR_GRAY, COLOR_WHITE)
end

function picture:handle_event()
    return false
end

ui.picture = function(opts)
    return picture:new(opts)
end

-- 5.7 ProgressBar
local progress_bar = setmetatable({}, { __index = BaseWidget })
progress_bar.__index = progress_bar

function progress_bar:new(opts)
    opts = opts or {}
    opts.w = opts.width or opts.w or 200
    opts.h = opts.height or opts.h or 24
    local o = BaseWidget.new(self, opts)
    o.progress = math.max(0, math.min(100, opts.progress or 0))
    o.show_percentage = opts.show_percentage ~= false
    o.text = opts.text
    o.text_style = { size = opts.text_size or opts.size or 12 }
    local dark = (current_theme == "dark")
    o.background_color = opts.background_color or (dark and COLOR_GRAY or 0xC618)
    o.progress_color = opts.progress_color or (dark and COLOR_BLUE or COLOR_SKY_BLUE)
    o.border_color = opts.border_color or (dark and COLOR_WHITE or 0x8410)
    o.text_color = opts.text_color or (dark and COLOR_WHITE or COLOR_BLACK)
    return o
end

function progress_bar:get_progress()
    return self.progress
end

function progress_bar:set_progress(value)
    self.progress = math.max(0, math.min(100, value))
    self:invalidate()
end

function progress_bar:set_text(text)
    self.text = tostring(text or "")
    self:invalidate()
end

function progress_bar:draw(ctx)
    if not self.visible then return end
    local ax, ay = self:get_absolute_position()
    ctx:fill_rect(ax + 1, ay + 1, self.w - 2, self.h - 2, self.background_color)
    ctx:stroke_rect(ax, ay, self.w, self.h, self.border_color)
    local innerWidth = math.max(0, self.w - 2)
    local fillWidth = math.floor(innerWidth * (self.progress / 100))
    if fillWidth > 0 then
        ctx:fill_rect(ax + 1, ay + 1, fillWidth, self.h - 2, self.progress_color)
    end
    if self.show_percentage or self.text then
        local label = self.text or (tostring(self.progress) .. "%")
        draw_text_in_rect_centered(ax, ay, self.w, self.h, label, {
            color = self.text_color,
            style = self.text_style,
            padding = 2
        })
    end
end

function progress_bar:handle_event()
    return false
end

ui.progress_bar = function(opts)
    return progress_bar:new(opts)
end

-- 5.8 Window
local function window_theme_color()
    return (current_theme == "dark") and COLOR_BLACK or COLOR_WHITE
end

local function window_snap_axis(self, axis, mode)
    local sc = self._scroll
    if not sc then return false end
    local pageSize, contentSize, offsetField
    if axis == "x" then
        pageSize = sc.page_width or self.w
        contentSize = sc.content_width or self.w
        offsetField = "offset_x"
        if not (sc.direction == "horizontal" or sc.direction == "both") then
            return false
        end
    else
        pageSize = sc.page_height or self.h
        contentSize = sc.content_height or self.h
        offsetField = "offset_y"
        if not (sc.direction == "vertical" or sc.direction == "both") then
            return false
        end
    end
    if pageSize <= 0 then return false end
    local pages = math.max(1, math.floor((contentSize + pageSize - 1) / pageSize))
    local current = sc[offsetField] or 0
    local cur = math.floor((-(current) + pageSize / 2) / pageSize)
    if mode == "increment" then
        cur = cur + 1
    elseif mode == "decrement" then
        cur = cur - 1
    elseif type(mode) == "number" then
        cur = mode
    end
    if cur < 0 then cur = 0 end
    if cur > pages - 1 then cur = pages - 1 end
    local target = -cur * pageSize
    if target ~= current then
        sc[offsetField] = target
        self:invalidate()
        return true
    end
    return false
end

local window = setmetatable({}, { __index = BaseWidget })
window.__index = window

function window:new(opts)
    opts = opts or {}
    opts.x = opts.x or 0
    opts.y = opts.y or 0
    opts.w = opts.w or render_state.viewport_w
    opts.h = opts.h or render_state.viewport_h
    local o = BaseWidget.new(self, opts)
    o.background_color = opts.background_color or window_theme_color()
    o.background_image = opts.background_image
    o._scroll = nil
    if opts.scroll then
        o:enable_scroll(opts.scroll)
    end
    return o
end

function window:add(child)
    child = BaseWidget.add(self, child)
    child._parentWindow = self
    return child
end

function window:remove(child)
    for i = #self.children, 1, -1 do
        if self.children[i] == child then
            table.remove(self.children, i)
            if child then
                if child.on_unmount then
                    pcall(child.on_unmount, child)
                end
                child.parent = nil
                child._parentWindow = nil
            end
            self:invalidate()
            return true
        end
    end
    return false
end

function window:clear()
    for i = #self.children, 1, -1 do
        local child = self.children[i]
        table.remove(self.children, i)
        if child then
            if child.on_unmount then
                pcall(child.on_unmount, child)
            end
            child.parent = nil
            child._parentWindow = nil
        end
    end
    self:invalidate()
end

function window:set_background_color(color)
    self.background_color = color
    self.background_image = nil
    self:invalidate()
end

function window:set_background_image(path)
    self.background_image = path
    self:invalidate()
end

function window:_scroll_bounds()
    local sc = self._scroll
    if not sc then return 0, 0, 0, 0 end
    local cw = sc.content_width or self.w
    local ch = sc.content_height or self.h
    local minX = math.min(0, self.w - cw)
    local maxX = 0
    local minY = math.min(0, self.h - ch)
    local maxY = 0
    return minX, maxX, minY, maxY
end

function window:_handle_scroll_gesture(evt, x, y)
    local sc = self._scroll
    if not sc or not sc.enabled then
        return false
    end
    if evt == "TOUCH_DOWN" then
        sc.active = self:contains_point(x, y)
        sc.dragging = false
        sc.start_x = x
        sc.start_y = y
        sc.base_offset_x = sc.offset_x
        sc.base_offset_y = sc.offset_y
        sc.snapped = false
        return false
    elseif evt == "MOVE_X" or evt == "MOVE_Y" then
        if not sc.active then return false end
        sc.dragging = true
        local dx = x - (sc.start_x or x)
        local dy = y - (sc.start_y or y)
        local minX, maxX, minY, maxY = self:_scroll_bounds()
        local changed = false
        local snap_horizontal = sc.snap_to_page and (sc.direction == "horizontal" or sc.direction == "both")
        local snap_vertical = sc.snap_to_page and (sc.direction == "vertical" or sc.direction == "both")
        if sc.direction == "horizontal" or sc.direction == "both" then
            if not snap_horizontal then
                local nx = clamp((sc.base_offset_x or 0) + dx, minX, maxX)
                if nx ~= sc.offset_x then
                    sc.offset_x = nx
                    changed = true
                end
            end
        end
        if sc.direction == "vertical" or sc.direction == "both" then
            if not snap_vertical then
                local ny = clamp((sc.base_offset_y or 0) + dy, minY, maxY)
                if ny ~= sc.offset_y then
                    sc.offset_y = ny
                    changed = true
                end
            end
        end
        if changed then
            self:invalidate()
        end
        return true
    elseif evt == "SINGLE_TAP" or evt == "LONG_PRESS" then
        local was_dragging = sc.dragging
        sc.active = false
        sc.dragging = false
        if was_dragging then
            if sc.snap_to_page then
                window_snap_axis(self, "x")
                window_snap_axis(self, "y")
            end
            return true
        end
    elseif evt == "SWIPE_LEFT" or evt == "SWIPE_RIGHT" then
        if sc.snap_to_page and (sc.direction == "horizontal" or sc.direction == "both") then
            local mode = (evt == "SWIPE_LEFT") and "increment" or "decrement"
            window_snap_axis(self, "x", mode)
            sc.active = false
            sc.dragging = false
            sc.snapped = true
            return true
        end
    elseif evt == "SWIPE_UP" or evt == "SWIPE_DOWN" then
        if sc.snap_to_page and (sc.direction == "vertical" or sc.direction == "both") then
            local mode = (evt == "SWIPE_DOWN") and "increment" or "decrement"
            window_snap_axis(self, "y", mode)
            sc.active = false
            sc.dragging = false
            sc.snapped = true
            return true
        end
    end
    return false
end

function window:enable_scroll(opts)
    opts = opts or {}
    self._scroll = {
        enabled = true,
        direction = opts.direction or "vertical",
        content_width = opts.content_width or opts.contentWidth or self.w,
        content_height = opts.content_height or opts.contentHeight or self.h,
        offset_x = 0,
        offset_y = 0,
        start_x = 0,
        start_y = 0,
        base_offset_x = 0,
        base_offset_y = 0,
        active = false,
        dragging = false,
        page_width = opts.page_width or self.w,
        page_height = opts.page_height or self.h,
        snap_to_page = opts.snap_to_page or false,
        snapped = false
    }
end

function window:set_content_size(w, h)
    if not self._scroll then
        self:enable_scroll({})
    end
    if w then self._scroll.content_width = w end
    if h then self._scroll.content_height = h end
end

-- 启用子页面管理
function window:enable_subpage_manager(opts)
    opts = opts or {}
    if not self._managed then
        self._managed = {
            pages = {},
            back_event_name = opts.back_event_name or "NAV.BACK",
            on_back = opts.on_back
        }
        if sys and sys.subscribe then
            sys.subscribe(self._managed.back_event_name, function()
                if self._managed.on_back then
                    pcall(self._managed.on_back)
                end
                local anyVisible = false
                for _, pg in pairs(self._managed.pages) do
                    if pg and pg.visible ~= false then
                        anyVisible = true
                        break
                    end
                end
                if not anyVisible then
                    self.visible = true
                    self.enabled = true
                    self:invalidate()
                end
            end)
        end
    end
    return self
end

-- 配置子页面工厂
function window:configure_subpages(factories)
    if not self._managed then
        self:enable_subpage_manager()
    end
    self._managed.factories = self._managed.factories or {}
    for k, v in pairs(factories or {}) do
        self._managed.factories[k] = v
    end
    return self
end

-- 显示子页面
function window:show_subpage(name, factory)
    if not self._managed then
        error("enable_subpage_manager must be called before show_subpage")
    end
    -- 隐藏所有其他子页面
    for key, pg in pairs(self._managed.pages) do
        if pg and pg.visible ~= false then
            pg.visible = false
            pg.enabled = false
            pg:invalidate()
        end
    end
    -- 如果子页面不存在，则创建
    if not self._managed.pages[name] then
        local f = factory
        if not f and self._managed.factories then
            f = self._managed.factories[name]
        end
        if not f then
            error("no factory for subpage '" .. tostring(name) .. "'")
        end
        self._managed.pages[name] = f()
        self._managed.pages[name]._parentWindow = self
        runtime.add(self._managed.pages[name])
    end
    -- 隐藏当前窗口，显示子页面
    self.visible = false
    self.enabled = false
    self._managed.pages[name].visible = true
    self._managed.pages[name].enabled = true
    self:invalidate()
    self._managed.pages[name]:invalidate()
end

-- 返回上级页面
function window:back()
    if self._parentWindow then
        self.visible = false
        self.enabled = false
        self:invalidate()
        local parent = self._parentWindow
        local anyVisible = false
        if parent._managed and parent._managed.pages then
            for _, pg in pairs(parent._managed.pages) do
                if pg and pg.visible ~= false then
                    anyVisible = true
                    break
                end
            end
        end
        if not anyVisible then
            parent.visible = true
            parent.enabled = true
            parent:invalidate()
        end
    end
end

-- 关闭子页面
function window:close_subpage(name, opts)
    if not self._managed or not self._managed.pages then
        return false
    end
    opts = opts or {}
    local pg = self._managed.pages[name]
    if not pg then
        return false
    end
    pg.visible = false
    pg.enabled = false
    pg:invalidate()
    if opts.destroy == true then
        runtime.remove(pg)
        self._managed.pages[name] = nil
        if collectgarbage then
            collectgarbage("collect")
        end
    end
    -- 检查是否还有其他可见的子页面
    local anyVisible = false
    for _, p in pairs(self._managed.pages) do
        if p and p.visible ~= false then
            anyVisible = true
            break
        end
    end
    if not anyVisible then
        self.visible = true
        self.enabled = true
        self:invalidate()
    end
    return true
end

function window:draw(ctx)
    local ax, ay = self:get_absolute_position()
    if self.background_image and lcd then
        if lcd.drawImage then
            lcd.drawImage(ax, ay, self.background_image)
        elseif lcd.showImage then
            lcd.showImage(ax, ay, self.background_image)
        else
            ctx:fill_rect(ax, ay, self.w, self.h, self.background_color)
        end
    else
        ctx:fill_rect(ax, ay, self.w, self.h, self.background_color)
    end
    for i = 1, #self.children do
        local child = self.children[i]
        if child and child.visible ~= false and child.draw then
            child:draw(ctx)
        end
    end
end

function window:dispatch_pointer(evt, x, y)
    if not self.visible or not self.enabled then return false end
    local inside = self:contains_point(x, y) or (self._scroll and self._scroll.dragging)
    if not inside and evt ~= "MOVE_X" and evt ~= "MOVE_Y" then
        return false
    end
    if self:_handle_scroll_gesture(evt, x, y) then
        return true
    end
    for i = #self.children, 1, -1 do
        if self.children[i]:dispatch_pointer(evt, x, y) then
            return true
        end
    end
    return false
end

ui.window = function(opts)
    return window:new(opts)
end

-- ================================
-- 6. 对外接口导出
-- ================================

function ui.sw_init(opts)
    opts = opts or {}
    if opts.theme == "light" or opts.theme == "dark" then
        current_theme = opts.theme
    end
    runtime.bindInput()
end

function ui.theme()
    return current_theme
end

function ui.add(widget)
    return runtime.add(widget)
end

function ui.remove(widget)
    return runtime.remove(widget)
end

function ui.clear(color)
    ui.render.background(color or COLOR_BLACK)
end

-- V1.7.2新增：屏幕休眠接口
-- @param enable_touch boolean | nil: 可选参数，为true或nil时触摸保持生效，为false时关闭所有触摸消息
function ui.sleep(enable_touch)
    -- 默认参数为true，即触摸生效
    local keep_touch_enabled = (enable_touch == nil) or (enable_touch == true)

    -- 调用exlcd休眠
    if exlcd and exlcd.sleep then
        sleep_flag = true
        exlcd.sleep()
    end

    -- 如果不需要触摸生效，则关闭所有触摸消息
    if not keep_touch_enabled and extp and extp.set_publish_enabled then
        local success = extp.set_publish_enabled("ALL", false)
        if success then
            -- 记录触摸被关闭的状态，用于唤醒时恢复
            runtime.touch_disabled_during_sleep = true
            log.info("exEasyUI", "触摸已禁用")
        else
            runtime.touch_disabled_during_sleep = false
            log.warn("exEasyUI", "禁用触摸失败")
        end
    else
        runtime.touch_disabled_during_sleep = false
        if keep_touch_enabled then
            log.info("exEasyUI", "触摸保持生效")
        end
    end
end

-- V1.7.2新增：屏幕唤醒接口
function ui.wakeup()
    -- 如果休眠时触摸被关闭，则恢复初始化时的触摸设置
    if runtime.touch_disabled_during_sleep and extp and extp.set_publish_enabled then
        -- 重新启用所有触摸消息
        if sleep_config and type(sleep_config) == "table" then
            local restored_count = 0
            local failed_count = 0
            for msg_type, enabled in pairs(sleep_config) do
                if type(msg_type) == "string" and type(enabled) == "boolean" then
                    local success = extp.set_publish_enabled(msg_type, enabled)
                    if success then
                        restored_count = restored_count + 1
                    else
                        failed_count = failed_count + 1
                        log.warn("exEasyUI", "恢复触摸消息失败:", msg_type, enabled)
                    end
                end
            end
            log.info("exEasyUI", string.format("屏幕唤醒，触摸已恢复（成功%d个，失败%d个）",
                restored_count, failed_count))
        else
            -- 如果 sleep_config 无效，启用所有触摸消息作为后备
            extp.set_publish_enabled("ALL", true)
            log.info("exEasyUI", "屏幕唤醒，触摸已启用（使用后备方案）")
        end
        runtime.touch_disabled_during_sleep = false
    else
        log.info("exEasyUI", "屏幕唤醒，恢复触摸设置")
    end
    exlcd.wakeup()
    sleep_flag = false
end

-- V1.7.2新增：设置背光亮度接口
-- @param level number: 背光亮度等级，具体取值范围由硬件决定
function ui.set_bl(level)
    if exlcd and exlcd.set_bl then
        -- 验证 level 参数
        if type(level) == "number" then
            exlcd.set_bl(level)
            log.info("exEasyUI", "设置背光亮度", level)
        else
            log.warn("exEasyUI", "背光亮度参数必须是数字，当前类型:", type(level))
        end
    else
        log.warn("exEasyUI", "set_bl接口不可用")
    end
end

-- V1.7.3新增：获取屏幕休眠状态接口
-- @return boolean true表示屏幕处于休眠状态，false表示屏幕处于工作状态
function ui.get_sleep()
    if exlcd and exlcd.get_sleep then
        local status = exlcd.get_sleep()
        log.info("exEasyUI", "获取屏幕休眠状态:", status and "休眠中" or "唤醒中")
        return status
    else
        log.warn("exEasyUI", "get_sleep接口不可用")
        return false
    end
end

-- V1.7.3新增：获取当前背光亮度接口
-- @return number 当前背光亮度级别(0-100)，如果接口不可用则返回nil
function ui.get_bl()
    if exlcd and exlcd.get_bl then
        local brightness = exlcd.get_bl()
        log.info("exEasyUI", "获取背光亮度:", brightness .. "%")
        return brightness
    else
        log.warn("exEasyUI", "get_bl接口不可用")
        return nil
    end
end

function ui.refresh()
    if not sleep_flag then
        ui.render.invalidate(nil)
    end
end

-- 已废除：预计1.8.0删除
function ui.renderFrame()
    return nil -- 返回空值
end

return ui