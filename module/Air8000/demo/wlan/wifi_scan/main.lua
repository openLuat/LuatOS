-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "air8000_wifiscan"
VERSION = "1.0.5"

-- sys库是标配
_G.sys = require("sys")
require "sysplus"

PWR8000S = gpio.setup(23, 0, gpio.PULLUP) -- 关闭Air8000S的LDO供电

gpio.debounce(0, 1000)
gpio.setup(0, function()
    sys.taskInit(function()
        log.info("复位Air8000S")
        PWR8000S(0)
        sys.wait(20)
        PWR8000S(1)
    end)
end, gpio.PULLDOWN)

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
sys.taskInit(function()
    while 1 do
        sys.wait(6000)
        airlink.statistics()
    end
end)

sys.taskInit(function()
    -- 稍微缓一下
    sys.wait(500)
    wlan.init()
    sys.wait(100)

    -- wifi扫描测试
    test_scan()
end)


-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
