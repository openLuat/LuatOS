
-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "air8000_wifi"
VERSION = "1.0.5"

dnsproxy = require("dnsproxy")
dhcpsrv = require("dhcpsrv")
httpplus = require("httpplus")

-- 如果需要升级WIFI固件，请打开下面两行注释
-- local fota_wifi = require("fota_wifi")
-- sys.taskInit(fota_wifi.request)

-- wifi的STA相关事件
sys.subscribe("WLAN_STA_INC", function(evt, data)
    -- evt 可能的值有: "CONNECTED", "DISCONNECTED"
    -- 当evt=CONNECTED, data是连接的AP的ssid, 字符串类型
    -- 当evt=DISCONNECTED, data断开的原因, 整数类型
    log.info("收到STA事件", evt)
end)


function test_sta()
    log.info("执行STA连接操作")
    wlan.connect("Xiaomi 13", "15055190176")
    -- netdrv.dhcp(socket.LWIP_STA, true)
    sys.wait(8000)
    -- iperf.server(socket.LWIP_STA)
    -- iperf.client(socket.LWIP_STA, "47.94.236.172")

    sys.wait(5000)
    while 1 do
        -- log.info("MAC地址", netdrv.mac(socket.LWIP_STA))
        -- log.info("IP地址", netdrv.ipv4(socket.LWIP_STA))
        -- log.info("ready?", netdrv.ready(socket.LWIP_STA))
        -- sys.wait(1000)
        -- log.info("执行http请求")
        -- local code = http.request("GET", "http://192.168.1.15:8000/README.md", nil, nil, {adapter=socket.LWIP_STA,timeout=3000}).wait()
        local code, headers, body = http.request("GET", "https://httpbin.air32.cn/bytes/2048", nil, nil, {adapter=socket.LWIP_STA,timeout=5000,debug=false}).wait()
        log.info("http执行结果", code, headers, body and #body)
        -- socket.sntp(nil, socket.LWIP_STA)
        sys.wait(2000)

        -- socket.sntp(nil)
        -- sys.wait(2000)
        -- log.info("执行ping操作")
        -- icmp.ping(socket.LWIP_STA, "183.2.172.177")
        -- sys.wait(2000)
    end
end

sys.subscribe("PING_RESULT", function(id, time, dst)
    log.info("ping", id, time, dst);
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

function ip_ready_handle(ip, adapter)
    log.info("ip_ready_handle",ip, adapter)
    if adapter == socket.LWIP_STA then
        log.info("wifi sta 链接成功")
    end
end

--  每隔6秒打印一次airlink统计数据, 调试用
-- sys.taskInit(function()
--     while 1 do
--         sys.wait(6000)
--         airlink.statistics()
--     end
-- end)

sys.taskInit(function()
    log.info("新的Air8000脚本...")
    wlan.init()
    test_sta()
    test_scan()
end)
sys.subscribe("IP_READY", ip_ready_handle)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
