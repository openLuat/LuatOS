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
直接使用Air8000开发板硬件测试即可；

本文件没有对外接口，直接在其他功能模块中require "ap_config_net"就可以加载运行；
]] 
dhcpsrv = require("dhcpsrv")

-- 初始化LED灯, 这里演示控制Air8000核心板蓝灯，其他开发板请查看硬件原理图自行修改(如果使用整机开发板可以用GPIO146)
local LEDA = gpio.setup(20, 0, gpio.PULLUP)
local scan_result = {}

function create_ap()
    log.info("执行AP创建操作", "test2")
    wlan.createAP("test2", "HZ88888888")
    netdrv.ipv4(socket.LWIP_AP, "192.168.4.1", "255.255.255.0", "192.168.4.1")
    dhcpsrv.create({adapter=socket.LWIP_AP})
end

function wifi_networking()
    httpsrv.start(80, handle_http_request, socket.LWIP_AP)
    log.info("web", "pls open url http://192.168.4.1/")
end

function handle_http_request(fd, method, uri, headers, body)
    log.info("httpsrv", method, uri, json.encode(headers), body)
    if uri == "/led/1" then
        LEDA(1)
        return 200, {}, "ok"
    elseif uri == "/led/0" then
        LEDA(0)
        return 200, {}, "ok"
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

function scan_done_handle()
    local result = wlan.scanResult()
    for k, v in pairs(result) do
        log.info("scan", (v["ssid"] and #v["ssid"] > 0) and v["ssid"] or "[隐藏SSID]", v["rssi"], (v["bssid"]:toHex()))
        if v["ssid"] and #v["ssid"] > 0 then
            table.insert(scan_result, v["ssid"])
        end
    end
    log.info("scan", "aplist", json.encode(scan_result))
end

function ip_ready_handle(ip, adapter)
    log.info("ip_ready_handle",ip, adapter)
    if adapter == socket.LWIP_STA then
        log.info("wifi sta 链接成功")
    end
end



function main_task()
    wlan.init()
    create_ap()
    wifi_networking()
end

sys.subscribe("WLAN_SCAN_DONE", scan_done_handle)
sys.subscribe("IP_READY", ip_ready_handle)
sys.taskInit(main_task)
