--[[
@module  rs485_test_win
@summary RS485 多路收发测试页（通道按钮区 + 统一收发日志）
@version 3.4
@date    2026.10.24
@author  江访
@usage
订阅: OPEN_RS485_TEST_WIN(id)          -- id 只是入口来源，页面列出全部 RS485 端口
发布: OTHER_FUNC_SET(id, true)         -- 上电并打开串口（手动初始化的路由按钮触发）
发布: OTHER_FUNC_GET                   -- 拉一次端口打开状态
发布: RS485_TEST_SEND(id, data)        -- 发送原始字节串
订阅: RS485_TEST_RESULT(id, ok, err)   -- 发送结果回执
发布: RS485_DE_HOLD(ms)                -- 方向脚自检，请求把 DE 拉高 ms 毫秒再回接收态
订阅: RS485_DE_HOLD_RESULT(ok, used, pins, bad) -- 自检结果：实际保持毫秒 / 拉高的脚 / 回读不到位的脚
订阅: PERIPH_RX(id, data)              -- 驱动收到的原始字节
订阅: OTHER_FUNC_STATUS / OTHER_FUNC_CHANGED(list) -- 端口打开状态
订阅: OTHER_FUNC_SET_RESULT(id, ok, err)  -- 打开结果，成功后补发排队中的发送

页面分上下两段：
  上方  通道按钮区：每路 485 一张通道卡，卡内自上而下是「通道号 + 类型」、串口信息、
        收发计数、发送按钮；一排放两张，有几路排几排
  下方  统一收发日志（最新在上）+ 右上角「DE 自检」「清空」，每路日志都带自己的通道号

每路的测试数据取 config.peripherals 条目的 test_data，缺省按通道序号生成
123 / 456 / 789 / 012 …，各路不同，交叉互连时一眼认出是谁发的。
按钮文案即「UARTn 发送 <该路测试数据>」。

初始化策略：进页面只自动初始化未标 manual_init 的端口；标了 manual_init 的路
（如挂在 UART1 上的非隔离 485）只给按钮，点它的按钮才上电打开串口并发送，
打开成功后补发这一帧。这条约定写在 config 的 manual_init 字段说明里。

日志判定（板上两路及以上、且存在跨串口的通道对时才判）：
  [OK] A 路发出的数据被 B 路收到，且 A、B 分属不同串口 → 这组交叉线通
  [NG] 3 秒内没有任何异串口的路收到 → 这组交叉线不通
只算异串口收到，本口回环不计通过（交叉互连测的就是跨口）。未通过的那条会写清是
「只收到本口回环」还是「只收到同串口镜像」还是根本没收到，并在末尾点名本机型可自测的通道对。
**同一 uart_id 上的多路是同一根 TX/RX 的镜像**：谁发谁都互相看得见，中间没有经过
外部接线。拿镜像判通过等于自己发自己收，接线断了也会报通过，所以同串口的一律不计。
同串口那组在板上无法自测（收发互见，接不接线看到的都一样），进页面时的日志行会写明
本机型哪几组能自测；只有一路、或全部路同串口的机型只记收发、不做判定。
接线约定：两路交叉互连，A 接 A、B 接 B，互发互收。

方向脚（DE）空闲就是低电平（接收态），只在每一帧的发送窗口里拉高几毫秒，万用表量永远是 0V。
要确认它真会翻，点「DE 自检」把方向脚拉高 2 秒再量，量完自动回接收态。

历史记录只在本页内存里，退出即清空；固定行池显示最前面若干条，
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

local ports = {}   -- { {id=, ch=, name=, data=, info=, manual_init=, opened=, tx_n=, rx_n=}, ... }
local port_of = {} -- id → ports 里的那一项
-- 未判定的发送：{ {id=, ch=, data=, waited=, self_rx=bool, mirror_rx=bool}, ... }
-- waited 数的是扫描次数而不是毫秒，超时口径与系统时钟无关（时钟跳变不会误判）
local pending = {}

local entries = {} -- { {ts=, kind="TX"|"RX"|"OK"|"NG"|"INFO", ch=, text=}, ... }
local ok_n, ng_n = 0, 0

local log_labels = {} -- 固定行池，只改文字不增删控件
local log_w = 0
local log_title = nil
local log_title_w = 0
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

-- 载荷展示：可打印短串给原文，否则给 HEX（日志行要短，原文优先）
local function fmt_payload(s)
    s = s or ""
    if #s == 0 then return "(空)" end
    if s:match("^[%g ]+$") and #s <= 24 then
        return s
    end
    return to_hex(s)
end

-- 测试数据：条目里写了 test_data 就用它，否则按通道序号生成 123 / 456 / 789 / 012 …
local function default_test_data(idx)
    local d = {}
    for k = 0, 2 do
        d[#d + 1] = tostring(((idx - 1) * 3 + k + 1) % 10)
    end
    return table.concat(d)
end

-- ==================== 历史记录 ====================

local function fmt_entry(e)
    local ts = e.ts or ""
    if e.kind == "TX" or e.kind == "RX" then
        local verb = (e.kind == "TX") and "发送:" or "接收:"
        return string.format("%s 通道%d %s%s", ts, e.ch or 0, verb, fmt_payload(e.text))
    end
    if e.kind == "OK" or e.kind == "NG" then
        return string.format("%s [%s] %s", ts, e.kind, tostring(e.text or ""))
    end
    return string.format("%s %s", ts, tostring(e.text or ""))
end

-- 只画可见行：最新一条贴顶（收发日志(最新在上)），省去滚动定位
local function render_log()
    local n = #log_labels
    local total = #entries
    for i = 1, n do
        local e = entries[total - i + 1]
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

-- 日志标题行带上判定计数
local function update_log_title()
    if log_title and not log_title:is_destroyed() then
        log_title:set_text(theme.fit_text(
            string.format("收发日志(最新在上) | 通过 %d | 未通过 %d", ok_n, ng_n),
            log_title_w, theme.fs("caption")))
    end
end

local function append_entry(kind, ch, text)
    entries[#entries + 1] = {
        ts = os.date("%H:%M:%S"),
        kind = kind,
        ch = ch,
        text = text or "",
    }
    while #entries > MAX_KEEP do table.remove(entries, 1) end
    update_log_title()
    render_log()
end

local function clear_log()
    entries = {}
    ok_n, ng_n = 0, 0
    pending = {}
    update_log_title()
    render_log()
end

-- 刷新某一路的收发计数与打开状态
local function update_stat(p)
    if not p then return end
    local state = p.opened and "已打开" or "未打开"
    safe_call(p.stat_label, "set_text", theme.fit_text(
        string.format("TX:%d RX:%d  %s", p.tx_n, p.rx_n, state), p.stat_w, theme.fs("micro")))
end

-- ==================== 交叉判定 ====================

-- 收发两端是否分属不同串口（跨口链路的最低要求）
local function is_cross_uart(from_id, to_id)
    local a, b = port_of[from_id], port_of[to_id]
    return a and b and a.uart_id ~= b.uart_id
end

-- 本机型能自测的通道对（分属不同串口），全部列出，没有则 nil
-- 分隔符用 ASCII 的 "-" 和 ","：内置字库不含箭头符号
local function cross_pair_hint()
    local out = {}
    for i = 1, #ports do
        for j = i + 1, #ports do
            if ports[i].uart_id ~= ports[j].uart_id then
                out[#out + 1] = string.format("通道%d-通道%d", ports[i].ch, ports[j].ch)
            end
        end
    end
    if #out == 0 then return nil end
    return table.concat(out, ",")
end

-- 板上没有对端、或全部路都挂在同一串口（收发互见）时没有可判定的对象
local function judge_enabled()
    return cross_pair_hint() ~= nil
end

-- 摘掉一条未判定的发送
local function drop_pending(idx)
    table.remove(pending, idx)
end

-- 找同内容、但由异串口端口发出的未判定发送，找到即判为交叉通过
-- 同一 uart_id 上的多路共用一根 TX/RX，收发互见不经过外部接线，一律不算交叉通过
local function find_cross(data, from_id)
    for i = 1, #pending do
        local p = pending[i]
        if p.data == data and p.id ~= from_id and is_cross_uart(p.id, from_id) then
            return i
        end
    end
    return nil
end

-- 标记本口回环 / 同串口镜像（超时结算时用来区分「收到了但没跨口」和「根本没收到」）
local function mark_loopback(data, from_id)
    for i = 1, #pending do
        local p = pending[i]
        if p.data == data then
            if p.id == from_id then
                p.self_rx = true
            elseif not is_cross_uart(p.id, from_id) then
                p.mirror_rx = true
            end
        end
    end
end

-- 每 SCAN_INTERVAL 扫一次：超时仍未被异串口端口收到的发送结算成 [NG]
local function scan_timeout()
    for i = #pending, 1, -1 do
        local p = pending[i]
        p.waited = (p.waited or 0) + 1
        if p.waited >= MATCH_SCANS then
            drop_pending(i)
            ng_n = ng_n + 1
            local why
            if p.self_rx then
                why = string.format("通道%d 只收到本口回环，对端未收到 \"%s\"",
                                    p.ch, visible_text(p.data))
            elseif p.mirror_rx then
                local hint = cross_pair_hint()
                why = string.format("通道%d 只收到同串口镜像（未经过外部接线），对端未收到 \"%s\"%s",
                                    p.ch, visible_text(p.data),
                                    hint and ("；这组同串口无法自测，请改接 " .. hint) or "")
            else
                local hint = cross_pair_hint()
                why = string.format("通道%d 的 \"%s\" 对端未收到%s",
                                    p.ch, visible_text(p.data),
                                    hint and ("；可自测的是 " .. hint) or "")
            end
            append_entry("NG", p.ch, why)
        end
    end
end

local function stop_match_timer()
    if match_timer then
        pcall(sys.timerStop, match_timer)
        match_timer = nil
    end
end

-- ==================== 动作 ====================

-- 实际发一帧（端口必须已打开）
local function fire_send(p, data)
    data = tostring(data or "")
    if #data == 0 then return end
    sys.publish("RS485_TEST_SEND", p.id, data)
    p.tx_n = p.tx_n + #data
    update_stat(p)
    append_entry("TX", p.ch, data)
    if judge_enabled() then
        pending[#pending + 1] = {
            id = p.id,
            ch = p.ch,
            data = data,
            waited = 0,
            self_rx = false,
            mirror_rx = false,
        }
    end
end

-- 点通道按钮：没初始化的路先初始化，打开成功后补发这一帧
local function do_send(p)
    if not p then return end
    if not p.opened then
        p.want_send = p.data
        sys.publish("OTHER_FUNC_SET", p.id, true)
        append_entry("INFO", p.ch, string.format("通道%d 正在打开", p.ch))
        return
    end
    fire_send(p, p.data)
end

-- 方向脚自检：让驱动把 DE 拉高 DE_HOLD_MS 毫秒再回接收态
-- 发送窗口只有几毫秒，万用表量不到电平跳变；拉够两秒才能量出高电平
local DE_HOLD_MS = 2000
local function do_de_hold()
    sys.publish("RS485_DE_HOLD", DE_HOLD_MS)
    append_entry("INFO", 0, string.format("DE 自检：方向脚拉高 %dms，量到高电平即正常", DE_HOLD_MS))
end

-- ==================== 事件 ====================

-- 驱动收包广播（periph_rs485 的 on_receive 发布）
local function on_rx(id, data)
    local p = port_of[id]
    if not p then return end
    if type(data) ~= "string" or #data == 0 then return end
    p.rx_n = p.rx_n + #data
    update_stat(p)
    append_entry("RX", p.ch, data)

    if not judge_enabled() then return end

    -- 先找跨串口匹配：交叉互连要的就是 A(UART1) 发、B(UART2) 收
    local i = find_cross(data, id)
    if i then
        local q = pending[i]
        drop_pending(i)
        ok_n = ok_n + 1
        append_entry("OK", p.ch,
            string.format("通道%d 收到 通道%d 的 \"%s\"，交叉线通过",
                          p.ch, q.ch, visible_text(data)))
        return
    end
    -- 没跨口：记成本口回环或同串口镜像，超时结算时说清「收到了但没过线」
    mark_loopback(data, id)
end

-- 发送回执；成功时本地已记过 TX，这里只处理失败
local function on_send_result(id, ok, err)
    local p = port_of[id]
    if not p then return end
    if ok then return end
    -- 失败的那条发送不会再有应答，直接摘掉，免得超时再报一次未通过
    for i = #pending, 1, -1 do
        if pending[i].id == id then
            drop_pending(i)
            break
        end
    end
    ng_n = ng_n + 1
    append_entry("NG", p.ch,
        string.format("通道%d 发送失败：%s", p.ch, tostring(err or "未知原因")))
end

-- 打开串口结果：成功补发排队中的那一帧，失败把原因记进日志
local function on_set_result(id, ok, err)
    local p = port_of[id]
    if not p then return end
    if not ok then
        p.opened = false
        p.want_send = nil
        ng_n = ng_n + 1
        update_stat(p)
        append_entry("NG", p.ch,
            string.format("通道%d 打开失败：%s", p.ch, tostring(err or "未知原因")))
        return
    end
    p.opened = true
    update_stat(p)
    local data = p.want_send
    p.want_send = nil
    if data then
        fire_send(p, data)
    end
end

-- 端口状态回填（打开 / 未打开）
local function on_status(list)
    if type(list) ~= "table" then return end
    for _, s in ipairs(list) do
        local p = s and port_of[s.id]
        if p then
            p.opened = s.enabled and true or false
            update_stat(p)
        end
    end
end

-- 方向脚自检结果：用 INFO 不用 NG，NG 留给交叉线判定，两者含义不同
local function on_de_hold_result(ok, used, pins, bad)
    if not ok then
        append_entry("INFO", 0, "DE 自检失败：" .. tostring(used or "未知原因"))
        return
    end
    local pin_text = (pins and pins ~= "") and pins or "DE 脚"
    if bad and bad ~= "" then
        append_entry("INFO", 0, string.format("DE 自检不通过：%s 回读不是高电平，查 de_pin 配置",
            tostring(bad)))
        return
    end
    append_entry("INFO", 0, string.format("DE 自检通过：%s 拉高 %s ms 回读高电平，已回接收态",
        pin_text, tostring(used)))
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
                    ch = idx,
                    name = p.name or p.id,
                    data = tostring(p.test_data or default_test_data(idx)),
                    uart_id = p.uart_id or 0,
                    baud = p.baud or 9600,
                    -- 手动初始化：进页面不自动上电开串口，点它的按钮才初始化
                    manual_init = (p.manual_init == true),
                    opened = false,
                    want_send = nil,
                    tx_n = 0,
                    rx_n = 0,
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

-- 单张通道卡：通道号 + 类型 / 串口信息 / 收发计数 / 发送按钮
local function build_channel_card(parent, x, y, w, h, p)
    local bw = 1
    local pad_in = theme.dp(8)
    -- 子控件坐标原点是卡片内容区（已扣掉描边），这里不再按 bw 内缩
    local inner = w - 2 * bw - 2 * pad_in

    local card = theme.card(parent, {
        x = x, y = y, w = w, h = h,
        border_w = bw,
    })

    local fs_name = theme.fs("body")
    local fs_sub = theme.fs("micro")
    local name_h = fs_name + theme.dp(4)
    local sub_h = fs_sub + theme.dp(4)

    theme.label(card, {
        x = pad_in, y = pad_in, w = inner, h = name_h,
        text = theme.fit_text(string.format("通道%d %s", p.ch, p.name), inner, fs_name),
        px_size = fs_name, color = theme.C.t1, align = airui.TEXT_ALIGN_LEFT,
    })

    p.info_w = inner
    p.info_label = theme.label(card, {
        x = pad_in, y = pad_in + name_h, w = inner, h = sub_h,
        text = theme.fit_text(p.info, inner, fs_sub),
        px_size = fs_sub, color = theme.C.t3, align = airui.TEXT_ALIGN_LEFT,
    })

    p.stat_w = inner
    p.stat_label = theme.label(card, {
        x = pad_in, y = pad_in + name_h + sub_h, w = inner, h = sub_h,
        text = "TX:0 RX:0  未打开", px_size = fs_sub,
        color = theme.C.t3, align = airui.TEXT_ALIGN_LEFT,
    })

    -- 按钮文案即「UARTn 发送 <该路测试数据>」，宽度按文字算，超宽就截断
    local btn_text = string.format("UART%d 发送 %s", p.uart_id, p.data)
    local fs_btn = math.max(16, theme.dp(13)) -- 与 theme.button 内部字号同口径
    local btn_w = theme.text_width(btn_text, fs_btn) + theme.dp(28)
    if btn_w > inner then
        btn_w = inner
        btn_text = theme.fit_text(btn_text, inner - theme.dp(20), fs_btn)
    end

    p.btn = theme.button(card, {
        x = pad_in, y = h - 2 * bw - pad_in - theme.dp(34),
        w = btn_w, h = theme.dp(34),
        text = btn_text, size = 13,
        on_click = function() do_send(p) end,
    })
end

local function build_ui()
    update_screen_size()
    main_container = theme.page_bg(airui.screen, sw, sh)

    local card_w = sw - 2 * pad
    local _, th = theme.header(main_container, {
        x = pad, y = pad, w = card_w,
        title = "RS485 测试",
        sub = judge_enabled() and "A-A、B-B 交叉互接，点按钮发送" or "点按钮发送",
        on_back = function() exwin.close(window_id) end,
    })

    local gap = theme.dp(8)
    local y = pad + th + gap

    -- ===== 上方：通道按钮区，一排两张 =====
    if #ports == 0 then
        theme.box(main_container, {
            x = pad, y = y, w = card_w, h = theme.dp(52),
            color = theme.C.black, opa = 0,
        })
        theme.label(main_container, {
            x = pad + theme.dp(12), y = y, w = card_w - theme.dp(24), h = theme.dp(52),
            text = "本机型未配置 RS485 端口", px_size = theme.fs("body"),
            color = theme.C.t2, align = airui.TEXT_ALIGN_LEFT,
        })
        y = y + theme.dp(52) + gap
    else
        local cols = 2
        local cell_gap = gap
        local cell_w = math.floor((card_w - (cols - 1) * cell_gap) / cols)
        local pad_in = theme.dp(8)
        local cell_h = pad_in
            + theme.fs("body") + theme.dp(4)
            + theme.fs("micro") + theme.dp(4)
            + theme.fs("micro") + theme.dp(4)
            + theme.dp(6) + theme.dp(34) + pad_in

        for i, p in ipairs(ports) do
            local col = (i - 1) % cols
            local row = math.floor((i - 1) / cols)
            build_channel_card(main_container,
                pad + col * (cell_w + cell_gap),
                y + row * (cell_h + gap),
                cell_w, cell_h, p)
        end
        local rows = math.ceil(#ports / cols)
        y = y + rows * (cell_h + gap)
    end

    -- ===== 下方：收发日志（最新在上）+ DE 自检 + 清空 =====
    local head_h = theme.dp(36)
    local clear_w = theme.dp(72)
    local de_w = theme.dp(96)
    log_title_w = card_w - clear_w - de_w - 2 * gap
    log_title = theme.label(main_container, {
        x = pad, y = y, w = log_title_w, h = head_h,
        text = "收发日志(最新在上)", px_size = theme.fs("caption"),
        color = theme.C.t2, align = airui.TEXT_ALIGN_LEFT,
    })
    -- 方向脚自检：拉高 DE 够长一段时间，现场好用万用表量（正常发送窗口只有几毫秒，表笔看不出来）
    theme.ghost_button(main_container, {
        x = pad + card_w - clear_w - de_w - gap, y = y, w = de_w, h = head_h,
        text = "DE 自检", size = 12, fg = theme.C.t2, border = theme.C.stroke,
        on_click = function() do_de_hold() end,
    })
    theme.ghost_button(main_container, {
        x = pad + card_w - clear_w, y = y, w = clear_w, h = head_h,
        text = "清空", size = 12, fg = theme.SEM.danger, border = theme.SEM.danger,
        on_click = function() clear_log() end,
    })
    y = y + head_h + gap

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

    update_log_title()
    for _, p in ipairs(ports) do update_stat(p) end
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
    sys.subscribe("RS485_DE_HOLD_RESULT", on_de_hold_result)

    -- 只自动初始化未标 manual_init 的路；手动初始化的路由各自按钮触发
    for _, p in ipairs(ports) do
        if not p.manual_init then
            sys.publish("OTHER_FUNC_SET", p.id, true)
        end
    end
    sys.publish("OTHER_FUNC_GET")
    clear_log()
    -- 先说清本机型哪几组能自测：同串口那组收发互见，接不接线看到的都一样
    if #ports >= 2 then
        local hint = cross_pair_hint()
        if hint then
            append_entry("INFO", 0, "可自测交叉线 " .. hint .. "（A 接 A、B 接 B）")
        else
            append_entry("INFO", 0, "本机型 485 全在同一串口上，收发互见，板上无法自测交叉线")
        end
    end
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
    sys.unsubscribe("RS485_DE_HOLD_RESULT", on_de_hold_result)
    if main_container then main_container:destroy(); main_container = nil end
    log_labels = {}
    log_title = nil
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
