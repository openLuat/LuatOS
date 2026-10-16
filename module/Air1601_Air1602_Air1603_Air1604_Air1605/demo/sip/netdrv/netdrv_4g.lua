--[[
@module  netdrv_4g
@summary Air160x V1.2 板载 Air780ER2 / UART3 4G单网卡驱动模块
@version 1.0
@date    2025.07.01
@author  朱天华
@usage
本文件为4G网卡驱动模块，核心业务逻辑为：
1、监听"IP_READY"和"IP_LOSE"，在日志中进行打印；

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



--此处订阅"IP_READY"和"IP_LOSE"两种消息
--在消息的处理函数中，仅仅打印了一些信息，便于实时观察4G网络的连接状态
--也可以根据自己的项目需求，在消息处理函数中增加自己的业务逻辑控制，例如可以在连网状态发生改变时更新网络图标
sys.subscribe("IP_READY", ip_ready_func)
sys.subscribe("IP_LOSE", ip_lose_func)

local function netdrv_4g_task_func()
    -- 复用同板 AirCAMERA_1032 的上电时序；GPIO65 低有效，复位后保持高。
    sys.wait(100)
    gpio.setup(42, 0) -- EN 低有效，保持使能。
    sys.wait(50)
    gpio.setup(65, 0) -- RST 拉低复位。
    sys.wait(100)
    gpio.set(65, 1) -- 释放复位，正常工作时保持高。
    log.info("netdrv_4g", "Air780ER2上电复位已释放")

    exnetif.set_priority_order({
        {
            airlink_4G = {
                auto_socket_switch = false,
                airlink_type = airlink.MODE_UART,
                airlink_uart_id = 3,
                airlink_uart_baud = 2000000,
                airlink_adapter = socket.LWIP_GP_GW,
            }
        }
    })
end

-- set_priority_order 必须在任务上下文调用；仅配置4G，不启用WiFi。
sys.taskInit(netdrv_4g_task_func)

