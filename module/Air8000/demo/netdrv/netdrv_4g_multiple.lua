--[[
@module  netdrv_4g_multiple
@summary 多网卡（4G网卡、WIFI STA网卡、通过SPI外挂CH390H芯片的以太网卡）驱动模块 
@version 1.0
@date    2025.10.20
@author  魏健强
@usage
本文件为多网卡驱动模块 ，核心业务逻辑为：
1、4G连接外部网络，生成WiFi热点为WiFi终端设备提供接入，支持以太网lan模式为其他以太网设备提供接入 ；

直接使用Air8000开发板硬件测试即可；

本文件没有对外接口，直接在其他功能模块中require "netdrv_4g_multiple"就可以加载运行；
]] 
dhcpsrv = require "dhcpsrv"
dnsproxy = require "dnsproxy"

local function lte_eth_setup()
    log.info("ch390", "打开LDO供电")
    gpio.setup(140, 1, gpio.PULLUP) -- 打开ch390供电
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
    -- socket.LWIP_ETH 网络适配器编号
    -- netdrv.CH390外挂CH390
    -- SPI ID 1, 片选 GPIO12
    netdrv.setup(socket.LWIP_ETH, netdrv.CH390, {
        spi = 1,
        cs = 12
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

local function lte_wifi_setup()
    log.info("执行AP创建操作")
    -- 创建wifi_ap热点
    wlan.createAP("test2", "HZ88888888")
    -- 设置ip, 子网掩码，网关
    local ipv4, mark, gw = netdrv.ipv4(socket.LWIP_AP, "192.168.5.1", "255.255.255.0", "192.168.5.1")
    log.info("LWIP_AP", ipv4, mark, gw)
    -- 详细的版本
    -- 创建一个dhcp服务器
    local dhcpsrv_opts = {
        adapter = socket.LWIP_AP, -- 监听哪个网卡, 必须填写
        mark = {255, 255, 255, 0}, -- 网络掩码, 默认 255.255.255.0
        gw = {192, 168, 5, 1}, -- 网关, 默认自动获取网卡IP，如果获取失败则使用 192.168.4.1
        ip_start = 100, -- ip起始地址, 默认100
        ip_end = 200, -- ip结束地址, 默认200
        ack_cb = function(ip, mac)
            log.info("ack_cb", "new client", ip, mac)
        end -- ack回调, 有客户端连接上来时触发, ip和mac地址会传进来
    }
    dhcpsrv.create(dhcpsrv_opts)
    -- 设置dns转发
    dnsproxy.setup(socket.LWIP_AP, socket.LWIP_GP)
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
    -- 开启4G->wifi的多网融合
    lte_wifi_setup()
    -- 设置4G为数据出口
    netdrv.napt(socket.LWIP_GP)
end

-- 启动一个task，task的处理函数为netdrv_multiple_task_func
sys.taskInit(netdrv_multiple_task_func)
