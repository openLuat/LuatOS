--[[
@module  settings_can_win
@summary CAN 总线测试页（设置页入口 · Air1602 CAN2 复用 UART2 · 点按钮发一帧）
@version 1.0
@date    2026.10.26
@author  江访
@usage
订阅: OPEN_CAN_WIN                → 打开本页
发布: CAN_OPEN_REQ / CAN_CLOSE_REQ / CAN_MODE_REQ(mode)
      CAN_SEND_REQ(data)          → 发一帧；不带参数时由业务层取配置里的 test_data
订阅: CAN_OPEN_RESULT(ok, err, info)  → 打开结果与总线信息
      CAN_SEND_RESULT(ok, err, body)  → 发送结果（body 为实际写进总线的那一帧）
      CAN_MODE_RESULT(ok, err, info)  → 切模式结果
      CAN_RX(msg_id, id_type, rtr, data) → 收到的一帧
      CAN_STATE(state, text)          → 总线状态变化
      CAN_NOTE(text)                  → 附加提示

门控: 无。CAN 是内置核心库，设置页入口常驻，打开时由业务层判断 can 是否存在。

=== 页面结构 ===

  总线信息卡（通道 / 波特率 / 发送帧 / 工作模式 / 测试数据 / 总线状态）
  发送按钮 + 清空按钮
  模式切换按钮（正常 ↔ 自收自发）
  收发日志（最新在上）

固定发送内容取 config.can 的 test_data，缺省 "CAN test"（正好 8 字节）。
进页面自动打开总线，退出页面自动 deinit。

=== 判定方式 ===

自测模式（页面按钮切到「自收自发」）：点「发送测试数据」，日志里应当**同时**出现
「发送」和「接收」两行同一 ID 的帧 —— 单板即可判定收发自检通路正常，不需要对端。

正常模式：接另一台 CAN 设备（或用 CAN 分析仪），两端各 120Ω 终端电阻，波特率一致，
点「发送」后对端应收到该帧；对端发帧时本页日志出现「接收」。此时「总线状态」应为
「主动错误(正常)」，变成「被动错误 / 离线」说明总线没应答或接线有问题。

=== 注意 ===

CAN2 复用 UART2，与 RS485 测试页是同一个串口、同一组引脚，底板拨码要切到 CAN 那一路；
两页不能同时开（页面互斥，退出 RS485 页会关串口）。现有固件 can 编号是 1-based（2 = CAN2），
且 can.node 过滤有 bug，业务层不做 ID 过滤，收到什么显示什么。
]]

local theme = require "ui_theme"

local window_id = nil
local main_container = nil

-- 日志最多保留条数
local MAX_KEEP = 200

local entries = {}      -- { {ts=, kind="TX"|"RX"|"INFO", text=}, ... }
local log_labels = {}   -- 固定行池，只改文字不增删控件
local log_w = 0

local info_setters = {} -- 总线信息行 → 更新闭包
local status_label = nil
local status_w = 0       -- 状态行可用宽度（失败原因可能很长，要截断）
local mode_btn = nil     -- 模式切换按钮（文案随当前模式变）
local curr_mode = "normal"
local tx_id, tx_ext = nil, true  -- 最近一次已知的发送帧 ID / 帧类型（日志显示用）

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

--[[帧 ID 格式化：扩展帧 8 位、标准帧 3 位补零]]
local function fmt_id(msg_id, is_ext)
    local id = tonumber(msg_id) or 0
    if is_ext == 1 or is_ext == true then return string.format("0x%08X", id) end
    return string.format("0x%03X", id)
end

--[[CAN 数据展示：全可打印 ASCII 就直接显示文本（如 "CAN test"），
--含有二进制字节就显示 HEX —— CAN 帧里出现 0x00/0xFF 很常见，直接塞进标签会截断在 0 字节处。]]
local function fmt_data(data)
    if type(data) ~= "string" or #data == 0 then return "(空)" end
    local printable = true
    for i = 1, #data do
        local b = data:byte(i)
        if b < 32 or b > 126 then printable = false break end
    end
    if printable then return data end
    -- 末尾补的空格要去掉，否则标签宽度预算里白占一格；两层都套括号，避免 gsub 的第二个返回值被展开
    return ((data:gsub(".", function(ch) return string.format("%02X ", ch:byte()) end)):gsub("%s+$", ""))
end

-- ==================== 日志 ====================

local function fmt_entry(e)
    local ts = e.ts or ""
    if e.kind == "TX" then return string.format("%s 发送 %s", ts, e.text) end
    if e.kind == "RX" then return string.format("%s 接收 %s", ts, e.text) end
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

-- ==================== 总线信息 ====================

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

--[[总线状态的语义色：主动错误 / 自收自发是绿，被动错误 / 离线是红，停止 / 休眠是灰]]
local function state_color(text)
    text = tostring(text or "")
    if text:find("离线", 1, true) or text:find("被动", 1, true) then return theme.SEM.danger end
    if text:find("停止", 1, true) or text:find("休眠", 1, true) then return theme.C.t3 end
    return theme.SEM.success
end

local function sync_mode_btn()
    if not mode_btn or mode_btn:is_destroyed() then return end
    mode_btn:set_text(curr_mode == "test" and "切换到正常模式" or "切换到自测模式")
end

local function apply_info(info)
    if type(info) ~= "table" then return end
    if info.mode then
        curr_mode = info.mode
        sync_mode_btn()
    end
    if info_setters.chan then
        local chan = "CAN" .. tostring(info.can_id or 0)
        if info.uart_id and info.uart_id > 0 then
            chan = chan .. " / UART" .. tostring(info.uart_id)
        end
        info_setters.chan(chan)
    end
    if info_setters.baud then info_setters.baud(tostring(info.bitrate or 0)) end
    tx_id, tx_ext = info.tx_id, info.ext ~= false
    if info_setters.frame then
        info_setters.frame(fmt_id(info.tx_id, tx_ext) .. (tx_ext and " 扩展" or " 标准"))
    end
    if info_setters.mode then
        info_setters.mode(tostring(info.mode_text or info.mode or "--"))
    end
    if info_setters.data then info_setters.data(fmt_data(info.test_data)) end
    -- 状态行由 set_status 单独维护（要带语义色），这里不覆盖
end

local function refresh_state_line(info)
    if info and info.running then
        local t = tostring(info.state_text or "已打开")
        -- 打开成功也可能已经是「离线(BusOff)」，颜色跟着状态走
        set_status(t, state_color(t))
    elseif info and info.state_text and info.state_text ~= "--" then
        set_status(tostring(info.state_text), theme.C.t3)
    end
end

-- ==================== 动作 ====================

-- 不带参数：发什么由 config.can 的 test_data 决定（缺省 "CAN test"）
local function do_send()
    sys.publish("CAN_SEND_REQ")
end

local function do_toggle_mode()
    sys.publish("CAN_MODE_REQ", curr_mode == "test" and "normal" or "test")
end

-- ==================== 事件回调 ====================

local function on_open_result(ok, err, info)
    apply_info(info)
    if ok then
        append_entry("INFO", info and info.mode == "test"
            and "CAN 已打开（自收自发），点发送可单板自检"
            or "CAN 已打开（正常模式），请确认对端与终端电阻")
        refresh_state_line(info)
    else
        local reason = tostring(err or "未知原因")
        if reason == "已关闭" then
            set_status("已关闭", theme.C.t3)
            append_entry("INFO", "CAN 已关闭")
        else
            set_status(reason, theme.SEM.danger)
            append_entry("INFO", "CAN 未打开：" .. reason)
        end
    end
end

local function on_send_result(ok, err, body)
    if ok then
        -- 帧 ID / 帧类型用信息卡里最新的那组（发送请求不带 ID，业务层按 config 固定发）
        append_entry("TX", string.format("%s [%d] %s", fmt_id(tx_id, tx_ext), #(body or ""), fmt_data(body)))
    else
        append_entry("INFO", "发送失败：" .. tostring(err or "未知原因"))
    end
end

local function on_rx(msg_id, id_type, rtr, data)
    local text
    if rtr == true then
        text = fmt_id(msg_id, id_type) .. " [RTR]"
    else
        text = string.format("%s [%d] %s", fmt_id(msg_id, id_type), #(data or ""), fmt_data(data))
    end
    append_entry("RX", text)
end

local function on_state(_, text)
    append_entry("INFO", "总线状态：" .. tostring(text or "--"))
    set_status(tostring(text or "--"), state_color(text))
end

local function on_note(text)
    append_entry("INFO", tostring(text or ""))
end

local function on_mode_result(ok, err, info)
    apply_info(info)
    if ok then
        append_entry("INFO", "已切换到" .. (curr_mode == "test" and "自收自发模式" or "正常模式"))
        refresh_state_line(info)
    else
        append_entry("INFO", "切换模式失败：" .. tostring(err or "未知原因"))
    end
end

-- ==================== 界面 ====================

local function build_ui()
    local ctx = theme.page({
        title = "CAN测试",
        sub = "CAN 总线收发自检（CAN2 / UART2）",
        on_back = function() exwin.close(window_id) end,
    })
    main_container = ctx.base
    local pad = ctx.pad
    local w = ctx.w
    local y = ctx.y

    -- ---------- 总线信息卡 ----------
    local row_h = theme.dp(30)
    local inner_pad = theme.dp(12)
    local row_n = 6
    local info_h = theme.dp(10) + theme.dp(22) + row_h * row_n + theme.dp(10) + 2
    local info_card = theme.card(main_container, { x = ctx.x, y = y, w = w, h = info_h })

    theme.section(info_card, {
        x = inner_pad, y = theme.dp(10), w = w - 2 * inner_pad - 2,
        text = "总线信息", px_size = theme.fs("micro"), color = theme.C.t3,
    })

    local fields = {
        { key = "chan",  label = "通道",     value = "CAN2 / UART2" },
        { key = "baud",  label = "波特率",   value = "1000000" },
        { key = "frame", label = "发送帧",   value = "--" },
        { key = "mode",  label = "工作模式", value = "正常" },
        { key = "data",  label = "测试数据", value = "CAN test" },
        { key = "stat",  label = "总线状态", value = "打开中" },
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

    -- ---------- 模式切换（正常 ↔ 自收自发） ----------
    mode_btn = theme.ghost_button(main_container, {
        x = ctx.x, y = y, w = w, h = btn_h,
        text = "切换到自测模式", size = fs_btn,
        fg = theme.C.t1, border = theme.C.line,
        on_click = function() do_toggle_mode() end,
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
    sys.subscribe("CAN_OPEN_RESULT", on_open_result)
    sys.subscribe("CAN_SEND_RESULT", on_send_result)
    sys.subscribe("CAN_MODE_RESULT", on_mode_result)
    sys.subscribe("CAN_RX", on_rx)
    sys.subscribe("CAN_STATE", on_state)
    sys.subscribe("CAN_NOTE", on_note)
    sys.publish("CAN_OPEN_REQ")
end

local function on_destroy()
    sys.unsubscribe("CAN_OPEN_RESULT", on_open_result)
    sys.unsubscribe("CAN_SEND_RESULT", on_send_result)
    sys.unsubscribe("CAN_MODE_RESULT", on_mode_result)
    sys.unsubscribe("CAN_RX", on_rx)
    sys.unsubscribe("CAN_STATE", on_state)
    sys.unsubscribe("CAN_NOTE", on_note)
    -- 退出页面就关总线：先退订再关，避免关闭回执打到已销毁的控件上
    sys.publish("CAN_CLOSE_REQ")
    if main_container then main_container:destroy(); main_container = nil end
    log_labels = {}
    status_label = nil
    info_setters = {}
    mode_btn = nil
end

local function on_get_focus() end
local function on_lose_focus() end

local function open_handler()
    window_id = exwin.open({
        on_create = on_create,
        on_destroy = on_destroy,
        on_lose_focus = on_lose_focus,
        on_get_focus = on_get_focus,
    })
end

sys.subscribe("OPEN_CAN_WIN", open_handler)
