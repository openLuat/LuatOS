--[[
@module air8606_test_win
@summary Air8606 CAN/RS232/GNSS/EX2网口/对外电源/看门狗诊断
@version 1.0.1
@date 2026.11.20

入口 OPEN_AIR8606_TEST_WIN(id)。使用 config.peripherals 中的真实驱动句柄。
CAN 发送按钮提交原始 ASCII 数据（最多8字节）；总线 ACK 与 RX 分开显示。
离开测试页不自动改变供电的原设计由 factory_new 收口接管：on_destroy 发
TEST_WIN_CLOSED，由 other_func_win 统一断电（与 uvc/rs485/audio 三页同一收口）。
]]
local theme = require "ui_theme"
local M = {}
local factories = {
    can=function() return require "periph_can" end,
    uart=function() return require "periph_uart" end,
    gnss=function() return require "periph_gnss" end,
    power=function() return require "periph_power" end,
    peer=function() return require "periph_peer" end,
    wdt=function() return require "periph_wdt" end,
}
local window_id, root, entry, handle, state_label, detail_label, data_input
local logs, log_labels = {}, {}
local log_width, current_id, poll_timer, busy = 0, nil, nil, false
local generation = 0

local function set_text(obj, value)
    if obj then pcall(obj.set_text, obj, tostring(value or "")) end
end

local function hex(data)
    local bytes = {}
    for i=1, math.min(#data, 64) do bytes[i]=string.format("%02X", data:byte(i)) end
    return table.concat(bytes, " ") .. (#data > 64 and " ..." or "")
end

local function payload(data)
    if type(data) ~= "string" then return tostring(data) end
    if data:match("^[%g ]+$") and #data <= 48 then return data end
    return hex(data)
end

local function render_log()
    for i, lab in ipairs(log_labels) do
        set_text(lab, theme.fit_text(logs[i] or "", log_width, theme.fs("caption")))
    end
end

local function append(text)
    table.insert(logs, 1, os.date("%H:%M:%S") .. " " .. tostring(text))
    if #logs > 80 then table.remove(logs) end
    render_log()
end

local function lookup(id)
    for _, p in ipairs((_G.project_config or {}).peripherals or {}) do
        if p.id == id then
            if p.handle then return p, p.handle end
            local factory = factories[p.type]
            if not factory then return p, nil, "不支持的测试类型" end
            local ok, mod = pcall(factory)
            if not ok then return p, nil, tostring(mod) end
            local h = mod.get(id)
            if not h then
                local err
                h, err = mod.init(p)
                if not h then return p, nil, tostring(err) end
            end
            p.handle = h
            return p, h
        end
    end
    return nil, nil, "没有找到外设配置: " .. tostring(id)
end

local function refresh()
    if not handle then return end
    local ok, st = pcall(handle.status, handle)
    if not ok or type(st) ~= "table" then set_text(state_label, "读取状态失败"); return end
    set_text(state_label, theme.fit_text(st.info or (st.enabled and "已开启" or "未开启"),
        log_width, theme.fs("body")))
    local detail = ""
    if entry.type == "can" then
        detail = "J31：2 脚 CAN_L，3 脚 CAN_H，1 脚 GND | 对端正常模式 500 kbps | 标准帧 0x123"
    elseif entry.type == "uart" then
        detail = string.format("UART%d / %d / 8N1，数据按 ASCII 发送；外部对端需相同串口参数",
            entry.uart_id, entry.baud or 57600)
    elseif entry.type == "gnss" then
        local g = st.gnss or {}
        if st.online then
            detail = string.format("UART1 115200 | RX %d 字节 | NMEA %d 行 | 丢弃 %d 行 | 卫星 %s",
                g.rx_bytes or 0, g.lines or 0, g.dropped or 0, tostring((g.gga or {}).satellites_tracked or "--"))
        else
            detail = "Air510W 接在 EX2 的 UART1，GPS_EN 为 EX2 GPIO26"
        end
    elseif entry.type == "peer" then
        local result = st.diag
        detail = "J15 接有 DHCP 的路由器，诊断使用 EX2 以太网访问测试服务器"
        if result and result.code then
            detail = string.format("J15 | HTTP %d | 收到 %d / 2048 字节", result.code, result.bytes or 0)
        end
    elseif entry.type == "wdt" then
        local wdt = st.wdt or {}
        detail = "外部看门狗不能从此页关闭。最近喂狗请求:" .. tostring(wdt.last_request or "--")
    elseif entry.id == "power_5v" then
        detail = "点「开启」，红表笔接 J17-1，黑表笔接 J17-2，应约 5 V。点「关闭」后复测。"
    elseif entry.type == "power" then
        detail = "仅控制该对外输出；VIN 电压跟随输入，不通过软件调压"
    end
    set_text(detail_label, theme.fit_text(detail, log_width, theme.fs("caption")))
end

local function action(method, a1, a2)
    if busy or not handle then return end
    local selected, gen = handle, generation
    local fn = selected[method]
    if type(fn) ~= "function" then append("该外设不支持 " .. method); return end
    busy = true
    sys.taskInit(function()
        local ok, ret, note = pcall(fn, selected, a1, a2)
        if gen ~= generation then return end
        busy = false
        if ok and ret == true then
            append(method .. " | " .. tostring(note or "操作完成"))
        else
            append(method .. " 失败 | " .. tostring(ok and note or ret))
        end
        refresh()
        sys.publish("OTHER_FUNC_GET")
    end)
end

local function on_rx(id, data)
    if id == current_id then append("RX " .. payload(data)); refresh() end
end
local function on_can_rx(id, frame)
    if id == current_id then
        append(string.format("CAN RX ID:0x%X %s %s", frame.id,
            frame.extended and "EXT" or "STD", payload(frame.data)))
        refresh()
    end
end
local function on_can_tx(id, ok)
    if id == current_id then append(ok and "CAN 总线发送成功 (ACK)" or "CAN 总线发送失败/无 ACK"); refresh() end
end
local function on_can_error(id, err)
    if id == current_id then append(err); refresh() end
end
local function on_peer_status() refresh() end

local function create_ui()
    local sw, sh = theme.content_fit(_G.screen_w or 1024, _G.screen_h or 600)
    local pad, gap = theme.page_margin(), theme.dp(10)
    local width = sw - 2 * pad
    log_width = width - theme.dp(24)
    root = theme.page_bg(airui.screen, sw, sh)
    local _, header_h = theme.header(root, {
        x=pad,y=pad,w=width,title=entry and entry.name or "外设诊断",
        sub="外设诊断",on_back=function() exwin.close(window_id) end,
    })
    local y = pad + header_h + gap
    local card_h = theme.dp(78)
    local card = theme.card(root,{x=pad,y=y,w=width,h=card_h})
    state_label=theme.label(card,{x=theme.dp(12),y=theme.dp(10),w=log_width,h=theme.dp(28),
        text="读取状态...",px_size=theme.fs("body"),color=theme.C.t1})
    detail_label=theme.label(card,{x=theme.dp(12),y=theme.dp(42),w=log_width,h=theme.dp(26),
        text="",px_size=theme.fs("caption"),color=theme.C.t3})
    y=y+card_h+gap
    local button_h=theme.dp(42)
    local button_w=math.floor((width-2*gap)/3)
    local function button(col, text, fn)
        return theme.button(root,{x=pad+(col-1)*(button_w+gap),y=y,w=button_w,h=button_h,
            text=text,size=13,on_click=fn})
    end
    if entry and entry.type == "wdt" then
        button(1,"手动喂狗请求",function() action("feed") end)
        button(2,"刷新状态",refresh)
    elseif entry and entry.type == "peer" then
        button(1,"网口诊断",function() action("diagnose") end)
        button(2,"刷新状态",refresh)
    else
        button(1,"开启",function() action("start") end)
        button(2,"关闭",function() action("stop") end)
        button(3,"刷新状态",refresh)
    end
    y=y+button_h+gap
    if entry and (entry.type == "uart" or entry.type == "can") then
        local send_w=theme.dp(150)
        local keyboard=theme.keyboard({parent=root,x=0,y=0,w=sw,h=theme.dp(200),
            mode="text",auto_hide=true,preview=true,on_commit=function(self) self:hide() end})
        data_input=theme.input(root,{x=pad,y=y,w=width-send_w-gap,h=button_h,
            text=entry.test_data or (entry.type == "can" and "CAN test" or "RS232 test"),
            max_len=entry.type == "can" and 8 or 256,placeholder="ASCII 发送内容",keyboard=keyboard})
        theme.button(root,{x=pad+width-send_w,y=y,w=send_w,h=button_h,text="发送",size=13,
            on_click=function()
                local ok,data=pcall(data_input.get_text,data_input)
                if ok then action("send",data,entry.tx_id) end
            end})
        y=y+button_h+gap
    end
    theme.label(root,{x=pad,y=y,w=width,h=theme.dp(28),text="诊断日志（最新在上）",
        px_size=theme.fs("caption"),color=theme.C.t2})
    y=y+theme.dp(30)
    local line_h=theme.fs("caption")+theme.dp(6)
    local count=math.max(1,math.floor((sh-y-pad)/line_h))
    for i=1,count do
        log_labels[i]=theme.label(root,{x=pad+theme.dp(12),y=y+(i-1)*line_h,w=log_width,h=line_h,
            text="",px_size=theme.fs("caption"),color=theme.C.t2})
    end
end

local function on_create()
    generation=generation+1
    logs,log_labels,busy={}, {},false
    local err
    entry,handle,err=lookup(current_id)
    create_ui()
    if not handle then set_text(state_label,err); append(err); return end
    sys.subscribe("PERIPH_RX",on_rx)
    sys.subscribe("PERIPH_CAN_RX",on_can_rx)
    sys.subscribe("PERIPH_CAN_TX",on_can_tx)
    sys.subscribe("PERIPH_CAN_ERROR",on_can_error)
    sys.subscribe("AIR8606_PEER_STATUS",on_peer_status)
    sys.subscribe("AIR8606_GNSS",on_peer_status)
    sys.subscribe("WATCHDOG_STATUS",on_peer_status)
    poll_timer=sys.timerLoopStart(refresh,1000)
    append("已选择 " .. tostring(entry.name or entry.id))
    refresh()
end

local function on_destroy()
    generation=generation+1
    if poll_timer then sys.timerStop(poll_timer);poll_timer=nil end
    sys.unsubscribe("PERIPH_RX",on_rx)
    sys.unsubscribe("PERIPH_CAN_RX",on_can_rx)
    sys.unsubscribe("PERIPH_CAN_TX",on_can_tx)
    sys.unsubscribe("PERIPH_CAN_ERROR",on_can_error)
    sys.unsubscribe("AIR8606_PEER_STATUS",on_peer_status)
    sys.unsubscribe("AIR8606_GNSS",on_peer_status)
    sys.unsubscribe("WATCHDOG_STATUS",on_peer_status)
    if root then root:destroy();root=nil end
    state_label,detail_label,data_input,handle,entry=nil,nil,nil,nil,nil
    log_labels={}
    busy=false
    window_id=nil
    -- factory_new 收口：与 uvc/rs485/audio 三页同款，通知 other_func_win 断电
    sys.publish("TEST_WIN_CLOSED")
end

local function open(id)
    if window_id then return end
    current_id=id
    window_id=exwin.open({on_create=on_create,on_destroy=on_destroy,
        on_lose_focus=function() end,on_get_focus=refresh})
end
sys.subscribe("OPEN_AIR8606_TEST_WIN",open)
M.open=open
return M
