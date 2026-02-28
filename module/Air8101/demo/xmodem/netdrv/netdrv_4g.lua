--[[
@module  netdrv_4g
@summary “通过SPI接口外挂4G模组(Air780EHM/Air780EHV/Air780EGH/Air780EPM)的4G网卡”驱动模块
@version 1.0
@date    2025.07.27
@author  马梦阳
@usage
本文件为 “通过SPI接口外挂4G模组(Air780EHM/Air780EHV/Air780EGH/Air780EPM)的4G网卡”驱动模块，核心业务逻辑为：
1、初始化和外部4G网卡的配置；
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
| Air8101核心板 |  Air780EHM/Air780EHV/Air780EGH/Air780EPM核心板  |
| ------------ | ---------------------------------------------- |
|     gnd      |                     GND                        |
|  54/DISP     |                     83/SPI0CS                  |
|  55/HSYN     |                     84/SPI0MISO                |
|    57/DE     |                     85/SPI0MOSI                |
|  28/DCLK     |                     86/SPI0CLK                 |
|    43/R2     |                     19/GPIO22                  |

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

三、以上两种硬件环境，Air8101使用的SPI0默认的一组引脚，也可以使用SPI1；使用SPI1时，硬件连接说明的更多资料参考：
https://docs.openluat.com/air8101/luatos/hardware/design/4gnet/

四、测试本功能模块时，Air780EHM/Air780EHV/Air780EGH/Air780EPM需要烧录以下软件：
1、最新版本的内核固件
2、脚本：https://gitee.com/openLuat/LuatOS/tree/master/module/Air8101/demo/airlink/Air8101_master_Air780EPM_slave/Air780EPM_slave

本文件没有对外接口，直接在其他功能模块中require "netdrv_4g"就可以加载运行；
]]

local exnetif = require "exnetif"

local function ip_ready_func(ip, adapter)
    if adapter == socket.LWIP_GP_GW then
        -- 在位置1和2设置自定义的DNS服务器ip地址：
        -- "223.5.5.5"，这个DNS服务器IP地址是阿里云提供的DNS服务器IP地址；
        -- "114.114.114.114"，这个DNS服务器IP地址是国内通用的DNS服务器IP地址；
        -- 可以加上以下两行代码，在自动获取的DNS服务器工作不稳定的情况下，这两个新增的DNS服务器会使DNS服务更加稳定可靠；
        -- 如果使用专网卡，不要使用这两行代码；
        -- 如果使用国外的网络，不要使用这两行代码；
        socket.setDNS(adapter, 1, "223.5.5.5")
        socket.setDNS(adapter, 2, "114.114.114.114")
        
        log.info("netdrv_4g.ip_ready_func", "IP_READY", socket.localIP(socket.LWIP_GP_GW))
    end
end

local function ip_lose_func(adapter)
    if adapter == socket.LWIP_GP_GW then
        log.warn("netdrv_4g.ip_lose_func", "IP_LOSE")
    end
end


-- 4G联网成功后，内核固件会产生一个"IP_READY"消息
-- 各个功能模块可以订阅"IP_READY"消息实时处理4G联网成功的事件
-- 也可以在任何时刻调用socket.adapter(socket.LWIP_GP_GW)来获取4G是否联网成功

-- 4G断网后，内核固件会产生一个"IP_LOSE"消息
-- 各个功能模块可以订阅"IP_LOSE"消息实时处理4G断网的事件
-- 也可以在任何时刻调用socket.adapter(socket.LWIP_GP_GW)来获取4G是否联网成功

--此处订阅"IP_READY"和"IP_LOSE"两种消息
--在消息的处理函数中，仅仅打印了一些信息，便于实时观察4G的联网状态
--也可以根据自己的项目需求，在消息处理函数中增加自己的业务逻辑控制，例如可以在联网状态发生改变时更新网络图标
-- 此处订阅"IP_READY"和"IP_LOSE"两种消息
-- 在消息的处理函数中，仅仅打印了一些信息，便于实时观察“通过SPI接口外挂4G模组(Air780EHM/Air780EHV/Air780EGH/Air780EPM)的4G网卡”的连接状态
-- 也可以根据自己的项目需求，在消息处理函数中增加自己的业务逻辑控制，例如可以在连网状态发生改变时更新网络图标
sys.subscribe("IP_READY", ip_ready_func)
sys.subscribe("IP_LOSE", ip_lose_func)


-- 配置SPI外接的4G单网卡，exnetif.set_priority_order使用的网卡编号为socket.LWIP_GP_GW
-- 本demo使用Air8101核心板+Air780EHM/Air780EHV/Air780EGH/Air780EPM核心板/开发板测试，Air8101核心板上的硬件配置为：
-- 工作在SPI主模式
-- 使用spi0，片选引脚使用GPIO15，rdy引脚使用gpio48
-- 如果使用的硬件和以上描述的环境不同，根据自己的硬件配置修改以下参数
exnetif.set_priority_order({
    { -- 开启4G虚拟网卡
        airlink_4G = {
            auto_socket_switch = false, -- 切换网卡时是否断开之前网卡的所有socket连接并用新的网卡重新建立连接
            airlink_type = airlink.MODE_SPI_MASTER, -- airlink工作模式
            airlink_spi_id = 0, -- airlink使用的SPI接口ID,选填参数
            airlink_cs_pin = 15,-- airlink使用的片选引脚gpio号,选填参数
            airlink_rdy_pin = 48-- airlink使用的rdy引脚gpio号,选填参数
        }
    }
})
