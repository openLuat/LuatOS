--[[
@module  netdrv_wifi_multiple
@summary 多网卡（RMII以太网卡、WIFI STA网卡、通过SPI外挂CH390H芯片的以太网卡）驱动模块 
@version 1.0
@date    2025.10.20
@author  魏健强
@usage
本文件为多网卡驱动模块 ，核心业务逻辑为：
1、WIFI连接外部网络,支持以太网lan模式为其他以太网设备提供接入,支持生成WiFi热点为WiFi终端设备提供接入；

直接使用Air8101核心板+以太网扩展板硬件测试即可；

本文件没有对外接口，直接在其他功能模块中require "netdrv_wifi_multiple"就可以加载运行；
]] 
dhcpsrv = require "dhcpsrv"
dnsproxy = require "dnsproxy"

local is_RMII = false -- 使用rmii接口或spi接口
local eth_adapter = socket.LWIP_USER1 -- 以太网网卡适配器编号
wlan.init()

local function eth_lan_setup()
    if is_RMII then
        eth_adapter = socket.LWIP_ETH
        --使用8101核心板+AirPHY以太网扩展板测试
        netdrv.setup(eth_adapter)
    else
        eth_adapter = socket.LWIP_USER1
        --使用8101核心板+AirETH以太网扩展板测试
        log.info("ch390", "打开LDO供电")
        gpio.setup(13, 1, gpio.PULLUP) -- 打开ch390供电
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
        -- eth_adapter 网络适配器编号
        -- netdrv.CH390外挂CH390
        -- SPI ID 1, 片选 GPIO12
        netdrv.setup(eth_adapter, netdrv.CH390, {
            spi = 0,
            cs = 15
        })
    end
    -- 确保ch390初始化完成,否则会出现netdrv.ipv4设置失败的情况
    sys.wait(1000)
    -- 设置ip, 子网掩码，网关
    local ipv4, mark, gw = netdrv.ipv4(eth_adapter, "192.168.4.1", "255.255.255.0", "192.168.4.1")
    log.info("ipv4", ipv4, mark, gw)
    -- 开启dhcp服务器
    dhcpsrv.create({
        adapter = eth_adapter
    })
    -- 设置dns转发
    dnsproxy.setup(eth_adapter, socket.LWIP_STA)
end

local function wifi_sta_ap_setup()
    log.info("执行AP创建操作")
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
    -- 开启dhcp服务器
    dhcpsrv.create(dhcpsrv_opts)
    -- 设置dns转发
    dnsproxy.setup(socket.LWIP_AP, socket.LWIP_STA)
end

local function netdrv_multiple_task_func()
    -- 设置wifi工作模式为STA+AP模式
    wlan.setMode(wlan.STATIONAP)
    -- 连接wifi
    wlan.connect("茶室-降功耗,找合宙!", "Air123456")
    -- 等待wifi_sta网络连接成功
    while not socket.adapter(socket.LWIP_STA) do
        -- 在此处阻塞等待wifi连接成功的消息"IP_READY"
        -- 或者等待1秒超时退出阻塞等待状态;
        -- 注意：此处的1000毫秒超时不要修改的更长；
        sys.waitUntil("IP_READY", 1000)
    end
    -- 开启wifi->以太网的多网融合
    eth_lan_setup()
    -- 开启wifi sta->ap的多网融合
    wifi_sta_ap_setup()
    -- 设置wifi_sta为数据出口
    netdrv.napt(socket.LWIP_STA)
end

-- 启动一个task，task的处理函数为netdrv_multiple_task_func
sys.taskInit(netdrv_multiple_task_func)
