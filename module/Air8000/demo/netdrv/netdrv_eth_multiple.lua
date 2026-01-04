--[[
@module  netdrv_eth_multiple
@summary 多网卡（4G网卡、WIFI STA网卡、通过SPI外挂CH390H芯片的以太网卡）驱动模块 
@version 1.0
@date    2025.10.20
@author  魏健强
@usage
本文件为多网卡驱动模块 ，核心业务逻辑为：
1、以太网连接外部网络,生成WiFi热点为WiFi终端设备提供接入 ；

直接使用Air8000开发板硬件测试即可；

本文件没有对外接口，直接在其他功能模块中require "netdrv_eth_multiple"就可以加载运行；
]] 
dhcpsrv = require "dhcpsrv"
dnsproxy = require "dnsproxy"

local static_ip = false

local function netdrv_multiple_task_func()
    -- 配置SPI外接以太网芯片CH390H的单网卡，exnetif.set_priority_order使用的网卡编号为socket.LWIP_ETH
    -- 本demo使用Air8000开发板测试，开发板上的硬件配置为：
    -- GPIO140为CH390H以太网芯片的供电使能控制引脚
    -- 使用spi1，片选引脚使用GPIO12
    -- 如果使用的硬件不是Air8000开发板，根据自己的硬件配置修改以下参数
    log.info("ch390", "打开LDO供电")
    gpio.setup(140, 1, gpio.PULLUP) -- 打开ch390供电
    local result = spi.setup(1, -- spi_id
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
        spi = 1,
        cs = 12
    })
    sys.wait(1000) -- 等待以太网模块初始化完成,去掉会导致以太网初始化失败
    if static_ip then
        -- 手动静态ip配置
        log.info("静态ip", netdrv.ipv4(socket.LWIP_ETH, "192.168.4.100", "255.255.255.0", "192.168.4.1"))
    else
        -- 使用dhcp动态获取ip地址
        netdrv.dhcp(socket.LWIP_ETH, true)
    end

    -- 等待eth_wan网络连接成功
    while not socket.adapter(socket.LWIP_ETH) do
        -- 在此处阻塞等待wifi连接成功的消息"IP_READY"
        -- 或者等待1秒超时退出阻塞等待状态;
        -- 注意：此处的1000毫秒超时不要修改的更长；
        sys.waitUntil("IP_READY", 1000)
    end
    -- eth_wan -> wifi_ap
    log.info("执行AP创建操作")
    -- 开启wifi_ap热点
    wlan.createAP("test2", "HZ88888888")
    -- 设置ip, 子网掩码，网关
    local ipv4, mark, gw = netdrv.ipv4(socket.LWIP_AP, "192.168.5.1", "255.255.255.0", "192.168.5.1")
    log.info("LWIP_AP", ipv4, mark, gw)
    while netdrv.ready(socket.LWIP_AP) ~= true do
        sys.wait(100)
    end
    -- 设置dns转发
    dnsproxy.setup(socket.LWIP_AP, socket.LWIP_ETH)
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
    -- 设置以太网为数据出口
    netdrv.napt(socket.LWIP_ETH)
end

-- 启动一个task，task的处理函数为netdrv_multiple_task_func
sys.taskInit(netdrv_multiple_task_func)
