--[[
@module  rs485_win
@summary 双路 RS485 测试页（UART1 / UART2 收发互测，日志实时刷新）
@version 1.0
@date    2026.10.21
@author  江访

=== 消息协议 ===
订阅: OPEN_RS485_WIN            -> 打开本页
订阅: RS485_EVENT(port, dir, data) -> 业务层收发事件（dir = "TX" / "RX"）
发布: RS485_SEND_REQ(port, data)   -> 请求业务层发送

=== 布局 ===
单页三块：
1、说明卡：接线提示 + 发送约定（UART1 发 123，UART2 发 456）；
2、通道卡 ×2（宽屏并排 / 窄屏上下堆叠）：波特率、方向脚、TX/RX 计数、发送按钮；
3、日志卡：最新记录置顶，行数按可用高度动态计算（不做滚动，避免卡片边缘出滑块）。

文字约束：不用内置字库缺失的符号，分隔统一用 "|"，箭头用 ASCII "->"。
]]

local theme = require "ui_theme"

local window_id = nil
local main_container = nil

-- 屏幕与布局
local sw, sh = 480, 800
local CARD_R = 18      -- 与 theme.card 默认圆角一致，显式传入以便算倒角内缩
local inset = 18

-- 日志与计数（模块级：窗口反复开关不清零，方便回看）
local history = {}
local history_max = 8
local log_label = nil
local counter_labels = {}
local port_state = { [1] = { tx = 0, rx = 0 }, [2] = { tx = 0, rx = 0 } }
-- 日志文本可用宽度/字号（build_ui 里按实际布局写入，用于逐行截断防换行撑破行盒）
local log_text_w, log_text_px = nil, nil

local EMPTY_LOG = "暂无收发记录，点通道卡按钮发送"

-- 端口参数（与 rs485_app 的口径一致）
local hw = ((_G.project_config or {}).hw or {}).rs485 or {}

local function port_meta(port)
    local c = (port == 1) and hw.uart1 or hw.uart2
    c = c or {}
    return {
        port = port,
        name = "UART" .. tostring(c.id or port),
        baud = c.baud or 9600,
        dir_pin = c.dir_pin or ((port == 1) and 65 or 57),
        payload = (port == 1) and "123" or "456",
    }
end

local PORTS = { port_meta(1), port_meta(2) }
local PORT_BY_NUM = { [1] = PORTS[1], [2] = PORTS[2] }

local function update_screen_size()
    sw, sh = screen_w or 480, screen_h or 800
    -- 宽屏有左栏时收窄到右侧内容区（窄屏原样返回）
    sw, sh = theme.content_fit(sw, sh)
end

--[[数据转可显示文本：纯可打印 ASCII 原样，其余转十六进制]]
local function data_to_display(data)
    if not data or #data == 0 then return "(空)" end
    for i = 1, #data do
        local b = data:byte(i)
        if b < 32 or b > 126 then
            local hex = data:toHex()
            if hex and #hex > 0 then return hex end
            return "(不可显示数据)"
        end
    end
    return data
end

--[[按可用宽度截断为单行（LVGL 的 label 会自动换行，不截断会把行盒撑破）]]
local function fit_line(text, max_w, px)
    text = tostring(text or "")
    if theme.text_width(text, px) <= max_w then return text end
    local keep = px * 3
    local cut = #text
    while cut > 1 and theme.text_width(string.sub(text, 1, cut), px) > max_w - keep do
        cut = cut - 1
    end
    -- 不要切在多字节字符中间（UTF-8 续字节 0x80~0xBF）
    while cut > 1 do
        local b = string.byte(text, cut)
        if b and b >= 0x80 and b < 0xC0 then cut = cut - 1 else break end
    end
    return string.sub(text, 1, cut) .. "..."
end

local function refresh_log()
    if not log_label then return end
    if #history == 0 then
        log_label:set_text(EMPTY_LOG)
        return
    end
    log_label:set_text(table.concat(history, "\n"))
end

local function refresh_counter(port)
    local lbl = counter_labels[port]
    local st = port_state[port]
    if not lbl or not st then return end
    lbl:set_text(string.format("TX %d   |   RX %d", st.tx, st.rx))
end

--[[追加一行日志：最新置顶，超出上限就丢最旧的]]
local function add_log(line)
    line = tostring(line or "")
    if log_text_w then line = fit_line(line, log_text_w, log_text_px) end
    table.insert(history, 1, line)
    while #history > history_max do
        table.remove(history)
    end
    refresh_log()
end

--[[业务层收发事件]]
local function on_rs485_event(port, dir, data)
    local st = port_state[port]
    local meta = PORT_BY_NUM[port]
    if not st or not meta then return end

    if dir == "TX" then
        st.tx = st.tx + 1
    elseif dir == "RX" then
        st.rx = st.rx + 1
    end
    refresh_counter(port)

    local now = os.date("%H:%M:%S") or "--:--:--"
    local action = (dir == "TX") and "发送" or "接收"
    add_log(string.format("%s  %s %s：%s", now, meta.name, action, data_to_display(data)))
end

--[[发送请求]]
local function send_req(port, data)
    if not exwin.is_active(window_id) then return end
    sys.publish("RS485_SEND_REQ", port, data)
end

--[[创建通道卡：标题 + 参数 + 计数 + 单发按钮]]
local function build_port_card(parent, x, y, w, h, meta, fs_title, fs_cap, fs_micro)
    local pad = theme.dp(12)
    local gap = theme.dp(6)
    local btn_h = math.max(36, theme.dp(36))
    local lh_title = fs_title + 3
    local lh_cap = fs_cap + 3
    local lh_micro = fs_micro + 3
    local inner_w = w - 2 * pad

    local card = theme.card(parent, { x = x, y = y, w = w, h = h })

    local cy = pad
    theme.label(card, {
        x = pad, y = cy, w = inner_w, h = lh_title,
        text = "通道" .. meta.port .. "  " .. meta.name, px_size = fs_title,
        color = theme.C.t1, align = airui.TEXT_ALIGN_LEFT,
    })
    cy = cy + lh_title

    theme.label(card, {
        x = pad, y = cy, w = inner_w, h = lh_micro,
        text = string.format("%d 8N1  |  方向脚 GPIO%d", meta.baud, meta.dir_pin),
        px_size = fs_micro, color = theme.C.t3, align = airui.TEXT_ALIGN_LEFT,
    })
    cy = cy + lh_micro

    counter_labels[meta.port] = theme.label(card, {
        x = pad, y = cy, w = inner_w, h = lh_cap,
        text = "TX 0   |   RX 0", px_size = fs_cap,
        color = theme.C.t2, align = airui.TEXT_ALIGN_LEFT,
    })
    cy = cy + lh_cap + gap

    theme.button(card, {
        x = pad, y = cy, w = inner_w, h = btn_h,
        text = meta.name .. " 发送 " .. meta.payload,
        size = fs_cap,
        on_click = function() send_req(meta.port, meta.payload) end,
    })

    refresh_counter(meta.port)
    return card
end

local function clear_all()
    history = {}
    port_state[1] = { tx = 0, rx = 0 }
    port_state[2] = { tx = 0, rx = 0 }
    refresh_counter(1)
    refresh_counter(2)
    refresh_log()
end

local function build_ui()
    update_screen_size()

    local ctx = theme.page({
        title = "RS485 测试",
        sub = "UART1 | UART2 双路收发互测",
        on_back = function() exwin.close(window_id) end,
    })
    main_container = ctx.base

    local gap = theme.dp(10)
    local small_gap = theme.dp(6)
    local fs_title = theme.fs("body")
    local fs_cap = theme.fs("caption")
    local fs_micro = theme.fs("micro")
    local lh_cap = fs_cap + 3
    local inset_px = theme.dp(CARD_R)

    -- 说明卡：接线提示 + 应答规则
    local info_h = inset_px * 2 + lh_cap * 2
    local inner_w = ctx.w - 2 * inset_px
    local info = theme.card(ctx.base, { x = ctx.x, y = ctx.y, w = ctx.w, h = info_h })

    local ly = inset_px
    theme.label(info, {
        x = inset_px, y = ly, w = inner_w, h = lh_cap,
        text = fit_line("UART1 与 UART2 需按 A-A、B-B 接线对接", inner_w, fs_cap),
        px_size = fs_cap, color = theme.C.t2, align = airui.TEXT_ALIGN_LEFT,
    })
    ly = ly + lh_cap
    theme.label(info, {
        x = inset_px, y = ly, w = inner_w, h = lh_cap,
        text = fit_line("通道1 发送 123，通道2 发送 456", inner_w, fs_cap),
        px_size = fs_cap, color = theme.C.t2, align = airui.TEXT_ALIGN_LEFT,
    })

    -- 通道卡：宽屏并排，窄屏堆叠
    local port_h = inset_px * 2 + (fs_title + 3) + (fs_micro + 3) + lh_cap + small_gap + math.max(36, theme.dp(36))
    local py = ctx.y + info_h + gap
    local wide = ctx.w >= 560

    if wide then
        local cw = math.floor((ctx.w - gap) / 2)
        build_port_card(ctx.base, ctx.x, py, cw, port_h, PORTS[1], fs_title, fs_cap, fs_micro)
        build_port_card(ctx.base, ctx.x + cw + gap, py, cw, port_h, PORTS[2], fs_title, fs_cap, fs_micro)
        py = py + port_h + gap
    else
        build_port_card(ctx.base, ctx.x, py, ctx.w, port_h, PORTS[1], fs_title, fs_cap, fs_micro)
        build_port_card(ctx.base, ctx.x, py + port_h + gap, ctx.w, port_h, PORTS[2], fs_title, fs_cap, fs_micro)
        py = py + port_h * 2 + gap * 2
    end

    -- 日志卡：吃掉剩余高度，行数按可用高度算
    local log_h = ctx.y + ctx.h - py
    if log_h < inset_px * 2 + theme.dp(24) + small_gap + lh_cap * 3 then
        log_h = inset_px * 2 + theme.dp(24) + small_gap + lh_cap * 3
    end
    local log_card = theme.card(ctx.base, { x = ctx.x, y = py, w = ctx.w, h = log_h })

    local log_w = ctx.w - 2 * inset_px
    log_text_w, log_text_px = log_w, fs_cap
    local row_h = math.max(theme.dp(24), fs_micro + 3)
    theme.section(log_card, {
        x = inset_px, y = inset_px, w = log_w - theme.dp(76), h = row_h,
        text = "收发日志（最新在上）", px_size = fs_micro, color = theme.C.t3,
    })
    theme.ghost_button(log_card, {
        x = ctx.w - inset_px - theme.dp(64), y = inset_px, w = theme.dp(64), h = row_h,
        text = "清空", size = fs_micro, on_click = clear_all,
    })

    local label_y = inset_px + row_h + small_gap
    local label_h = log_h - label_y - inset_px
    history_max = math.max(3, math.floor(label_h / lh_cap))
    while #history > history_max do table.remove(history) end

    log_label = theme.label(log_card, {
        x = inset_px, y = label_y, w = log_w, h = history_max * lh_cap,
        text = EMPTY_LOG, px_size = fs_cap,
        color = theme.C.t1, align = airui.TEXT_ALIGN_LEFT,
    })
    refresh_log()
end

local function on_create()
    counter_labels = {}
    log_label = nil
    build_ui()
    sys.subscribe("RS485_EVENT", on_rs485_event)
end

local function on_destroy()
    sys.unsubscribe("RS485_EVENT", on_rs485_event)
    if main_container then
        main_container:destroy()
        main_container = nil
    end
    counter_labels = {}
    log_label = nil
end

--[[主题切换后标记脏，等本页重新获得焦点时再重建（与 settings_win 同一套做法）]]
local theme_dirty = false
local function on_theme_changed() theme_dirty = true end
sys.subscribe("UI_THEME_CHANGED", on_theme_changed)

local function on_get_focus()
    if theme_dirty then
        theme_dirty = false
        if main_container then
            main_container:destroy()
            main_container = nil
        end
        counter_labels = {}
        log_label = nil
        build_ui()
    else
        refresh_log()
    end
end

local function on_lose_focus() end

local function open_handler()
    window_id = exwin.open({
        on_create = on_create,
        on_destroy = on_destroy,
        on_lose_focus = on_lose_focus,
        on_get_focus = on_get_focus,
    })
end

sys.subscribe("OPEN_RS485_WIN", open_handler)
