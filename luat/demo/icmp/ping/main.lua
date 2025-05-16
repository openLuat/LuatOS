-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "pingtest"

VERSION = "1.0.2"
-- sys库是标配
sys = require("sys")

sys.subscribe("PING_RESULT", function(id, time, dst)
    log.info("ping", id, time, dst);
end)

sys.taskInit(function()
    local adapter = socket.LWIP_GP
    local ip = "121.14.77.221"
    -- icmp.debug(true)
    if wlan and wlan.connect then
        sys.wait(500)
        wlan.init()
        wlan.connect("luatos1234", "12341234")
        adapter = socket.LWIP_STA
        -- ip = "192.168.1.10"
    end
    sys.waitUntil("IP_READY")
    sys.wait(1000)
    icmp.setup(adapter)
    while 1 do
        log.info("执行PING操作", ip)
        icmp.ping(adapter, ip)
        sys.waitUntil("PING_RESULT", 3000)
        sys.wait(1000)
    end
end)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
