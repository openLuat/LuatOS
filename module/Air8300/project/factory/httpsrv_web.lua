--[[
@module  httpsrv_web
@summary HTTP Web管理界面（网口1, 192.168.1.183:80）
@version 1.0
@date    2026.09.24

路由：
  GET  / /index.html     → index.html
  GET  /api/status       → 传感器+设备+网络状态
  GET  /api/sensor       → 温湿度数据
  GET  /api/network      → 网络状态
  GET  /api/comm/status  → 通讯状态（继电器+温湿度+寄存器表+日志）
  GET  /api/relay/status → 4路继电器状态
  POST /api/relay/set    → 单路继电器开/关 {channel:0~3, state:0/1}
  POST /api/relay/all    → 全部继电器开/关 {state:0/1}
  POST /api/relay/read   → 触发一次继电器状态回读
  GET  /api/led/state    → 三色LED当前状态
  POST /api/led/set      → 三色LED控制 {color:"red"/"green"/"blue"/"off"}（三路互斥）
  GET  /api/config       → 当前网络配置（密码掩码）
  POST /api/config       → 保存配置
  POST /api/wifi/scan    → 触发WiFi扫描
  GET  /api/wifi/scan    → 扫描结果
  GET  /api/priority     → 优先级列表
  POST /api/priority     → 保存优先级
  GET  /api/log?msg=xxx  → 调试日志
]] 

local rtu_regmap = require("rtu_slave_regmap")
local net_drv = require("net_drv")
local net_config = require("net_config")
local power_mgr = require("power_mgr")
local gpio_ctrl = require("gpio_ctrl")
local fota_app = require("fota_app")
local relay_ctrl = require("relay_ctrl")
local led = require("led")

-- HTTP 服务器配置
local SERVER_PORT = 80
local ADAPTER = socket.LWIP_ETH        -- 网口1, 192.168.1.183

-- 链路状态判定窗口（秒）：该时间内有成功数据更新即认为链路正常
local LINK_OK_WINDOW = 30
-- 最近一次温湿度成功采集时间 / 最近一次继电器状态更新时间
local last_tcp_th_time = 0
local last_relay_time = 0

-- 获取设备信息
local function get_device_info()
    local c = net_config.load()
    local info = {
        imei = mobile.imei() or "",
        iccid = mobile.iccid() or "",
        csq = mobile.csq() or 0,
        fw_version = rtos.firmware() or "",
        project = PROJECT or "SOCKET_LONG_CONNECTION",
        version = VERSION or "002.999.001",
        device_name = c.device_name or "Air8300",
        ntp_server = c.ntp_server or "ntp.aliyun.com",
        timezone = c.timezone or "UTC+8",
        ntp_time = os.date("%Y-%m-%d %H:%M:%S", os.time()),
    }
    return info
end

-- 获取实时数据（温湿度 + 4路继电器状态）
local function get_sensor_data()
    local data = rtu_regmap.get_all_data()
    local relay = {}
    local st = relay_ctrl.get_state() or data.relay or {}
    for i = 1, relay_ctrl.get_channel_count() do
        relay[i] = st[i] or 0
    end
    local result = {
        temperature = data.temperature or 0,
        humidity = data.humidity or 0,
        cpu_temperature = data.cpu_temperature or 0,
        vbat_voltage = data.vbat_voltage or 0,
        latitude = data.latitude or "",
        longitude = data.longitude or "",
        signal_strength = data.signal_strength or 0,
        imei = data.imei or "",
        iccid = data.iccid or "",
        timestamp = data.timestamp or 0,
        relay = relay,
    }
    return result
end

-- 获取网络状态
local function get_network_status()
    local function ip_info(adapter)
        local is_eth = (adapter == socket.LWIP_ETH or adapter == socket.LWIP_USER1)
        if socket.adapter(adapter) and (not is_eth or netdrv.link(adapter)) then
            local ip, mask, gw = netdrv.ipv4(adapter)
            return { ip = ip or "--", mask = mask or "--", gw = gw or "--", ready = true }
        end
        return { ip = "--", mask = "--", gw = "--", ready = false }
    end
    local w = ip_info(socket.LWIP_STA)
    if w.ready and wlan.getInfo then
        local wi = wlan.getInfo()
        if wi then w.rssi = wi.rssi end
    end
    w.ssid = net_drv.get_wifi_ssid()
    local e1 = ip_info(socket.LWIP_ETH)
    local e2 = ip_info(socket.LWIP_USER1)
    return {
        wifi = w,
        eth1 = e1,
        eth2 = e2,
        net4g = {
            ready = socket.adapter(socket.LWIP_GP) and true or false,
            csq = mobile.csq() or 0,
            rssi = mobile.rssi(),
            rsrp = mobile.rsrp(),
            imei = mobile.imei() or "--",
            iccid = mobile.iccid() or "--",
            sim_ready = mobile.simPin() and true or false,
            net_status = mobile.status(),
            operator = net_drv.get_operator(),
        },
    }
end

-- 温湿度采集日志（最近5条，纯字符串）
local sensor_log = {}
local function on_tcp_temp_humidity_update(temp, humi)
    last_tcp_th_time = os.time()
    local msg = string.format("[%s] 采集成功 温度:%.1f℃ 湿度:%.1f%%", os.date("%H:%M:%S"), temp or 0, humi or 0)
    log.info("web", "温湿度:", msg)
    table.insert(sensor_log, msg)
    if #sensor_log > 5 then table.remove(sensor_log, 1) end
end
sys.subscribe("TCP_TEMP_HUMIDITY_UPDATE", on_tcp_temp_humidity_update)

-- 温湿度采集失败日志
local function on_tcp_temp_humidity_error(status)
    local msg = string.format("[%s] 采集失败 状态:%s", os.date("%H:%M:%S"), tostring(status))
    log.warn("web", "温湿度:", msg)
    table.insert(sensor_log, msg)
    if #sensor_log > 5 then table.remove(sensor_log, 1) end
end
sys.subscribe("TCP_TEMP_HUMIDITY_ERROR", on_tcp_temp_humidity_error)

-- 继电器状态更新（记录最近更新时间，用于页面显示链路状态）
local function on_relay_status_update(state)
    last_relay_time = os.time()
end
sys.subscribe("RELAY_STATUS_UPDATE", on_relay_status_update)

-- 继电器操作日志（最近10条，纯字符串）
local relay_log = {}
local function on_relay_op_log(msg)
    local s = string.format("[%s] %s", os.date("%H:%M:%S"), tostring(msg or ""))
    log.info("web", "继电器:", s)
    table.insert(relay_log, s)
    if #relay_log > 10 then table.remove(relay_log, 1) end
end
sys.subscribe("RELAY_OP_LOG", on_relay_op_log)

-- 从站 Modbus 请求日志（RTU + TCP 分开）
local slave_log = {}
local tcp_log = {}
local function on_modbus_rtu_req(msg)
    local s = string.format("[%s] %s", os.date("%H:%M:%S"), tostring(msg or ""))
    table.insert(slave_log, s)
    if #slave_log > 10 then table.remove(slave_log, 1) end
end
local function on_modbus_tcp_req(msg)
    local s = string.format("[%s] %s", os.date("%H:%M:%S"), tostring(msg or ""))
    table.insert(tcp_log, s)
    if #tcp_log > 10 then table.remove(tcp_log, 1) end
end
sys.subscribe("MODBUS_RTU_REQ", on_modbus_rtu_req)
sys.subscribe("MODBUS_TCP_REQ", on_modbus_tcp_req)

-- 获取4路继电器状态（1-based 数组）
local function get_relay_state()
    local ch_count = relay_ctrl.get_channel_count()
    local st = relay_ctrl.get_state() or {}
    local arr = {}
    for i = 1, ch_count do
        arr[i] = st[i] or 0
    end
    return arr, ch_count
end

-- 获取通讯状态
local function get_comm_status()
    local data = rtu_regmap.get_all_data()
    local relay_state, ch_count = get_relay_state()
    local now = os.time()
    local relay_ok = (last_relay_time > 0) and ((now - last_relay_time) < LINK_OK_WINDOW)
    local th_ok = (last_tcp_th_time > 0) and ((now - last_tcp_th_time) < LINK_OK_WINDOW)
    -- 继电器状态字符串，如 "1,0,1,0"（依次为继电器1~4，1=吸合 0=断开）
    local relay_str = table.concat(relay_state, ",")
    return {
        -- RS485 继电器主站（隔离485 UART1）
        relay = {
            uart = 1, baud = 9600, dir_pin = 37,
            slave_id = 1, coil_base = "0x0000", channels = ch_count,
            state = relay_state,
            state_str = relay_str,
            status = relay_ok and "ok" or "timeout",
        },
        -- 温湿度采集（Modbus TCP 主站，网口1）
        tcp_master = {
            adapter = "网口1", ip = "192.168.1.100", port = 500,
            slave_id = 1, reg_start = "0x0000", reg_count = 2,
            temperature = data.temperature or 0,
            humidity = data.humidity or 0,
            status = th_ok and "ok" or "timeout",
        },
        rs485_slave = {
            uart = 3, baud = 9600, dir_pin = 36, slave_id = 1,
        },
        tcp_slave = {
            ip = "192.168.1.185", port = 502, slave_id = 1,
        },
        registers = {
            {addr="0x0000-01",cnt=2,name="环境湿度",src="以太网温湿度变送器",value=string.format("%.1f %%RH",data.humidity or 0)},
            {addr="0x0002-03",cnt=2,name="环境温度",src="以太网温湿度变送器",value=string.format("%.1f ℃",data.temperature or 0)},
            {addr="0x0004-05",cnt=2,name="CPU温度",src="模块内部 ADC",value=string.format("%.1f ℃",data.cpu_temperature or 0)},
            {addr="0x0006-07",cnt=2,name="VBAT电压",src="模块内部 ADC",value=string.format("%.3f V",data.vbat_voltage or 0)},
            {addr="0x0008-11",cnt=10,name="LBS纬度",src="定位模块",value=data.latitude or "--"},
            {addr="0x0012-1B",cnt=10,name="LBS经度",src="定位模块",value=data.longitude or "--"},
            {addr="0x001C",cnt=1,name="4G信号强度",src="移动网络",value=string.format("%d dBm",data.signal_strength or 0)},
            {addr="0x001D-28",cnt=12,name="设备IMEI",src="移动网络",value=data.imei or "--"},
            {addr="0x0029-36",cnt=14,name="SIM ICCID",src="移动网络",value=data.iccid or "--"},
            {addr="0x0037-38",cnt=2,name="时间戳",src="NTP",value=tostring(data.timestamp or 0)},
            {addr="0x0039",cnt=1,name="继电器1状态",src="485继电器模块",value=string.format("%d（%s）",relay_state[1] or 0,(relay_state[1] == 1) and "吸合" or "断开")},
            {addr="0x003A",cnt=1,name="继电器2状态",src="485继电器模块",value=string.format("%d（%s）",relay_state[2] or 0,(relay_state[2] == 1) and "吸合" or "断开")},
            {addr="0x003B",cnt=1,name="继电器3状态",src="485继电器模块",value=string.format("%d（%s）",relay_state[3] or 0,(relay_state[3] == 1) and "吸合" or "断开")},
            {addr="0x003C",cnt=1,name="继电器4状态",src="485继电器模块",value=string.format("%d（%s）",relay_state[4] or 0,(relay_state[4] == 1) and "吸合" or "断开")},
        },
        log = sensor_log,
        relay_log = relay_log,
        slave_log = slave_log,
        tcp_log = tcp_log,
    }
end

-- URL 解码
local function url_decode(s)
    if not s then return "" end
    s = string.gsub(s, "+", " ")
    s = string.gsub(s, "%%(%x%x)", function(h) return string.char(tonumber(h, 16)) end)
    return s
end

-- HTTP 请求处理回调
local function handle_http_request(fd, method, uri, headers, body)
    -- 静默高频请求，避免日志刷屏
    if uri == "/api/status" or uri == "/api/sensor" or uri == "/api/network"
        or string.sub(uri, 1, 10) == "/api/config" 
        or string.sub(uri, 1, 13) == "/api/wifi/scan"
        or string.sub(uri, 1, 13) == "/api/priority"
        or string.sub(uri, 1, 14) == "/api/relay/status"
        or string.sub(uri, 1, 14) == "/api/led/state"
        or string.sub(uri, 1, 14) == "/api/comm/status" then
    elseif string.sub(uri, 1, 9) == "/api/log?" then
        -- 页面操作日志（URL 解码后输出）
        local msg = url_decode(string.sub(uri, 10))
        log.info("web", msg)
    else
        log.info("web", method, uri)
    end
    
    if uri == "/" or uri == "/index.html" then
        local f = io.open("/luadb/index.html", "r")
        if f then
            local content = f:read("*a")
            f:close()
            log.info("httpsrv", "首页响应, 内容长度:", #content)
            return 200, {
                ["Content-Type"] = "text/html; charset=utf-8",
            }, content
        end
        log.warn("httpsrv", "index.html 文件未找到")
        return 404, {}, "html file not found"
    end
    
    -- API: 设备全部状态
    if uri == "/api/status" then
        local result = {
            code = 0,
            msg = "ok",
            data = {
                sensor = get_sensor_data(),
                device = get_device_info(),
                network = get_network_status(),
                comm = get_comm_status(),
            }
        }
        local json_str = json.encode(result)
        return 200, {
            ["Content-Type"] = "application/json; charset=utf-8",
            ["Access-Control-Allow-Origin"] = "*",
        }, json_str
    end
    
    -- API: 传感器数据
    if uri == "/api/sensor" then
        local result = {
            code = 0,
            msg = "ok",
            data = get_sensor_data(),
        }
        local json_str = json.encode(result)
        return 200, {
            ["Content-Type"] = "application/json; charset=utf-8",
            ["Access-Control-Allow-Origin"] = "*",
        }, json_str
    end
    
    -- API: 网络状态
    if uri == "/api/network" then
        local result = {
            code = 0,
            msg = "ok",
            data = get_network_status(),
        }
        local json_str = json.encode(result)
        return 200, {
            ["Content-Type"] = "application/json; charset=utf-8",
            ["Access-Control-Allow-Origin"] = "*",
        }, json_str
    end

    -- API: 4路继电器状态
    if uri == "/api/relay/status" then
        local relay_state, ch_count = get_relay_state()
        local now = os.time()
        local result = {
            code = 0,
            msg = "ok",
            data = {
                channels = ch_count,
                state = relay_state,
                state_str = table.concat(relay_state, ","),
                status = ((last_relay_time > 0) and ((now - last_relay_time) < LINK_OK_WINDOW)) and "ok" or "timeout",
            }
        }
        return 200, {
            ["Content-Type"] = "application/json; charset=utf-8",
            ["Access-Control-Allow-Origin"] = "*",
        }, json.encode(result)
    end

    -- API: 单路继电器开/关 {channel:0~3, state:0/1}
    if uri == "/api/relay/set" and method == "POST" then
        local ok, tbl = pcall(json.decode, body or "{}")
        local channel = ok and tonumber(tbl.channel) or nil
        local state = ok and tonumber(tbl.state) or nil
        if channel == nil or state == nil then
            return 400, {}, json.encode({code=-1, msg="参数错误"})
        end
        -- 【关键】HTTP 回调由 C 层直接调用，不在协程中，不能直接执行会 sys.wait 的 Modbus 事务，
        --        否则会触发 "attempt to yield from outside a coroutine" 导致 Lua VM 退出、设备重启。
        --        此处只投递异步命令，由 relay_ctrl 常驻工作协程串行执行；
        --        真实执行结果由 relay_ctrl 广播，页面通过 /api/relay/status 轮询刷新。
        if state == 1 then
            relay_ctrl.post_open(channel)
        else
            relay_ctrl.post_close(channel)
        end
        -- 返回 0 表示"命令已成功入队"（并非执行结果）；真实结果由 relay_ctrl 广播，
        -- 页面通过 /api/relay/status 以 1 秒周期轮询确认（含乐观更新保护，避免状态闪回）。
        return 200, {["Content-Type"]="application/json"}, json.encode({
            code = 0,
            msg = "ok",
            data = { state = get_relay_state() },
        })
    end

    -- API: 全部继电器开/关 {state:0/1}
    if uri == "/api/relay/all" and method == "POST" then
        local ok, tbl = pcall(json.decode, body or "{}")
        local state = ok and tonumber(tbl.state) or nil
        if state == nil then
            return 400, {}, json.encode({code=-1, msg="参数错误"})
        end
        -- 同 /api/relay/set：非协程环境只能投递异步命令，不能直接执行 Modbus 事务
        if state == 1 then
            relay_ctrl.post_all_open()
        else
            relay_ctrl.post_all_close()
        end
        -- 同 /api/relay/set：返回 0 表示命令已入队，真实结果由状态轮询确认
        return 200, {["Content-Type"]="application/json"}, json.encode({
            code = 0,
            msg = "ok",
            data = { state = get_relay_state() },
        })
    end

    -- API: 触发一次继电器状态回读
    if uri == "/api/relay/read" and method == "POST" then
        -- 同 /api/relay/set：非协程环境只能投递异步命令，结果由状态接口轮询获取
        relay_ctrl.post_read()
        return 200, {["Content-Type"]="application/json"}, json.encode({
            code = 0,
            msg = "回读已触发",
            data = { state = get_relay_state() },
        })
    end

    -- API: 三色LED当前状态
    if uri == "/api/led/state" and method == "GET" then
        return 200, {["Content-Type"]="application/json; charset=utf-8"}, json.encode({
            code = 0,
            msg = "ok",
            data = { color = led.get_state() },
        })
    end

    -- API: 三色LED控制 {color:"red"/"green"/"blue"/"off"}（三路互斥，同一时刻只亮一路）
    if uri == "/api/led/set" and method == "POST" then
        local ok, tbl = pcall(json.decode, body or "{}")
        local color = ok and tbl.color or nil
        -- 【关键】LED 控制仅 gpio.set，不含 sys.wait，可在 HTTP 回调（非协程环境）中直接执行
        if color == nil or not led.set_color(color) then
            return 400, {}, json.encode({code=-1, msg="参数错误（color 可选 red/green/blue/off）"})
        end
        return 200, {["Content-Type"]="application/json; charset=utf-8"}, json.encode({
            code = 0,
            msg = "ok",
            data = { color = led.get_state() },
        })
    end

    -- API: 获取配置（密码掩码）
    if uri == "/api/config" and method == "GET" then
        return 200, {["Content-Type"]="application/json"}, json.encode({code=0, data=net_config.get_masked()})
    end
    -- API: 保存配置
    if uri == "/api/config" and method == "POST" then
        local ok, tbl = pcall(json.decode, body or "{}")
        if ok and type(tbl) == "table" then
            net_config.save(tbl)
            return 200, {}, json.encode({code=0, msg="ok"})
        end
        return 400, {}, json.encode({code=-1, msg="数据格式错误"})
    end
    -- API: 触发WiFi扫描
    if uri == "/api/wifi/scan" and method == "POST" then
        net_drv.wifi_scan()
        return 200, {}, json.encode({code=0, msg="扫描已触发，3秒后获取结果"})
    end
    -- API: 获取WiFi扫描结果
    if uri == "/api/wifi/scan" and method == "GET" then
        local results = net_drv.wifi_scan_result()
        local list = {}
        for _, ap in ipairs(results) do
            table.insert(list, {ssid = ap.ssid or "", rssi = ap.rssi or 0})
        end
        return 200, {}, json.encode({code=0, data=list})
    end
    -- API: 获取优先级
    if uri == "/api/priority" and method == "GET" then
        return 200, {}, json.encode({code=0, data=net_config.load().priority})
    end
    -- API: 保存优先级
    if uri == "/api/priority" and method == "POST" then
        local ok, tbl = pcall(json.decode, body or "{}")
        if ok and tbl.priority then
            net_config.save({priority = tbl.priority})
            return 200, {}, json.encode({code=0, msg="优先级已更新"})
        end
        return 400, {}, json.encode({code=-1, msg="数据格式错误"})
    end
    
    -- API: 恢复出厂设置
    if uri == "/api/reset" and method == "POST" then
        net_config.reset()
        return 200, {}, json.encode({code=0, msg="已恢复默认配置"})
    end
    if uri == "/api/power" and method == "POST" then
        local ok, tbl = pcall(json.decode, body or "{}")
        if ok and tbl.mode then
            power_mgr.set_mode(tbl.mode)
            return 200, {}, json.encode({code=0, msg="ok"})
        end
        return 400, {}, json.encode({code=-1})
    end
    if uri == "/api/power" and method == "GET" then
        return 200, {}, json.encode({code=0, mode=power_mgr.get_mode()})
    end
    -- GPIO 控制
    if uri == "/api/gpio/set" and method == "POST" then
        local ok, tbl = pcall(json.decode, body or "{}")
        if ok and tbl.pin and tbl.state ~= nil then
            gpio_ctrl.set(tbl.pin, tbl.state)
            return 200, {}, json.encode({code=0})
        end
        return 400, {}, json.encode({code=-1})
    end
    if uri == "/api/gpio/list" then
        return 200, {}, json.encode({code=0, data=gpio_ctrl.list()})
    end
    if string.sub(uri or "", 1, 13) == "/api/gpio/get?" then
        local pin = tonumber(string.match(uri, "pin=(%d+)")) or 0
        return 200, {}, json.encode({code=0, pin=pin, state=gpio_ctrl.get(pin)})
    end
    -- FOTA 升级
    if uri == "/api/fota/check" and method == "POST" then
        sys.taskInit(function() fota_app.check() end)
        return 200, {}, json.encode({code=0})
    end
    if uri == "/api/fota/reboot" and method == "POST" then
        sys.wait(500); rtos.reboot()
        return 200, {}, json.encode({code=0})
    end
    if uri == "/api/fota/status" then
        return 200, {}, json.encode({code=0, data=fota_app.get_status()})
    end
    if uri == "/api/fota/config" then
        if method == "POST" then
            local ok, tbl = pcall(json.decode, body or "{}")
            if ok then fota_app.config({auto=tbl.auto, interval=tbl.interval}); return 200, {}, json.encode({code=0}) end
            return 400, {}, json.encode({code=-1})
        else
            return 200, {}, json.encode({code=0, data=fota_app.get_config()})
        end
    end
    
    -- API: 通讯状态
    if uri == "/api/comm/status" and method == "GET" then
        return 200, {["Content-Type"]="application/json"}, json.encode({code=0, data=get_comm_status()})
    end
    
    -- 调试日志: GET /api/log?msg=xxx
    if method == "GET" and string.sub(uri, 1, 9) == "/api/log?" then
        return 200, {}, "ok"
    end
    
    -- 忽略浏览器自动请求
    if uri == "/favicon.ico" then
        return 404, {}, ""
    end
    
    -- 其余路径返回 404
    log.info("httpsrv", "未匹配路径:", uri)
    return 404, {}, "Not Found: " .. uri
end

-- 启动 HTTP 服务器
sys.taskInit(function()
    -- 等待网口1网络就绪
    log.info("httpsrv", "等待网口1网络就绪...")
    while not socket.adapter(ADAPTER) do
        sys.wait(1000)
    end
    
    sys.wait(2000)
    local server_ip = socket.localIP(ADAPTER) or "192.168.1.183"
    log.info("httpsrv", "网口1已就绪, IP:", server_ip)
    
    -- 启动 HTTP 服务器（网口1）
    httpsrv.start(SERVER_PORT, handle_http_request, ADAPTER)
    
    log.info("httpsrv", "HTTP Web服务器已启动")
    log.info("httpsrv", "访问地址: http://" .. server_ip)
    log.info("httpsrv", "监听端口:", SERVER_PORT)
    
    -- 保持服务器运行
    while true do
        sys.wait(60000)
        log.info("httpsrv", "Web服务器运行中, 访问 http://" .. socket.localIP(ADAPTER))
    end
end)

-- WiFi AP 热点 HTTP 服务器（电脑可通过 WiFi 直连访问）
sys.taskInit(function()
    local AP_ADAPTER = socket.LWIP_AP
    log.info("httpsrv", "等待WiFi AP就绪...")
    while not netdrv.ready(AP_ADAPTER) do
        sys.wait(1000)
    end
    sys.wait(1000)
    local ap_ip = socket.localIP(AP_ADAPTER) or "192.168.4.1"
    httpsrv.start(SERVER_PORT, handle_http_request, AP_ADAPTER)
    log.info("httpsrv", "WiFi AP Web服务器已启动")
    log.info("httpsrv", "WiFi访问: http://" .. ap_ip)
end)

log.info("httpsrv", "Web管理模块加载完成")
