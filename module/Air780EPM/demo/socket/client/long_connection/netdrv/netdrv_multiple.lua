--[[
@module  netdrv_multiple
@summary 多网卡（4G网卡、WIFI STA网卡、通过SPI外挂CH390H芯片的以太网卡）驱动模块
@version 1.0
@date    2025.07.31
@author  孟伟
@usage
本文件为多网卡驱动模块 ，核心业务逻辑为：
1、调用libnetif.set_priority_order配置多网卡的控制参数以及优先级；

直接使用Air780EPM 1.3版本开发板测试即可；

本文件没有对外接口，直接在其他功能模块中require "netdrv_multiple"就可以加载运行；
]]


local e_netif = require "e_netif"

-- 网卡状态变化通知回调函数
-- 当libnetif中检测到网卡切换或者所有网卡都断网时，会触发调用此回调函数
-- 当网卡切换切换时：
--     net_type：string类型，表示当前使用的网卡字符串
--     adapter：number类型，表示当前使用的网卡id
-- 当所有网卡断网时：
--     net_type：为nil
--     adapter：number类型，为-1
local function netdrv_multiple_notify_cbfunc(net_type,adapter)
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
    e_netif.set_priority_order(
        {
            -- “通过SPI外挂CH390H芯片”的以太网卡，使用Air780EPM 1.3版本开发板验证
            {
                ETHERNET = {
                    -- 供电使能GPIO
                    pwrpin = 20,
                    -- 设置的多个“已经IP READY，但是还没有ping通”网卡，循环执行ping动作的间隔（单位毫秒，可选）
                    -- 如果没有传入此参数，libnetif会使用默认值10秒
                    ping_time = 3000,

                    -- 连通性检测ip(选填参数)；
                    -- 如果没有传入ip地址，libnetif中会默认使用httpdns能否成功获取baidu.com的ip作为是否连通的判断条件；
                    -- 如果传入，一定要传入可靠的并且可以ping通的ip地址；
                    -- ping_ip = "填入可靠的并且可以ping通的ip地址",

                    -- 网卡芯片型号(选填参数)，仅spi方式外挂以太网时需要填写。
                    tp = netdrv.CH390,
                    opts = { spi = 0, cs = 8 }
                }
            },
            -- 4G网卡
            {
                LWIP_GP = true
            },
        }
    )
end

-- 设置网卡状态变化通知回调函数netdrv_multiple_notify_cbfunc
e_netif.notify_status(netdrv_multiple_notify_cbfunc)

-- 如果存在udp网络应用，并且udp网络应用中，根据应用层的心跳能够判断出来udp数据通信出现了异常；
-- 可以在判断出现异常的位置，调用一次libnetif.check_network_status()接口，强制对当前正式使用的网卡进行一次连通性检测；
-- 如果存在tcp网络应用，不需要用户调用libnetif.check_network_status()接口去控制，libnetif会在tcp网络应用通信异常时自动对当前使用的网卡进行连通性检测。


-- 启动一个task，task的处理函数为netdrv_multiple_task_func
-- 在处理函数中调用libnetif.set_priority_order设置网卡优先级
-- 因为libnetif.set_priority_order要求必须在task中被调用，所以此处启动一个task
sys.taskInit(netdrv_multiple_task_func)
