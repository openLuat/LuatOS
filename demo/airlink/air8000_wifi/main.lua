
-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "air8000_gpio_ext"
VERSION = "1.0.5"

-- sys库是标配
_G.sys = require("sys")
require "sysplus"
dnsproxy = require("dnsproxy")
dhcpsrv = require("dhcpsrv")
httpplus = require("httpplus")

PWR8000S = gpio.setup(23, 0, gpio.PULLUP) -- 关闭Air8000S的LDO供电


function test_ap()
    wlan.createAP("uiot5678", "12345678")
    netdrv.ipv4(socket.LWIP_AP, "192.168.4.1", "255.255.255.0", "0.0.0.0")
    sys.wait(100)
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

function test_sta()
    wlan.connect("luatos1234", "12341234")
    netdrv.dhcp(socket.LWIP_STA, true)
    netdrv.napt(socket.LWIP_STA)
    while 1 do
        -- log.info("MAC地址", netdrv.mac(socket.LWIP_STA))
        -- log.info("IP地址", netdrv.ipv4(socket.LWIP_STA))
        -- log.info("ready?", netdrv.ready(socket.LWIP_STA))
        sys.wait(1000)
        log.info("执行http请求")
        -- local code = http.request("GET", "http://192.168.1.15:8000/README.md", nil, nil, {adapter=socket.LWIP_STA,timeout=3000}).wait()
        local code, headers, body = http.request("GET", "https://httpbin.air32.cn/bytes/2048", nil, nil, {adapter=socket.LWIP_STA,timeout=3000}).wait()
        log.info("http执行结果", code, headers, body and #body)
    end
end

function test_scan()
    while 1 do
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

sys.taskInit(function()
    -- 稍微缓一下
    sys.wait(10)
    -- 初始化airlink
    airlink.init()
    -- 启动底层线程, 从机模式
    airlink.start(1)
    PWR8000S(1)
    netdrv.setup(socket.LWIP_STA, netdrv.WHALE)
    netdrv.setup(socket.LWIP_AP, netdrv.WHALE)

    sys.wait(100)
    wlan.init()
    sys.wait(100)
    
    -- 启动AP测试
    -- test_ap()

    -- 连接STA测试
    -- test_sta()

    -- wifi扫描测试
    test_scan()
end)


-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
