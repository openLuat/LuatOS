--[[
@module  netdrv_eth_wan
@summary 以太网卡驱动模块 
@version 1.0
@date    2025.10.20
@author  魏健强
@usage
本文件为以太网卡驱动模块 ，核心业务逻辑为：
1、开启以太网wan；

直接使用Air8101核心板+以太网扩展板硬件测试即可；

本文件没有对外接口，直接在其他功能模块中require "netdrv_eth_wan"就可以加载运行；
]] 
local static_ip = false

local is_RMII = true -- 使用rmii接口或spi接口
local eth_adapter = socket.LWIP_USER1 -- 以太网网卡适配器编号
local function ip_ready_func(ip, adapter)
    log.info("netdrv_eth_wan.ip_ready_func", "IP_READY", socket.localIP(eth_adapter))
end

local function ip_lose_func(adapter)
    if adapter == eth_adapter then
        log.warn("netdrv_eth_wan.ip_lose_func", "IP_LOSE")
    end
end

-- 以太网联网成功（成功连接路由器，并且获取到了IP地址）后，内核固件会产生一个"IP_READY"消息
-- 各个功能模块可以订阅"IP_READY"消息实时处理以太网联网成功的事件
-- 也可以在任何时刻调用socket.adapter(eth_adapter)来获取以太网是否连接成功

-- 以太网断网后，内核固件会产生一个"IP_LOSE"消息
-- 各个功能模块可以订阅"IP_LOSE"消息实时处理以太网断网的事件
-- 也可以在任何时刻调用socket.adapter(eth_adapter)来获取以太网是否连接成功

-- 此处订阅"IP_READY"和"IP_LOSE"两种消息
-- 在消息的处理函数中，仅仅打印了一些信息，便于实时观察“通过SPI外挂CH390H芯片的以太网卡”的连接状态
-- 也可以根据自己的项目需求，在消息处理函数中增加自己的业务逻辑控制，例如可以在连网状态发生改变时更新网络图标
sys.subscribe("IP_READY", ip_ready_func)
sys.subscribe("IP_LOSE", ip_lose_func)
local function eth_wan_setup()
    if is_RMII then
        eth_adapter = socket.LWIP_ETH
        -- 使用8101核心板+AirPHY以太网扩展板测试
        log.info("使用RMII接口连接以太网PHY芯片")
        netdrv.setup(eth_adapter)
    else
        eth_adapter = socket.LWIP_USER1
        -- 使用8101核心板+AirETH以太网扩展板测试
        log.info("ch390", "打开LDO供电")
        gpio.setup(13, 1, gpio.PULLUP) -- 打开ch390供电
        local result = spi.setup(0, -- spi_id
        nil, 0, -- CPHA
        0, -- CPOL
        8, -- 数据宽度
        25600000 -- ,--频率
        -- spi.MSB,--高低位顺序    可选，默认高位在前
        -- spi.master,--主模式     可选，默认主
        -- spi.full--全双工       可选，默认全双工
        )
        log.info("main", "open", result)
        if result ~= 0 then -- 返回值为0，表示打开成功
            log.info("main", "spi open error", result)
            return
        end
        -- 初始化指定netdrv设备,
        -- eth_adapter 网络适配器编号
        -- netdrv.CH390外挂CH390
        -- SPI ID 1, 片选 GPIO12
        netdrv.setup(eth_adapter, netdrv.CH390, {
            spi = 0,
            cs = 15
        })
    end
    sys.wait(1000) -- 等待以太网模块初始化完成,去掉会导致以太网初始化失败
    if static_ip then
        -- 静态ip配置
        log.info("静态ip", netdrv.ipv4(eth_adapter, "192.168.4.100", "255.255.255.0", "192.168.4.1"))
    else
        -- 使用dhcp动态获取ip地址
        netdrv.dhcp(eth_adapter, true)
    end
    log.info("LWIP_ETH", "mac addr", netdrv.mac(eth_adapter))
end


local function http_test()
    -- sys.waitUntil("IP_READY")
    while 1 do
        sys.wait(6000)
        log.info("http", http.request("GET", "http://httpbin.air32.cn/bytes/4096", nil, nil, {
            adapter = eth_adapter
        }).wait()) -- adapter指定为以太网联网方式
        log.info("lua", rtos.meminfo())
        log.info("sys", rtos.meminfo("sys"))
    end
end
sys.taskInit(eth_wan_setup)
sys.taskInit(http_test)


