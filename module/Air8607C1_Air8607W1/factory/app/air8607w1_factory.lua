local cfg = require("air8607c1_config").w1
local board = require "air8607c1_board"
local baseboard = require "air8607c1_baseboard"
local time_app = require "settings_time_app"
local M = {}

function M.sd_test(verify)
    if not (spi and fatfs and fatfs.unmount) then return false, "底包缺少 SPI 或 FATFS" end
    local sd = cfg.sd
    local power, mounted
    -- 合并桌面功能后，开机时 storage_pri_app 已经把 /sd 挂载好了；
    -- 记录一下，测试结束后好把桌面用的挂载还回去。
    local ok_exists, had_mount = pcall(io.exists, sd.mount_point)
    had_mount = ok_exists and had_mount or false

    -- 断电时必须把 CS/CLK/MOSI 拉低。否则卡片会通过这些信号线的
    -- 输入保护二极管“寄生取电”，VDD 掉不到复位阈值，第二次初始化
    -- 就会出现 CMD0 有响应、ACMD41 一直忙到超时的情况。
    local function sd_bus_low()
        pcall(spi.close, sd.spi)
        pcall(gpio.setup, sd.cs, gpio.OUTPUT, gpio.PULLDOWN, 0)
        pcall(gpio.setup, sd.clk, gpio.OUTPUT, gpio.PULLDOWN, 0)
        pcall(gpio.setup, sd.mosi, gpio.OUTPUT, gpio.PULLDOWN, 0)
        -- MISO 是卡片的输出脚，保持输入下拉，避免通过上拉电阻倒灌供电。
        pcall(gpio.setup, sd.miso, nil, gpio.PULLDOWN)
    end

    local function sd_mount_once()
        -- 先让 CS/CLK/MOSI 变低，再断电，确保卡片真正掉电复位。
        sd_bus_low()
        power(0)
        sys.wait(1000)

        -- 断电期间保持信号低；上电前再把 CS 拉高。
        gpio.setup(sd.cs, 1)
        power(1)
        sys.wait(500)

        assert(spi.setup(sd.spi, 255, 0, 0, 8, 400000) == 0, "SPI1 初始化失败")
        return fatfs.mount(fatfs.SPI, sd.mount_point, sd.spi, sd.cs, sd.hz,
                           nil, 1, false)
    end

    local called, passed, detail = pcall(function()
        -- 桌面存储可能已在开机时挂载过 SD，先卸载再走测试的完整上电/挂载流程，
        -- 否则 fatfs.mount 会因挂载点已存在而失败。
        pcall(fatfs.unmount, sd.mount_point)
        power = assert(gpio.setup(sd.power, 0), "SD_3V3 使能脚初始化失败")
        assert(gpio.setup(sd.cs, 1), "TF 片选脚初始化失败")

        local ok, err
        for attempt = 1, 2 do
            ok, err = sd_mount_once()
            if ok then break end
            log.warn("factory_w1", "SD", "mount retry", attempt, tostring(err))
            sys.wait(500)
        end
        if not ok then return false, "TF 挂载失败，请检查 J216 和 FAT32 格式：" .. tostring(err) end

        mounted = true
        return verify()
    end)
    local unmounted, code = true, 0
    if mounted then
        unmounted, code = pcall(fatfs.unmount, sd.mount_point)
        sys.wait(100)
    end
    sd_bus_low()
    if power then power(0) end
    -- 下次点击前保持断电，并让 CS/CLK/MOSI 保持低电平。
    sys.wait(500)

    --[[测试把卡断电卸载后要还原桌面用的挂载，否则回到桌面后文件管理、
    合宙网盘都看不到 /sd（只能重启恢复）。测试本身已经在 sd_mount_once 里
    做过完整的断电/上电/CMD0/ACMD41 流程，这里按同一组参数重新挂载不影响结论。
    测试前本来没挂载（例如未开 sd_card 功能）时仍保持断电，维持原工装行为。]]
    if had_mount and power then
        gpio.setup(sd.cs, 1)
        power(1)
        sys.wait(300)
        local remounted = spi.setup(sd.spi, 255, 0, 0, 8, 400000) == 0
            and fatfs.mount(fatfs.SPI, sd.mount_point, sd.spi, sd.cs, sd.hz, nil, 1, false)
        if not remounted then
            log.warn("factory_w1", "SD", "测试后恢复桌面挂载失败，重启后可恢复")
        end
    end

    if not unmounted or code ~= 0 then return false, "TF 卸载失败：" .. tostring(code) end
    if not called then return false, tostring(passed) end
    return passed, detail
end

function M.dac_test(session)
    if not (audio_v2 and audio_v2.tts) then return false, "底包缺少 DAC/TTS 支持" end
    local dac = cfg.dac
    local req, ended, enabled
    local called, passed, detail = pcall(function()
        enabled = assert(gpio.setup(dac.pa, 0), "功放使能脚初始化失败")
        -- V1030 CCM4211 内置 DAC 无需配置 I2S。功放由这里限时控制。
        audio_v2.config_pa_power_ctrl(false, 0, 1, 0)
        audio_v2.soft_volume(dac.volume)
        audio_v2.on(function(index, event)
            if req and index == req and event == audio_v2.REQUEST_END then ended = true end
        end)
        enabled(1)
        sys.wait(50)
        if session and session.closed then return false end
        local ok, index = audio_v2.tts(dac.text)
        if not ok or not index then return false, "DAC 播放请求失败" end
        req = index
        for _ = 1, 150 do
            if session and session.closed then return false end
            if ended then return true, "J102 听到「音频播放测试」后点「通过」。" end
            sys.wait(20)
        end
        return false, "DAC 播放超时"
    end)
    if req and not ended then pcall(audio_v2.stop, req) end
    pcall(audio_v2.on, nil)
    if enabled then enabled(0) end
    if not called then return false, tostring(passed) end
    return passed, detail
end

function M.serial_test(id, session)
    if not uart then return false, "底包缺少 UART" end
    local serial = cfg.serial
    local port = serial[id]
    local opened, sent, power, direction
    local function receive()
        local data = uart.read(port.id, 1024) or ""
        if #data > 0 and not session.closed then
            session.rx_bytes = session.rx_bytes + #data
            session.on_rx(data)
            log.info("factory_w1", id, "RX", #data, data:toHex())
        end
    end

    local called, passed, detail = pcall(function()
        if session.closed then return false end
        if id ~= "ttl" then
            direction = assert(gpio.setup(serial.rs485.de, 0), "RS485 DE 初始化失败")
            power = assert(gpio.setup(serial.power, 1), "RS232/485 供电开启失败")
            sys.wait(100)
            if session.closed then return false end
        end
        local ret = uart.setup(port.id, serial.baud, 8, 1, uart.NONE, uart.LSB, 2048, port.de, 0)
        if ret ~= 0 then return false, "UART" .. port.id .. " 初始化失败：" .. tostring(ret) end
        opened = true
        uart.on(port.id, "sent", function() sent = true end)
        local name = baseboard.current().name
        log.info("factory_w1", name, id, "UART", port.id, serial.baud, "8N1", "SSCOM")
        for n = 1, 3 do
            if session.closed or session.verdict == false then return false, "已停止收发" end
            local msg = string.format("AIR8607C1 %s %s TEST %d/3\r\n", name, id:upper(), n)
            sent = false
            if uart.write(port.id, msg) ~= #msg then return false, "UART 发送失败" end
            -- 停止前先等当前短帧发送完成，自动 DE 在字节发送结束后回到接收。
            for _ = 1, 100 do
                sys.wait(10)
                if not session.closed then receive() end
                if sent then break end
            end
            if not sent then return false, "UART 发送未完成" end
            if session.closed then return false end
            session.tx_count = n
            log.info("factory_w1", id, "TX", msg:sub(1, -3))
        end
        session.on_ready("已发送三条。请核对 SSCOM 收到三条，再发数据给板子核对。")
        while not session.closed and session.verdict == nil do
            receive()
            sys.wait(50)
        end
        if session.verdict == true and session.rx_bytes > 0 then
            return true, "三条发送及板端接收内容均已确认"
        end
        return false, "现场确认收发异常"
    end)

    if opened then
        pcall(uart.on, port.id, "sent", nil)
        pcall(uart.close, port.id)
    end
    if direction then direction(0) end
    if power then power(0) end
    if not called then return false, tostring(passed) end
    return passed, detail
end

local airlink_started, wlan_ready = false, false

local function wifi_init(session)
    if not (airlink and netdrv and wlan and socket and http) then return false, "底包缺少 Airlink/WLAN/HTTP" end
    if not airlink_started then
        -- 桌面网络管理可能已在开机时把 Air6205 初始化好，此时直接复用，
        -- 不重复 config/init，避免和 C1 功能测试抢同一路 SPI5。
        if airlink.ready() then
            airlink_started = true
        else
            local w = cfg.wifi
            assert(gpio.setup(w.cs, 1), "SPI5 片选脚初始化失败")
            local power = assert(gpio.setup(w.power, 1), "Wi-Fi 供电开启失败")
            sys.wait(200)
            if session.closed then power(0); return false end
            airlink.config(airlink.CONF_SPI_ID, w.spi)
            airlink.config(airlink.CONF_SPI_CS, w.cs)
            airlink.config(airlink.CONF_SPI_RDY, w.rdy)
            airlink.config(airlink.CONF_SPI_SPEED, w.hz)
            airlink.init()
            if not netdrv.setup(socket.LWIP_STA, netdrv.WHALE) then
                power(0)
                return false, "Wi-Fi 网卡创建失败"
            end
            airlink.start(airlink.MODE_SPI_MASTER)
            airlink_started = true
        end
    end
    for _ = 1, 50 do
        if session.closed then return false end
        if airlink.ready() then
            if not wlan_ready then
                if wlan.init() == false then return false, "WLAN 初始化失败" end
                wlan_ready = true
            end
            return true
        end
        sys.wait(200)
    end
    return false, "Air6205 未就绪，请检查供电、SPI5 和从机固件"
end

function M.wifi_scan(session)
    local ok, err = wifi_init(session)
    if not ok then return false, err end
    local done
    local function on_scan_done() done = true end
    sys.subscribe("WLAN_SCAN_DONE", on_scan_done)
    local called, passed, detail = pcall(function()
        if wlan.scan() == false then return false, "无法启动热点扫描" end
        for _ = 1, 100 do
            if session.closed then return false end
            if done then break end
            sys.wait(100)
        end
        if not done then return false, "热点扫描超时" end
        local seen, list = {}, {}
        for _, ap in ipairs(wlan.scanResult(32) or {}) do
            local ssid = ap.ssid
            if type(ssid) == "string" and #ssid > 0 and #ssid <= 32 and utf8.len(ssid) and not seen[ssid] then
                seen[ssid] = true
                list[#list + 1] = {ssid = ssid, rssi = tonumber(ap.rssi) or -127}
            end
        end
        table.sort(list, function(a, b) return a.rssi > b.rssi end)
        session.on_scan(list)
        if #list == 0 then return false, "未发现热点，请检查天线及 2.4 GHz 网络" end
        return true, string.format("发现 %d 个热点，选择或输入 SSID。", #list)
    end)
    sys.unsubscribe("WLAN_SCAN_DONE", on_scan_done)
    if not called then return false, tostring(passed) end
    return passed, detail
end

function M.wifi_test(session, ssid, password)
    if type(ssid) ~= "string" or #ssid == 0 or #ssid > 32 or ssid:find("\0", 1, true) then
        return false, "请输入有效的 SSID（1 至 32 字节）"
    end
    if type(password) ~= "string" or password:find("\0", 1, true)
        or (#password ~= 0 and (#password < 8 or #password > 63)) then
        return false, "Wi-Fi 密码应为 8 至 63 字节，开放热点可留空"
    end
    local ready, reason = wifi_init(session)
    if not ready then return false, reason end
    local sta = socket.LWIP_STA
    local function address()
        if socket.adapter(sta) ~= true then return nil end
        local ip = socket.localIP(sta)
        if ip and ip ~= "" and ip ~= "0.0.0.0" then return ip end
    end
    local called, passed, detail = pcall(function()
        if address() then
            wlan.disconnect()
            for _ = 1, 20 do
                if session.closed then return false end
                if not address() then break end
                sys.wait(100)
            end
            if address() then return false, "旧 Wi-Fi 连接未断开" end
        end
        if session.closed then return false end
        if wlan.connect(ssid, password, 1) == false then return false, "发送 Wi-Fi 连接请求失败" end
        local ip
        for _ = 1, 100 do
            if session.closed then return false end
            ip = address()
            if ip then break end
            sys.wait(250)
        end
        if not ip then return false, "Wi-Fi 连接或 DHCP 超时，请检查热点和密码" end
        session.on_status("已取得 IP " .. ip .. "，正在验证联网。")
        local code, _, data = http.request("GET", cfg.wifi.url, nil, nil, {adapter = sta, timeout = 10000}).wait()
        local bytes = type(data) == "string" and #data or 0
        log.info("factory_w1", "wifi", "HTTP", code, "bytes", bytes, "IP", ip, "SSID", ssid)
        if code ~= 200 or bytes ~= 2048 then
            return false, string.format("已取得 IP %s，HTTP %s，收到 %d B", ip, tostring(code), bytes)
        end
        return true, string.format("IP %s，HTTP 200，收到 %d B", ip, bytes)
    end)
    pcall(wlan.disconnect)
    if not called then return false, tostring(passed) end
    return passed, detail
end

function M.wifi_factory_test(session)
    -- 工装配置随脚本烧录，手动热点使用界面的输入值。
    local raw = io.readFile("/luadb/wifi.local.json", "rb", 0, 513)
    if type(raw) ~= "string" or raw == "" then return false, "缺少工厂 Wi-Fi 配置 wifi.local.json" end
    if #raw > 512 then return false, "工厂 Wi-Fi 配置过长" end
    local ok, defaults = pcall(json.decode, raw)
    if not ok or type(defaults) ~= "table" then return false, "工厂 Wi-Fi 配置格式错误" end
    return M.wifi_test(session, defaults.ssid, defaults.password)
end

function M.wifi_dl_test(session)
    local p = cfg.wifi_dl
    if not session then return false, "测试会话无效" end
    local detail = string.format("J21：1=%s，2=%s，3=%s 接工具 TX，4=%s 接工具 RX，5=%s。PIN1 是 5V，不是 24V。",
        p.pin1, p.pin2, p.pin3, p.pin4, p.pin5)
    session.on_ready(detail)
    while not session.closed and session.verdict == nil do
        sys.wait(50)
    end
    if session.closed then return false end
    if session.verdict then
        return true, "现场人工确认 Air6205 下载口正常"
    end
    return false, "现场人工确认 Air6205 下载口异常"
end

local function format_time(t)
    return string.format("%04d-%02d-%02d %02d:%02d:%02d",
        t.year, t.mon or t.month, t.day, t.hour, t.min, t.sec)
end

local function time_stamp(t)
    local ok, ts = pcall(os.time, {
        year = t.year, month = t.mon or t.month, day = t.day,
        hour = t.hour, min = t.min, sec = t.sec,
    })
    if not ok or not ts then return nil end
    return math.tointeger and math.tointeger(ts) or math.floor(ts)
end

function M.vrtc_mark(session)
    if not (fskv and fskv.init()) then return false, "FSKV 不可用，无法保存断电前基准" end
    local t = time_app.get_time()
    local ts = time_stamp(t)
    if not ts then return false, "当前 RTC 时间无效" end
    local text = format_time(t)
    if not fskv.set(cfg.vrtc.key, string.format("%d|%s", ts, text)) then
        return false, "保存断电前时间基准失败"
    end
    return true, string.format("已记录 %s。请装好 CR2032，断主电 %d 秒后重新上电，再进本页点「读取 RTC」。",
        text, cfg.vrtc.off_seconds)
end

function M.vrtc_read(session)
    if not (fskv and fskv.init()) then return false, "FSKV 不可用，无法读取断电前时间基准" end
    local raw = fskv.get(cfg.vrtc.key)
    if type(raw) ~= "string" or raw == "" then
        return false, "未找到断电前时间基准，请先点「记录当前时间」"
    end
    local base_ts, base_text = raw:match("^(%-?%d+)|(.+)$")
    base_ts = tonumber(base_ts)
    if not base_ts then return false, "断电前时间基准格式错误" end
    local t = time_app.get_time()
    local now_ts = time_stamp(t)
    if not now_ts then return false, "当前 RTC 时间无效" end
    local now_text = format_time(t)
    if now_ts <= base_ts then
        return false, string.format("RTC 未前进：断电前 %s，当前 %s，请检查 CR2032 极性和电量。",
            base_text, now_text)
    end
    return true, string.format("断电前 %s，当前 %s。RTC 已前进，请核对时间连续后点「通过」。",
        base_text, now_text)
end

local function mjpeg_mode(app_id)
    local c = cfg.uvc
    local ok, count = camera.get_usb_config(app_id, camera.CONF_UVC_FORMAT)
    if not ok or not count then return nil end
    local fallback
    for format = 1, count do
        local valid, kind, frames = camera.get_usb_config(app_id, camera.CONF_UVC_FORMAT, format)
        if valid and kind == camera.FORMAT_MJPG and frames then
            for frame = 1, frames do
                local good, fps, w, h = camera.get_usb_config(app_id, camera.CONF_UVC_RESOLUTION, format, frame)
                if good and w > 0 and h > 0 then
                    local mode = {format = format, frame = frame, w = w, h = h, fps = fps}
                    if w == c.w and h == c.h then return mode end
                    if w <= 640 and h <= 480 and (not fallback or w * h < fallback.w * fallback.h) then
                        fallback = mode
                    end
                end
            end
        end
    end
    return fallback
end

function M.camera_test(session)
    if not (camera and camera.USB and usb and usb.mode and pm and zbuff and airui.camera) then
        return false, "底包缺少 USB Host/UVC 预览支持"
    end
    local c = cfg.uvc
    local widget, app_id, buffers, got_frame, disconnected, host
    local called, passed, detail = pcall(function()
        if session.closed then return false end
        assert(board.set_pwm1(0), "关闭 J8 VBUS 失败")
        pm.power(pm.USB, false)
        sys.wait(180)
        if session.closed then return false end
        assert(usb.mode(c.bus, usb.HOST), "切换 USB Host 失败")
        host = true
        pm.power(pm.USB, true)
        sys.wait(100)
        if session.closed then return false end
        widget = assert(session.make_preview(camera.USB), "预览显示缓冲分配失败")
        camera.on(camera.USB, "scanned", nil)
        camera.on(camera.USB, "usb_raw", function(id, event, slot)
            if session.closed then return end
            if event == usb.EV_CONNECT and not app_id then
                app_id = id
            elseif id == app_id and event == usb.EV_DISCONNECT then
                disconnected = true
            elseif id == app_id and not got_frame and event == usb.EV_NEW_RX and buffers then
                local data = buffers[slot + 1]
                got_frame = data and data:used() > 4 and data:toStr(0, 2) == "\255\216"
            end
        end)
        assert(camera.preview(camera.USB, true), "开启 UVC 解码预览失败")
        assert(board.set_pwm1(100), "打开 J8 VBUS 失败")
        for _ = 1, 80 do
            if session.closed then return false end
            if app_id then break end
            sys.wait(100)
        end
        if not app_id or disconnected then return false, "未枚举摄像头，请检查 J8 和 1034 双路 5 V 供电" end
        local mode = mjpeg_mode(app_id)
        if not mode then return false, "摄像头未提供可预览的 MJPEG 分辨率" end
        assert(camera.set_usb_config(app_id, camera.CONF_UVC_RESOLUTION, mode.format, mode.frame),
            "设置 MJPEG 档位失败")
        local size = mode.w * mode.h
        buffers = {}
        buffers[1] = assert(zbuff.create(size), "UVC 第一块缓冲分配失败")
        buffers[2] = assert(zbuff.create(size), "UVC 第二块缓冲分配失败")
        assert(camera.cache(camera.USB, app_id, buffers[1], buffers[2]), "UVC 缓冲登记失败")
        assert(camera.stream(camera.USB, app_id, 0), "UVC 开流失败")
        log.info("factory_w1", "uvc", c.model, "app", app_id, "MJPEG", mode.w, mode.h, mode.fps)
        for _ = 1, 60 do
            if session.closed or session.verdict == false then return false, "预览已停止" end
            if disconnected or got_frame then break end
            sys.wait(100)
        end
        if disconnected then return false, "摄像头已断开" end
        if not got_frame then return false, "开流后未收到 MJPEG 画面" end
        session.on_ready(string.format("%dx%d MJPEG 已收到，请确认画面持续更新。", mode.w, mode.h))
        while not session.closed and not disconnected and session.verdict == nil do sys.wait(100) end
        if disconnected then return false, "摄像头已断开" end
        if session.verdict == true then return true, "MJPEG 预览已人工确认" end
        return false, "现场确认画面异常"
    end)

    -- USB/解码均由底包异步收尾。先停预览和流，再释放 UI 及双缓冲。
    if host then
        pcall(camera.on, camera.USB, "usb_raw", nil)
        pcall(camera.preview, camera.USB, false)
        if app_id then pcall(camera.close, app_id) end
    end
    local power_ok, off = pcall(board.set_pwm1, 0)
    if host then
        pcall(pm.power, pm.USB, false)
        sys.wait(250)
    end
    if widget then
        pcall(widget.stop, widget)
        pcall(widget.destroy, widget)
    end
    if buffers then
        for _, data in ipairs(buffers) do data:free() end
    end
    if not power_ok or not off then return false, "J8 VBUS 关闭失败" end
    if not called then return false, tostring(passed) end
    return passed, detail
end

return M
