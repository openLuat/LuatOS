-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "pingtest"

VERSION = "1.0.2"
-- sys库是标配
sys = require("sys")

sys.subscribe("PING_RESULT", function(id, time, dst)
    log.info("ping", id, time, dst);
end)

sys.taskInit(function()
    sys.waitUntil("IP_READY")
    sys.wait(1000)
    icmp.setup(socket.LWIP_GP)
    while 1 do
        icmp.ping(socket.LWIP_GP, "121.14.77.221")
        sys.waitUntil("PING_RESULT", 3000)
        sys.wait(3000)
    end
end)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
