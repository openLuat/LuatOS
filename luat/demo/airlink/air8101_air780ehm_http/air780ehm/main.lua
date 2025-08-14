PROJECT = "airlink_spi_slave"
VERSION = "1.0.0"

_G.sys = require("sys")
_G.sysplus = require("sysplus")
dnsproxy = require ("dnsproxy")

-- 订阅airlink的SDATA事件，打印收到的信息。
local function airlink_sdata(data)
    log.info("收到AIRLINK_SDATA!!", data)
end

sys.subscribe("AIRLINK_SDATA", airlink_sdata)
sys.subscribe("IP_READY", function(id, ip)
    log.info("收到IP_READY!!", id, ip)
end)

sys.taskInit(function()
    sys.wait(100)
    airlink.init()
    netdrv.setup(socket.LWIP_USER0, netdrv.WHALE)
    sys.wait(100)
    airlink.start(0)
    netdrv.ipv4(socket.LWIP_USER0, "192.168.111.1", "255.255.255.0", "192.168.111.2")
    sys.waitUntil("IP_READY")
    netdrv.napt(socket.LWIP_GP)

    dnsproxy.setup(socket.LWIP_USER0, socket.LWIP_GP)
    while 1 do
        sys.wait(1000)
        log.info("ticks", mcu.ticks(), hmeta.chip(), hmeta.model(), hmeta.hwver())
        airlink.statistics()
    end
end)

sys.run()
