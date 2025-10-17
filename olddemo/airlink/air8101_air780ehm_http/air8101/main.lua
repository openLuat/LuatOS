PROJECT = "airlink_spi_master"
VERSION = "1.0.0"

_G.sys = require("sys")
_G.sysplus = require("sysplus")
dnsproxy = require ("dnsproxy")

sys.taskInit(function()
    sys.wait(100)
    airlink.init()
    log.info("创建桥接网络设备")
    netdrv.setup(socket.LWIP_USER0, netdrv.WHALE)
    airlink.config(airlink.CONF_SPI_CS, 15)
    airlink.config(airlink.CONF_SPI_RDY, 48)
    airlink.start(1)
    netdrv.ipv4(socket.LWIP_USER0, "192.168.111.2", "255.255.255.0", "192.168.111.1")
    sys.wait(100)
    sys.waitUntil("IP_READY", 10000)
    while 1 do
        sys.wait(1000)
        log.info("ticks", mcu.ticks(), hmeta.chip(), hmeta.model(), hmeta.hwver())
        airlink.statistics()
        log.info("执行http请求")
        local code, headers, body = http.request("GET", "https://httpbin.air32.cn/bytes/2048", nil, nil, {adapter=socket.LWIP_USER0,timeout=3000}).wait()
        log.info("http执行结果", code, code, headers, body)
    end
end)

sys.run()
