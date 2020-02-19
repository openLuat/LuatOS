local sys = require("sys")


log.setLevel("DEBUG")
log.debug("main", "hi from debug")
log.info("main", "hi from info")
log.warn("main", "hi from warn")
log.error("main", "hi from error")

wlan.setMode("wlan0", wlan.STATION)
print("mac: " .. wlan.get_mac())
wlan.connect("uiot", "1234567890")

sys.subscribe("WLAN_READY", function ()
    print("!!! wlan ready event !!!")
    socket.ntpSync()
end)


sys.taskInit(function()
    sys.waitUntil("WLAN_READY", 30000)
    
    local s = socket.tcp()
    s:host("site0.cn")
    s:port(80)
    s:on("connect", function(re)
        print("connect result", re)
    end)
    s:on("recv", function(re)
        print("recv", re)
    end)
    print("netc info", s)
    s:connect()
    sys.wait(1000)
    s:send("GET / HTTP/1.0\r\nHost: site0.cn\r\n\r\n")
end)

sys.run()
