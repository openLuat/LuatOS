-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "wifidemo"
VERSION = "1.0.0"


local scan_result = {}

sys.taskInit(function()
    wlan.init()
    sys.wait(100)
    wlan.connect("luatos1234", "12341234")

    sys.waitUntil("IP_READY")
    sys.wait(100)
    iperf.client(socket.LWIP_STA, "47.94.236.172")

    sys.wait(90*1000)
    iperf.abort()
end)

sys.subscribe("IPERF_REPORT", function(bytes, ms_duration, bandwidth)
    log.info("iperf", bytes, ms_duration, bandwidth)
end)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
