
_G.sys = require("sys")

sys.subscribe("NTP_UPDATE", function(source)
    log.info("sntp", "时间同步成功", source)
end)

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
