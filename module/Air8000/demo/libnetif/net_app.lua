--[[
@module  net_app
@summary net_app 网络管理模块
@version 1.0
@date    2025.07.14
@author  wjq
@usage
本文件为网络管理模块，核心业务逻辑为：
1、初始化网络优先级功能，以太网->WIFI
可以根据优先级自动切换网络
2、设置多网融合功能，以太网给wifi_ap提供网络
本文件没有对外接口，直接在main.lua中require "net_app"就可以加载运行；
]]
libnetif = require "libnetif"
sys.taskInit(function()
    sys.wait(5000)
    --设置网络优先级
    libnetif.set_priority_order({
        {
            ETHERNET = {
                pwrpin = 140,             -- 供电使能引脚(number)
                ping_time = 3000,         -- 填写ping_ip且未ping通时的检测间隔(ms, 可选，默认为10秒)
                ping_ip = "112.125.89.8", -- 连通性检测IP(选填参数),默认使用httpdns获取baidu.com的ip作为判断条件
                tp = netdrv.CH390,        -- 网卡芯片型号(选填参数)，仅spi方式外挂以太网时需要填写。
                opts = { spi = 1, cs = 12 }
            }
        },
        {
            WIFI = {
                ssid = "test",           --wifi名称
                password = "HZ88888888", --wifi密码
                -- ping_ip = "112.125.89.8"     -- 连通性检测IP(选填参数),默认使用httpdns获取baidu.com的ip作为判断条件
            }
        },
        {              -- 最低优先级网络
            LWIP_GP = true -- 启用4G网络
        }
    })
    sys.wait(5000)
    --设置多网融合功能
    -- libnetif.setproxy(socket.LWIP_ETH, socket.LWIP_STA, "test", "HZ88888888", 140 ,{tp = netdrv.CH390, opts = { spi = 1, cs = 12}})
end)
