--[[
@module  httpsrv_web
@summary HTTP Web管理界面（网口1, 192.168.1.183:80）
@version 1.3
@date    2026.06.09

路由：
  GET  / /index.html     → index.html
  GET  /api/status       → 传感器+设备+网络状态
  GET  /api/sensor       → 温湿度数据
  GET  /api/network      → 网络状态
  GET  /api/comm/status  → 通讯状态（寄存器表+传感器日志）
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

-- HTTP 服务器配置
local SERVER_PORT = 80
local ADAPTER = socket.LWIP_ETH        -- 网口1, 192.168.1.183

-- 获取设备信息
local function get_device_info()
    local c = net_config.load()
    local info = {
        imei = mobile.imei() or "",
        iccid = mobile.iccid() or "",
        csq = mobile.csq() or 0,
        fw_version = rtos.version() or "",
        project = PROJECT or "SOCKET_LONG_CONNECTION",
        version = VERSION or "001.999.000",
        device_name = c.device_name or "Air8000",
        ntp_server = c.ntp_server or "ntp.aliyun.com",
        timezone = c.timezone or "UTC+8",
        ntp_time = os.date("%Y-%m-%d %H:%M:%S", os.time()),
    }
    return info
end

-- 获取实时传感器数据
local function get_sensor_data()
    local data = rtu_regmap.get_all_data()
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

-- 传感器读取日志（最近5条，纯字符串）
local sensor_log = {}
sys.subscribe("SENSOR_READ_RESULT", function(status, temp, humi)
    local s = tostring(status or "unknown")
    local t = temp or 0
    local h = humi or 0
    local msg = string.format("[%s] %s 温度:%.1f℃ 湿度:%.1f%%", os.date("%H:%M:%S"), s, t, h)
    log.info("web", "传感器:", msg)
    table.insert(sensor_log, msg)
    if #sensor_log > 5 then table.remove(sensor_log, 1) end
end)

-- 从站 Modbus 请求日志（RTU + TCP 分开）
local slave_log = {}
local tcp_log = {}
sys.subscribe("MODBUS_RTU_REQ", function(msg)
    local s = string.format("[%s] %s", os.date("%H:%M:%S"), tostring(msg or ""))
    table.insert(slave_log, s)
    if #slave_log > 10 then table.remove(slave_log, 1) end
end)
sys.subscribe("MODBUS_TCP_REQ", function(msg)
    local s = string.format("[%s] %s", os.date("%H:%M:%S"), tostring(msg or ""))
    table.insert(tcp_log, s)
    if #tcp_log > 10 then table.remove(tcp_log, 1) end
end)

-- 获取通讯状态
local function get_comm_status()
    local data = rtu_regmap.get_all_data()
    return {
        rs485_master = {
            uart = 1, baud = 9600, dir_pin = 37,
            slave_id = 1, reg_start = "0x001E", reg_count = 2,
            temperature = data.temperature or 0,
            humidity = data.humidity or 0,
            status = (data.temperature ~= 0 or data.humidity ~= 0) and "ok" or "timeout",
        },
        rs485_slave = {
            uart = 3, baud = 9600, dir_pin = 36, slave_id = 1,
        },
        tcp_slave = {
            ip = "192.168.1.185", port = 502, slave_id = 1,
        },
        registers = {
            {addr="0x0000-01",cnt=2,name="RTU传感器湿度",src="RS485 XY-MD02",value=string.format("%.1f %%RH",data.humidity or 0)},
            {addr="0x0002-03",cnt=2,name="RTU传感器温度",src="RS485 XY-MD02",value=string.format("%.1f ℃",data.temperature or 0)},
            {addr="0x0004-05",cnt=2,name="CPU温度",src="模块内部 ADC",value=string.format("%.1f ℃",data.cpu_temperature or 0)},
            {addr="0x0006-07",cnt=2,name="VBAT电压",src="模块内部 ADC",value=string.format("%.3f V",data.vbat_voltage or 0)},
            {addr="0x0008-11",cnt=10,name="LBS纬度",src="定位模块",value=data.latitude or "--"},
            {addr="0x0012-1B",cnt=10,name="LBS经度",src="定位模块",value=data.longitude or "--"},
            {addr="0x001C",cnt=1,name="4G信号强度",src="移动网络",value=string.format("%d dBm",data.signal_strength or 0)},
            {addr="0x001D-28",cnt=12,name="设备IMEI",src="移动网络",value=data.imei or "--"},
            {addr="0x0029-36",cnt=14,name="SIM ICCID",src="移动网络",value=data.iccid or "--"},
            {addr="0x0037-38",cnt=2,name="时间戳",src="NTP",value=tostring(data.timestamp or 0)},
        },
        log = sensor_log,
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
    if uri == "/api/fota/download" and method == "POST" then
        sys.taskInit(function() fota_app.download() end)
        return 200, {}, json.encode({code=0})
    end
    if uri == "/api/fota/reboot" and method == "POST" then
        fota_app.reboot()
        return 200, {}, json.encode({code=0})
    end
    if uri == "/api/fota/status" then
        return 200, {}, json.encode({code=0, data=fota_app.get_status()})
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
    
    -- 启动 HTTP 服务器
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

log.info("httpsrv", "Web管理模块加载完成")
