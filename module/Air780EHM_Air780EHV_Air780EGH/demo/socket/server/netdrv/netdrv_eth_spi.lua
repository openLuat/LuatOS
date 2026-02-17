--[[
@module  netdrv_eth_spi
@summary “通过SPI外挂CH390H芯片的以太网卡”驱动模块 
@version 1.0
@date    2025.11.15
@author  王世豪
@usage
本文件为“通过SPI外挂CH390H芯片的以太网卡”驱动模块 ，核心业务逻辑为：
1、打开AirETH_1000配件板供电开关；
2、初始化spi0，初始化以太网卡，并且在以太网卡上开启DHCP(动态主机配置协议)；
3、以太网卡的连接状态发生变化时，在日志中进行打印；

Air780EXX核心板和AirETH_1000配件板的硬件接线方式为:
Air780EXX核心板通过TYPE-C USB口供电（核心板背面的功耗测试开关拨到OFF一端）；
| Air780EXX核心板  |  AirETH_1000配件板 |
| --------------- | ----------------- |
| 3V3             | 3.3v              |
| gnd             | gnd               |
| 86/SPI0CLK      | SCK               |
| 83/SPI0CS       | CSS               |
| 84/SPI0MISO     | SDO               |
| 85/SPI0MOSI     | SDI               |
| 107/GPIO21      | INT               |


本文件没有对外接口，直接在其他功能模块中require "netdrv_eth_spi"就可以加载运行；
]]

local exnetif = require "exnetif"

local function ip_ready_func(ip, adapter)    
    if adapter == socket.LWIP_ETH then
        -- 在位置1和2设置自定义的DNS服务器ip地址：
        -- "223.5.5.5"，这个DNS服务器IP地址是阿里云提供的DNS服务器IP地址；
        -- "114.114.114.114"，这个DNS服务器IP地址是国内通用的DNS服务器IP地址；
        -- 可以加上以下两行代码，在自动获取的DNS服务器工作不稳定的情况下，这两个新增的DNS服务器会使DNS服务更加稳定可靠；
        -- 如果使用专网卡，不要使用这两行代码；
        -- 如果使用国外的网络，不要使用这两行代码；
        socket.setDNS(adapter, 1, "223.5.5.5")
        socket.setDNS(adapter, 2, "114.114.114.114")

        log.info("netdrv_eth_spi.ip_ready_func", "IP_READY", socket.localIP(socket.LWIP_ETH))
    end
end

local function ip_lose_func(adapter)    
    if adapter == socket.LWIP_ETH then
        log.warn("netdrv_eth_spi.ip_lose_func", "IP_LOSE")
	sys.publish(SERVER_TOPIC, "SOCKET_CLOSED")
    end
end


-- 以太网联网成功（成功连接路由器，并且获取到了IP地址）后，内核固件会产生一个"IP_READY"消息
-- 各个功能模块可以订阅"IP_READY"消息实时处理以太网联网成功的事件
-- 也可以在任何时刻调用socket.adapter(socket.LWIP_ETH)来获取以太网是否连接成功

-- 以太网断网后，内核固件会产生一个"IP_LOSE"消息
-- 各个功能模块可以订阅"IP_LOSE"消息实时处理以太网断网的事件
-- 也可以在任何时刻调用socket.adapter(socket.LWIP_ETH)来获取以太网是否连接成功

--此处订阅"IP_READY"和"IP_LOSE"两种消息
--在消息的处理函数中，仅仅打印了一些信息，便于实时观察“通过SPI外挂CH390H芯片的以太网卡”的连接状态
--也可以根据自己的项目需求，在消息处理函数中增加自己的业务逻辑控制，例如可以在连网状态发生改变时更新网络图标
sys.subscribe("IP_READY", ip_ready_func)
sys.subscribe("IP_LOSE", ip_lose_func)


-- 配置SPI外接以太网芯片CH390H的单网卡，exnetif.set_priority_order使用的网卡编号为socket.LWIP_ETH
-- 本demo使用Air780EHM/EHV/EGH核心板+AirETH_1000配件板测试，核心板上的硬件配置为：
-- 核心板的VDD 3V3管脚对AirETH_1000配件板进行供电；3V3管脚是作为LDO 3.3V输出，供测试用的，仅在使用DCDC供电时有输出，默认打开，无需控制
-- 使用spi0，片选引脚使用GPIO15
-- 如果使用的硬件和以上描述的环境不同，根据自己的硬件配置修改以下参数
exnetif.set_priority_order({
    {
        ETHERNET = {
            pwrpin = nil, 
            tp = netdrv.CH390,
            opts = {spi = 0, cs = 8}
        }
    }
})
