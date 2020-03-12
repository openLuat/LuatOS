local sys = require("sys")

log.info("main", "socket demo")

log.info("mac", wlan.get_mac())
wlan.connect("uiot", "1234567890")

sys.subscribe("WLAN_READY", function ()
    print("!!! wlan ready event !!!")
    --socket.ntpSync()
end)

local PB7 = 27
gpio.setup(PB7, function(msg) log.info("IQR", "PB7/27", msg) end)


sys.taskInit(function()
    while 1 do
        if wlan.ready() then
            local s = socket.tcp()
            s:host("www.baidu.com")
            s:port(80)
            s:on("connect", function(id, re)
                log.info("netc", "connect result", re)
                if re then
                    s:send("GET / HTTP/1.0\r\nHost: www.baidu.com\r\n\r\n")
                end
            end)
            s:on("recv", function(id, re)
                print("recv", id, #re, re)
            end)
            log.info("netc", "info", s)
            if s:start() == 0 then
                sys.waitUntil("NETC_END_" .. s:id(), 30000)
                log.info("netc", "GET NETC_END or timeout")
            else
                log.info("netc", "netc start fail!!")
            end
            s:clean()
            sys.wait(10000)
        else
            log.info("wifi", "wifi NOT ready yet")
            sys.waitUntil("WLAN_READY", 30000)
        end
    end
end)

sys.run()
