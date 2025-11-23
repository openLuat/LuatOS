
_G.sys = require("sys")

sys.taskInit(function()
    sys.waitUntil("IP_READY")
    while 1 do
        sys.wait(1000)
        socket.sntp({
            "ntp.aliyun.com",
            "ntp2.aliyun.com",
            "ntp3.aliyun.com",
            "ntp4.aliyun.com",
        })
    end

end)

sys.run()
