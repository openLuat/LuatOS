--[[
@module  netdrv_multiple
@summary 多网卡（AirLink 4G网卡、通过SPI外挂CH390H芯片的以太网卡）驱动模块(Air1601版本)
@version 1.0
@date    2026.03.16
@author  朱天华
@usage
本文件为多网卡驱动模块，核心业务逻辑为：
1、调用exnetif.set_priority_order配置多网卡的控制参数以及优先级；

直接使用Air1601开发板硬件测试即可；

本文件没有对外接口，直接在其他功能模块中require "netdrv_multiple"就可以加载运行；
]]


local exnetif = require "exnetif"

-- 网卡状态变化通知回调函数
local function netdrv_multiple_notify_cbfunc(net_type, adapter)
    socket.setDNS(adapter, 1, "223.5.5.5")
    socket.setDNS(adapter, 2, "114.114.114.114")

    if type(net_type) == "string" then
        log.info("netdrv_multiple_notify_cbfunc", "use new adapter", net_type, adapter)
    elseif type(net_type) == "nil" then
        log.warn("netdrv_multiple_notify_cbfunc", "no available adapter", net_type, adapter)
    else
        log.warn("netdrv_multiple_notify_cbfunc", "unknown status", net_type, adapter)
    end
end


local function init_airlink_net()
    local uartid = 3
    uart.setup(uartid, 6000000, 8, 1)
    airlink.init()
    airlink.config(airlink.CONF_UART_ID, uartid)
    airlink.start(airlink.MODE_UART)
    netdrv.setup(socket.LWIP_USER0, netdrv.WHALE)
    netdrv.ipv4(socket.LWIP_USER0, "192.168.111.1", "255.255.255.0", "192.168.111.2")
    log.info("桥接网络设备", netdrv.link(socket.LWIP_USER0))
end

local function netdrv_multiple_task_func()
    init_airlink_net()

    exnetif.set_priority_order({
        {
            ETHERNET = {
                pwrpin = 140,
                tp = netdrv.CH390,
                opts = {spi = 1, cs = 12}
            }
        },
        {
            AIRLINK = {
                adapter = socket.LWIP_USER0
            }
        }
    }, netdrv_multiple_notify_cbfunc)
end

sys.taskInit(netdrv_multiple_task_func)
