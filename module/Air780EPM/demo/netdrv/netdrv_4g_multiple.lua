--[[
@module  netdrv_4g_multiple
@summary 多网卡（4G网卡、通过SPI外挂CH390H芯片的以太网卡）驱动模块 
@version 1.0
@date    2025.10.20
@author  魏健强
@usage
本文件为多网卡驱动模块 ，核心业务逻辑为：
1、4G连接外部网络，以太网lan模式为其他以太网设备提供接入 ；

直接使用Air780EPM V1.3开发板硬件测试即可；

本文件没有对外接口，直接在其他功能模块中require "netdrv_4g_multiple"就可以加载运行；
]] 
dhcpsrv = require "dhcpsrv"
dnsproxy = require "dnsproxy"

local function lte_eth_setup()
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
    log.info("LWIP_ETH", ipv4, mark, gw)
    -- 开启dhcp服务器
    dhcpsrv.create({adapter = socket.LWIP_ETH})
    -- 设置dns转发
    dnsproxy.setup(socket.LWIP_ETH, socket.LWIP_GP)
end


local function netdrv_multiple_task_func()
    -- 等待4G网络连接成功
    while not socket.adapter() do
        -- 在此处阻塞等待4G网卡连接成功的消息"IP_READY"
        -- 或者等待1秒超时退出阻塞等待状态;
        -- 注意：此处的1000毫秒超时不要修改的更长；
        sys.waitUntil("IP_READY", 1000)
    end
    -- 开启4G->以太网的多网融合
    lte_eth_setup()
    -- 设置4G为数据出口
    netdrv.napt(socket.LWIP_GP)
end

-- 启动一个task，task的处理函数为netdrv_multiple_task_func
sys.taskInit(netdrv_multiple_task_func)
