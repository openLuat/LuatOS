--[[
@module  netif_app
@summary netif_app 网络管理模块 
@version 1.0
@date    2025.07.14
@author  wjq
@usage
本文件为网络管理模块，核心业务逻辑为：
1、初始化网络优先级功能，以太网->WIFI
可以根据优先级自动切换网络
2、设置多网融合功能，以太网给wifi_ap提供网络
本文件没有对外接口，直接在main.lua中require "netif_app"就可以加载运行；
]]
libnetif = require "libnetif"
sys.taskInit(function()
    sys.wait(5000)
    --设置网络优先级
    libnetif.set_priority_order({
    -- Air8101 支持 MAC接口 与 SPI接口 两种方式外挂以太网，程序中默认使用MAC接口，请根据实际情况选择。
        -- Air8101 MAC接口 外挂以太网的配置代码：
        {
            ETHERNET = {
                pwrpin = 13,                    -- 供电使能引脚(number)，根据接线引脚选择，Air8101核心板默认为gpio13
                ping_time = 3000,               -- 填写ping_ip且未ping通时的检测间隔(ms, 可选，默认为10秒)
                ping_ip = "112.125.89.8"        -- 连通性检测IP(选填参数),默认使用httpdns获取baidu.com的ip作为判断条件
            }
        },
        -- Air8101 SPI接口 外挂以太网的配置代码：
        -- {
        --     ETHUSER1 = {
        --         pwrpin = 13,                    -- 供电使能引脚(number)，根据接线引脚选择，Air8101核心板默认为gpio13
        --         ping_time = 3000,               -- 填写ping_ip且未ping通时的检测间隔(ms, 可选，默认为10秒)
        --         ping_ip = "112.125.89.8",       -- 连通性检测IP(选填参数),默认使用httpdns获取baidu.com的ip作为判断条件
        --         tp = netdrv.CH390,              -- 网卡芯片型号(选填参数)，仅spi方式外挂以太网时需要填写。
        --         opts = { spi = 0, cs = 15 }
        --     }
        -- },
        {
            WIFI = {
                ssid = "test",                  --wifi名称
                password = "HZ88888888",        --wifi密码
                -- ping_ip = "112.125.89.8"     -- 连通性检测IP(选填参数),默认使用httpdns获取baidu.com的ip作为判断条件
            }
        }
    })
    --设置多网融合功能
    -- libnetif.setproxy(socket.LWIP_AP, socket.LWIP_ETH, "test", "HZ88888888", 13)
end)
