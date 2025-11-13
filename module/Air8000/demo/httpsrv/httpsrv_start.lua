--[[
@module  httpsrv_start
@summary Air8000 HTTP服务器应用模块
@version 1.0
@date    2025.10.24
@author  拓毅恒
@usage
本文件为Air8000开发板演示 HTTP 服务器功能的应用模块，核心业务逻辑为：
1. 初始化HTTP服务器
2. 配置HTTP服务器参数
3. 启动HTTP服务器服务
4. 处理HTTP请求和响应
]]

-- 初始化LED灯, 这里演示控制Air8000开发板绿灯，其他开发板请查看硬件原理图自行修改(如果使用整机开发板可以用GPIO146)
local LEDA = gpio.setup(146, 0, gpio.PULLUP)

local function handle_http_request(fd, method, uri, headers, body)
    log.info("httpsrv", method, uri, body or "")
    
    if uri == "/led/1" then
        LEDA(1)
        log.info("LED Control", "Turned ON")
        return 200, {}, "ok"
    elseif uri == "/led/0" then
        LEDA(0)
        log.info("LED Control", "Turned OFF")
        return 200, {}, "ok"
    elseif uri == "/send/text" then
        log.info("Text Request", "Method:", method, "Body Length:", body and #body or 0)
        if method == "POST" and body and #body > 0 then
            -- 直接打印接收到的文本内容
            log.info("Received Text:", body)
            return 200, {}, "ok"
        end
        return 400, {}, "Invalid request"
    elseif uri == "/scan/go" then
        wlan.scan()
        return 200, {}, "ok"
    elseif uri == "/scan/list" then
        return 200, {["Content-Type"]="application/json"}, (json.encode({data=scan_result, ok=true}))
    elseif uri == "/connect" then
        if method == "POST" and body and #body > 2 then
            local jdata = json.decode(body)
            if jdata and jdata.ssid then
                sys.timerStart(wlan.connect, 500, jdata.ssid, jdata.passwd)
                return 200, {}, "ok"
            end
        end
        return 400, {}, "ok"
    elseif uri == "/connok" then
        log.info("connok", json.encode({ip=socket.localIP(2)}))
        return 200, {["Content-Type"]="application/json"}, json.encode({ip=socket.localIP(2)})
    end
    return 404, {}, "Not Found" .. uri
end


-- 检测当前使用的网卡适配器
local function get_current_adapter()
    -- 检查各个网卡是否就绪
    if netdrv and netdrv.ready(socket.LWIP_AP) then
        return socket.LWIP_AP, "AP"
    elseif netdrv and netdrv.ready(socket.LWIP_STA) then
        return socket.LWIP_STA, "STA"
    elseif netdrv and netdrv.ready(socket.LWIP_ETH) then
        return socket.LWIP_ETH, "ETH"
    end
end

local function start_http_server()
    -- 等待网络就绪事件
    sys.waitUntil("CREATE_OK")
    
    -- 获取当前使用的网卡适配器
    local adapter, adapter_name = get_current_adapter()
    local local_ip = socket.localIP(adapter)
    
    -- 启动HTTP服务器
    httpsrv.start(80, handle_http_request, adapter)
    log.info("HTTP", "文件服务器已启动，使用" .. adapter_name .. "模式")
    
    if adapter == socket.LWIP_AP then
        log.info("HTTP", "请连接WiFi: luatos8888 密码: 12345678")
    end
    
    log.info("HTTP", "访问地址: http://" .. (local_ip or "192.168.4.1"))
end

local function scan_done_handle()
    local result = wlan.scanResult()
    scan_result = {}
    for k, v in pairs(result) do
        log.info("scan", (v["ssid"] and #v["ssid"] > 0) and v["ssid"] or "[隐藏SSID]", v["rssi"], (v["bssid"]:toHex()))
        if v["ssid"] and #v["ssid"] > 0 then
            table.insert(scan_result, {
                ssid = v["ssid"],
                rssi = v["rssi"]
            })
        end
    end
    log.info("scan", "aplist count:", #scan_result)
end

-- 订阅WiFi扫描完成事件
sys.subscribe("WLAN_SCAN_DONE", scan_done_handle)

sys.taskInit(start_http_server)