local theme = require "ui_theme"
local factory = require "air8607c1_factory"
local w1 = require "air8607w1_factory"
local cfg = require("air8607c1_config").w1
local M = {}
local px = theme.dp

local function button(ctx, x, y, w, text, on_click)
    return theme.button(ctx.base, {x = ctx.x + x, y = ctx.y + y, w = w, h = px(42),
        text = text, on_click = on_click})
end

local function wifi_panel(ctx, session, run)
    local gap, input_y = px(10), px(52)
    local half = (ctx.w - gap) // 2
    local kb = theme.keyboard({parent = ctx.base, x = 0, y = 0, w = ctx.sw, h = px(200),
        mode = "text", auto_hide = true, preview = true})
    kb:hide()
    local ssid = theme.input(ctx.base, {x = ctx.x, y = ctx.y + input_y, w = half, h = px(42),
        placeholder = "选择热点或输入 SSID", keyboard = kb, max_len = 32})
    local password = theme.input(ctx.base, {x = ctx.x + half + gap, y = ctx.y + input_y, w = half, h = px(42),
        placeholder = "Wi-Fi 密码（开放热点留空）", password_mode = true, keyboard = kb, max_len = 63})
    local list
    local function draw(list_data)
        if list then list:destroy() end
        list = theme.card(ctx.base, {x = ctx.x, y = ctx.y + px(157), w = ctx.w,
            h = ctx.h - px(157), scrollable = true})
        for i, ap in ipairs(list_data) do
            local row = px(46)
            theme.row(list, {x = 0, y = (i - 1) * row, w = ctx.w - 2, h = row,
                text = ap.ssid, right = string.format("%d dBm", ap.rssi), right_w = px(112),
                on_click = function()
                    ssid:set_text(ap.ssid)
                    password:set_text("")
                end})
        end
    end
    session.on_scan = draw
    button(ctx, 0, px(102), px(145), "扫描热点", function()
        kb:hide()
        run("正在扫描 2.4 GHz 热点", function() return w1.wifi_scan(session) end, "待连接")
    end)
    button(ctx, px(155), px(102), px(170), "连接并验证联网", function()
        kb:hide()
        local name, key = ssid:get_text() or "", password:get_text() or ""
        run("正在连接 Wi-Fi", function() return w1.wifi_test(session, name, key) end, "通过")
    end)
    button(ctx, px(335), px(102), px(166), "工厂 Wi-Fi 连接HJ", function()
        kb:hide()
        run("正在连接工厂 Wi-Fi", function() return w1.wifi_factory_test(session) end, "通过")
    end)
    session.on_close = function() kb:hide() end
end

local function text_view(data)
    local pattern = utf8.len(data) and "[%z\1-\8\11\12\14-\31\127]" or "[^ -~\r\n\t]"
    return (data:gsub(pattern, function(byte) return string.format("\\x%02X", byte:byte()) end))
end

local function serial_panel(ctx, session, run, item)
    local received, hex_mode = "", false
    local y = px(58)
    local count = theme.label(ctx.base, {x = ctx.x, y = ctx.y + y,
        w = ctx.w - px(96), h = px(30), text = "板端接收 0 字节"})
    local rx = theme.input(ctx.base, {x = ctx.x, y = ctx.y + y + px(38), w = ctx.w, h = ctx.h - px(164),
        disabled = true, max_len = 8192})
    local function render()
        local output = hex_mode and (received:toHex():gsub("..", "%0 ")) or text_view(received)
        rx:set_text(output)
        rx:set_cursor(-1)
        count:set_text(string.format("板端接收 %d 字节（最近 2048 字节）", session.rx_bytes or 0))
    end
    button(ctx, ctx.w - px(84), y - px(5), px(84), "HEX", function(widget)
        hex_mode = not hex_mode
        widget:set_text(hex_mode and "文本" or "HEX")
        render()
    end)
    session.on_rx = function(data)
        received = (received .. data):sub(-2048)
        render()
    end
    local actions_y = ctx.h - px(48)
    button(ctx, 0, actions_y, px(142), "发送三条", function()
        run("正在发送三条测试数据", function()
            session.tx_count, session.rx_bytes, session.verdict = 0, 0, nil
            received = ""
            render()
            return w1.serial_test(item.id, session)
        end, "通过")
    end)
    button(ctx, px(154), actions_y, px(142), "收发正常", function()
        if not session.running then return end
        if session.tx_count == 3 and session.rx_bytes > 0 then
            session.verdict = true
        else
            session.on_status("请先确认 SSCOM 收到三条，并给板子发数据核对。")
        end
    end)
    button(ctx, px(308), actions_y, px(112), "异常", function()
        if session.running then session.verdict = false end
    end)
end

local function camera_panel(ctx, session, run)
    local w = math.min(cfg.uvc.w, ctx.w)
    local h = math.min(cfg.uvc.h, ctx.h - px(113))
    local view = theme.box(ctx.base, {x = ctx.x + (ctx.w - w) // 2, y = ctx.y + px(52),
        w = w, h = h, color = 0x000000, opa = 255})
    session.make_preview = function(id)
        return airui.camera({parent = view, x = 0, y = 0, w = w, h = h, fit = "contain",
            auto_start = true, register_target = true, camera_id = id})
    end
    local y = ctx.h - px(48)
    button(ctx, 0, y, px(142), "开始预览", function()
        run("正在给摄像头供电并枚举", function()
            session.preview_ready, session.verdict = false, nil
            return w1.camera_test(session)
        end, "通过")
    end)
    button(ctx, px(154), y, px(142), "画面正常", function()
        if session.running and session.preview_ready then session.verdict = true end
    end)
    button(ctx, px(308), y, px(112), "异常", function()
        if session.running then session.verdict = false end
    end)
end

local function wifi_dl_panel(ctx, session, run)
    local p = cfg.wifi_dl
    local card = theme.card(ctx.base, {x = ctx.x, y = ctx.y + px(56), w = ctx.w,
        h = ctx.h - px(112)})
    theme.label(card, {x = px(12), y = px(12), w = ctx.w - px(24), h = px(150),
        text = string.format("J21 下载口：1=%s，2=%s，3=%s 接工具 TX，4=%s 接工具 RX，5=%s。\n"
            .. "PIN1 是 5V，不是 24V。\n"
            .. "用 Air6205 工具读版本或下载从机固件，按工具要求触发 WIFI_RESET。",
            p.pin1, p.pin2, p.pin3, p.pin4, p.pin5)})
    local y = ctx.h - px(48)
    button(ctx, 0, y, px(142), "开始检查", function()
        session.verdict = nil
        run("正在准备 WiFi 下载口检查", function() return w1.wifi_dl_test(session) end, "通过")
    end)
    button(ctx, px(154), y, px(142), "识别/下载正常", function()
        if session.running then session.verdict = true end
    end)
    button(ctx, px(308), y, px(112), "异常", function()
        if session.running then session.verdict = false end
    end)
end

local function vrtc_panel(ctx, session, run)
    local card = theme.card(ctx.base, {x = ctx.x, y = ctx.y + px(56), w = ctx.w,
        h = ctx.h - px(112)})
    theme.label(card, {x = px(12), y = px(12), w = ctx.w - px(24), h = px(150),
        text = string.format("CR2032 → VRTC 备电测试。\n"
            .. "先点「记录当前时间」，装好 CR2032 后断主电 %d 秒。\n"
            .. "重新上电进入本页点「读取 RTC」，核对时间连续后点「通过」。",
            cfg.vrtc.off_seconds)})
    local gap = px(8)
    local bw = (ctx.w - gap * 3) // 4
    local y = ctx.h - px(48)
    button(ctx, 0, y, bw, "记录当前时间", function()
        run("正在保存断电前时间基准", function() return w1.vrtc_mark(session) end, "待确认")
    end)
    button(ctx, bw + gap, y, bw, "读取 RTC", function()
        run("正在读取 RTC 时间", function() return w1.vrtc_read(session) end, "待确认")
    end)
    button(ctx, 2 * (bw + gap), y, bw, "通过", function()
        factory.confirm("vrtc", true, "断电后 RTC 时间连续")
    end)
    button(ctx, 3 * (bw + gap), y, bw, "异常", function()
        factory.confirm("vrtc", false, "断电后 RTC 时间未保持")
    end)
end

local panels = {wifi = wifi_panel, ttl = serial_panel, rs232 = serial_panel, rs485 = serial_panel,
    uvc = camera_panel, wifi_dl = wifi_dl_panel, vrtc = vrtc_panel}

function M.open(item, show_result)
    local build = panels[item.id]
    if not build then return end
    local session = {}
    local window_id, ctx, status
    local function destroy()
        if ctx then ctx.base:destroy(); ctx = nil end
    end
    local function update(key, result)
        if key == item.id and not session.closed then show_result(status, result, true) end
    end
    function session.on_status(text)
        if not session.closed then status:set_text(text) end
    end
    function session.on_ready(text)
        if session.closed then return end
        if item.id == "uvc" then session.preview_ready = true end
        factory.wait_for_check(item.id, text)
    end
    local function run(message, action, outcome)
        local started = factory.run_job(item.id, message, function()
            if session.closed then return false end
            session.running = true
            local ok, passed, result = pcall(action)
            session.running = false
            if session.closed then destroy() end
            if not ok then return false, tostring(passed) end
            return passed, result
        end, outcome, session)
        if not started then session.on_status("请等待当前测试完成。") end
    end
    window_id = exwin.open({
        on_create = function()
            ctx = theme.page({title = item.name, sub = item.desc, icon = item.icon,
                on_back = function() exwin.close(window_id) end})
            status = theme.label(ctx.base, {x = ctx.x, y = ctx.y, w = ctx.w, h = px(50)})
            update(item.id, factory.result(item.id))
            build(ctx, session, run, item)
            sys.subscribe("C1_TEST_RESULT", update)
        end,
        on_destroy = function()
            session.closed = true
            if session.on_close then session.on_close() end
            sys.unsubscribe("C1_TEST_RESULT", update)
            factory.cancel(item.id)
            -- 预览页根对象须比原生 USB 解码任务晚释放。
            if item.id == "uvc" and session.running then
                ctx.base:set_hidden(true)
            else
                destroy()
            end
        end,
    })
end

return M
