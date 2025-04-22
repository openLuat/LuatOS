-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "WIFI_AP"
VERSION = "1.0.0"
--[[
本demo演示AP的配网实例
1. 启动后, 会创建一个 luatos_ + mac地址的热点
2. 热点密码是 12345678
3. 热点网关是 192.168.4.1, 同时也是配网网页的ip
4. http://192.168.4.1
]]

-- sys库是标配
_G.sys = require("sys")
require "sysplus"
dnsproxy = require("dnsproxy")
dhcpsrv = require("dhcpsrv")
httpplus = require("httpplus")
local LEDA= gpio.setup(20, 0, gpio.PULLUP)

function create_ap()
    log.info("执行AP创建操作", "luatos8888")
    wlan.createAP("luatos8888", "12345678")
    sys.wait(1000)
    netdrv.ipv4(socket.LWIP_AP, "192.168.4.1", "255.255.255.0", "0.0.0.0")
    dnsproxy.setup(socket.LWIP_AP, socket.LWIP_GP)
    dhcpsrv.create({adapter=socket.LWIP_AP})
    while 1 do
        if netdrv.ready(socket.LWIP_GP) then
            netdrv.napt(socket.LWIP_GP)
            break
        end
        sys.wait(1000)
    end
end

function wifi_networking()
   sys.wait(3000)
    -- AP的ssid和password
    wlan.scan()
    -- sys.wait(500)
    httpsrv.start(80, function(fd, method, uri, headers, body)
        log.info("httpsrv", method, uri, json.encode(headers), body)
        -- /led是控制灯的API
        if uri == "/led/1" then
            LEDA(1)
            return 200, {}, "ok"
        elseif uri == "/led/0" then
            LEDA(0)
            return 200, {}, "ok"
        -- 扫描AP
        elseif uri == "/scan/go" then
            wlan.scan()
            return 200, {}, "ok"
        -- 前端获取AP列表
        elseif uri == "/scan/list" then
            return 200, {["Content-Type"]="applaction/json"}, (json.encode({data=_G.scan_result, ok=true}))
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
            return 200, {["Content-Type"]="applaction/json"}, json.encode({ip=socket.localIP()})
        end
        -- 其他情况就是找不到了
        return 404, {}, "Not Found" .. uri
    end, socket.LWIP_AP)
    log.info("web", "pls open url http://192.168.4.1/")
end

-- wifi扫描成功后, 会有WLAN_SCAN_DONE消息, 读取即可
sys.subscribe("WLAN_SCAN_DONE", function ()
    local result = wlan.scanResult()
    _G.scan_result = {}
    for k,v in pairs(result) do
        log.info("scan", (v["ssid"] and #v["ssid"] > 0) and v["ssid"] or "[隐藏SSID]", v["rssi"], (v["bssid"]:toHex()))
        if v["ssid"] and #v["ssid"] > 0 then
            table.insert(_G.scan_result, v["ssid"])
        end
    end
    log.info("scan", "aplist", json.encode(_G.scan_result))
end)

sys.subscribe("IP_READY", function()
    -- 联网成功后, 模拟上报到服务器
    log.info("wlan", "已联网", "通知服务器")

end)

function test_scan()
    while 1 do
        log.info("执行wifi扫描")
        wlan.scan()
        sys.wait(30 * 1000)
    end
end
sys.subscribe("WLAN_SCAN_DONE", function ()
    local results = wlan.scanResult()
    log.info("scan", "results", #results)
    for k,v in pairs(results) do
        log.info("scan", v["ssid"], v["rssi"], (v["bssid"]:toHex()))
    end
end)

--  每隔6秒打印一次airlink统计数据, 调试用
-- sys.taskInit(function()
--     while 1 do
--         sys.wait(6000)
--         airlink.statistics()
--     end
-- end)

sys.taskInit(function()
    -- -- 稍微缓一下
    -- sys.wait(10)
    -- -- 初始化airlink
    -- airlink.init()
    -- -- 启动底层线程, 从机模式
    -- airlink.start(1)
    -- PWR8000S(1)
    -- sys.wait(500) -- 稍微缓一下
    -- airlink.test(10)
    -- sys.wait(100)
    -- netdrv.setup(socket.LWIP_STA, netdrv.WHALE)
    -- netdrv.setup(socket.LWIP_AP, netdrv.WHALE)

    -- sys.wait(100)
    wlan.init()
    sys.wait(100)

    -- 启动AP测试
    create_ap()
    wifi_networking()
    -- 连接STA测试
    -- test_sta()

    -- wifi扫描测试
    -- test_scan()
end)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!