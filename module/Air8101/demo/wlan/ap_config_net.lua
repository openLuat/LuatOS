--[[
@module  ap_config_net
@summary wifi配网功能模块 
@version 1.0
@date    2025.10.20
@author  魏健强
@usage 本文为wifi配网功能模块,核心逻辑为
1、开启wifi_ap热点；
2、模块开启http服务器；
3、用户通过手机等设备连接wifi_ap热点，访问http网页进行wifi配网；
直接使用Air8101核心板硬件测试即可；

本文件没有对外接口，直接在其他功能模块中require "ap_config_net"就可以加载运行；
]]
dhcpsrv = require("dhcpsrv")
 
-- 初始化LED灯, 根据实际GPIO修改
-- local LEDA= gpio.setup(12, 0, gpio.PULLUP)

local scan_result = {}

local function create_ap()
    log.info("执行AP创建操作", "test2")
    wlan.createAP("test2", "HZ88888888")
    netdrv.ipv4(socket.LWIP_AP, "192.168.4.1", "255.255.255.0", "192.168.4.1")
    dhcpsrv.create({
        adapter = socket.LWIP_AP
    })
end

local function handle_http_request(fd, method, uri, headers, body)
    -- log.info("httpsrv", method, uri, json.encode(headers), body)
    log.info("httpsrv", "fd", fd, "method", method, "uri", uri, "headers", json.encode(headers), "body", body)
    -- /led是控制灯的API
    if uri == "/led/1" then
        -- LEDA(1)
        log.info("led", "on")
        return 200, {}, "ok"
    elseif uri == "/led/0" then
        -- LEDA(0)
        log.info("led", "off")
        return 200, {}, "ok"
        -- 处理消息
    elseif uri == "/msg" then
        local messageData = json.decode(body) -- 假设消息是 JSON 格式
        if messageData and messageData.message then
            log.info("Received message:", messageData.message)
            -- 处理接收到的消息，例如保存、转发、响应等等
            return 200, {}, "Message received: " .. messageData.message
        end

        -- 扫描AP
    elseif uri == "/scan/go" then
        wlan.scan()
        log.info("scan", "start")
        return 200, {}, "ok"
        -- 前端获取AP列表
    elseif uri == "/scan/list" then
        return 200, {
            ["Content-Type"] = "applaction/json"
        }, (json.encode({
            data = scan_result,
            ok = true
        }))
        -- 前端填好了ssid和密码, 那就连接吧
    elseif uri == "/connect" then
        if method == "POST" and body and #body > 2 then
            local jdata = json.decode(body)
            if jdata and jdata.ssid then
                -- 开启一个定时器联网, 否则这个情况可能会联网完成后才执行完
                sys.timerStart(wlan.connect, 500, jdata.ssid, jdata.passwd)
                return 200, {}, "ok"
            end
        end
        return 400, {}, "ok"
        -- 根据ip地址来判断是否已经连接成功
    elseif uri == "/connok" then
        return 200, {
            ["Content-Type"] = "applaction/json"
        }, json.encode({
            ip = socket.localIP()
        })
    elseif uri == "/send" then
        if method == "POST" and body and #body > 2 then
            local jdata = json.decode(body)
            if jdata and jdata.msg then
                log.info("Received message:", jdata.msg)
                return 200, {}, "Message received"
            end
        end
        return 400, {}, "Bad Request"

    end
    -- 其他情况就是找不到了
    return 404, {}, "Not Found" .. uri
end

local function wifi_networking()
    httpsrv.start(80, handle_http_request, socket.LWIP_AP)
    log.info("web", "pls open url http://192.168.4.1/")
end

-- wifi扫描成功后, 会有WLAN_SCAN_DONE消息, 读取即可
local function scan_done_handle()
    local result = wlan.scanResult()
    scan_result = {}
    for k, v in pairs(result) do
        log.info("scan", (v["ssid"] and #v["ssid"] > 0) and v["ssid"] or "[隐藏SSID]", v["rssi"], (v["bssid"]:toHex()))
        if v["ssid"] and #v["ssid"] > 0 then
            table.insert(scan_result, v["ssid"])
        end
    end
    log.info("scan", "aplist", json.encode(scan_result))
end

local function main_task()
    wlan.init()
    create_ap()
    wifi_networking()
end

local function ip_ready_handle()
    -- wifi联网成功后, 在这里进行后续应用逻辑的扩展处理
    log.info("wlan", "已联网")
    -- sys.taskInit(sockettest)
end

sys.subscribe("WLAN_SCAN_DONE", scan_done_handle)
sys.subscribe("IP_READY", ip_ready_handle)
sys.taskInit(main_task)
