-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "Air1601_wifi"
VERSION = "1.0.0"

dnsproxy = require("dnsproxy")
dhcpsrv = require("dhcpsrv")
httpplus = require("httpplus")
-- wifi的STA相关事件
sys.subscribe("WLAN_STA_INC", function(evt, data)
    -- evt 可能的值有: "CONNECTED", "DISCONNECTED"
    -- 当evt=CONNECTED, data是连接的AP的ssid, 字符串类型
    -- 当evt=DISCONNECTED, data断开的原因, 整数类型
    log.info("收到STA事件", evt, data)
end)


function test_sta()
    log.info("执行STA连接操作")
    wlan.connect("luatos1234", "12341234")
    sys.waitUntil("IP_READY")
    while 1 do
        log.info("wlan", "info", json.encode(wlan.getInfo()))
        log.info("执行http请求")
        local code, headers, body = http.request("GET", "http://httpbin.air32.cn/bytes/2048", nil, nil, {
            adapter = socket.LWIP_STA,
            timeout = 5000,
            debug = false
        }).wait()
        log.info("http执行结果", code, headers, body and #body)
        sys.wait(2000)
    end
end

sys.subscribe("WLAN_SCAN_DONE", function()
    local results = wlan.scanResult()
    log.info("scan", "results", #results)
    for k, v in pairs(results) do
        log.info("scan", v["ssid"], v["rssi"], (v["bssid"]:toHex()))
    end
end)

sys.taskInit(function()

    airlink.config(airlink.CONF_SPI_ID, 1) -- SPI1
    airlink.config(airlink.CONF_SPI_CS, 8) -- GPIO8
    airlink.config(airlink.CONF_SPI_RDY, 22) -- GPIO18
    airlink.config(airlink.CONF_SPI_SPEED, 8 * 1000000) -- 8MHz速度
    airlink.init()
    log.info("注册STA和AP设备")
    netdrv.setup(socket.LWIP_STA, netdrv.WHALE)
    netdrv.setup(socket.LWIP_AP, netdrv.WHALE)
    -- 启动底层线程, 主机模式
    airlink.start(1)
    -- airlink初始化，等待1s
    sys.wait(1000)
    -- 初始化wlan
    wlan.init()
    -- 连接STA测试
    test_sta()
end)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
