--[[
@module  netdrv_eth_rmii
@summary “通过MAC层的rmii接口外挂PHY芯片（LAN8720Ai）的以太网卡”驱动模块 
@version 1.0
@date    2025.07.24
@author  马梦阳
@usage
本文件为“通过MAC层的rmii接口外挂PHY芯片（LAN8720Ai）的以太网卡”驱动模块 ，核心业务逻辑为：
1、打开PHY芯片供电开关；
2、初始化以太网卡，并且在以太网卡上开启DHCP(动态主机配置协议)；
3、以太网卡的连接状态发生变化时，在日志中进行打印；

Air8101核心板和AirPHY_1000配件板的硬件接线方式为:
Air8101核心板通过TYPE-C USB口供电（核心板背面的功耗测试开关拨到OFF一端）；
如果测试发现软件重启，并且日志中出现  poweron reason 0，表示供电不足，此时再通过直流稳压电源对核心板的VIN管脚进行5V供电；
| Air8101核心板 |  AirPHY_1000配件板  |
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

本文件没有对外接口，直接在其他功能模块中require "netdrv_eth_rmii"就可以加载运行；
]]

local exnetif = require "exnetif"

local function ip_ready_func(ip, adapter)
    if adapter == socket.LWIP_ETH then
        -- 在位置1和2设置自定义的DNS服务器ip地址：
        -- "223.5.5.5"，这个DNS服务器IP地址是阿里云提供的DNS服务器IP地址；
        -- "114.114.114.114"，这个DNS服务器IP地址是国内通用的DNS服务器IP地址；
        -- 可以加上以下两行代码，在自动获取的DNS服务器工作不稳定的情况下，这两个新增的DNS服务器会使DNS服务更加稳定可靠；
        -- 如果使用专网卡，不要使用这两行代码；
        -- 如果使用国外的网络，不要使用这两行代码；
        socket.setDNS(adapter, 1, "223.5.5.5")
        socket.setDNS(adapter, 2, "114.114.114.114")
        log.info("netdrv_eth_rmii.ip_ready_func", "IP_READY", socket.localIP(socket.LWIP_ETH))
    end
end

local function ip_lose_func(adapter)
    if adapter == socket.LWIP_ETH then
        log.warn("netdrv_eth_rmii.ip_lose_func", "IP_LOSE")
    end
end


-- 以太网联网成功（成功连接路由器，并且获取到了IP地址）后，内核固件会产生一个"IP_READY"消息
-- 各个功能模块可以订阅"IP_READY"消息实时处理以太网联网成功的事件
-- 也可以在任何时刻调用socket.adapter(socket.LWIP_ETH)来获取以太网是否连接成功

-- 以太网断网后，内核固件会产生一个"IP_LOSE"消息
-- 各个功能模块可以订阅"IP_LOSE"消息实时处理以太网断网的事件
-- 也可以在任何时刻调用socket.adapter(socket.LWIP_ETH)来获取以太网是否连接成功

-- 此处订阅"IP_READY"和"IP_LOSE"两种消息
-- 在消息的处理函数中，仅仅打印了一些信息，便于实时观察“通过MAC层的rmii接口外挂PHY芯片（LAN8720Ai）的以太网卡”的连接状态
-- 也可以根据自己的项目需求，在消息处理函数中增加自己的业务逻辑控制，例如可以在连网状态发生改变时更新网络图标
sys.subscribe("IP_READY", ip_ready_func)
sys.subscribe("IP_LOSE", ip_lose_func)


-- 配置“通过MAC层的rmii接口外挂PHY芯片（LAN8720Ai）”的以太网单网卡，exnetif.set_priority_order使用的网卡编号为socket.LWIP_ETH
-- 本demo使用Air8101核心板+AirPHY_1000配件板测试，核心板上的硬件配置为：
-- GPIO13为AirPHY_1000以太网芯片的供电使能控制引脚； VDD 3V3引脚是Air8101内部的LDO输出引脚，最大输出电流300mA；GPIO13在Air8101内部使能控制这个LDO的输出
-- 如果使用的硬件和以上描述的环境不同，根据自己的硬件配置修改以下参数
exnetif.set_priority_order({
    {
        ETHERNET = 
	{
	    -- 供电使能GPIO，此demo使用的59脚3V3供电，受GPIO13控制
	    pwrpin = 13
	}
    }
})
