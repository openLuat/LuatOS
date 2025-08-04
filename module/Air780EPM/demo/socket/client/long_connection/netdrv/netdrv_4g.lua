--[[
@module  netdrv_4g
@summary “4G网卡”驱动模块
@version 1.0
@date    2025.07.31
@author  孟伟
@usage
本文件为4G网卡驱动模块，核心业务逻辑为：
1、监听"IP_READY"和"IP_LOSE"，在日志中进行打印；

本文件没有对外接口，直接在其他功能模块中require "netdrv_4g"就可以加载运行；
]]

local function ip_ready_func()
    log.info("netdrv_4g.ip_ready_func", "IP_READY", socket.localIP(socket.LWIP_GP))
end

local function ip_lose_func()
    log.warn("netdrv_4g.ip_lose_func", "IP_LOSE")
end



--此处订阅"IP_READY"和"IP_LOSE"两种消息
--在消息的处理函数中，仅仅打印了一些信息，便于实时观察4G网络的连接状态
--也可以根据自己的项目需求，在消息处理函数中增加自己的业务逻辑控制，例如可以在连网状态发生改变时更新网络图标
sys.subscribe("IP_READY", ip_ready_func)
sys.subscribe("IP_LOSE", ip_lose_func)

-- 设置默认网卡为socket.LWIP_GP
-- 在Air780EPM上，内核固件运行起来之后，默认网卡就是socket.LWIP_GP
-- 在单4G网卡使用场景下，下面这一行代码加不加都没有影响，为了和其他网卡驱动模块的代码风格保持一致，所以加上了
socket.dft(socket.LWIP_GP)