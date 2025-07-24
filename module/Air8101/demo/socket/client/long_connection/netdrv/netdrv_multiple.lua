--[[
@module  netdrv_multiple
@summary 多网卡（WIFI STA网卡、通过MAC层的rmii接口外挂PHY芯片（LAN8720Ai）的以太网卡、通过SPI外挂CH390H芯片的以太网卡、通过SPI外挂4G模组的4G网卡）驱动模块 
@version 1.0
@date    2025.07.24
@author  朱天华
@usage
本文件为多网卡驱动模块 ，核心业务逻辑为：
1、调用libnetif.set_priority_order配置多网卡的控制参数以及优先级；


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


通过SPI外挂CH390H芯片的以太网卡：
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


本文件没有对外接口，直接在其他功能模块中require "netdrv_multiple"就可以加载运行；
]]


local libnetif = require "libnetif"

local function netdrv_multiple_task_func()
    --设置网络优先级
    libnetif.set_priority_order(
        {
            -- “通过MAC层的rmii接口外挂PHY芯片（LAN8720Ai）”的以太网卡，可以使用Air8101核心板+AirPHY_1000配件板验证
            {
                ETHERNET = {
                    -- 供电使能GPIO，此demo使用的59脚3V3供电，受GPIO13控制
                    pwrpin = 13,
                    -- 设置的多个“已经IP READY，但是还没有ping通”网卡，循环执行ping动作的间隔（单位毫秒，可选）
                    -- 如果没有传入此参数，libnetif会使用默认值10秒
                    ping_time = 3000,

                    -- 连通性检测ip(选填参数)；
                    -- 如果没有传入ip地址，libnetif中会默认使用httpdns能否成功获取baidu.com的ip作为是否连通的判断条件；
                    -- 如果传入，一定要传入可靠的并且可以ping通的ip地址；
                    -- ping_ip = "填入可靠的并且可以ping通的ip地址",                   
                }
            },

            -- “通过SPI外挂CH390H芯片”的以太网卡，可以使用Air8101核心板+AirETH_1000配件板验证
            {
                ETHUSER1 = {
                    -- 供电使能GPIO，此demo使用的59脚3V3供电，受GPIO13控制
                    pwrpin = 13,
                    -- 设置的多个“已经IP READY，但是还没有ping通”网卡，循环执行ping动作的间隔（单位毫秒，可选）
                    -- 如果没有传入此参数，libnetif会使用默认值10秒
                    ping_time = 3000, 

                    -- 连通性检测ip(选填参数)；
                    -- 如果没有传入ip地址，libnetif中会默认使用httpdns能否成功获取baidu.com的ip作为是否连通的判断条件；
                    -- 如果传入，一定要传入可靠的并且可以ping通的ip地址；
                    -- ping_ip = "填入可靠的并且可以ping通的ip地址",

                    -- 网卡芯片型号(选填参数)，仅spi方式外挂以太网时需要填写。
                    tp = netdrv.CH390, 
                    opts = {spi=0, cs=15}
                }
            },

            -- WIFI STA网卡
            {
                WIFI = {
                    -- 要连接的WIFI路由器名称
                    ssid = "茶室-降功耗,找合宙!",
                    -- 要连接的WIFI路由器密码
                    password = "Air123456", 

                    -- 连通性检测ip(选填参数)；
                    -- 如果没有传入ip地址，libnetif中会默认使用httpdns能否成功获取baidu.com的ip作为是否连通的判断条件；
                    -- 如果传入，一定要传入可靠的并且可以ping通的ip地址；
                    -- ping_ip = "填入可靠的并且可以ping通的ip地址",
                }
            }
        }
    )
end


sys.taskInit(netdrv_multiple_task_func)
