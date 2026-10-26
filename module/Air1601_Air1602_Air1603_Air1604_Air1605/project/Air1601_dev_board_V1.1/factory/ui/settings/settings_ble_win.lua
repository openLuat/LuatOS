--[[
@module  settings_ble_win
@summary 蓝牙(BLE)测试页（设置页入口 · Air5101S 串口模块 · 点按钮发一包测试数据）
@version 1.0
@date    2026.10.26
@author  江访
@usage
订阅: OPEN_BLE_WIN              → 打开本页
发布: BLE_OPEN_REQ / BLE_CLOSE_REQ / BLE_DISCONNECT_REQ
      BLE_SEND_REQ(data)         → 发一包；不带参数时由业务层取配置里的 test_data
订阅: BLE_OPEN_RESULT(ok, err, info) → 蓝牙打开结果与模块信息
      BLE_SEND_RESULT(ok, err, body) → 发送结果回执（body 为实际发出的文本）
      BLE_STATUS(connected)          → 手机连接 / 断开
      BLE_RX(data)                   → 收到的一包原文
      BLE_NOTE(text)                 → 附加提示

门控: features.ble（与 settings_app 里 settings_ble_app 的门控条件一致）

=== 页面结构 ===

  模块信息卡（设备名称 / 串口 / 波特率 / MAC / 固件版本 / 连接状态）
  发送按钮 + 清空按钮
  断开按钮（做完一轮连接测试，手动断开好让手机重连）
  收发日志（最新在上，纯文本；不发 HEX、不显 HEX）

固定发送内容取 config.peripherals 里 ble 条目的 test_data，缺省 "BLE test"。
进页面自动打开蓝牙（AT 模式），退出页面释放串口。

=== 判定方式 ===

手机端用任意 BLE 调试 App（nRF Connect / 蓝牙调试助手）搜索设备名（缺省 Air1601_Test），
连上后看本页「连接状态」变「已连接」；点「发送测试数据」，手机端应收到 "BLE test"；
手机端往模块写数据，本页日志里会出现「接收: ...」。收发都通即判定蓝牙正常。

=== 注意 ===

UART3 与 4G / WiFi / GNSS 共用，进本页会把串口从 4G 手里抢过来，退出页面后 4G 不会自动恢复，
要继续用 4G 联网请重启设备。
]]

local theme = require "ui_theme"

local window_id = nil
local main_container = nil

-- 日志最多保留条数
local MAX_KEEP = 200

local entries = {}      -- { {ts=, kind="TX"|"RX"|"INFO", text=}, ... }
local log_labels = {}   -- 固定行池，只改文字不增删控件
local log_w = 0

local info_setters = {} -- 模块信息行 → 更新闭包
local status_label = nil
local status_w = 0       -- 状态行可用宽度（失败原因可能很长，要截断）

-- ==================== 基础工具 ====================

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

-- 收到的原文转成单行可显示文本（换行压成空格，ASCII 控制字符换成点）
-- 只处理 ASCII 控制字符：>=0x80 的字节是 UTF-8 正文（手机发中文很常见），必须原样保留
local function visible_text(s)
    s = tostring(s or "")
    s = s:gsub("[\r\n\t]+", " ")
    return (s:gsub("[%z\1-\31\127]", "."))
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

-- ==================== 模块信息 ====================

-- 状态行：文案 + 语义色（成功绿 / 失败红 / 进行中灰）
local function set_status(text, color)
    if status_label and not status_label:is_destroyed() then
        -- 失败原因可能是一整句话，行高只有一行，超出的部分必须自己截掉
        if status_w > 0 then
            text = fit_text(text, status_w, theme.fs("caption"))
        end
        status_label:set_text(text)
        status_label:set_color(color)
    end
end

local function apply_info(info)
    if type(info) ~= "table" then return end
    if info_setters.name then info_setters.name(tostring(info.dev_name or "--")) end
    if info_setters.uart then info_setters.uart("UART" .. tostring(info.uart_id or 0)) end
    if info_setters.baud then info_setters.baud(tostring(info.baud or 9600)) end
    if info_setters.mac then info_setters.mac(tostring(info.mac or "--")) end
    if info_setters.ver then info_setters.ver(tostring(info.ver or "--")) end
    -- 发送内容不在页面上展示：判据只有「发没发出去 + 收到什么」，
    -- 实际发出去的文本由 BLE_SEND_RESULT 回执带回来写进日志，改配置不用改页面
end

local function refresh_status(connected)
    if connected then
        set_status("已连接", theme.SEM.success)
    else
        set_status("等待连接", theme.SEM.warning)
    end
end

-- ==================== 动作 ====================

-- 不带参数：发什么由 config.peripherals 里 ble 条目的 test_data 决定（缺省 "BLE test"）
local function do_send()
    sys.publish("BLE_SEND_REQ")
end

local function do_disconnect()
    sys.publish("BLE_DISCONNECT_REQ")
end

-- ==================== 事件回调 ====================

local function on_open_result(ok, err, info)
    apply_info(info)
    if ok then
        append_entry("INFO", "蓝牙已打开，等待手机连接")
        refresh_status(info and info.connected)
    else
        local reason = tostring(err or "未知原因")
        if reason == "已关闭" then
            set_status("已关闭", theme.C.t3)
            append_entry("INFO", "蓝牙已关闭")
        else
            set_status(reason, theme.SEM.danger)
            append_entry("INFO", "蓝牙未打开：" .. reason)
        end
    end
end

local function on_send_result(ok, err, body)
    if ok then
        append_entry("TX", body)
    else
        append_entry("INFO", "发送失败：" .. tostring(err or "未知原因"))
    end
end

local function on_status(connected)
    append_entry("INFO", connected and "手机已连接" or "手机已断开")
    refresh_status(connected)
end

local function on_rx(data)
    append_entry("RX", visible_text(data))
end

local function on_note(text)
    append_entry("INFO", tostring(text or ""))
end

-- ==================== 界面 ====================

local function build_ui()
    local ctx = theme.page({
        title = "蓝牙测试",
        sub = "BLE 收发自检（Air5101S）",
        on_back = function() exwin.close(window_id) end,
    })
    main_container = ctx.base
    local pad = ctx.pad
    local w = ctx.w
    local y = ctx.y

    -- ---------- 模块信息卡 ----------
    local row_h = theme.dp(30)
    local inner_pad = theme.dp(12)
    local row_n = 6
    local info_h = theme.dp(10) + theme.dp(22) + row_h * row_n + theme.dp(10) + 2
    local info_card = theme.card(main_container, { x = ctx.x, y = y, w = w, h = info_h })

    theme.section(info_card, {
        x = inner_pad, y = theme.dp(10), w = w - 2 * inner_pad - 2,
        text = "模块信息", px_size = theme.fs("micro"), color = theme.C.t3,
    })

    local fields = {
        { key = "name", label = "设备名称",   value = "--" },
        { key = "uart", label = "串口",       value = "UART3" },
        { key = "baud", label = "波特率",     value = "9600" },
        { key = "mac",  label = "MAC 地址",   value = "--" },
        { key = "ver",  label = "固件版本",   value = "--" },
        { key = "stat", label = "连接状态",   value = "打开中" },
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
            status_w = value_w
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

    -- ---------- 发送 / 清空 ----------
    local btn_h = theme.dp(40)
    local btn_gap = theme.dp(10)
    local clr_w = theme.dp(84)
    local send_w = w - clr_w - btn_gap

    local fs_btn = 13
    theme.button(main_container, {
        x = ctx.x, y = y, w = send_w, h = btn_h,
        text = "发送测试数据", size = fs_btn,
        on_click = function() do_send() end,
    })
    local bx = ctx.x + send_w + btn_gap
    theme.ghost_button(main_container, {
        x = bx, y = y, w = clr_w, h = btn_h,
        text = "清空", size = fs_btn, fg = theme.SEM.danger, border = theme.SEM.danger,
        on_click = function() clear_log() end,
    })

    y = y + btn_h + btn_gap

    -- ---------- 断开 ----------
    theme.ghost_button(main_container, {
        x = ctx.x, y = y, w = w, h = btn_h,
        text = "断开手机连接", size = fs_btn,
        fg = theme.C.t1, border = theme.C.line,
        on_click = function() do_disconnect() end,
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
    sys.subscribe("BLE_OPEN_RESULT", on_open_result)
    sys.subscribe("BLE_SEND_RESULT", on_send_result)
    sys.subscribe("BLE_STATUS", on_status)
    sys.subscribe("BLE_RX", on_rx)
    sys.subscribe("BLE_NOTE", on_note)
    sys.publish("BLE_OPEN_REQ")
end

local function on_destroy()
    sys.unsubscribe("BLE_OPEN_RESULT", on_open_result)
    sys.unsubscribe("BLE_SEND_RESULT", on_send_result)
    sys.unsubscribe("BLE_STATUS", on_status)
    sys.unsubscribe("BLE_RX", on_rx)
    sys.unsubscribe("BLE_NOTE", on_note)
    -- 退出页面就释放串口：先退订再关，避免关闭回执打到已销毁的控件上
    sys.publish("BLE_CLOSE_REQ")
    if main_container then main_container:destroy(); main_container = nil end
    log_labels = {}
    status_label = nil
    info_setters = {}
end

local function on_get_focus() end
local function on_lose_focus() end

local function open_handler()
    -- 与 settings_app 里 settings_ble_app 的门控条件保持一致
    local fe = (_G.project_config or {}).features or {}
    if not fe.ble then
        log.warn("settings_ble", "features.ble 未开启，忽略打开请求")
        return
    end
    window_id = exwin.open({
        on_create = on_create,
        on_destroy = on_destroy,
        on_lose_focus = on_lose_focus,
        on_get_focus = on_get_focus,
    })
end

sys.subscribe("OPEN_BLE_WIN", open_handler)
