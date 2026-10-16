--[[
@module  netdrv_multiple
@summary 多网卡（通过SPI外挂CH390H芯片的以太网卡、AirLink 4G网卡、AirLink WiFi网卡）驱动模块 
@version 1.0
@date    2025.07.24
@author  朱天华
@usage
本文件为多网卡驱动模块 ，核心业务逻辑为：
1、调用exnetif.set_priority_order配置多网卡的控制参数以及优先级；
   exnetif内部自动完成WiFi硬件初始化；

注意：airlink_4G和airlink_wifi都使用UART3，只能二选一开启。

直接使用Air1601开发板硬件测试即可；

本文件没有对外接口，直接在其他功能模块中require "netdrv_multiple"就可以加载运行；
]]


local exnetif = require "exnetif"

-- WiFi STA状态事件回调
local function wifi_sta_func(evt, data)
    -- evt 可能的值有: "CONNECTED", "DISCONNECTED"
    -- 当evt=CONNECTED, data是连接的AP的ssid, 字符串类型
    -- 当evt=DISCONNECTED, data断开的原因, 整数类型
    log.info("收到STA事件", evt, data)
end
sys.subscribe("WLAN_STA_INC", wifi_sta_func)

-- 网卡状态变化通知回调函数
-- 当exnetif中检测到网卡切换或者所有网卡都断网时，会触发调用此回调函数
-- 当网卡切换切换时：
--     net_type：string类型，表示当前使用的网卡字符串
--     adapter：number类型，表示当前使用的网卡id
-- 当所有网卡断网时：
--     net_type：为nil
--     adapter：number类型，为-1
local function netdrv_multiple_notify_cbfunc(net_type,adapter)
    -- 在位置1和2设置自定义的DNS服务器ip地址：
    -- "223.5.5.5"，这个DNS服务器IP地址是阿里云提供的DNS服务器IP地址；
    -- "114.114.114.114"，这个DNS服务器IP地址是国内通用的DNS服务器IP地址；
    -- 可以加上以下两行代码，在自动获取的DNS服务器工作不稳定的情况下，这两个新增的DNS服务器会使DNS服务更加稳定可靠；
    -- 如果使用专网卡，不要使用这两行代码；
    -- 如果使用国外的网络，不要使用这两行代码；
    socket.setDNS(adapter, 1, "223.5.5.5")
    socket.setDNS(adapter, 2, "114.114.114.114")
    
    if type(net_type)=="string" then
        log.info("netdrv_multiple_notify_cbfunc", "use new adapter", net_type, adapter)
    elseif type(net_type)=="nil" then
        log.warn("netdrv_multiple_notify_cbfunc", "no available adapter", net_type, adapter)
    else
        log.warn("netdrv_multiple_notify_cbfunc", "unknown status", net_type, adapter)
    end
end

local function netdrv_multiple_task_func()
    --设置网卡优先级
    -- exnetif.set_priority_order内部会自动完成：
    --   - ETHERNET：SPI以太网初始化
    --   - airlink_wifi：airlink_wifi_hardware_init（GPIO12/22/23）→ uart.setup → airlink → wlan.connect
    --   - airlink_4G：uart.setup → airlink → 4G拨号
    exnetif.set_priority_order(
        {
            -- "通过SPI外挂CH390H芯片"的以太网卡，使用Air1601开发板验证
            {
                ETHERNET = {
                    -- VBAT给CH390H供电使能
                    -- 设置的多个"已经IP READY，但是还没有ping通"网卡，循环执行ping动作的间隔（单位毫秒，可选）
                    -- 如果没有传入此参数，exnetif会使用默认值10秒
                    pwrpin = nil,
                    ping_time = 3000,

                    -- 连通性检测ip(选填参数)；
                    -- 如果没有传入ip地址，exnetif中会默认使用httpdns能否成功获取baidu.com的ip作为是否连通的判断条件；
                    -- 如果传入，一定要传入可靠的并且可以ping通的ip地址；
                    -- ping_ip = "填入可靠的并且可以ping通的ip地址",     
                    
                    -- 网卡芯片型号(选填参数)，仅spi方式外挂以太网时需要填写。
                    tp = netdrv.CH390, 
                    opts = {spi=1, cs=14, irq=51}
                }
            },

            -- AirLink WiFi网卡（Air1601 WHALE方案）
            -- 注意：airlink_wifi和airlink_4G都使用UART3，二者只能开启一个
            {
                airlink_wifi = {
                    auto_socket_switch = false,     -- 切换网卡时是否断开之前网卡的所有socket连接并用新的网卡重新建立连接
                    airlink_type = airlink.MODE_UART, -- airlink工作模式：UART模式
                    airlink_uart_id = 3,            -- airlink使用的UART接口ID
                    airlink_uart_baud = 2000000,    -- airlink使用的UART波特率，默认2000000
                    ssid = "116",                   -- WiFi名称
                    password = "hezhou666",      -- WiFi密码
                }
            },

            -- AirLink 4G网卡（Air1601外挂Air780EPM）
            -- 注意：airlink_4G和airlink_wifi都使用UART3，二者只能开启一个
            -- {
            --     airlink_4G = {
            --         auto_socket_switch = false,     -- 切换网卡时是否断开之前网卡的所有socket连接并用新的网卡重新建立连接
            --         airlink_type = airlink.MODE_UART, -- airlink工作模式：UART模式
            --         airlink_uart_id = 3,            -- airlink使用的UART接口ID
            --         airlink_uart_baud = 2000000,    -- airlink使用的UART波特率，默认2000000
            --         airlink_adapter = socket.LWIP_GP_GW -- Air1601使用socket.LWIP_GP_GW网卡标识
            --     }
            -- }
        }
    )    
end

-- 设置网卡状态变化通知回调函数netdrv_multiple_notify_cbfunc
exnetif.notify_status(netdrv_multiple_notify_cbfunc)

-- 如果存在udp网络应用，并且udp网络应用中，根据应用层的心跳能够判断出来udp数据通信出现了异常；
-- 可以在判断出现异常的位置，调用一次exnetif.check_network_status()接口，强制对当前正式使用的网卡进行一次连通性检测；
-- 如果存在tcp网络应用，不需要用户调用exnetif.check_network_status()接口去控制，exnetif会在tcp网络应用通信异常时自动对当前使用的网卡进行连通性检测。


-- 启动一个task，task的处理函数为netdrv_multiple_task_func
-- 在处理函数中调用exnetif.set_priority_order设置网卡优先级
-- 因为exnetif.set_priority_order要求必须在task中被调用，所以此处启动一个task
sys.taskInit(netdrv_multiple_task_func)
