
-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "air780epm_WAN"
VERSION = "1.0.5"

dnsproxy = require("dnsproxy")
dhcpsrv = require("dhcpsrv")
httpplus = require("httpplus")

gpio.setup(20, 1) -- 打开lan供电

function eth_wan()

    sys.wait(3000)
    local result = spi.setup(
        0,--spi id
        nil,
        0,--CPHA
        0,--CPOL
        8,--数据宽度
        25600000--,--频率
        -- spi.MSB,--高低位顺序    可选，默认高位在前
        -- spi.master,--主模式     可选，默认主
        -- spi.full--全双工       可选，默认全双工
    )
    log.info("main", "open",result)
    if result ~= 0 then--返回值为0，表示打开成功
        log.info("main", "spi open error",result)
        return
    end
    
    sys.wait(200)
    log.info("netdrv", "初始化WAN")    
    
    netdrv.setup(socket.LWIP_ETH, netdrv.CH390, {spi=0,cs=8})
    sys.wait(100)
    netdrv.dhcp(socket.LWIP_ETH, true)
    log.info("netdrv", "以太网就绪")


end



sys.taskInit(function()

    
    sys.taskInit(eth_wan)
    sys.wait(1000)
    while 1 do
        sys.wait(1000)
        local result, ip, adapter = sys.waitUntil("IP_READY", 3000)
        log.info("ready?", result, ip, adapter)
        if adapter and adapter ==  socket.LWIP_ETH then
            break
        end
    end
    sys.wait(500)

    iperf.server(socket.LWIP_ETH)

    while 1 do
        sys.wait(6000)
        -- local code, headers, body = http.request("GET", "http://httpbin.air32.cn/bytes/4096", nil, nil, {adapter=socket.LWIP_ETH}).wait()
        local code, headers, body = http.request("GET", "http://www.baidu.com/", nil, nil, {adapter=socket.LWIP_ETH}).wait()
        log.info("http", code, headers, body and #body)
        log.info("lua", rtos.meminfo())
        log.info("sys", rtos.meminfo("sys"))
    end
end)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
