-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "WIFI_AP"
VERSION = "1.0.0"

-- sys库是标配
_G.sys = require("sys")
require "sysplus"
dnsproxy = require("dnsproxy")
dhcpsrv = require("dhcpsrv")
httpplus = require("httpplus")
local fota_wifi = require("fota_wifi")

local function wifi_fota_task_func()
    local result = fota_wifi.request()
    if result then
        log.info("fota_wifi", "升级任务执行成功")
    else
        log.info("fota_wifi", "升级任务执行失败")
    end
end

-- 判断网络是否正常
local function wait_ip_ready()
    local result, ip, adapter = sys.waitUntil("IP_READY", 30000)
    if result then
        log.info("fota_wifi", "开始执行升级任务")
        sys.taskInit(wifi_fota_task_func)
    else
        log.error("当前正在升级WIFI&蓝牙固件，请插入可以上网的SIM卡")
    end
end

-- 初始化LED灯, 这里演示控制Air8000核心板蓝灯，其他开发板请查看硬件原理图自行修改(如果使用整机开发板可以用GPIO146)
local LEDA = gpio.setup(20, 0, gpio.PULLUP)


function create_ap()
    log.info("执行AP创建操作", "luatos8888")
    wlan.createAP("luatos8888", "12345678")
    sys.wait(1000)
    netdrv.ipv4(socket.LWIP_AP, "192.168.4.1", "255.255.255.0", "0.0.0.0")
    dhcpsrv.create({adapter=socket.LWIP_AP})
end

function wifi_networking()
    sys.wait(3000)
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
        return 200, {["Content-Type"]="application/json"}, (json.encode({data=_G.scan_result, ok=true}))
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
    _G.scan_result = {}
    for k, v in pairs(result) do
        log.info("scan", (v["ssid"] and #v["ssid"] > 0) and v["ssid"] or "[隐藏SSID]", v["rssi"], (v["bssid"]:toHex()))
        if v["ssid"] and #v["ssid"] > 0 then
            table.insert(_G.scan_result, v["ssid"])
        end
    end
    log.info("scan", "aplist", json.encode(_G.scan_result))
end

function ip_ready_handle(ip, adapter)
    log.info("ip_ready_handle",ip, adapter)
    if adapter == socket.LWIP_STA then
        log.info("wifi sta 链接成功")
    end
end



function main_task()
    wlan.init()
    sys.wait(100)

    create_ap()
    wifi_networking()


end

-- 在设备启动时检查网络状态
sys.taskInit(wait_ip_ready)

sys.subscribe("WLAN_SCAN_DONE", scan_done_handle)
sys.subscribe("IP_READY", ip_ready_handle)
sys.taskInit(main_task)

-- 用户代码已结束---------------------------------------------
sys.run()
