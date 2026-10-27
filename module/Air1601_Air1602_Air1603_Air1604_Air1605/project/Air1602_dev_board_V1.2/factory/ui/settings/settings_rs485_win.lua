--[[
@module  settings_rs485_win
@summary RS485 测试页（设置页入口 · UART2 + GPIO64 方向脚 + GPIO46 使能 · 固定发送 "RS485 test"）
@version 1.0
@date    2026.10.26
@author  江访
@usage
订阅: OPEN_RS485_WIN            → 打开本页
发布: RS485_OPEN_REQ / RS485_CLOSE_REQ / RS485_SEND_REQ(data)
订阅: RS485_OPEN_RESULT(ok, err, info) → 端口打开结果与端口信息
      RS485_SEND_RESULT(ok, err)       → 发送结果回执
      RS485_RX(data)                   → 收到的一帧原文

门控: features.rs485（与 settings_app 里 settings_rs485_app 的门控条件一致）

=== 页面结构 ===

  端口信息卡（串口 / 方向脚 / 波特率 / 发送内容 / 端口状态）
  发送按钮 + 清空按钮
  收发日志（最新在上，纯文本；不发 HEX、不显 HEX）

固定发送内容取 config.peripherals 里 rs485 条目的 test_data，缺省 "RS485 test"。
进页面自动打开串口，退出页面关闭，UART2 不会一直被占着。

=== 判定方式 ===

本页只做「能不能通」：点发送把固定内容推到总线上，用 PC 端的 USB-485 转换器（或
另一台设备）看是否原样收到；对端发回来的内容会显示在下方日志里。日志只存本页内存，
退出即清空。

=== DE 方向脚 ===

方向脚空闲恒为低电平（接收态），只在每一帧的发送窗口里拉高十几毫秒，万用表量不到 ——
量不到是正常现象，不是没发。要确认通信通不通，看对端有没有收到，不要靠量这个脚。
]]

local theme = require "ui_theme"

local window_id = nil
local main_container = nil

local sw, sh = 480, 800

-- 日志最多保留条数
local MAX_KEEP = 200

local entries = {}      -- { {ts=, kind="TX"|"RX"|"INFO", text=}, ... }
local log_labels = {}   -- 固定行池，只改文字不增删控件
local log_w = 0

local info_setters = {} -- 端口信息行 → 更新闭包
local status_label = nil
local test_data = "RS485 test"

-- ==================== 基础工具 ====================

local function update_screen_size()
    sw, sh = screen_w or 480, screen_h or 800
    sw, sh = theme.content_fit(sw, sh)
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
    local keep = px * 3 + px
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

-- 收到的原文转成单行可显示文本（换行压成空格，不可打印字符换成点）
local function visible_text(s)
    s = tostring(s or "")
    s = s:gsub("[\r\n\t]+", " ")
    return s:gsub("[^%g ]", ".")
end

-- ==================== 日志 ====================

local function fmt_entry(e)
    local ts = e.ts or ""
    if e.kind == "TX" then return string.format("%s 发送: %s", ts, e.text) end
    if e.kind == "RX" then return string.format("%s 接收: %s", ts, e.text) end
    return string.format("%s %s", ts, tostring(e.text or ""))
end

-- 只画可见行：最新一条贴顶（最新在上），省去滚动定位
local function render_log()
    local n = #log_labels
    local total = #entries
    for i = 1, n do
        local e = entries[total - i + 1]
        local lab = log_labels[i]
        if lab and not lab:is_destroyed() then
            if e then
                lab:set_text(fit_text(fmt_entry(e), log_w, theme.fs("caption")))
            else
                lab:set_text("")
            end
        end
    end
end

local function append_entry(kind, text)
    entries[#entries + 1] = { ts = fmt_time(), kind = kind, text = text or "" }
    while #entries > MAX_KEEP do table.remove(entries, 1) end
    render_log()
end

local function clear_log()
    entries = {}
    render_log()
end

-- ==================== 端口信息 ====================

-- 端口状态行：文案 + 语义色（成功绿 / 失败红 / 进行中灰）
local function set_status(text, color)
    if status_label and not status_label:is_destroyed() then
        status_label:set_text(text)
        status_label:set_color(color)
    end
end

local function apply_info(info)
    if type(info) ~= "table" then return end
    test_data = tostring(info.test_data or test_data)
    if info_setters.uart then info_setters.uart("UART" .. tostring(info.uart_id or 0)) end
    if info_setters.de then
        info_setters.de(info.de_pin and ("GPIO" .. tostring(info.de_pin)) or "自动")
    end
    if info_setters.baud then info_setters.baud(tostring(info.baud or 9600)) end
    if info_setters.data then info_setters.data(test_data) end
end

-- ==================== 动作 ====================

local function do_send()
    append_entry("TX", test_data)
    sys.publish("RS485_SEND_REQ", test_data)
end

-- ==================== 事件回调 ====================

local function on_open_result(ok, err, info)
    apply_info(info)
    if ok then
        set_status("已打开", theme.SEM.success)
        append_entry("INFO", "串口已打开")
    else
        set_status(tostring(err or "未打开"), theme.SEM.danger)
        append_entry("INFO", "串口未打开：" .. tostring(err or "未知原因"))
    end
end

local function on_send_result(ok, err)
    if ok then return end      -- 成功那条已经在点击时记过 TX
    append_entry("INFO", "发送失败：" .. tostring(err or "未知原因"))
end

local function on_rx(data)
    append_entry("RX", visible_text(data))
end

-- ==================== 界面 ====================

local function build_ui()
    update_screen_size()

    local ctx = theme.page({
        title = "RS485 测试",
        sub = "UART2 半双工收发自检",
        on_back = function() exwin.close(window_id) end,
    })
    main_container = ctx.base
    local pad = ctx.pad
    local w = ctx.w
    local y = ctx.y

    -- ---------- 端口信息卡 ----------
    local row_h = theme.dp(30)
    local inner_pad = theme.dp(12)
    local info_h = theme.dp(10) + theme.dp(22) + row_h * 5 + theme.dp(10) + 2
    local info_card = theme.card(main_container, { x = ctx.x, y = y, w = w, h = info_h })

    theme.section(info_card, {
        x = inner_pad, y = theme.dp(10), w = w - 2 * inner_pad - 2,
        text = "端口信息", px_size = theme.fs("micro"), color = theme.C.t3,
    })

    local fields = {
        { key = "uart", label = "串口",       value = "UART2" },
        { key = "de",   label = "方向脚(DE)", value = "GPIO64" },
        { key = "baud", label = "波特率",     value = "9600" },
        { key = "data", label = "发送内容",   value = test_data },
        { key = "stat", label = "端口状态",   value = "打开中" },
    }
    local row_w = w - 2 * inner_pad - 2
    local label_w = math.floor(w * 0.34)
    local value_w = row_w - 2 * theme.dp(12) - label_w
    local ry = theme.dp(10) + theme.dp(22)
    for i, f in ipairs(fields) do
        local _, value_label = theme.kv_row(info_card, {
            x = inner_pad, y = ry, w = row_w, h = row_h,
            label = f.label, value = f.value,
            size = "caption", label_w = label_w,
            label_color = theme.C.t2, value_color = theme.C.t1,
        })
        ry = ry + row_h
        if f.key == "stat" then
            status_label = value_label
        else
            info_setters[f.key] = function(text)
                if value_label and not value_label:is_destroyed() then
                    value_label:set_text(fit_text(text, value_w, theme.fs("caption")))
                end
            end
        end
        if i < #fields then
            theme.divider(info_card, { x = inner_pad, y = ry, w = w - 2 * inner_pad - 2 })
        end
    end

    y = y + info_h + pad

    -- ---------- 操作按钮 ----------
    local btn_h = theme.dp(40)
    local btn_gap = theme.dp(10)
    local clr_w = theme.dp(84)
    local send_w = w - clr_w - btn_gap

    local fs_btn = 13
    -- 按钮内部字号是 max(16, dp(13))，量宽必须用同一口径，否则会误截断
    local fs_btn_px = math.max(16, theme.dp(fs_btn))
    local send_text = "发送 " .. test_data
    if theme.text_width(send_text, fs_btn_px) > send_w - theme.dp(16) then
        send_text = fit_text(send_text, send_w - theme.dp(16), fs_btn_px)
    end
    theme.button(main_container, {
        x = ctx.x, y = y, w = send_w, h = btn_h,
        text = send_text, size = fs_btn,
        on_click = function() do_send() end,
    })
    local bx = ctx.x + send_w + btn_gap
    theme.ghost_button(main_container, {
        x = bx, y = y, w = clr_w, h = btn_h,
        text = "清空", size = fs_btn, fg = theme.SEM.danger, border = theme.SEM.danger,
        on_click = function() clear_log() end,
    })

    y = y + btn_h + pad

    -- ---------- 收发日志（最新在上） ----------
    local log_h = ctx.y + ctx.h - y
    if log_h < theme.dp(60) then log_h = theme.dp(60) end
    local head_h = theme.dp(26)
    local line_h = theme.fs("caption") + theme.dp(4)
    local lines = math.floor((log_h - 2 - head_h - theme.dp(6)) / line_h)
    if lines < 1 then lines = 1 end
    local card_h = head_h + lines * line_h + theme.dp(8)

    local log_card = theme.card(main_container, { x = ctx.x, y = y, w = w, h = card_h })
    theme.label(log_card, {
        x = inner_pad, y = theme.dp(4), w = w - 2 * inner_pad - 2, h = head_h,
        text = "收发日志(最新在上)", px_size = theme.fs("caption"),
        color = theme.C.t2, align = airui.TEXT_ALIGN_LEFT,
    })

    log_w = w - 2 * inner_pad - 2
    log_labels = {}
    for i = 1, lines do
        log_labels[i] = theme.label(log_card, {
            x = inner_pad, y = head_h + (i - 1) * line_h,
            w = log_w, h = line_h,
            text = "", px_size = theme.fs("caption"),
            color = theme.C.t1, align = airui.TEXT_ALIGN_LEFT,
        })
    end
end

-- ==================== 窗口生命周期 ====================

local function on_create()
    build_ui()
    sys.subscribe("RS485_OPEN_RESULT", on_open_result)
    sys.subscribe("RS485_SEND_RESULT", on_send_result)
    sys.subscribe("RS485_RX", on_rx)
    sys.publish("RS485_OPEN_REQ")
end

local function on_destroy()
    sys.unsubscribe("RS485_OPEN_RESULT", on_open_result)
    sys.unsubscribe("RS485_SEND_RESULT", on_send_result)
    sys.unsubscribe("RS485_RX", on_rx)
    -- 退出页面就释放 UART2：先退订再关，避免关串口的回执打到已销毁的控件上
    sys.publish("RS485_CLOSE_REQ")
    if main_container then main_container:destroy(); main_container = nil end
    log_labels = {}
    status_label = nil
    info_setters = {}
end

local function on_get_focus() end
local function on_lose_focus() end

local function open_handler()
    -- 与 settings_app 里 settings_rs485_app 的门控条件保持一致
    local fe = (_G.project_config or {}).features or {}
    if not fe.rs485 then
        log.warn("settings_rs485", "features.rs485 未开启，忽略打开请求")
        return
    end
    window_id = exwin.open({
        on_create = on_create,
        on_destroy = on_destroy,
        on_lose_focus = on_lose_focus,
        on_get_focus = on_get_focus,
    })
end

sys.subscribe("OPEN_RS485_WIN", open_handler)
