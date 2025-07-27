--[[
@module  netdrv_4g
@summary “通过SPI接口外挂4G模组(Air780EHM/Air780EHV/Air780EGH/Air780EPM)的4G网卡”驱动模块 
@version 1.0
@date    2025.07.27
@author  朱天华
@usage
本文件为 “通过SPI接口外挂4G模组(Air780EHM/Air780EHV/Air780EGH/Air780EPM)的4G网卡”驱动模块，核心业务逻辑为：
1、初始化和外部4G网卡的配置（初始化AirLINK、配置桥接网络、配置SPI、静态配置IP地址/子网掩码/网关）；
2、4G网卡的连接状态发生变化时，在日志中进行打印；


硬件环境使用以下两种环境中的一种即可：
1、Air8101核心板+Air780EHM/Air780EHV/Air780EGH/Air780EPM核心板
2、Air8101核心板+Air780EHM/Air780EHV/Air780EGH/Air780EPM开发板

一、当使用第1种硬件环境时，Air8101核心板和Air780EHM/Air780EHV/Air780EGH/Air780EPM核心板的硬件接线方式为:

1、Air8101核心板：
- 核心板通过TYPE-C USB口供电（核心板背面的功耗测试开关拨到OFF一端）；
- 如果测试发现软件重启，并且日志中出现  poweron reason 0，表示供电不足，此时再通过直流稳压电源对核心板的VIN管脚进行5V供电；

2、Air780EHM/Air780EHV/Air780EGH/Air780EPM核心板：
- 核心板通过TYPE-C USB口供电（TYPE-C USB口旁边的ON/OFF拨动开关拨到ON一端）；
- 如果测试发现软件重启，并且日志中出现  poweron reason 0，表示供电不足，此时再通过直流稳压电源对核心板的5V管脚进行5V供电；

3、
| Air8101核心板 | Air780EHM/Air780EHV/Air780EGH/Air780EPM核心板  |
| ------------ | ---------------------------------------------- |
|     gnd      |                     GND                        |
|  54/DISP     |                     83/SPI0CS                  |
|  55/HSYN     |                     84/SPI0MISO                |
|    57/DE     |                     85/SPI0MOSI                |
|  28/DCLK     |                     86/SPI0CLK                 |
|    43/R2     |                     19/GPIO22                  |
|  75/GPIO28   |                     22/GPIO1                   |

二、当使用第2种硬件环境时，Air8101核心板和Air780EHM/Air780EHV/Air780EGH/Air780EPM开发板的硬件接线方式为:

1、Air8101核心板：
- 核心板通过TYPE-C USB口供电（核心板背面的功耗测试开关拨到OFF一端）；
- 如果测试发现软件重启，并且日志中出现  poweron reason 0，表示供电不足，此时再通过直流稳压电源对核心板的VIN管脚进行5V供电；

2、Air780EHM/Air780EHV/Air780EGH/Air780EPM开发板：
- 核心板通过TYPE-C USB口供电（外部供电/USB供电拨动开关拨到USB供电一端）；
- 如果测试发现软件重启，并且日志中出现  poweron reason 0，表示供电不足，此时再通过直流稳压电源对开发板的4V管脚进行4V供电；

3、
| Air8101核心板 | Air780EHM/Air780EHV/Air780EGH/Air780EPM开发板  |
| ------------ | ---------------------------------------------- |
|     gnd      |                     GND                        |
|  54/DISP     |                     SPI_CS                     |
|  55/HSYN     |                     SPI_MISO                   |
|    57/DE     |                     SPI_MOSI                   |
|  28/DCLK     |                     SPI_CLK                    |
|    43/R2     |                     GPIO22                     |
|  75/GPIO28   |                     GPIO1                      |

三、以上两种硬件环境，Air8101使用的SPI0默认的一组引脚，也可以使用SPI1；使用SPI1时，硬件连接说明的更多资料参考：
https://docs.openluat.com/air8101/luatos/hardware/design/4gnet/
软件代码需要做以下配置：
airlink.config(airlink.CONF_SPI_ID, 1)
airlink.config(airlink.CONF_SPI_CS, 10)

四、测试本功能模块时，Air780EHM/Air780EHV/Air780EGH/Air780EPM需要烧录以下软件：
1、最新版本的内核固件
2、脚本：https://gitee.com/openLuat/LuatOS/tree/master/module/Air8101/demo/multi_network/WIFI_4G_ETH/Air8101_Air780EPM/Air780EPM_master

本文件没有对外接口，直接在其他功能模块中require "netdrv_4g"就可以加载运行；
]]

local function ip_ready_func()
    log.info("netdrv_4g.ip_ready_func", "IP_READY", socket.localIP(socket.LWIP_USER0))
end

local function ip_lose_func()
    log.warn("netdrv_4g.ip_lose_func", "IP_LOSE")
end



--此处订阅"IP_READY"和"IP_LOSE"两种消息
--在消息的处理函数中，仅仅打印了一些信息，便于实时观察“通过SPI接口外挂4G模组(Air780EHM/Air780EHV/Air780EGH/Air780EPM)的4G网卡”的连接状态
--也可以根据自己的项目需求，在消息处理函数中增加自己的业务逻辑控制，例如可以在连网状态发生改变时更新网络图标
sys.subscribe("IP_READY", ip_ready_func)
sys.subscribe("IP_LOSE", ip_lose_func)




-- 初始化airlink，Air8101和4G网卡之间，在spi之上，基于airlink协议通信
airlink.init()
-- 创建桥接网络设备
-- 此处第一个参数必须是socket.LWIP_USER0，是因为Air780EHM/Air780EHV/Air780EGH/Air780EPM使用的也是socket.LWIP_USER0，双方是点对点通讯的对等网络
-- 此处第二个参数必须是netdrv.WHALE，表示虚拟网卡的实现方式
netdrv.setup(socket.LWIP_USER0, netdrv.WHALE)
-- 启动airlink，配置Air8101作为SPI从机模式。
airlink.start(airlink.MODE_SPI_SLAVE)

-- 静态配置IPv4地址
-- 本地ip地址为"192.168.111.1"，网关ip地址为"192.168.111.2"，子网掩码为"255.255.255.0"
-- 此处设置的本地ip地址要和Air780EHM/Air780EHV/Air780EGH/Air780EPM中设置的网关ip地址完全一样
-- 此处设置的网关ip地址要和Air780EHM/Air780EHV/Air780EGH/Air780EPM中设置的本地ip地址完全一样
-- 此处设置的子网掩码要和Air780EHM/Air780EHV/Air780EGH/Air780EPM中设置的子网掩码完全一样
netdrv.ipv4(socket.LWIP_USER0, "192.168.111.1", "255.255.255.0", "192.168.111.2")

--4G联网成功后，内核固件会产生一个"IP_READY"消息
--各个功能模块可以订阅"IP_READY"消息实时处理4G联网成功的事件
--也可以在任何时刻调用socket.adapter(socket.LWIP_USER0)来获取4G网络是否连接成功

--4G断网后，内核固件会产生一个"IP_LOSE"消息
--各个功能模块可以订阅"IP_LOSE"消息实时处理4G网络断网的事件
--也可以在任何时刻调用socket.adapter(socket.LWIP_USER0)来获取4G网络是否连接成功
