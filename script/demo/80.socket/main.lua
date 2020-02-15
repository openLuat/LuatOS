local sys = require("sys")

wlan.setMode("wlan0", wlan.STATION)
print("mac: " .. wlan.get_mac())
wlan.connect("uiot", "1234567890")

sys.subscribe("WLAN_READY", function ()
    print("!!! wlan ready event !!!")
    socket.ntpSync()
end)


sys.taskInit(function()
    sys.waitUntil("WLAN_READY", 30000)
    while 1 do
        if wlan.ready() then
            print("Gooooooooooooooooooooooooo!")
            local temp = (sensor.ds18b20(28) or "")
            print("TEMP: " .. temp)
            local t = {"GET /api/w60x/report/ds18b20?mac=", wlan.get_mac(), "&temp=", temp, " HTTP/1.0\r\n",
                    "Host: site0.cn\r\n",
                    "User-Agent: LuatOS/0.1.0\r\n",
                        "\r\n"}
            local data = table.concat(t)
            local s = socket.tcp()
            print(">>>>", s)
            s:connect("site0.cn", 80)
            --socket.connect(s, "site0.cn", 80)
            sys.wait(1000)
            s:send(data)
            --socket.send(s, data)
            sys.wait(2000)
            s:close()
            --socket.close(s)
            s = nil
            print("Dooooooooooooooooooooooond!")
            sys.wait(3000)
        else
            sys.waitUntil("WLAN_READY", 30000)
        end
    end
end)

sys.run()
