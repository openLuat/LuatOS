--[[
@module  ui_viewer
@summary 满屏照片查看器：左右滑动切图、轻触呼出控制条、自动轮播可暂停
@version 1.0
@date    2026.10.22

=== 交互约定 ===
  - 左右滑动（位移 >= 60px 且横向占优）：上一张 / 下一张，循环滚动；
  - 轻触画面（不点在控制条上）：显示 / 隐藏控制条；
  - 控制条 4 秒无操作自动隐藏；
  - 控制条上：主界面 / 相册列表 / 上一张 / 自动轮播开关 / 下一张；
  - 自动轮播按 conf.photo.auto_sec（默认 3 秒一张），暂停后固定当前照片。

=== 触摸怎么接 ===
按钮用组件自己的 on_click；滑动/轻触用 airui.touch_subscribe 的全局坐标。
两者不冲突：只处理在“非控制条区域”抬起的手势，避免点按钮时又触发一次轻触。

=== 单张加载任务 ===
连续快速滑动时不能每张都开一个解码任务（会互相把对方刚建好的控件销毁）。
这里用 want/loading 双标志做合并：同一时刻只有一个解码任务，后到的请求覆盖前一个。
]]
local conf = require "conf"
local theme = require "theme"
local photo_cache = require "photo_cache"
local photo_view = require "photo_view"

local M = {}
local C = theme.C
local SW, SH = conf.W, conf.H
local P = conf.photo

-- ==================== 运行时状态 ====================
local root = nil
local photo_layer = nil
local overlay = nil
local loading_box = nil
local loading_label = nil

local lb_name = nil
local lb_index = nil
local btn_auto = nil
local btn_auto2 = nil       -- 底栏的“自动轮播中/已暂停”
local top_bar = nil         -- 顶栏容器（只切它，不切整屏 overlay）
local bottom_bar = nil      -- 底栏容器

local photos = nil
local cur = 1

local auto_on = true        -- 跨次进入保持用户选择
local auto_timer = nil
local bar_timer = nil
local bars_visible = true

local loading = false
local want_load = false
local hint_pending = false  -- 只有从目录页进入查看器那一次为 true（决定要不要弹“正在打开照片...”）
local visible = false       -- 查看器是否正在显示（根容器常驻，只切显隐）
local session = 0           -- 每次进入/退出查看器 +1，用来作废过期的预载任务

local down_x, down_y, down_t = 0, 0, 0
local down_in_bar = false
local pending_t0, pending_src = nil, nil   -- 用户动作时刻 + 动作名，用于打印“显示用时”

-- ==================== 时间基准 ====================
local TICKS_PER_MS = 1
do
    local hz = mcu and mcu.hz and mcu.hz()
    if type(hz) == "number" and hz > 1 then
        TICKS_PER_MS = hz / 1000
    end
end

local function now_ms()
    if mcu and mcu.ticks then
        return mcu.ticks() / TICKS_PER_MS
    end
    return os.time() * 1000
end

-- ==================== 定时器 ====================
local function cancel_auto()
    if auto_timer then
        sys.timerStop(auto_timer)
        auto_timer = nil
    end
end

local function cancel_bar_timer()
    if bar_timer then
        sys.timerStop(bar_timer)
        bar_timer = nil
    end
end

local function schedule_auto()
    cancel_auto()
    if not root or not auto_on then return end
    auto_timer = sys.timerStart(function()
        auto_timer = nil
        if root and auto_on then
            M.next("轮播")
        end
    end, P.auto_sec * 1000)
end

-- ==================== 控制条显隐 ====================
--[[只隐藏/显示上下两条，不动 overlay
overlay 是全屏容器：一旦 set_hidden，LVGL 会把整屏标脏，
而照片是 .bin 按行从 SD 读的，整屏重绘等于重读 1.23MB，点一下屏幕就卡 1 秒。
只切两条控制条的话，只有 84+100 行会重绘（约 380KB），快很多。
]]
local function apply_bars_visible(v)
    bars_visible = v
    if top_bar then top_bar:set_hidden(not v) end
    if bottom_bar then bottom_bar:set_hidden(not v) end
end

local function hide_bars()
    if not root then return end
    apply_bars_visible(false)
    cancel_bar_timer()
    if P.touch_debug then log.info("viewer", "bars hide @", math.floor(now_ms())) end
end

local function show_bars()
    if not root then return end
    apply_bars_visible(true)
    cancel_bar_timer()
    bar_timer = sys.timerStart(function()
        bar_timer = nil
        hide_bars()
    end, P.bar_hint_ms)
    if P.touch_debug then log.info("viewer", "bars show @", math.floor(now_ms())) end
end

-- ==================== 加载提示 ====================
local function set_loading(on, text, color, sub)
    if not loading_box then return end
    if on then
        loading_label:set_text(text or "正在打开照片...")
        loading_label:set_color(color or C.on_dark)
        loading_box:set_hidden(false)
    else
        loading_box:set_hidden(true)
    end
    if sub ~= nil then
        lb_index:set_text(sub)
    end
end

-- ==================== 顶部/底部控制条 ====================
local function refresh_auto_ui()
    if btn_auto then
        btn_auto:set_text(auto_on and "暂停轮播" or "自动轮播")
        btn_auto:set_style({
            bg_color = auto_on and C.accent or 0x3A2A20,
            bg_opa = 255,
            text_color = auto_on and 0xFFFFFF or C.on_dark,
            radius = 12,
            border_width = 1,
            border_color = auto_on and C.accent or 0x5A4436,
            pressed_bg_color = C.accent_d,
            pressed_text_color = 0xFFFFFF,
        })
    end
    if btn_auto2 then
        btn_auto2:set_text(auto_on and string.format("自动轮播中 %d 秒一张，点此暂停", P.auto_sec)
            or "已暂停，固定当前照片，点此继续")
        btn_auto2:set_style({
            bg_color = auto_on and C.accent or 0x3A2A20,
            bg_opa = 255,
            text_color = auto_on and 0xFFFFFF or C.on_dark,
            radius = 12,
            border_width = 1,
            border_color = auto_on and C.accent or 0x5A4436,
            pressed_bg_color = C.accent_d,
            pressed_text_color = 0xFFFFFF,
        })
    end
end

local function toggle_auto()
    auto_on = not auto_on
    refresh_auto_ui()
    if auto_on then
        schedule_auto()
    else
        cancel_auto()
    end
    show_bars()
end

local function build_bars()
    -- ===== 顶栏 =====
    local top = airui.container({
        parent = overlay, x = 0, y = 0, w = SW, h = 84,
        color = C.mask, color_opacity = 175, radius = 0, border_width = 0,
    })
    top_bar = top
    theme.dark_button(top, 16, 14, 118, 56, "主界面", 19, function()
        theme.defer(function()
            if M.app then M.app.go_home() end
        end)
    end)
    theme.dark_button(top, 146, 14, 118, 56, "相册列表", 19, function()
        theme.defer(function()
            if M.app then M.app.close_viewer() end
        end)
    end)

    lb_name = theme.label(top, 282, 14, 430, 26, "", 19, C.on_dark)
    lb_index = theme.label(top, 282, 42, 430, 24, "", 16, C.on_dark2)

    btn_auto = theme.dark_button(top, 736, 14, 128, 56, "暂停轮播", 18, toggle_auto, auto_on)
    theme.dark_button(top, 878, 14, 130, 56, "上一张", 19, function()
        theme.defer(M.prev)
    end)

    -- ===== 底栏 =====
    local bottom = airui.container({
        parent = overlay, x = 0, y = 500, w = SW, h = 100,
        color = C.mask, color_opacity = 160, radius = 0, border_width = 0,
    })
    bottom_bar = bottom
    theme.dark_button(bottom, 160, 12, 150, 56, "上一张", 20, function()
        theme.defer(M.prev)
    end)
    btn_auto2 = theme.dark_button(bottom, 326, 12, 372, 56,
        string.format("自动轮播中 %d 秒一张，点此暂停", P.auto_sec), 18, toggle_auto, auto_on)
    theme.dark_button(bottom, 714, 12, 150, 56, "下一张", 20, function()
        theme.defer(M.next)
    end)

    theme.label(bottom, 0, 72, SW, 20, "左右滑动切换照片，轻触画面显示/隐藏控制条",
        15, C.on_dark2, airui.TEXT_ALIGN_CENTER)
end

-- ==================== 单张显示 ====================
local function update_head()
    if not photos or not photos[cur] then return end
    lb_name:set_text(photos[cur].name)
    lb_index:set_text(string.format("第 %d / %d 张", cur, #photos))
end

local function request_load()
    want_load = true
    if loading then return end
    loading = true

    sys.taskInit(function()
        local my = session
        while want_load do
            want_load = false
            if my ~= session or not root or not photos or not photos[cur] then break end

            local idx = cur
            local entry = photos[idx]
            -- 这一轮对应的“用户动作时刻”（点击小图 / 上一张 / 下一张 / 轮播）
            local t0, src = pending_t0, pending_src
            pending_t0, pending_src = nil, nil
            update_head()

            -- 只读 4KB 头：尺寸/有效性；读不到就按屏幕尺寸兜底
            local meta = photo_cache.ensure(entry)
            if my ~= session or not root or not photos or not photos[cur] then break end

            -- “正在打开照片...”只在“从目录页点小图进来”那一次提示；
            -- 轮播/滑动/上一张下一张都不再弹（生成过的图本来就秒开）。
            -- 缓存已存在时不弹，避免一闪而过的黑框。
            if hint_pending then
                hint_pending = false
                if not photo_view.cached(entry, meta and meta.w, meta and meta.h) then
                    set_loading(true, "正在打开照片...")
                    sys.wait(30)      -- 让提示先画出来，再去跑阻塞的解码
                end
            end

            local eng, err, cached = photo_view.show(entry, meta, SW, SH)
            if my ~= session or not root or not photos or not photos[cur] then break end

            if idx ~= cur then
                -- 解码期间用户又滑走了：这次结果作废，下一轮直接解新的
                log.info("viewer", "结果已过期，跳过", entry.name)
            elseif eng then
                set_loading(false)
                if meta and meta.w then
                    lb_index:set_text(string.format("第 %d / %d 张   %d x %d",
                        idx, #photos, meta.w, meta.h))
                end
                log.info("viewer", cached and "复用/命中" or "现场解码",
                    entry.name, "引擎", eng, "槽位", photo_cache.count())

                -- ===== 显示用时 =====
                -- airui.full_refresh() 内部是 lv_refr_now()：同步把这一帧画完，
                -- 所以能分开看到“取图（解码/读缓存）”和“真正上屏（LVGL 重绘）”两段耗时。
                local t1 = now_ms()
                local t2 = t1
                if P.time_debug and airui and airui.full_refresh then
                    pcall(airui.full_refresh)
                    t2 = now_ms()
                end
                if t0 and P.time_debug then
                    -- now_ms() 是浮点，%d 前必须取整（Lua 5.3 会对非整数报错）
                    log.info("viewer", string.format(
                        "%s -> 显示 %d ms（取图 %d + 上屏 %d）%s",
                        src or "加载",
                        math.floor(t2 - t0), math.floor(t1 - t0), math.floor(t2 - t1),
                        cached and "缓存" or "生成"))
                end
                -- 顺手把下一张的 .bin 先做出来，翻过去就是秒开。
                -- 轮播时几乎立刻开始（否则赶不上 3 秒节拍），手动浏览时晚一点再占 CPU。
                if #photos > 1 then
                    photo_view.prefetch(photos[(idx % #photos) + 1], auto_on and 200 or 1500)
                end
                -- 间隔从“画出来”开始算，而不是从按下按键开始算
                schedule_auto()
            else
                -- 兜底也失败：把提示留在屏幕上，等用户切走（自动轮播继续跳过它）
                set_loading(true, "无法显示（渐进式 JPEG 或内存不足）", 0xFFB4A4)
                log.error("viewer", "照片显示失败", entry.path, tostring(err))
                schedule_auto()
            end
        end
        loading = false
    end)
end

--[[跳到第 i 张（1 基，自动环绕）
@param number i
@param string|nil label 动作名，只用于日志（上一张 / 下一张 / 轮播 / 点击小图）
]]
function M.show(i, label)
    if not root or not photos or #photos == 0 then return end
    local n = #photos
    i = ((i - 1) % n) + 1
    cur = i
    update_head()
    pending_t0 = now_ms()
    pending_src = type(label) == "string" and label or "切换"
    request_load()
end

function M.next(label)
    if not photos or #photos == 0 then return end
    M.show(cur + 1, type(label) == "string" and label or "下一张")
    schedule_auto()
end

function M.prev(label)
    if not photos or #photos == 0 then return end
    M.show(cur - 1, type(label) == "string" and label or "上一张")
    schedule_auto()
end

-- ==================== 触摸手势 ====================
local last_tp_t = 0

function M.on_touch(state, x, y, track_id, ts)
    if not visible or not root then return end

    local t = nil
    if P.touch_debug then t = math.floor(now_ms()) end

    if state == airui.TP_DOWN then
        down_x, down_y = x or 0, y or 0
        -- 不用回调里的 timestamp：不同固件单位不一致（ms / tick），
        -- 统一用 mcu.ticks() 折算，按下抬起同一个时间基准
        down_t = now_ms()
        down_in_bar = bars_visible and ((y or 0) < 92 or (y or 0) > 498)
        if t then
            log.info("tp", "DOWN", x, y, "gap", t - last_tp_t,
                "bars", bars_visible and 1 or 0, "inbar", down_in_bar and 1 or 0)
            last_tp_t = t
        end
        return
    end

    if state ~= airui.TP_UP then return end

    local dx = (x or 0) - down_x
    local dy = (y or 0) - down_y
    local adx, ady = math.abs(dx), math.abs(dy)
    local dt = now_ms() - down_t
    if dt < 0 then dt = P.swipe_max_ms + 1 end

    if t then
        log.info("tp", "UP", x, y, "dt", math.floor(dt), "dx", dx, "dy", dy)
        last_tp_t = t
    end

    -- 1) 横向滑动（解码较重，挪出输入事件回调再执行）
    if dt <= P.swipe_max_ms and adx >= P.swipe_min_dx and adx > ady * 1.5 and not down_in_bar then
        if t then log.info("tp", "-> swipe", dx < 0 and "next" or "prev") end
        if dx < 0 then
            theme.defer(M.next)
        else
            theme.defer(M.prev)
        end
        return
    end

    -- 2) 轻触：显示 / 隐藏控制条（点在控制条上交给按钮）
    if adx <= P.tap_slop and ady <= P.tap_slop and dt <= P.tap_max_ms then
        if down_in_bar then
            if t then log.info("tp", "-> 点在控制条上，交给按钮") end
            return
        end
        if t then log.info("tp", "-> tap", bars_visible and "hide" or "show") end
        if bars_visible then hide_bars() else show_bars() end
        return
    end

    if t then log.info("tp", "-> 未命中手势") end
end

-- ==================== 构建 / 隐藏 / 销毁 ====================
--[[进入查看器
页面复用策略：
  - 在“目录页 <-> 查看器”之间来回：只 root:open()/set_hidden()，控件和帧缓冲都保留，
    这样最常见的返回再进不会触发 2.46MB 大块 churn；
  - 回首页 / 锁屏：destroy() 彻底释放（含 2.46MB），首页不会背着大图。
]]
function M.build(app, list, index)
    session = session + 1
    if type(list) ~= "table" or #list == 0 then
        log.warn("viewer", "照片列表为空，不进入查看器")
        return
    end
    M.app = app
    photos = list
    cur = index or 1
    if cur < 1 then cur = 1 end
    if cur > #photos then cur = #photos end
    hint_pending = true        -- 这次是“从目录页点进来的”，允许弹一次加载提示

    if not root then
        root = airui.container({
            parent = nil, x = 0, y = 0, w = SW, h = SH,
            color = 0x0A0A0A, radius = 0, border_width = 0,
        })

        -- 照片图层：视频/图片控件都挂在这里，永远在控制条下面
        photo_layer = airui.container({
            parent = root, x = 0, y = 0, w = SW, h = SH,
            color = 0x000000, radius = 0, border_width = 0,
        })
        photo_view.attach(photo_layer)

        -- 控制层
        overlay = airui.container({
            parent = root, x = 0, y = 0, w = SW, h = SH,
            color = 0x000000, color_opacity = 0, radius = 0, border_width = 0,
        })
        build_bars()

        -- 加载提示：放在控制层之后，永远在最上面
        loading_box = airui.container({
            parent = root, x = SW / 2 - 190, y = SH / 2 - 58, w = 380, h = 116,
            color = C.mask, color_opacity = 235, radius = 18,
            border_color = 0x5A4436, border_width = 1,
        })
        loading_label = theme.label(loading_box, 16, 26, 348, 64,
            "正在打开照片...", 20, C.on_dark, airui.TEXT_ALIGN_CENTER)
        loading_box:set_hidden(true)
    else
        cancel_auto()
        cancel_bar_timer()
        set_loading(false)
    end

    visible = true
    root:open()                 -- 取消隐藏 + 置顶（盖在目录页之上）

    refresh_auto_ui()
    update_head()
    show_bars()
    -- 从目录页点小图进来的这一次，记下时刻，用来打印“点击小图 -> 显示”的用时
    pending_t0 = now_ms()
    pending_src = "点击小图"
    request_load()
    schedule_auto()
end

--[[离开查看器但还在相册里（返回目录页）：只隐藏，保留帧缓冲]]
function M.hide()
    session = session + 1
    cancel_auto()
    cancel_bar_timer()
    set_loading(false)

    if root then root:set_hidden(true) end

    photos = nil
    want_load = false
    visible = false
    loading = false       -- 旧加载任务会因 session 变化自行退出
end

--[[彻底销毁：回首页 / 锁屏时调用，释放页面和 2.46MB 照片帧缓冲]]
function M.destroy()
    session = session + 1
    cancel_auto()
    cancel_bar_timer()

    photo_view.destroy()

    if root then
        pcall(function() root:destroy() end)
    end

    root, photo_layer, overlay = nil, nil, nil
    top_bar, bottom_bar = nil, nil
    loading_box, loading_label = nil, nil
    lb_name, lb_index, btn_auto, btn_auto2 = nil, nil, nil, nil
    photos = nil
    want_load = false
    visible = false
    loading = false
end

--[[查看器是否正在显示（app 用来决定是否把触摸交给这里）]]
function M.active()
    return visible and root ~= nil
end

return M
