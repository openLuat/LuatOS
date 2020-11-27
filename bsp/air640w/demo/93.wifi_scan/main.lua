
-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "wifiscan"
VERSION = "1.0.0"

-- 引入必要的库文件(lua编写), 内部库不需要require
local sys = require "sys"

-- 打印demo信息, 免得下错demo了
log.info("main", "wifi scan demo")
-- 打印设备的mac地址, 没有mac地址的设备会有各种问题
log.info("mac", wlan.get_mac())

-- 先扫描,再连接
sys.taskInit(function()
    while 1 do
        -- 开启扫描
        wlan.scan()
        -- 通常几秒钟就扫描完成, 这里等30秒算是保险点
        sys.waitUntil("WLAN_SCAN_DONE", 30000)
        -- 读取扫描结果
        local re = wlan.scanResult()
        for i in ipairs(re) do
            -- 逐一打印, 如果你需要全部信息, 可以尝试 log.info("wlan", json.encode(re[i]))
            log.info("wlan", "info", re[i].ssid, re[i].rssi)
        end
        -- 打印完成
        log.info("wlan", "scan done", #re, "===============================")
        -- 休眠3秒, 继续下一次循环
        sys.wait(3000)
    end
end)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
