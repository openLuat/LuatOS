--[[
@module  netdrv_pc
@summary “pc模拟器网卡”驱动模块 
@version 1.0
@date    2025.07.01
@author  朱天华
@usage
本文件为pc模拟器网卡驱动模块，核心业务逻辑为：
1、监听"IP_READY"和"IP_LOSE"，在日志中进行打印；

本文件没有对外接口，直接在其他功能模块中require "netdrv_pc"就可以加载运行；
]]

local function ip_ready_func(ip, adapter)    
    if adapter == socket.ETH0 then
        log.info("netdrv_pc.ip_ready_func", "IP_READY", socket.localIP(socket.ETH0))
    end
end

local function ip_lose_func(adapter)    
    if adapter == socket.ETH0 then
        log.warn("netdrv_pc.ip_lose_func", "IP_LOSE")
    end
end



--此处订阅"IP_READY"和"IP_LOSE"两种消息
--在消息的处理函数中，仅仅打印了一些信息，便于实时观察pc模拟器网络的连接状态
--也可以根据自己的项目需求，在消息处理函数中增加自己的业务逻辑控制，例如可以在连网状态发生改变时更新网络图标
sys.subscribe("IP_READY", ip_ready_func)
sys.subscribe("IP_LOSE", ip_lose_func)

-- 设置默认网卡为socket.ETH0
-- pc模拟器上的默认网卡仍然需要使用接口(socket.ETH0)来设置，因为exnetif扩展库当前还不支持模拟器
socket.dft(socket.ETH0)
