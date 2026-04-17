--[[
@module  netdrv_4g
@summary "通过UART接口外挂4G模组(Air780EPM)的4G网卡"驱动模块
@version 1.0
@date    2026.4.15
@author  王城钧
@usage
本文件为 "通过UART接口外挂4G模组(Air780EPM)的4G网卡"驱动模块，核心业务逻辑为：
1、初始化和外部4G网卡的配置；
2、4G网卡的连接状态发生变化时，在日志中进行打印；
3、通过HTTP GET请求测试网络连接情况。


测试本功能模块时，Air780EPM需要烧录以下软件：
1、最新版本的内核固件(固件需支持airlink over uart功能)
2、脚本：https://gitee.com/openLuat/LuatOS/tree/master/module/Air1601/demo/Air1601_780EPM_airlink/Air780EPM

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
-- 也可以在任何时刻调用socket.adapter(socket.LWIP_GP_GW来获取4G是否联网成功

-- 4G断网后，内核固件会产生一个"IP_LOSE"消息
-- 各个功能模块可以订阅"IP_LOSE"消息实时处理4G断网的事件
-- 也可以在任何时刻调用socket.adapter(socket.LWIP_GP_GW)来获取4G是否联网成功

--此处订阅"IP_READY"和"IP_LOSE"两种消息
-- 在消息的处理函数中，仅仅打印了一些信息，便于实时观察4G的联网状态
-- 也可以根据自己的项目需求，在消息处理函数中增加自己的业务逻辑控制，例如可以在联网状态发生改变时更新网络图标
-- 此处订阅"IP_READY"和"IP_LOSE"两种消息
-- 在消息的处理函数中，仅仅打印了一些信息，便于实时观察"通过UART接口外挂4G模组(Air780EPM)的4G网卡"的连接状态
-- 也可以根据自己的项目需求，在消息处理函数中增加自己的业务逻辑控制，例如可以在连网状态发生改变时更新网络图标
sys.subscribe("IP_READY", ip_ready_func)
sys.subscribe("IP_LOSE", ip_lose_func)

local function netdrv_4g_task_func()
    -- 配置UART外接的4G单网卡
    -- 本demo使用Air1601核心板+Air780EPM核心板/开发板测试，Air1601核心板上的硬件配置为：
    -- 工作在UART模式
    -- 使用uart3，波特率2000000
    -- 如果使用的硬件和以上描述的环境不同，根据自己的硬件配置修改以下参数
    exnetif.set_priority_order({
        { -- 开启4G虚拟网卡
            airlink_4G = {
                auto_socket_switch = false, -- 切换网卡时是否断开之前网卡的所有socket连接并用新的网卡重新建立连接
                airlink_type = airlink.MODE_UART, -- airlink工作模式：UART模式
                airlink_uart_id = 3, -- airlink使用的UART接口ID
                airlink_uart_baud = 2000000, -- airlink使用的UART波特率，默认2000000
                airlink_adapter = socket.LWIP_GP_GW -- Air1601使用socket.LWIP_GP_GW网卡标识
            }
        }
    })
end

-- 启动一个task，task的处理函数为netdrv_4g_task_func
-- 在处理函数中调用exnetif.set_priority_order设置网卡优先级
-- 因为exnetif.set_priority_order要求必须在task中被调用，所以此处启动一个task
sys.taskInit(netdrv_4g_task_func)

