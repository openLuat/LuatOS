
wlan.setMode("wlan0", 1)
wlan.connect("uiot", "czcjhp1985cbm")

local count = 0
local netc_a, netc_b, netc_c, netc_d
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

        netc_a:on("close", function() end)
        netc_b:on("close", function() end)
        netc_c:on("close", function() end)
        netc_d:on("close", function() end)
    end
    timer.mdelay(100)
    collectgarbage()
    count = count + 1
end
