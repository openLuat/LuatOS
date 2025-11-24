
_G.sys = require("sys")

sys.taskInit(function()
    sys.waitUntil("IP_READY")
    while 1 do
        sys.wait(1000)
        socket.sntp_port(1123)
        socket.sntp({
            "124.116.178.136",
        })
    end

end)

sys.run()
