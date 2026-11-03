--[[
@module  netdrv_eth_spi
@summary “通过SPI外挂CH390H芯片的以太网卡”驱动模块
@version 1.0
@date    2025.07.24
@author  马梦阳
@usage
本文件为“通过SPI外挂CH390H芯片的以太网卡”驱动模块，核心业务逻辑为：
1、打开CH390H芯片供电开关；
2、初始化spi0，初始化以太网卡，并且在以太网卡上开启DHCP(动态主机配置协议)；
3、以太网卡的连接状态发生变化时，在日志中进行打印；

默认接线参数：GPIO20 供电使能、spi0、CS=GPIO8、INT=GPIO22。
若你的板子没把 INT 接到 GPIO22，把下面 opts 里的 irq 去掉即可
(去掉后退化为轮询模式，不影响功能)。

本文件没有对外接口，直接在其他功能模块中require "netdrv_eth_spi"就可以加载运行；
]]

local exnetif = require "exnetif"

local function ip_ready_func(ip, adapter)
    if adapter == socket.LWIP_ETH then
        -- 在位置1和2设置自定义的DNS服务器ip地址：
        -- "223.5.5.5"，这个DNS服务器IP地址是阿里云提供的DNS服务器IP地址；
        -- "114.114.114.114"，这个DNS服务器IP地址是国内通用的DNS服务器IP地址；
        -- 这里默认加入两个自定义 DNS（阿里云 / 国内通用），提高 DNS 稳定性；
        -- 如果使用内网/专网环境，请把下面两行注释掉；
        socket.setDNS(adapter, 1, "223.5.5.5")
        socket.setDNS(adapter, 2, "114.114.114.114")

        log.info("netdrv_eth_spi.ip_ready_func", "IP_READY", socket.localIP(socket.LWIP_ETH))
    end
end

local function ip_lose_func(adapter)
    if adapter == socket.LWIP_ETH then
        log.warn("netdrv_eth_spi.ip_lose_func", "IP_LOSE")
    end
end


-- 以太网联网成功（成功连接路由器，并且获取到了IP地址）后，内核固件会产生一个"IP_READY"消息
-- 各个功能模块可以订阅"IP_READY"消息实时处理以太网联网成功的事件
-- 也可以在任何时刻调用socket.adapter(socket.LWIP_ETH)来获取以太网是否连接成功

-- 以太网断网后，内核固件会产生一个"IP_LOSE"消息
-- 各个功能模块可以订阅"IP_LOSE"消息实时处理以太网断网的事件
-- 也可以在任何时刻调用socket.adapter(socket.LWIP_ETH)来获取以太网是否连接成功

--此处订阅"IP_READY"和"IP_LOSE"两种消息
--在消息的处理函数中，仅仅打印了一些信息，便于实时观察“通过SPI外挂CH390H芯片的以太网卡”的连接状态
--也可以根据自己的项目需求，在消息处理函数中增加自己的业务逻辑控制，例如可以在连网状态发生改变时更新网络图标
sys.subscribe("IP_READY", ip_ready_func)
sys.subscribe("IP_LOSE", ip_lose_func)


local function netdrv_eth_spi_task_func()
-- 配置SPI外接以太网芯片CH390H的单网卡，exnetif.set_priority_order使用的网卡编号为socket.LWIP_ETH
-- 开发板上的硬件配置为：
-- GPIO20为CH390H以太网芯片的供电使能控制引脚
-- 使用spi0，片选引脚使用GPIO8，中断引脚使用GPIO22
-- 如果使用的硬件和以上描述的环境不同，根据自己的硬件配置修改以下参数
    exnetif.set_priority_order({
        {
            ETHERNET = {
                pwrpin = 20,
                tp = netdrv.CH390,
                opts = {spi = 0, cs = 8, irq = 22}
            }
        }
    })
end

-- 启动一个task，task的处理函数为netdrv_eth_spi_task_func
-- 在处理函数中调用exnetif.set_priority_order设置网卡优先级
-- 因为exnetif.set_priority_order要求必须在task中被调用，所以此处启动一个task
sys.taskInit(netdrv_eth_spi_task_func)
