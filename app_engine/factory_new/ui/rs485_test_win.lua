--[[
@module  rs485_test_win
@summary RS485 多端口交叉收发测试页（端口发送按钮 + 收发与判定日志）
@version 2.0
@date    2026.10.23
@author  江访
@usage
订阅: OPEN_RS485_TEST_WIN(id)          -- id 只是入口来源，页面列出全部 RS485 端口
发布: OTHER_FUNC_SET(id, true)         -- 进页面把每个端口都上电并打开串口
发布: OTHER_FUNC_GET                   -- 拉一次端口打开状态
发布: RS485_TEST_SEND(id, data)        -- 发送原始字节串
订阅: RS485_TEST_RESULT(id, ok, err)   -- 发送结果回执
订阅: PERIPH_RX(id, data)              -- 驱动收到的原始字节
订阅: OTHER_FUNC_STATUS / OTHER_FUNC_CHANGED(list) -- 端口打开状态
订阅: OTHER_FUNC_SET_RESULT(id, ok, err)  -- 端口打开失败记进日志

页面按 config.peripherals 里 type = "rs485" 的条目逐个列端口，每路一个发送按钮，
按钮文案就是「发送 + 该路测试数据」（485 1 → 发送123，485 2 → 发送456）。
测试数据取条目的 test_data，缺省按端口序号生成 123 / 456 / 789 / 012 …。

交叉互连测试要求两个端口同时在线，所以进页面把所有端口一起上电打开，
不按入口行只开一路。

日志按时间顺序列出各端口的 TX / RX，并对每次发送做交叉判定：
  [OK] A 端口发出的数据被 B 端口收到 → 这组交叉线通
  [NG] 3 秒内没有任何其它端口收到 → 这组交叉线不通
只算其它端口收到，本口回环不计通过（交叉互连测的就是跨口）。

接线约定：485 1A 接 485 2A，485 1B 接 485 2B，两路交叉互连后互发互收。

历史记录只在本页内存里，退出即清空；固定行池显示末尾若干条，
行数按可用高度算，保证最新一条始终可见。
]]

local theme = require "ui_theme"

local window_id = nil
local main_container = nil

local sw, sh = 480, 800
local pad = 15

-- 历史记录：只留最近 MAX_KEEP 条，超出丢最旧的
local MAX_KEEP = 200
-- 未判定发送的扫描间隔与超时：扫描数 = 超时 / 间隔
local SCAN_INTERVAL = 500
local MATCH_TIMEOUT = 3000
local MATCH_SCANS = math.ceil(MATCH_TIMEOUT / SCAN_INTERVAL)

local ports = {}   -- { {id=, name=, data=, info=, btn=, ...}, ... }
local port_of = {} -- id → ports 里的那一项
-- 未判定的发送：{ {id=, data=, waited=, self_rx=bool}, ... }
-- waited 数的是扫描次数而不是毫秒，超时口径与系统时钟无关（时钟跳变不会误判）
local pending = {}

local entries = {}      -- { {ts=, dir="TX"|"RX"|"OK"|"NG", id=端口 id, text=}, ... }
local tx_n, rx_n = 0, 0 -- 收发字节计数
local ok_n, ng_n = 0, 0 -- 判定计数

local log_labels = {} -- 固定行池，只改文字不增删控件
local log_w = 0
local count_label = nil
local count_w = 0
local match_timer = nil

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

-- 能直接看的原文（不可打印字符换成点）
local function visible_text(s)
    return (tostring(s or ""):gsub("[^%g ]", "."))
end

-- 载荷展示：可打印短串给原文 + HEX，否则只给 HEX
local function fmt_payload(s)
    s = s or ""
    if #s == 0 then return "(空)" end
    local hex = to_hex(s)
    if s:match("^[%g ]+$") and #s <= 24 then
        return string.format('"%s" = %s', s, hex)
    end
    return hex
end

-- 测试数据：条目里写了 test_data 就用它，否则按端口序号生成 123 / 456 / 789 / 012 …
local function default_test_data(idx)
    local d = {}
    for k = 0, 2 do
        d[#d + 1] = tostring(((idx - 1) * 3 + k + 1) % 10)
    end
    return table.concat(d)
end

-- ==================== 历史记录 ====================

local function fmt_entry(e)
    if e.dir == "OK" or e.dir == "NG" then
        return string.format("%s [%s] %s", e.ts or "", e.dir, tostring(e.text or ""))
    end
    return string.format("%s %s %s  %s", e.ts or "", e.dir or "", e.id or "",
                          fmt_payload(e.text))
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

local function update_count()
    if count_label and not count_label:is_destroyed() then
        count_label:set_text(theme.fit_text(
            string.format("TX %dB | RX %dB | 通过 %d | 未通过 %d", tx_n, rx_n, ok_n, ng_n),
            count_w, theme.fs("micro")))
    end
end

local function append_entry(dir, id, text)
    entries[#entries + 1] = {
        ts = os.date("%H:%M:%S"),
        dir = dir,
        id = id,
        text = text or "",
    }
    while #entries > MAX_KEEP do table.remove(entries, 1) end
    if dir == "TX" then
        tx_n = tx_n + #(text or "")
    elseif dir == "RX" then
        rx_n = rx_n + #(text or "")
    end
    update_count()
    render_log()
end

local function clear_log()
    entries = {}
    tx_n, rx_n = 0, 0
    ok_n, ng_n = 0, 0
    pending = {}
    update_count()
    render_log()
end

-- ==================== 交叉判定 ====================

-- 摘掉一条未判定的发送
local function drop_pending(idx)
    table.remove(pending, idx)
end

-- 找同内容、但由其它端口发出的未判定发送，找到即判为交叉通过
local function find_cross(data, from_id)
    for i = 1, #pending do
        local p = pending[i]
        if p.data == data and p.id ~= from_id then return i end
    end
    return nil
end

-- 标记本口回环（超时结算时用来区分「只收到自己的」和「根本没收到」）
local function mark_self_rx(data, from_id)
    for i = 1, #pending do
        local p = pending[i]
        if p.data == data and p.id == from_id then
            p.self_rx = true
            return
        end
    end
end

-- 每 SCAN_INTERVAL 扫一次：超时仍未被其它端口收到的发送结算成 [NG]
local function scan_timeout()
    for i = #pending, 1, -1 do
        local p = pending[i]
        p.waited = (p.waited or 0) + 1
        if p.waited >= MATCH_SCANS then
            drop_pending(i)
            ng_n = ng_n + 1
            if p.self_rx then
                append_entry("NG", p.id,
                    string.format("%s 只收到本口回环，对端未收到 \"%s\"", p.id, visible_text(p.data)))
            else
                append_entry("NG", p.id,
                    string.format("%s 的 \"%s\" 对端未收到", p.id, visible_text(p.data)))
            end
        end
    end
end

local function stop_match_timer()
    if match_timer then
        pcall(sys.timerStop, match_timer)
        match_timer = nil
    end
end

-- ==================== 事件 ====================

-- 驱动收包广播（periph_rs485 的 on_receive 发布）
local function on_rx(id, data)
    if not port_of[id] then return end
    if type(data) ~= "string" or #data == 0 then return end
    append_entry("RX", id, data)

    -- 先找跨口匹配：交叉互连要的就是 A 发 B 收
    local i = find_cross(data, id)
    if i then
        local p = pending[i]
        drop_pending(i)
        ok_n = ok_n + 1
        append_entry("OK", id,
            string.format("%s 收到 %s 的 \"%s\"，交叉线通过", id, p.id, visible_text(data)))
        return
    end
    mark_self_rx(data, id)
end

-- 发送回执；成功时本地已记过 TX，这里只处理失败与本口回环
local function on_send_result(id, ok, err)
    if not port_of[id] then return end
    if ok then return end
    -- 失败的那条发送不会再有应答，直接摘掉，免得超时再报一次未通过
    for i = #pending, 1, -1 do
        if pending[i].id == id then
            drop_pending(i)
            break
        end
    end
    ng_n = ng_n + 1
    append_entry("NG", id, string.format("%s 发送失败：%s", id, tostring(err or "未知原因")))
end

-- 端口状态回填（打开 / 未打开 + 串口描述）
local function on_status(list)
    if type(list) ~= "table" then return end
    for _, s in ipairs(list) do
        local p = s and port_of[s.id]
        if p and p.info_label and not p.info_label:is_destroyed() then
            local state = s.enabled and "已打开" or "未打开"
            safe_call(p.info_label, "set_text",
                theme.fit_text(state .. " | " .. p.info, p.info_w, theme.fs("micro")))
        end
    end
end

-- 端口打开失败（进页面会把各路都打开，打不开要看得见）
local function on_set_result(id, ok, err)
    if not port_of[id] or ok then return end
    ng_n = ng_n + 1
    append_entry("NG", id, string.format("%s 打开失败：%s", id, tostring(err or "未知原因")))
end

-- ==================== 动作 ====================

-- 点某一路的发送按钮
local function do_send(p)
    if not p then return end
    sys.publish("RS485_TEST_SEND", p.id, p.data)
    append_entry("TX", p.id, p.data)
    pending[#pending + 1] = {
        id = p.id,
        data = p.data,
        waited = 0,
        self_rx = false,
    }
end

-- ==================== 端口清单 ====================

-- 从 config.peripherals 取全部 rs485 条目，保持声明顺序
local function collect_ports()
    ports = {}
    port_of = {}
    local list = _G.project_config and _G.project_config.peripherals
    if type(list) ~= "table" then return end

    local seen = {}
    for i, p in ipairs(list) do
        if p and p.type == "rs485" and p.id then
            if seen[p.id] then
                log.warn("rs485_test_win", "外设 id 重复，跳过", p.id)
            else
                seen[p.id] = true
                local idx = #ports + 1
                local item = {
                    id = p.id,
                    name = p.name or p.id,
                    data = tostring(p.test_data or default_test_data(idx)),
                    uart_id = p.uart_id or 0,
                    baud = p.baud or 9600,
                }
                local de = p.de_pin and ("DE:GPIO" .. tostring(p.de_pin)) or "DE:自动"
                -- 分隔符用 ASCII 的 "|" 而不是 "·"(U+00B7)：内置字库不含 U+00B7
                item.info = string.format("UART%d | %s | %d", item.uart_id, de, item.baud)
                ports[idx] = item
                port_of[item.id] = item
            end
        elseif p and p.type == "rs485" then
            log.warn("rs485_test_win", "外设缺 id，跳过", "#" .. i)
        end
    end
end

-- ==================== 界面 ====================

local function build_ui()
    update_screen_size()
    main_container = theme.page_bg(airui.screen, sw, sh)

    local card_w = sw - 2 * pad
    local _, th = theme.header(main_container, {
        x = pad, y = pad, w = card_w,
        title = "RS485 收发测试",
        sub = "485 1A-2A / 1B-2B 交叉互连，点按钮发送",
        on_back = function() exwin.close(window_id) end,
    })

    local gap = theme.dp(8)
    local y = pad + th + gap

    -- 端口区：每路一行，行内左边名称与串口描述、右边发送按钮
    local row_h = theme.dp(52)
    local n = #ports
    if n == 0 then
        theme.box(main_container, {
            x = pad, y = y, w = card_w, h = row_h,
            color = theme.C.black, opa = 0,
        })
        theme.label(main_container, {
            x = pad + theme.dp(12), y = y, w = card_w - theme.dp(24), h = row_h,
            text = "本机型未配置 RS485 端口", px_size = theme.fs("body"),
            color = theme.C.t2, align = airui.TEXT_ALIGN_LEFT,
        })
        y = y + row_h + gap
    else
        local bw = 1
        local inner_w = card_w - 2 * bw - theme.dp(16)
        local card = theme.card(main_container, {
            x = pad, y = y, w = card_w, h = n * row_h + 2 * bw,
            border_w = bw,
        })
        y = y + n * row_h + 2 * bw + gap

        local fs_btn = math.max(16, theme.dp(13)) -- 与 theme.button 内部字号同口径
        for i, p in ipairs(ports) do
            -- 子控件坐标原点是卡片内容区（已扣掉描边），这里不再按 bw 内缩
            local ry = (i - 1) * row_h

            local btn_text = "发送" .. p.data
            local btn_w = theme.text_width(btn_text, fs_btn) + theme.dp(28)
            local name_w = inner_w - btn_w - theme.dp(12)
            if name_w < theme.dp(60) then name_w = theme.dp(60) end

            local name_h = theme.fs("body") + theme.dp(4)
            theme.label(card, {
                x = theme.dp(8), y = ry + theme.dp(6), w = name_w, h = name_h,
                text = p.name, px_size = theme.fs("body"),
                color = theme.C.t1, align = airui.TEXT_ALIGN_LEFT,
            })
            p.info_w = name_w
            p.info_label = theme.label(card, {
                x = theme.dp(8), y = ry + theme.dp(6) + name_h, w = name_w,
                h = theme.fs("micro") + theme.dp(4),
                text = p.info, px_size = theme.fs("micro"),
                color = theme.C.t3, align = airui.TEXT_ALIGN_LEFT,
            })

            p.btn = theme.button(card, {
                x = inner_w - btn_w + theme.dp(8), y = ry + math.floor((row_h - theme.dp(34)) / 2),
                w = btn_w, h = theme.dp(34),
                text = btn_text, size = 13,
                on_click = function() do_send(p) end,
            })

            if i < n then
                theme.box(card, {
                    x = theme.dp(8), y = ry + row_h - 1,
                    w = inner_w, h = 1,
                    color = theme.C.stroke, opa = 255,
                })
            end
        end
    end

    -- 清空 + 计数
    local mode_h = theme.dp(36)
    local small_w = theme.dp(72)
    theme.ghost_button(main_container, {
        x = pad, y = y, w = small_w, h = mode_h,
        text = "清空", size = 12, fg = theme.SEM.danger, border = theme.SEM.danger,
        on_click = function() clear_log() end,
    })
    count_w = card_w - small_w - gap
    count_label = theme.label(main_container, {
        x = pad + small_w + gap, y = y, w = count_w, h = mode_h,
        text = "TX 0B | RX 0B | 通过 0 | 未通过 0", px_size = theme.fs("micro"),
        color = theme.C.t3, align = airui.TEXT_ALIGN_RIGHT,
    })
    y = y + mode_h + gap

    -- 收发日志：固定行池，最新贴底
    local log_h = sh - y - pad
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

    update_count()
end

-- ==================== 窗口生命周期 ====================

local function on_create()
    collect_ports()
    build_ui()
    sys.subscribe("PERIPH_RX", on_rx)
    sys.subscribe("RS485_TEST_RESULT", on_send_result)
    sys.subscribe("OTHER_FUNC_SET_RESULT", on_set_result)
    sys.subscribe("OTHER_FUNC_STATUS", on_status)
    sys.subscribe("OTHER_FUNC_CHANGED", on_status)

    -- 交叉互连测试要求各路同时在线：进页面把所有端口一起上电并打开串口
    for _, p in ipairs(ports) do
        sys.publish("OTHER_FUNC_SET", p.id, true)
    end
    sys.publish("OTHER_FUNC_GET")
    clear_log()
    stop_match_timer()
    match_timer = sys.timerLoopStart(scan_timeout, SCAN_INTERVAL)
end

local function on_destroy()
    stop_match_timer()
    sys.unsubscribe("PERIPH_RX", on_rx)
    sys.unsubscribe("RS485_TEST_RESULT", on_send_result)
    sys.unsubscribe("OTHER_FUNC_SET_RESULT", on_set_result)
    sys.unsubscribe("OTHER_FUNC_STATUS", on_status)
    sys.unsubscribe("OTHER_FUNC_CHANGED", on_status)
    if main_container then main_container:destroy(); main_container = nil end
    log_labels = {}
    count_label = nil
    ports = {}
    port_of = {}
    pending = {}
end

local function on_get_focus() end
local function on_lose_focus() end

-- 入口事件带的 id 只说明是从哪一行进来的，页面固定列出全部端口，不按 id 只开一路
local function open_handler()
    window_id = exwin.open({
        on_create = on_create,
        on_destroy = on_destroy,
        on_lose_focus = on_lose_focus,
        on_get_focus = on_get_focus,
    })
end

sys.subscribe("OPEN_RS485_TEST_WIN", open_handler)
