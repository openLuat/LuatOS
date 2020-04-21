
local sys = require("sys")

wlan.setMode("wlan0", 1)
wlan.connect("uiot", "124567890")

local count = 0
local netc_a, netc_b, netc_c, netc_d
sys.taskInit(function()
    while count < 10000 do
        if wlan.ready() == 1 then
            -- 新建4个连接对象, 但不连接
            netc_a = socket.tcp()
            netc_b = socket.tcp()
            netc_c = socket.tcp()
            netc_d = socket.tcp()

            netc_a:host("site0.cn")
            netc_b:host("www.baidu.com")
            netc_c:host("nutz.cn")
            netc_d:host("qq.com")

            netc_a:port(80)
            netc_b:port(80)
            netc_c:port(80)
            netc_d:port(80)

            netc_a:on("close", function() log.info("test", "netc_a close event") end)
            netc_b:on("close", function() log.info("test", "netc_b close event") end)
            netc_c:on("close", function() log.info("test", "netc_c close event") end)
            netc_d:on("close", function() log.info("test", "netc_d close event") end)
        end
        sys.wait(100)
        collectgarbage()
        count = count + 1
    end
end)

sys.run()

