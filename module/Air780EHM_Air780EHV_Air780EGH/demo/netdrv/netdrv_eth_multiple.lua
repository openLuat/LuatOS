--[[
@module  netdrv_eth_multiple
@summary 双以太网驱动模块 
@version 1.0
@date    2025.10.20
@author  魏健强
@usage
本文件为多网卡驱动模块 ，核心业务逻辑为：
1、以太网WAN连接外部网络, 其他需要上网的设备连接模块以太网LAN口上网；

直接使用Air780EHM/Air780EHV/Air780EGH 核心板硬件测试即可；

本文件没有对外接口，直接在其他功能模块中require "netdrv_eth_multiple"就可以加载运行；
]] 
dhcpsrv = require "dhcpsrv"
dnsproxy = require "dnsproxy"

local static_ip = false


local function eth_wan_setup()
    log.info("ch390", "打开LDO供电")
    gpio.setup(20, 1, gpio.PULLUP) -- 打开ch390供电
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
    -- socket.LWIP_ETH 网络适配器编号
    -- netdrv.CH390外挂CH390
    -- SPI ID 1, 片选 GPIO12
    netdrv.setup(socket.LWIP_ETH, netdrv.CH390, {
        spi = 0,
        cs = 8
    })
    sys.wait(1000) -- 等待以太网模块初始化完成,去掉会导致以太网初始化失败
    if static_ip then
        -- 静态ip配置
        log.info("静态ip", netdrv.ipv4(socket.LWIP_ETH, "192.168.4.100", "255.255.255.0", "192.168.4.1"))
    else
        -- 使用dhcp动态获取ip地址
        netdrv.dhcp(socket.LWIP_ETH, true)
    end
    log.info("LWIP_ETH", "mac addr", netdrv.mac(socket.LWIP_ETH))
end

local function eth_lan_setup()
    log.info("ch390", "打开LDO供电")
    gpio.setup(21, 1, gpio.PULLUP) -- 打开ch390供电
    local result = spi.setup(1, -- spi_id
    nil, 0, -- CPHA
    0, -- CPOL
    8, -- 数据宽度
    25600000 -- ,--频率
    )
    log.info("main", "open", result)
    if result ~= 0 then -- 返回值为0，表示打开成功
        log.info("main", "spi open error", result)
        return
    end

    -- 初始化指定netdrv设备,
    -- socket.LWIP_USER0 网络适配器编号
    -- netdrv.CH390外挂CH390
    -- SPI ID 1, 片选 GPIO12
    netdrv.setup(socket.LWIP_USER0, netdrv.CH390, {
        spi = 1,
        cs = 12
    })
    -- 确保ch390初始化完成,否则会出现netdrv.ipv4设置失败的情况
    sys.wait(1000)
    -- 设置ip, 子网掩码，网关
    local ipv4, mark, gw = netdrv.ipv4(socket.LWIP_USER0, "192.168.5.1", "255.255.255.0", "192.168.5.1")
    log.info("ipv4", ipv4, mark, gw)
    -- 开启dhcp服务器
    dhcpsrv.create({
        adapter = socket.LWIP_USER0
    })
end


local function netdrv_multiple_task_func()
    eth_wan_setup()
    eth_lan_setup()
    -- 设置dns转发
    dnsproxy.setup(socket.LWIP_USER0, socket.LWIP_ETH)
    -- 设置以太网为数据出口
    netdrv.napt(socket.LWIP_ETH)
end

local function http_test()
    -- sys.waitUntil("IP_READY")
    while 1 do
        sys.wait(6000)
        log.info("http", http.request("GET", "http://httpbin.air32.cn/bytes/4096", nil, nil, {
            adapter = socket.LWIP_ETH
        }).wait()) -- adapter指定为以太网联网方式
        log.info("lua", rtos.meminfo())
        log.info("sys", rtos.meminfo("sys"))
    end
end

-- 启动一个task，task的处理函数为netdrv_multiple_task_func
sys.taskInit(netdrv_multiple_task_func)
sys.taskInit(http_test)