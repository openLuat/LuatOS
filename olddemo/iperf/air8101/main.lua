-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "wifidemo"
VERSION = "1.0.0"

-- 引入必要的库文件(lua编写), 内部库不需要require
sys = require("sys")
require("sysplus")

--[[
本demo演示AP的配网实例
1. 启动后, 会创建一个 luatos_ + mac地址的热点
2. 热点密码是 12341234
3. 热点网关是 192.168.4.1, 同时也是配网网页的ip
4. http://192.168.4.1
]]


if wdt then
    --添加硬狗防止程序卡死，在支持的设备上启用这个功能
    wdt.init(9000)--初始化watchdog设置为9s
    sys.timerLoopStart(wdt.feed, 3000)--3s喂一次狗
end

-- 初始化LED灯, 开发板上左右2个led分别是gpio12/gpio13
local LEDA= gpio.setup(12, 0, gpio.PULLUP)
-- local LEDB= gpio.setup(13, 0, gpio.PULLUP)

local scan_result = {}

sys.taskInit(function()
    wlan.init()
    sys.wait(100)
    wlan.connect("luatos1234", "12341234")

    sys.waitUntil("IP_READY")
    sys.wait(100)
    iperf.client(socket.LWIP_STA, "47.94.236.172")

    sys.wait(30*1000)
    iperf.abort()
end)

sys.subscribe("IPERF_REPORT", function(bytes, ms_duration, bandwidth)
    log.info("iperf", bytes, ms_duration, bandwidth)
end)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
