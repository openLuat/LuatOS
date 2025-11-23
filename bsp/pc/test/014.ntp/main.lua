
_G.sys = require("sys")

sys.taskInit(function()
    sys.waitUntil("IP_READY")
    while 1 do
        socket.sntp()
        sys.waitUntil("NTP_UPDATE", 10000)
        local tm = socket.ntptm()
        log.info("tm数据", json.encode(tm))
        log.info("时间戳", string.format("%u.%03d", tm.tsec, tm.tms))
        sys.wait(5000)
    end
end)

sys.run()
