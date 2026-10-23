--[[
@module  rs485_test_win
@summary RS485 收发测试页（发送 + 收发历史记录，TabOS 深色玻璃态）
@version 1.0
@date    2026.10.23
@author  江访
@usage
订阅: OPEN_RS485_TEST_WIN(id)
发布: OTHER_FUNC_SET(id, true)         -- 进页面上电并打开串口
发布: RS485_TEST_SEND(id, data)       -- 发送原始字节串
订阅: RS485_TEST_RESULT(id, ok, err) -- 发送结果回执
订阅: PERIPH_RX(id, data)             -- 驱动收到的原始字节

历史记录只在本页内存里，退出即清空；固定行池显示末尾若干条，
行数按可用高度算，保证最新一条始终可见。

发送格式两档：
  HEX  按十六进制字节发，空格 / 冒号 / 逗号 / 连字符做分隔（"01 03 00"、"01:03:00"、"010300" 均可）
  文本 按输入的原始字符串发
历史里一律按 HEX 展示，文本档额外带一段原文便于核对。
]]

local theme = require "ui_theme"

local window_id = nil
local main_container = nil

local sw, sh = 480, 800
local pad = 15

-- 历史记录：只留最近 MAX_KEEP 条，超出丢最旧的
local MAX_KEEP = 200

local periph_id = nil
local hex_mode = true
local entries = {}      -- { {ts=, dir="TX"|"RX", hex=bool, text=string}, ... }
local tx_n, rx_n = 0, 0 -- 收发字节计数

local log_labels = {}   -- 固定行池，只改文字不增删控件
local log_w = 0
local count_label = nil
local count_w = 0
local btn_hex, btn_txt = nil, nil
local textarea = nil
local keyboard = nil

local status_info = ""  -- 端口描述，来自 OTHER_FUNC_STATUS

-- ==================== 基础工具 ====================

local function update_screen_size()
    sw, sh = screen_w or 480, screen_h or 800
    sw, sh = theme.content_fit(sw, sh)
    pad = theme.page_margin()
end

-- theme 包装对象 / airui 对象的方法都用 pcall 兜着调，控件已销毁时不至于炸
local function safe_call(obj, method, a1, a2)
    if obj == nil then return end
    local ok, fn = pcall(function() return obj[method] end)
    if not ok or type(fn) ~= "function" then return end
    pcall(fn, obj, a1, a2)
end

-- 字节串 → "01 03 00"
local function to_hex(s)
    local out = {}
    for i = 1, #s do
        out[#out + 1] = string.format("%02X", s:byte(i))
    end
    return table.concat(out, " ")
end

-- 十六进制文本 → 字节串；失败返回 nil + 原因
local function parse_hex(s)
    local clean = tostring(s or ""):gsub("[%s:,%._-]", "")
    if #clean < 2 then return nil, "内容为空" end
    if #clean % 2 ~= 0 then return nil, "HEX 位数必须为偶数" end
    if not clean:match("^%x+$") then return nil, "HEX 只允许 0-9 A-F" end
    local out = {}
    for i = 1, #clean, 2 do
        out[#out + 1] = string.char(tonumber(clean:sub(i, i + 1), 16))
    end
    return table.concat(out)
end

-- 能直接看的原文（不可打印字符换成点），用于文本档的历史附注
local function visible_text(s)
    return (tostring(s or ""):gsub("[^%g ]", "."))
end

-- ==================== 历史记录 ====================

local function fmt_entry(e)
    -- "!!" 是提示行（格式错误 / 发送失败 / 未配置），直接显示原文不转 HEX
    if e.dir == "!!" then
        return string.format("%s  !!  %s", e.ts or "", tostring(e.text or ""))
    end
    local body = string.format("%s  %s  %s", e.ts or "", e.dir or "", to_hex(e.text or ""))
    if not e.hex then
        body = body .. "  |\"" .. visible_text(e.text) .. "\""
    end
    return body
end

-- 只画可见行：最新一条贴底，省去滚动定位
local function render_log()
    local n = #log_labels
    local total = #entries
    for i = 1, n do
        local e = entries[total - n + i]
        local lab = log_labels[i]
        if lab and not lab:is_destroyed() then
            if e then
                lab:set_text(theme.fit_text(fmt_entry(e), log_w, theme.fs("caption")))
            else
                lab:set_text("")
            end
        end
    end
end

local function append_entry(dir, text, is_hex)
    entries[#entries + 1] = {
        ts = os.date("%H:%M:%S"),
        dir = dir,
        hex = is_hex and true or false,
        text = text or "",
    }
    while #entries > MAX_KEEP do table.remove(entries, 1) end
    if dir == "TX" then
        tx_n = tx_n + #(text or "")
    elseif dir == "RX" then
        rx_n = rx_n + #(text or "")
    end
    if count_label and not count_label:is_destroyed() then
        count_label:set_text(theme.fit_text(
            string.format("TX %dB | RX %dB | %d 条", tx_n, rx_n, #entries), count_w, theme.fs("micro")))
    end
    render_log()
end

local function clear_log()
    entries = {}
    tx_n, rx_n = 0, 0
    if count_label and not count_label:is_destroyed() then
        count_label:set_text(theme.fit_text("TX 0B | RX 0B | 0 条", count_w, theme.fs("micro")))
    end
    render_log()
end

-- ==================== 事件 ====================

-- 驱动收包广播（periph_rs485 的 on_receive 发布）
local function on_rx(id, data)
    if id ~= periph_id then return end
    if type(data) ~= "string" or #data == 0 then return end
    append_entry("RX", data, true)
end

-- 发送回执（业务层发布）；成功时本地已记过 TX，这里只补失败原因
local function on_send_result(id, ok, err)
    if id ~= periph_id then return end
    if ok then return end
    append_entry("!!", tostring(err or "发送失败"), true)
end

-- 端口状态（业务层发布，用于标题栏副标题）
local function on_status(list)
    if type(list) ~= "table" then return end
    for _, s in ipairs(list) do
        if s.id == periph_id then
            status_info = tostring(s.info or "")
        end
    end
end

-- ==================== 动作 ====================

-- HEX / 文本 档位切换
local function set_mode(is_hex)
    hex_mode = is_hex and true or false
    safe_call(btn_hex, "set_style", {
        bg_color = hex_mode and theme.C.amber or theme.C.surface,
        bg_opa = hex_mode and theme.OPA.fill_hi or theme.OPA.fill,
        text_color = hex_mode and theme.C.on_amber or theme.C.t1,
        border_color = hex_mode and theme.C.amber or theme.C.stroke,
    })
    safe_call(btn_txt, "set_style", {
        bg_color = (not hex_mode) and theme.C.amber or theme.C.surface,
        bg_opa = (not hex_mode) and theme.OPA.fill_hi or theme.OPA.fill,
        text_color = (not hex_mode) and theme.C.on_amber or theme.C.t1,
        border_color = (not hex_mode) and theme.C.amber or theme.C.stroke,
    })
end

local function do_send()
    if keyboard then safe_call(keyboard, "hide") end
    local raw = ""
    if textarea then raw = textarea:get_text() or "" end
    if raw == "" then return end

    local data, err
    if hex_mode then
        data, err = parse_hex(raw)
        if not data then
            append_entry("!!", err or "HEX 格式错误", true)
            return
        end
    else
        data = raw
    end

    if not periph_id then
        append_entry("!!", "本机型未配置 RS485", true)
        return
    end
    sys.publish("RS485_TEST_SEND", periph_id, data)
    append_entry("TX", data, hex_mode)
end

-- ==================== 界面 ====================

local function build_ui()
    update_screen_size()
    main_container = theme.page_bg(airui.screen, sw, sh)

    local card_w = sw - 2 * pad
    local _, th = theme.header(main_container, {
        x = pad, y = pad, w = card_w,
        title = "RS485 测试",
        sub = "发送数据并查看收发历史",
        on_back = function() exwin.close(window_id) end,
    })

    local gap = theme.dp(8)
    local y = pad + th + gap

    -- 键盘统一规范（与 wifi 密码键盘一致）：parent 挂本页根容器，w 取内容区宽
    keyboard = theme.keyboard({
        parent = main_container,
        x = 0, y = 0, w = sw, h = theme.dp(200),
        mode = "text", auto_hide = true, preview = true,
        on_commit = function(self) self:hide() end,
    })

    -- 档位切换 + 清空 + 计数
    local mode_h = theme.dp(36)
    local small_w = theme.dp(72)
    btn_hex = theme.ghost_button(main_container, {
        x = pad, y = y, w = small_w, h = mode_h,
        text = "HEX", size = 12,
        on_click = function() set_mode(true) end,
    })
    btn_txt = theme.ghost_button(main_container, {
        x = pad + small_w + gap, y = y, w = small_w, h = mode_h,
        text = "文本", size = 12,
        on_click = function() set_mode(false) end,
    })
    theme.ghost_button(main_container, {
        x = pad + 2 * (small_w + gap), y = y, w = small_w, h = mode_h,
        text = "清空", size = 12, fg = theme.SEM.danger, border = theme.SEM.danger,
        on_click = function() clear_log() end,
    })

    count_w = card_w - 3 * (small_w + gap) - theme.dp(8)
    if count_w < theme.dp(60) then count_w = theme.dp(60) end
    count_label = theme.label(main_container, {
        x = pad + 3 * (small_w + gap), y = y, w = count_w, h = mode_h,
        text = "TX 0B | RX 0B | 0 条", px_size = theme.fs("micro"),
        color = theme.C.t3, align = airui.TEXT_ALIGN_RIGHT,
    })

    -- 收发历史：固定行池，最新贴底
    y = y + mode_h + gap
    local input_h = theme.dp(46)
    local log_h = sh - y - pad - input_h - gap
    local line_h = theme.fs("caption") + theme.dp(4)
    if log_h < line_h then log_h = line_h end
    local lines = math.floor(log_h / line_h)
    if lines < 1 then lines = 1 end

    theme.box(main_container, {
        x = pad, y = y, w = card_w, h = lines * line_h,
        color = theme.C.black, opa = 255,
        radius = theme.R.md, border = theme.C.stroke, border_w = 1,
    })

    log_w = card_w - theme.dp(16)
    log_labels = {}
    for i = 1, lines do
        log_labels[i] = theme.label(main_container, {
            x = pad + theme.dp(8), y = y + (i - 1) * line_h,
            w = log_w, h = line_h,
            text = "", px_size = theme.fs("caption"),
            color = theme.C.t2, align = airui.TEXT_ALIGN_LEFT,
        })
    end

    -- 输入行：内容输入 + 发送
    y = y + lines * line_h + gap
    local send_w = theme.dp(88)
    local ta_w = card_w - send_w - gap
    textarea = theme.input({
        parent = main_container,
        x = pad, y = y, w = ta_w, h = input_h,
        text = "", placeholder = hex_mode and "01 03 00 00 00 02" or "要发送的文本",
        max_len = 256, font_size = theme.fs("body"),
        keyboard = keyboard,
    })
    theme.button(main_container, {
        x = pad + ta_w + gap, y = y, w = send_w, h = input_h,
        text = "发送",
        on_click = function() do_send() end,
    })

    set_mode(true)
end

-- ==================== 窗口生命周期 ====================

local function on_create()
    build_ui()
    sys.subscribe("PERIPH_RX", on_rx)
    sys.subscribe("RS485_TEST_RESULT", on_send_result)
    sys.subscribe("OTHER_FUNC_STATUS", on_status)
    sys.subscribe("OTHER_FUNC_CHANGED", on_status)

    -- 进页面即上电 + 打开串口，开关状态由 CHANGED 事件回填
    if periph_id then
        sys.publish("OTHER_FUNC_SET", periph_id, true)
        sys.publish("OTHER_FUNC_GET")
    end
    clear_log()
end

local function on_destroy()
    sys.unsubscribe("PERIPH_RX", on_rx)
    sys.unsubscribe("RS485_TEST_RESULT", on_send_result)
    sys.unsubscribe("OTHER_FUNC_STATUS", on_status)
    sys.unsubscribe("OTHER_FUNC_CHANGED", on_status)
    if keyboard then safe_call(keyboard, "destroy"); keyboard = nil end
    if main_container then main_container:destroy(); main_container = nil end
    log_labels = {}
    textarea = nil
    count_label = nil
    btn_hex, btn_txt = nil, nil
end

local function on_get_focus() end
local function on_lose_focus() end

local function open_handler(id)
    if id then periph_id = id end
    window_id = exwin.open({
        on_create = on_create,
        on_destroy = on_destroy,
        on_lose_focus = on_lose_focus,
        on_get_focus = on_get_focus,
    })
end

sys.subscribe("OPEN_RS485_TEST_WIN", open_handler)
