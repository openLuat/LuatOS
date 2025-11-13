--[[
@module  netdrv_eth_spi
@summary "以太网SPI网卡"驱动模块
@version 1.0
@date    2025.11.4
@author  拓毅恒
@usage
本文件为以太网SPI网卡驱动模块，核心业务逻辑为：
1、初始化以太网SPI接口；
2、配置以太网适配器；
3、设置IP地址；
4、当网络连接成功后，会发布CREATE_OK事件通知HTTP服务器启动；

本文件没有对外接口，直接在其他功能模块中require "netdrv_eth_spi"就可以加载运行；
]]

gpio.setup(140, 1, gpio.PULLUP)     --打开ch390供电

-- 以太网IP状态变化处理
local function eth_ip_ready_func(ip, adapter)
    if adapter == socket.LWIP_ETH then
        log.info("netdrv_eth_spi", "IP_READY", ip)
        -- 发布CREATE_OK事件，通知HTTP服务器启动
        sys.publish("CREATE_OK")
    end
end

-- 订阅以太网相关事件
sys.subscribe("IP_READY", eth_ip_ready_func)

-- 创建并启动以太网初始化任务
local function netdrv_eth_init_task()
    -- 设置默认网卡为socket.LWIP_ETH
    socket.dft(socket.LWIP_ETH)
    
    -- 初始化SPI接口连接CH390
    local result = spi.setup(
        1,--串口id
        nil,
        0,--CPHA
        0,--CPOL
        8,--数据宽度
        25600000--频率
    )
    if result ~= 0 then--返回值为0，表示打开成功
        log.info("netdrv_eth_spi", "SPI初始化失败", result)
        return
    end
    log.info("netdrv_eth_spi", "SPI初始化成功")

    -- 设置CH390驱动和网络参数
    netdrv.setup(socket.LWIP_ETH, netdrv.CH390, {spi=1,cs=12})
    sys.wait(3000)
    
    -- 配置从路由器获取IP地址（DHCP客户端模式）
    log.info("netdrv_ethernet_spi", "开始从路由器获取IP地址...")
    netdrv.dhcp(socket.LWIP_ETH, true)  -- 启用DHCP客户端
    sys.wait(3000)
    
    -- 获取并显示分配的IP地址
    local ipv4, mark, gw = netdrv.ipv4(socket.LWIP_ETH)
    -- 手动设置IP地址
    -- local ipv4,mark, gw = netdrv.ipv4(socket.LWIP_ETH, "192.168.4.1", "255.255.255.0", "192.168.4.1")
    server_ip = ipv4
    log.info("netdrv_ethernet_spi", "IP配置完成:", ipv4, mark, gw)
    -- 等待以太网连接
    while netdrv.link(socket.LWIP_ETH) ~= true do
        sys.wait(100)
    end
    while netdrv.link(socket.LWIP_GP) ~= true do
        sys.wait(100)
    end
    log.info("netdrv_ethernet_spi", "以太网连接状态:", netdrv.link(socket.LWIP_ETH))
end

-- 启动以太网初始化任务
sys.taskInit(netdrv_eth_init_task)