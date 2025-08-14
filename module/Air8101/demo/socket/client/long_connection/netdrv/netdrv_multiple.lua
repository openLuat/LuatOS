--[[
@module  netdrv_multiple
@summary 多网卡（WIFI STA网卡、通过MAC层的rmii接口外挂PHY芯片（LAN8720Ai）的以太网卡、通过SPI外挂CH390H芯片的以太网卡、通过SPI外挂4G模组的4G网卡）驱动模块 
@version 1.0
@date    2025.07.24
@author  朱天华
@usage
本文件为多网卡驱动模块 ，核心业务逻辑为：
1、调用exnetif.set_priority_order配置多网卡的控制参数以及优先级；


通过MAC层的rmii接口外挂PHY芯片（LAN8720Ai）的以太网卡：
Air8101核心板和AirPHY_1000配件板的硬件接线方式为:
Air8101核心板通过TYPE-C USB口供电（核心板背面的功耗测试开关拨到OFF一端）；
如果测试发现软件重启，并且日志中出现  poweron reason 0，表示供电不足，此时再通过直流稳压电源对核心板的VIN管脚进行5V供电；
| Air8101核心板 | AirPHY_1000配件板  |
| ------------ | ------------------ |
|    59/3V3    |         3.3v       |
|     gnd      |         gnd        |
|     5/D2     |         RX1        |
|    72/D1     |         RX0        |
|    71/D3     |         CRS        |
|     4/D0     |         MDIO       |
|     6/D4     |         TX0        |
|    74/PCK    |         MDC        |
|    70/D5     |         TX1        |
|     7/D6     |         TXEN       |
|     不接     |          NC        |
|    69/D7     |         CLK        |


通过SPI外挂CH390H芯片的以太网卡（此网卡和4G网卡硬件连接有冲突，如果使用以太网，可以优先使用rmii接口的以太网卡，如果必须使用spi以太网卡，注意更换以太网或者4G网卡使用的spi，不要冲突）：
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


通过SPI接口外挂4G模组(Air780EHM/Air780EHV/Air780EGH/Air780EPM)的4G网卡：
Air8101核心板和Air780EHM/Air780EHV/Air780EGH/Air780EPM核心板或者开发板的硬件接线方式，参考netdrv_4g.lua的文件头注释；



本文件没有对外接口，直接在其他功能模块中require "netdrv_multiple"就可以加载运行；
]]


local exnetif = require "exnetif"

-- 网卡状态变化通知回调函数
-- 当exnetif中检测到网卡切换或者所有网卡都断网时，会触发调用此回调函数
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
    exnetif.set_priority_order(
        {
            -- “通过MAC层的rmii接口外挂PHY芯片（LAN8720Ai）”的以太网卡，可以使用Air8101核心板+AirPHY_1000配件板验证
            {
                ETHERNET = {
                    -- 供电使能GPIO，此demo使用的59脚3V3供电，受GPIO13控制
                    pwrpin = 13,
                    -- 设置的多个“已经IP READY，但是还没有ping通”网卡，循环执行ping动作的间隔（单位毫秒，可选）
                    -- 如果没有传入此参数，exnetif会使用默认值10秒
                    ping_time = 3000,

                    -- 连通性检测ip(选填参数)；
                    -- 如果没有传入ip地址，exnetif中会默认使用httpdns能否成功获取baidu.com的ip作为是否连通的判断条件；
                    -- 如果传入，一定要传入可靠的并且可以ping通的ip地址；
                    -- ping_ip = "填入可靠的并且可以ping通的ip地址",                   
                }
            },

            -- “通过SPI外挂CH390H芯片”的以太网卡，可以使用Air8101核心板+AirETH_1000配件板验证
            -- {
            --     ETHUSER1 = {
            --         -- 供电使能GPIO，此demo使用的59脚3V3供电，受GPIO13控制
            --         pwrpin = 13,
            --         -- 设置的多个“已经IP READY，但是还没有ping通”网卡，循环执行ping动作的间隔（单位毫秒，可选）
            --         -- 如果没有传入此参数，exnetif会使用默认值10秒
            --         ping_time = 3000, 

            --         -- 连通性检测ip(选填参数)；
            --         -- 如果没有传入ip地址，exnetif中会默认使用httpdns能否成功获取baidu.com的ip作为是否连通的判断条件；
            --         -- 如果传入，一定要传入可靠的并且可以ping通的ip地址；
            --         -- ping_ip = "填入可靠的并且可以ping通的ip地址",

            --         -- 网卡芯片型号(选填参数)，仅spi方式外挂以太网时需要填写。
            --         tp = netdrv.CH390, 
            --         opts = {spi=0, cs=15}
            --     }
            -- },

            -- WIFI STA网卡
            {
                WIFI = {
                    -- 要连接的WIFI路由器名称
                    ssid = "茶室-降功耗,找合宙!",
                    -- 要连接的WIFI路由器密码
                    password = "Air123456", 

                    -- 连通性检测ip(选填参数)；
                    -- 如果没有传入ip地址，exnetif中会默认使用httpdns能否成功获取baidu.com的ip作为是否连通的判断条件；
                    -- 如果传入，一定要传入可靠的并且可以ping通的ip地址；
                    -- ping_ip = "填入可靠的并且可以ping通的ip地址",
                }
            }
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
