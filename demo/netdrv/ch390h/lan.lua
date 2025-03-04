
-- 引入必要的库文件(lua编写), 内部库不需要require
sys = require("sys")
sysplus = require("sysplus")

dhcps = require "dhcpsrv"
dnsproxy = require "dnsproxy"

sys.taskInit(function ()
    -- sys.wait(3000)
    local result = spi.setup(
        0,--串口id
        nil,
        0,--CPHA
        0,--CPOL
        8,--数据宽度
        51200000--,--频率
        -- spi.MSB,--高低位顺序    可选，默认高位在前
        -- spi.master,--主模式     可选，默认主
        -- spi.full--全双工       可选，默认全双工
    )
    log.info("main", "open",result)
    if result ~= 0 then--返回值为0，表示打开成功
        log.info("main", "spi open error",result)
        return
    end

    netdrv.setup(socket.LWIP_ETH, netdrv.CH390, {spi=0,cs=8})
    sys.wait(3000)
    local ipv4,mark, gw = netdrv.ipv4(socket.LWIP_ETH, "192.168.4.1", "255.255.255.0", "192.168.4.1")
    log.info("ipv4", ipv4,mark, gw)
    while netdrv.link(socket.LWIP_ETH) ~= true do
        sys.wait(100)
    end
    while netdrv.link(socket.LWIP_GP) ~= true do
        sys.wait(100)
    end
    dhcps.create({adapter=socket.LWIP_ETH})
    dnsproxy.setup(socket.LWIP_ETH, socket.LWIP_GP)
    netdrv.napt(socket.LWIP_GP)
    if iperf then
        log.info("启动iperf服务器端")
        iperf.server(socket.LWIP_ETH)
    end
end)


sys.taskInit(function()
    -- sys.waitUntil("IP_READY")
    while 1 do
        sys.wait(300000)
        -- log.info("http", http.request("GET", "http://httpbin.air32.cn/bytes/4096", nil, nil, {adapter=socket.LWIP_ETH}).wait())
        log.info("lua", rtos.meminfo())
        log.info("sys", rtos.meminfo("sys"))
        -- log.info("psram", rtos.meminfo("psram"))
    end
end)
