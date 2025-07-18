--[[
@module  wan
@summary wan功能测试模块
@version 1.0
@date    2025.07.01
@author  Jensen
@usage
使用Air780EGH核心板，通过以太网模块CH390H连接路由器LAN口，在路由器DHCP获取IP地址后可以访问互联网
]]

-- 网络配置，netdrv模块启动ch390h以太网模块
function network_setup()
    -- 配置以太网模块ch390h的spi接口参数，使用SPI0
    -- sys.wait(3000)
    local result = spi.setup(
        0,--串口id
        nil,
        0,--CPHA
        0,--CPOL
        8,--数据宽度
        38400000--,--频率，这里注意若通过杜邦线连接CH390H与核心板需调整总线速率，过大的速率会造成通信失败
        -- spi.MSB,--高低位顺序    可选，默认高位在前
        -- spi.master,--主模式     可选，默认主
        -- spi.full--全双工       可选，默认全双工
    )
    log.info("main", "open",result)
    if result ~= 0 then--返回值为0，表示打开成功
        log.info("main", "spi open error",result)
        return
    end
    -- 配置以太网网络,使用SPI0, CS为GPIO08
    netdrv.setup(socket.LWIP_ETH, netdrv.CH390, {spi=0,cs=8})
    -- 使能DHCP
    netdrv.dhcp(socket.LWIP_ETH, true)
end

-- CH390H通过网线连接路由器LAN口，路由器已拨号上网，通过路由器接入互联网进行http通信测试
function test_http_requet()
    -- sys.waitUntil("IP_READY")
    while 1 do
        sys.wait(6000)
        -- 定时通过http get请求来获取4K数据
        log.info("http", http.request("GET", "http://httpbin.air32.cn/bytes/4096", nil, nil, {adapter=socket.LWIP_ETH}).wait())
        log.info("lua", rtos.meminfo())
        log.info("sys", rtos.meminfo("sys"))
    end
end

-- 启动wan网络配置任务
sys.taskInit(network_setup)
-- 启动wan网络数据通信任务
sys.taskInit(test_http_requet)