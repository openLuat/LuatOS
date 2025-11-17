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

Air8101核心板和AirETH_1000配件板的硬件接线方式为:
Air8101核心板通过TYPE-C USB口供电（核心板背面的功耗测试开关拨到OFF一端）；
如果测试发现软件重启，并且日志中出现  poweron reason 0，表示供电不足，此时再通过直流稳压电源对核心板的VIN管脚进行5V供电；
| Air8101核心板   |  AirETH_1000配件板 |
| --------------- | ----------------- |
| 59/3V3          | 3.3v              |
| gnd             | gnd               |
| 28/DCLK         | SCK               |
| 54/DISP         | CSS               |
| 55/HSYN         | SDO               |
| 57/DE           | SDI               |
| 14/GPIO8        | INT               |

本文件没有对外接口，直接在其他功能模块中require "netdrv_eth_spi"就可以加载运行；
]]

local exnetif = require "exnetif"

local function ip_ready_func(ip, adapter)
    if adapter == socket.LWIP_USER1 then
        log.info("netdrv_eth_spi.ip_ready_func", "IP_READY: ", socket.localIP(socket.LWIP_USER1))
    end
end

local function ip_lose_func()
    log.warn("netdrv_eth_spi.ip_lose_func", "IP_LOSE")
    sys.publish(SERVER_TOPIC, "SOCKET_CLOSED")
end

--此处订阅"IP_READY"和"IP_LOSE"两种消息
--在消息的处理函数中，仅仅打印了一些信息，便于实时观察“通过SPI外挂CH390H芯片的以太网卡”的连接状态
--也可以根据自己的项目需求，在消息处理函数中增加自己的业务逻辑控制，例如可以在连网状态发生改变时更新网络图标
sys.subscribe("IP_READY", ip_ready_func)
sys.subscribe("IP_LOSE", ip_lose_func)


-- 以太网联网成功（成功连接路由器，并且获取到了IP地址）后，内核固件会产生一个"IP_READY"消息
-- 各个功能模块可以订阅"IP_READY"消息实时处理以太网联网成功的事件
-- 也可以在任何时刻调用socket.adapter(socket.LWIP_USER1)来获取以太网是否连接成功

-- 以太网断网后，内核固件会产生一个"IP_LOSE"消息
-- 各个功能模块可以订阅"IP_LOSE"消息实时处理以太网断网的事件
-- 也可以在任何时刻调用socket.adapter(socket.LWIP_USER1)来获取以太网是否连接成功

--此处订阅"IP_READY"和"IP_LOSE"两种消息
--在消息的处理函数中，仅仅打印了一些信息，便于实时观察“通过SPI外挂CH390H芯片的以太网卡”的连接状态
--也可以根据自己的项目需求，在消息处理函数中增加自己的业务逻辑控制，例如可以在连网状态发生改变时更新网络图标
sys.subscribe("IP_READY", ip_ready_func)
sys.subscribe("IP_LOSE", ip_lose_func)

-- 配置SPI外接以太网芯片CH390H的单网卡，exnetif.set_priority_order使用的网卡编号为socket.LWIP_USER1
-- 本demo使用的Air8101核心板+AirETH_1000配件板, 核心板上的硬件配置为：
-- GPIO13为CH390H以太网芯片的供电使能控制引脚
-- 使用spi0，片选引脚使用GPIO15
exnetif.set_priority_order({
    {
        ETHUSER1 = {
            -- 供电使能GPIO，此demo使用的59脚3V3供电，受GPIO13控制
            pwrpin = 13,
            -- 网卡芯片型号(选填参数)，仅spi方式外挂以太网时需要填写。
            tp = netdrv.CH390, 
            opts = {spi=0, cs=15}
        }
    }
})
