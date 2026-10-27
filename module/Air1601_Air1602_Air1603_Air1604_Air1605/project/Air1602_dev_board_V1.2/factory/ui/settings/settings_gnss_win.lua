--[[
@module  settings_gnss_win
@summary GNSS 定位页（设置页入口 · UART3 + Air510W · 经纬度/卫星/精度实时刷新）
@version 1.0
@date    2026.10.26
@author  江访
@usage
订阅: OPEN_GNSS_WIN              → 打开本页
发布: GNSS_OPEN_REQ / GNSS_CLOSE_REQ
订阅: GNSS_OPEN_RESULT(ok, err, info) → 打开结果与端口描述
      GNSS_STATUS(state)              → OPEN / FIXED / LOSE / CLOSE
      GNSS_DATA(t)                    → 每秒一帧定位快照

门控: features.gnss（与 settings_app 里 settings_gnss_app 的门控条件一致）

=== 页面结构 ===

  定位状态卡（状态 / 参与定位卫星 / 海拔 / 水平精度 / UTC 时间）
  坐标卡（纬度 / 经度 / 地面速度 / 航向）
  开始-停止定位按钮
  事件日志（最新在上）

=== 进页面就开、退页面就关 ===

和 RS485 测试页同一套生命周期：进页发 GNSS_OPEN_REQ、退页发 GNSS_CLOSE_REQ，
UART3 不会一直被 GNSS 占着（这块板子上它还接 4G 模组，由硬件切换）。
代价是每次进页面都从冷启动开始；首次定位通常 30~60 秒，AGPS 可用时更快。

=== 数值显示 ===

取不到的字段一律显示 "--"，不拿 0 冒充（0,0 正好是几内亚湾，容易被当成真实定位）。
纬度/经度按 正 = N/E、负 = S/W 显示。速度由 RMC 的「节」换算成 km/h（×1.852）。
]]

local theme = require "ui_theme"

local window_id = nil
local main_container = nil

local sw, sh = 480, 800

-- 日志最多保留条数
local MAX_KEEP = 100

local entries = {}      -- { {ts=, text=}, ... }
local log_labels = {}   -- 固定行池，只改文字不增删控件
local log_w = 0

local setters = {}      -- 字段 key → 更新闭包
local status_label = nil
local status_w = 260    -- 状态行可用宽度，建卡时按实际值宽覆盖
local act_btn = nil
local running = false
local state_now = "CLOSE"

local STATE_TEXT = {
    CLOSE = "未开启",
    OPEN  = "搜星中",
    FIXED = "已定位",
    LOSE  = "定位丢失",
}

local NUMERIC_KEYS = { "sats", "alt", "hdop", "utc", "lat", "lng", "speed", "course" }

-- ==================== 基础工具 ====================

local function update_screen_size()
    sw, sh = screen_w or 480, screen_h or 800
    sw, sh = theme.content_fit(sw, sh)
end

local function state_color(state)
    if state == "FIXED" then return theme.SEM.success end
    if state == "OPEN"  then return theme.SEM.warning end
    if state == "LOSE"  then return theme.SEM.danger end
    return theme.C.t2
end

-- 时间戳 HH:MM:SS；无 RTC / os.date 不可用时退回空串
local function fmt_time()
    local ok, s = pcall(os.date, "%H:%M:%S")
    if ok and type(s) == "string" then return s end
    return "--:--:--"
end

--[[单行文本截断：超宽截到预算内并补 ASCII "..."
不用省略号 U+2026：内置 hzfont 没有这个字形，会渲染成方框。]]
local function fit_text(text, w, px)
    text = tostring(text or "")
    if text == "" then return "--" end
    if theme.text_width(text, px) <= w then return text end
    -- "..." 三个 ASCII 字符的宽度（0.55 x 字号 x 3），再留 2px 余量
    local keep = math.floor(px * 0.55 * 3) + 2
    local cut = #text
    while cut > 1 and theme.text_width(string.sub(text, 1, cut), px) > w - keep do
        cut = cut - 1
    end
    -- 不要切在多字节字符中间（UTF-8 续字节 0x80~0xBF）
    while cut > 1 do
        local b = string.byte(text, cut)
        if b and b >= 0x80 and b < 0xC0 then cut = cut - 1 else break end
    end
    return string.sub(text, 1, cut) .. "..."
end

-- 整数型数值（卫星数）：取不到显示 "--"，不用 %d 直接打浮点（Lua 5.3 会报错）
local function fmt_int(v, unit)
    v = tonumber(v)
    if not v then return "--" end
    local s = string.format("%d", math.floor(v))
    if unit then s = s .. " " .. unit end
    return s
end

-- 浮点型数值：pattern 由调用方给，unit 追加在末尾
local function fmt_float(v, pattern, unit)
    v = tonumber(v)
    if not v then return "--" end
    local s = string.format(pattern, v)
    if unit then s = s .. " " .. unit end
    return s
end

-- 经纬度：正值标 N/E，负值标 S/W（RMC 用正负号表示半球）
local function fmt_coord(v, pos, neg)
    v = tonumber(v)
    if not v then return "--" end
    return string.format("%.6f %s", math.abs(v), (v >= 0) and pos or neg)
end

-- ==================== 日志 ====================

local function render_log()
    local n = #log_labels
    local total = #entries
    for i = 1, n do
        local e = entries[total - i + 1]
        local lab = log_labels[i]
        if lab and not lab:is_destroyed() then
            if e then
                lab:set_text(fit_text(string.format("%s %s", e.ts or "", e.text or ""),
                                      log_w, theme.fs("caption")))
            else
                lab:set_text("")
            end
        end
    end
end

local function append_entry(text)
    entries[#entries + 1] = { ts = fmt_time(), text = tostring(text or "") }
    while #entries > MAX_KEEP do table.remove(entries, 1) end
    render_log()
end

-- ==================== 状态与数值 ====================

local function set_status(text, color)
    if status_label and not status_label:is_destroyed() then
        status_label:set_text(fit_text(text, status_w, theme.fs("caption")))
        status_label:set_color(color)
    end
end

local function set_value(key, text)
    local f = setters[key]
    if f then f(text) end
end

local function clear_values()
    for i = 1, #NUMERIC_KEYS do
        set_value(NUMERIC_KEYS[i], "--")
    end
end

local function refresh_btn()
    if act_btn then
        pcall(act_btn.set_text, act_btn, running and "停止定位" or "开始定位")
    end
end

-- ==================== 事件回调 ====================

local function on_open_result(ok, err)
    if ok then
        running = true
        set_status(STATE_TEXT[state_now] or "搜星中", state_color(state_now))
        append_entry("定位已打开")
    else
        running = false
        set_status(tostring(err or "打开失败"), theme.SEM.danger)
        append_entry("打开失败：" .. tostring(err or "未知原因"))
    end
    refresh_btn()
end

local function on_status(state)
    if type(state) ~= "string" then return end
    state_now = state
    set_status(STATE_TEXT[state] or state, state_color(state))
    append_entry("状态：" .. (STATE_TEXT[state] or state))
    if state == "CLOSE" then
        running = false
        refresh_btn()
        clear_values()
    elseif not running then
        --[[OPEN / FIXED / LOSE 都意味着定位已经在跑，按钮必须同步成「停止定位」。

        不能只靠 GNSS_OPEN_RESULT：它和 GNSS_STATUS 是两条独立消息，谁先到不确定；
        而 on_open_result 里 append_entry 若中途出错，后面的 refresh_btn 就整段跳过，
        于是出现「状态已搜星中、按钮还写开始定位」的错位。]]
        running = true
        refresh_btn()
    end
end

local function on_data(t)
    if type(t) ~= "table" then return end
    set_value("sats",   fmt_int(t.sats, "颗"))
    set_value("alt",    fmt_float(t.alt, "%.1f", "m"))
    set_value("hdop",   fmt_float(t.hdop, "%.2f"))
    set_value("utc",    t.utc or "--")
    set_value("lat",    fmt_coord(t.lat, "N", "S"))
    set_value("lng",    fmt_coord(t.lng, "E", "W"))
    -- RMC 的 speed 单位是「节」，1 节 = 1.852 km/h
    set_value("speed",  fmt_float(t.speed and t.speed * 1.852 or nil, "%.2f", "km/h"))
    set_value("course", fmt_float(t.course, "%.1f"))
end

-- app 层的诊断提示（例如 6 秒收不到 NMEA）
local function on_note(text)
    append_entry(tostring(text or ""))
end

-- ==================== 界面 ====================

-- 标题栏副标题：直接从 config 读，打开页面时就有值，不必等 OPEN_RESULT
local function port_sub()
    local list = (_G.project_config or {}).peripherals
    local p = nil
    if type(list) == "table" then
        for _, it in ipairs(list) do
            if it and it.type == "gnss" then
                p = it
                break
            end
        end
    end
    p = p or {}
    local mode = (p.gnssmode == 2) and "单北斗" or "全定位"
    return string.format("UART%s %s %s", tostring(p.uart_id or 3),
                         tostring(p.baud or 115200), mode)
end

--[[一张信息卡：字段表 -> 行，返回卡高；key="stat" 的行接成状态行（带语义色）]]
local function build_kv_card(parent, x, y, w, title, fields)
    local row_h = theme.dp(30)
    local inner_pad = theme.dp(12)
    local card_h = theme.dp(10) + theme.dp(22) + row_h * #fields + theme.dp(10) + 2

    local card = theme.card(parent, { x = x, y = y, w = w, h = card_h })
    theme.section(card, {
        x = inner_pad, y = theme.dp(10), w = w - 2 * inner_pad - 2,
        text = title, px_size = theme.fs("micro"), color = theme.C.t3,
    })

    local row_w = w - 2 * inner_pad - 2
    local label_w = math.floor(w * 0.34)
    local value_w = row_w - 2 * theme.dp(12) - label_w
    local ry = theme.dp(10) + theme.dp(22)
    for i, f in ipairs(fields) do
        local _, value_label = theme.kv_row(card, {
            x = inner_pad, y = ry, w = row_w, h = row_h,
            label = f.label, value = f.value,
            size = "caption", label_w = label_w,
            label_color = theme.C.t2, value_color = theme.C.t1,
        })
        ry = ry + row_h
        if f.key == "stat" then
            status_label = value_label
            status_w = value_w
        else
            setters[f.key] = function(text)
                if value_label and not value_label:is_destroyed() then
                    value_label:set_text(fit_text(text, value_w, theme.fs("caption")))
                end
            end
        end
        if i < #fields then
            theme.divider(card, { x = inner_pad, y = ry, w = row_w })
        end
    end
    return card_h
end

local function build_ui()
    update_screen_size()

    local ctx = theme.page({
        title = "GNSS 定位",
        sub = port_sub(),
        on_back = function() exwin.close(window_id) end,
    })
    main_container = ctx.base
    local pad = ctx.pad
    local w = ctx.w
    local y = ctx.y

    -- ---------- 模式说明（标题下方第一条） ----------
    --[[当前走 exgnss.DEFAULT（应用模式 1），语义是「一直开着，除非自己手动关」：
    进页面自动 open，退出页面 on_destroy 才发 CLOSE_REQ。不像 TIMERORSUC/TIMER 那样
    定位成功或超时会自己关，所以必须把「要手动关」这件事写在页面上，否则用户会以为
    定位成功后页面会自己停。label 是自动换行的，高度按估算行数预留，避免文字被裁。]]
    local note_fs = theme.fs("caption")
    local note_text = "常开模式（exgnss.DEFAULT）：进页面自动开启并持续定位，"
                   .. "需手动点「停止定位」或退出本页才会关闭。"
    local note_h = theme.text_lines(note_text, w, note_fs) * (note_fs + 3)
    theme.label(main_container, {
        x = ctx.x, y = y, w = w, h = note_h,
        text = note_text, px_size = note_fs,
        color = theme.C.t3, align = airui.TEXT_ALIGN_LEFT,
    })
    y = y + note_h + theme.dp(6)

    -- ---------- 定位状态卡 ----------
    y = y + build_kv_card(main_container, ctx.x, y, w, "定位状态", {
        { key = "stat", label = "定位状态",      value = STATE_TEXT[state_now] or "未开启" },
        { key = "sats", label = "参与定位卫星",  value = "--" },
        { key = "alt",  label = "海拔",          value = "--" },
        { key = "hdop", label = "水平精度(HDOP)", value = "--" },
        { key = "utc",  label = "UTC 时间",      value = "--" },
    }) + pad

    -- ---------- 坐标卡 ----------
    y = y + build_kv_card(main_container, ctx.x, y, w, "坐标", {
        { key = "lat",    label = "纬度",      value = "--" },
        { key = "lng",    label = "经度",      value = "--" },
        { key = "speed",  label = "地面速度",  value = "--" },
        { key = "course", label = "航向",      value = "--" },
    }) + pad

    -- ---------- 开始 / 停止 ----------
    local btn_h = theme.dp(40)
    act_btn = theme.button(main_container, {
        x = ctx.x, y = y, w = w, h = btn_h,
        text = running and "停止定位" or "开始定位", size = 13,
        on_click = function()
            if running then
                sys.publish("GNSS_CLOSE_REQ")
            else
                set_status("打开中", theme.SEM.info)
                sys.publish("GNSS_OPEN_REQ")
            end
        end,
    })
    y = y + btn_h + pad

    -- ---------- 事件日志（最新在上） ----------
    local log_h = ctx.y + ctx.h - y
    if log_h < theme.dp(50) then log_h = theme.dp(50) end
    local head_h = theme.dp(26)
    local line_h = theme.fs("caption") + theme.dp(4)
    local lines = math.floor((log_h - 2 - head_h - theme.dp(6)) / line_h)
    if lines < 1 then lines = 1 end
    local card_h = head_h + lines * line_h + theme.dp(8)

    local log_card = theme.card(main_container, { x = ctx.x, y = y, w = w, h = card_h })
    theme.label(log_card, {
        x = theme.dp(12), y = theme.dp(4), w = w - 2 * theme.dp(12) - 2, h = head_h,
        text = "事件日志(最新在上)", px_size = theme.fs("caption"),
        color = theme.C.t2, align = airui.TEXT_ALIGN_LEFT,
    })

    log_w = w - 2 * theme.dp(12) - 2
    log_labels = {}
    for i = 1, lines do
        log_labels[i] = theme.label(log_card, {
            x = theme.dp(12), y = head_h + (i - 1) * line_h,
            w = log_w, h = line_h,
            text = "", px_size = theme.fs("caption"),
            color = theme.C.t1, align = airui.TEXT_ALIGN_LEFT,
        })
    end
end

-- ==================== 窗口生命周期 ====================

local function on_create()
    -- 每次进页面都是新一轮：状态回到未开启，按钮回到「开始定位」
    state_now = "CLOSE"
    running = false
    build_ui()
    sys.subscribe("GNSS_OPEN_RESULT", on_open_result)
    sys.subscribe("GNSS_STATUS", on_status)
    sys.subscribe("GNSS_DATA", on_data)
    sys.subscribe("GNSS_NOTE", on_note)
    append_entry("正在打开定位...")
    sys.publish("GNSS_OPEN_REQ")
end

local function on_destroy()
    sys.unsubscribe("GNSS_OPEN_RESULT", on_open_result)
    sys.unsubscribe("GNSS_STATUS", on_status)
    sys.unsubscribe("GNSS_DATA", on_data)
    sys.unsubscribe("GNSS_NOTE", on_note)
    -- 退出页面就释放 UART3：先退订再关，避免关闭回执打到已销毁的控件上
    sys.publish("GNSS_CLOSE_REQ")
    if main_container then main_container:destroy(); main_container = nil end
    -- 日志只存本页内存，退出即清空；下次进来是新的一轮定位记录
    entries = {}
    log_labels = {}
    status_label = nil
    act_btn = nil
    setters = {}
    running = false
end

local function on_get_focus() end
local function on_lose_focus() end

local function open_handler()
    -- 与 settings_app 里 settings_gnss_app 的门控条件保持一致
    local fe = (_G.project_config or {}).features or {}
    if not fe.gnss then
        log.warn("settings_gnss", "features.gnss 未开启，忽略打开请求")
        return
    end
    window_id = exwin.open({
        on_create = on_create,
        on_destroy = on_destroy,
        on_lose_focus = on_lose_focus,
        on_get_focus = on_get_focus,
    })
end

sys.subscribe("OPEN_GNSS_WIN", open_handler)
