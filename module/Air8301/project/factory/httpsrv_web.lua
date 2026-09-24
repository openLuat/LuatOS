--[[
@module  httpsrv_web
@summary HTTP Web管理界面（网口1, 192.168.1.183:80，Air8301出厂固件）
@version 1.0
@date    2026.09.22
@author  江访
@usage
路由：
  GET  / /index.html     → index.html
  GET  /api/status       → 传感器+设备+网络状态
  GET  /api/sensor       → 继电器状态 + 温湿度数据
  GET  /api/network      → 网络状态
  GET  /api/comm/status  → 通讯状态（寄存器表+通讯日志）
  GET  /api/relay/status → 继电器状态
  POST /api/relay/control→ 继电器控制（open/close/toggle/all_open/all_close/read）
  GET  /api/config       → 当前网络配置（密码掩码）
  POST /api/config       → 保存配置
  POST /api/wifi/scan    → 触发WiFi扫描
  GET  /api/wifi/scan    → 扫描结果
  GET  /api/priority     → 优先级列表
  POST /api/priority     → 保存优先级
  POST /api/reset        → 恢复默认配置
  GET  /api/fota/status  → FOTA 状态
  POST /api/fota/check   → 触发检测更新
  GET  /api/log?msg=xxx  → 调试日志
  GET  /api/temp         → 网口TCP温湿度
]]

local rtu_regmap = require("rtu_slave_regmap")
local net_drv = require("net_drv")
local net_config = require("net_config")
local relay_ctrl = require("relay_ctrl")
local fota_app = require("fota_app")

-- HTTP 服务器配置
local SERVER_PORT = 80
local ADAPTER = socket.LWIP_ETH        -- 网口1, 192.168.1.183

--[[
获取设备信息

@local
@function get_device_info
@return table 设备信息
]]
local function get_device_info()
    local c = net_config.load()
    local info = {
        imei = mobile.imei() or "",
        iccid = mobile.iccid() or "",
        csq = mobile.csq() or 0,
        fw_version = rtos.firmware() or "",
        project = PROJECT or "Air8301_Factory",
        version = VERSION or "001.999.000",
        device_name = c.device_name or "Air8301",
        ntp_server = c.ntp_server or "ntp.aliyun.com",
        timezone = c.timezone or "UTC+8",
        ntp_time = os.date("%Y-%m-%d %H:%M:%S", os.time()),
    }
    return info
end

--[[
获取继电器状态数组（1-based 标准数组，供 JSON 序列化为 [通道0,通道1,…]）

说明（实测踩坑点）：JSON 数组要求 Lua 表从下标 1 开始连续编号。
若按 0 基下标构造（list[0]~list[3]），json.encode 的数组判定不可靠，
会导致网页取到错误/缺失的数据（下标错位、通道 0 丢失，甚至整表退化为对象），
表现为"网页继电器开关点了没反应、状态对不上"。
故此处统一返回 1-based 数组，序列化结果即 [c0,c1,c2,c3]，
前端用 list[i] 即可直接对应通道 i。

@local
@function get_relay_list
@return table 状态列表（1-based：list[1] 对应通道 0，……）
]]
local function get_relay_list()
    local st = relay_ctrl.get_state() or {}
    local list = {}
    for i = 1, relay_ctrl.get_channel_count() do
        list[i] = st[i] or 0
    end
    return list
end

--[[
获取实时数据（继电器 + 温湿度 + 系统）

@local
@function get_sensor_data
@return table 数据表
]]
local function get_sensor_data()
    local data = rtu_regmap.get_all_data()
    local result = {
        relay = get_relay_list(),
        relay_count = relay_ctrl.get_channel_count(),
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

--[[
获取网络状态

@local
@function get_network_status
@return table 网络状态表
]]
local function get_network_status()
    -- 获取指定网卡的 IP 信息
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

-- 温湿度读取日志（最近5条）
local temp_log = {}

--[[
温湿度更新回调：记录日志

@local
@function on_temp_humidity_update
@param temp number 温度
@param humi number 湿度
]]
local function on_temp_humidity_update(temp, humi)
    local msg = string.format("[%s] 温度:%.1f℃ 湿度:%.1f%%",
        os.date("%H:%M:%S"), temp or 0, humi or 0)
    table.insert(temp_log, msg)
    if #temp_log > 5 then table.remove(temp_log, 1) end
end

-- 从站 Modbus 请求日志（RTU + TCP 分开）
local slave_log = {}
local tcp_log = {}

--[[
RTU 从站请求日志回调

@local
@function on_modbus_rtu_req
@param msg string 日志文本
]]
local function on_modbus_rtu_req(msg)
    local s = string.format("[%s] %s", os.date("%H:%M:%S"), tostring(msg or ""))
    table.insert(slave_log, s)
    if #slave_log > 10 then table.remove(slave_log, 1) end
end

--[[
TCP 从站请求日志回调

@local
@function on_modbus_tcp_log
@param msg string 日志文本
]]
local function on_modbus_tcp_log(msg)
    local s = string.format("[%s] %s", os.date("%H:%M:%S"), tostring(msg or ""))
    table.insert(tcp_log, s)
    if #tcp_log > 10 then table.remove(tcp_log, 1) end
end

--[[
继电器主站通讯日志回调

@local
@function on_modbus_master_log
@param msg string 日志文本
]]
local function on_modbus_master_log(msg)
    local s = string.format("[%s] %s", os.date("%H:%M:%S"), tostring(msg or ""))
    table.insert(slave_log, s)
    if #slave_log > 10 then table.remove(slave_log, 1) end
end

sys.subscribe("TEMP_HUMIDITY_UPDATE", on_temp_humidity_update)
sys.subscribe("MODBUS_RTU_REQ", on_modbus_rtu_req)
sys.subscribe("MODBUS_TCP_LOG", on_modbus_tcp_log)
sys.subscribe("MODBUS_MASTER_LOG", on_modbus_master_log)

--[[
获取通讯状态

@local
@function get_comm_status
@return table 通讯状态表
]]
local function get_comm_status()
    local data = rtu_regmap.get_all_data()
    local relay_list = get_relay_list()
    local relay_str = table.concat(relay_list, ",")
    return {
        rs485_master = {
            uart = 11, baud = 9600, dir_pin = 153,
            slave_id = 1, reg_start = "0x0000", reg_count = relay_ctrl.get_channel_count(),
            relay = relay_str,
            status = "ok",
        },
        rs485_slave = {
            uart = 1, baud = 115200, dir_pin = 2, slave_id = 1,
        },
        tcp_slave = {
            ip = "192.168.1.185", port = 502, slave_id = 1,
        },
        registers = {
            {addr="0x0000",cnt=1,name="继电器状态位掩码",src="485继电器模块",value=relay_str},
            {addr="0x0001-04",cnt=4,name="继电器各路开关(读=状态,写=开关)",src="485继电器模块",value=relay_str},
            {addr="0x0005-06",cnt=2,name="CPU温度",src="模块内部 ADC",value=string.format("%.1f ℃",data.cpu_temperature or 0)},
            {addr="0x0007-08",cnt=2,name="VBAT电压",src="模块内部 ADC",value=string.format("%.3f V",data.vbat_voltage or 0)},
            {addr="0x0009-12",cnt=10,name="LBS纬度",src="定位模块",value=data.latitude or "--"},
            {addr="0x0013-1C",cnt=10,name="LBS经度",src="定位模块",value=data.longitude or "--"},
            {addr="0x001D",cnt=1,name="4G信号强度",src="移动网络",value=string.format("%d dBm",data.signal_strength or 0)},
            {addr="0x001E-29",cnt=12,name="设备IMEI",src="移动网络",value=data.imei or "--"},
            {addr="0x002A-37",cnt=14,name="SIM ICCID",src="移动网络",value=data.iccid or "--"},
            {addr="0x0038-39",cnt=2,name="时间戳",src="NTP",value=tostring(data.timestamp or 0)},
            {addr="0x003A-3B",cnt=2,name="温湿度传感器-温度",src="网口TCP主站",value=string.format("%.1f ℃",data.temperature or 0)},
            {addr="0x003C-3D",cnt=2,name="温湿度传感器-湿度",src="网口TCP主站",value=string.format("%.1f %%RH",data.humidity or 0)},
            {addr="0x0050",cnt=1,name="继电器控制字(可写)",src="Modbus主站",value="0x0000~0xFFFF"},
        },
        log = temp_log,
        slave_log = slave_log,
        tcp_log = tcp_log,
    }
end

--[[
URL 解码

@local
@function url_decode
@param s string 原始字符串
@return string 解码后字符串
]]
local function url_decode(s)
    if not s then return "" end
    s = string.gsub(s, "+", " ")
    s = string.gsub(s, "%%(%x%x)", function(h) return string.char(tonumber(h, 16)) end)
    return s
end

--[[
处理继电器控制请求

背景（实测踩坑点）：httpsrv 的请求回调运行在 socket 回调上下文（非协程）。
若在本函数中直接调用 relay_ctrl.open()/close()/toggle()/all_open()/all_close()/read_status()，
其内部会走 comm_core → exmodbus → sys.waitUntil 等待 485 主站应答，
在非协程中 yield 会触发错误：
  attempt to yield from outside a coroutine
进而 Lua VM 退出并重启（设备 15 秒后重启）。
对策：本函数只做"指令投递"，通过 sys.publish 发布 RELAY_SET_REQ
（relay_ctrl 已在协程上下文中订阅该消息并执行），HTTP 侧立即返回受理结果。
状态显示由前端轮询 /api/relay/status 获取，因此应答中的 relay 为下发瞬间的缓存值。

@local
@function handle_relay_control
@param tbl table 请求体 {action=..., channel=...}
@return table 应答表
]]
local function handle_relay_control(tbl)
    local action = tbl.action or ""
    local ch = tbl.channel
    -- 只做指令投递，绝不在此（非协程）直接调用会阻塞等待的继电器接口
    if action == "open" and ch then
        sys.publish("RELAY_SET_REQ", ch, "open")
    elseif action == "close" and ch then
        sys.publish("RELAY_SET_REQ", ch, "close")
    elseif action == "toggle" and ch then
        sys.publish("RELAY_SET_REQ", ch, "toggle")
    elseif action == "all_open" then
        sys.publish("RELAY_SET_REQ", nil, "all_open")
    elseif action == "all_close" then
        sys.publish("RELAY_SET_REQ", nil, "all_close")
    elseif action == "read" then
        sys.publish("RELAY_SET_REQ", nil, "read")
    else
        return { code = -1, msg = "非法操作或缺少通道号" }
    end
    return { code = 0, msg = "accepted", data = { relay = get_relay_list() } }
end

--[[
HTTP 请求处理回调

@local
@function handle_http_request
@param fd userdata 连接
@param method string 请求方法
@param uri string 请求路径
@param headers table 请求头
@param body string 请求体
@return number 状态码
@return table 响应头
@return string 响应体
]]
local function handle_http_request(fd, method, uri, headers, body)
    -- 静默高频请求，避免日志刷屏
    if uri == "/api/status" or uri == "/api/sensor" or uri == "/api/network"
        or string.sub(uri, 1, 10) == "/api/config"
        or string.sub(uri, 1, 13) == "/api/wifi/scan"
        or string.sub(uri, 1, 13) == "/api/priority"
        or string.sub(uri, 1, 14) == "/api/comm/status"
        or string.sub(uri, 1, 12) == "/api/relay/s" then
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
        return 200, {
            ["Content-Type"] = "application/json; charset=utf-8",
            ["Access-Control-Allow-Origin"] = "*",
        }, json.encode(result)
    end

    -- API: 数据（继电器 + 温湿度）
    if uri == "/api/sensor" then
        local result = { code = 0, msg = "ok", data = get_sensor_data() }
        return 200, {
            ["Content-Type"] = "application/json; charset=utf-8",
            ["Access-Control-Allow-Origin"] = "*",
        }, json.encode(result)
    end

    -- API: 网口TCP温湿度
    if uri == "/api/temp" then
        local d = rtu_regmap.get_all_data()
        return 200, {["Content-Type"]="application/json; charset=utf-8"},
            json.encode({code=0, data={temperature=d.temperature or 0, humidity=d.humidity or 0}})
    end

    -- API: 网络状态
    if uri == "/api/network" then
        local result = { code = 0, msg = "ok", data = get_network_status() }
        return 200, {
            ["Content-Type"] = "application/json; charset=utf-8",
            ["Access-Control-Allow-Origin"] = "*",
        }, json.encode(result)
    end

    -- API: 继电器状态
    if uri == "/api/relay/status" and method == "GET" then
        return 200, {["Content-Type"]="application/json; charset=utf-8"},
            json.encode({code=0, data={relay=get_relay_list(), relay_count=relay_ctrl.get_channel_count()}})
    end

    -- API: 继电器控制
    if uri == "/api/relay/control" and method == "POST" then
        local ok, tbl = pcall(json.decode, body or "{}")
        if ok and type(tbl) == "table" then
            local resp = handle_relay_control(tbl)
            return 200, {["Content-Type"]="application/json; charset=utf-8"}, json.encode(resp)
        end
        return 400, {}, json.encode({code=-1, msg="数据格式错误"})
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

    -- API: FOTA 升级
    if uri == "/api/fota/check" and method == "POST" then
        fota_app.check()
        return 200, {}, json.encode({code=0})
    end
    if uri == "/api/fota/status" then
        return 200, {}, json.encode({code=0, data=fota_app.get_status()})
    end
    if uri == "/api/fota/config" then
        if method == "POST" then
            local ok, tbl = pcall(json.decode, body or "{}")
            if ok then
                fota_app.config({auto=tbl.auto, interval=tbl.interval})
                return 200, {}, json.encode({code=0})
            end
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

--[[
启动网口1的 HTTP 服务器任务

@local
@function task_httpsrv_eth
]]
local function task_httpsrv_eth()
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
end

--[[
启动 WiFi AP 热点的 HTTP 服务器任务（电脑可通过 WiFi 直连访问）

@local
@function task_httpsrv_ap
]]
local function task_httpsrv_ap()
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
end

sys.taskInit(task_httpsrv_eth)
sys.taskInit(task_httpsrv_ap)

log.info("httpsrv", "Web管理模块加载完成")
