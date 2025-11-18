--[[
@module  netdrv_eth_lan
@summary “通过SPI外挂CH390H芯片的以太网卡”驱动模块 
@version 1.0
@date    2025.10.20
@author  魏健强
@usage
本文件为“通过SPI外挂CH390H芯片的以太网卡”驱动模块 ，核心业务逻辑为：
1、开启以太网lan；

直接使用Air780EHM/Air780EHV/Air780EGH 核心板硬件测试即可；

本文件没有对外接口，直接在其他功能模块中require "netdrv_eth_lan"就可以加载运行；
]] 
dhcps = require "dhcpsrv"

local function eth_lan_setup()

    log.info("ch390", "打开LDO供电")
    gpio.setup(20, 1, gpio.PULLUP) -- 打开ch390供电
    local result = spi.setup(0, -- spi_id
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
    -- socket.LWIP_ETH 网络适配器编号
    -- netdrv.CH390外挂CH390
    -- SPI ID 1, 片选 GPIO12
    netdrv.setup(socket.LWIP_ETH, netdrv.CH390, {
        spi = 0,
        cs = 8
    })
    -- 确保ch390初始化完成,否则会出现netdrv.ipv4设置失败的情况
    sys.wait(1000)
    -- 设置ip, 子网掩码，网关
    local ipv4, mark, gw = netdrv.ipv4(socket.LWIP_ETH, "192.168.4.1", "255.255.255.0", "192.168.4.1")
    log.info("ipv4", ipv4, mark, gw)
    -- 开启dhcp服务器
    dhcps.create({
        adapter = socket.LWIP_ETH
    })
end

sys.taskInit(eth_lan_setup)
