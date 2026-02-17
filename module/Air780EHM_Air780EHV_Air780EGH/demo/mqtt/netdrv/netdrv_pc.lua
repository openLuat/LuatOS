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
        -- 在位置1和2设置自定义的DNS服务器ip地址：
        -- "223.5.5.5"，这个DNS服务器IP地址是阿里云提供的DNS服务器IP地址；
        -- "114.114.114.114"，这个DNS服务器IP地址是国内通用的DNS服务器IP地址；
        -- 可以加上以下两行代码，在自动获取的DNS服务器工作不稳定的情况下，这两个新增的DNS服务器会使DNS服务更加稳定可靠；
        -- 如果使用专网卡，不要使用这两行代码；
        -- 如果使用国外的网络，不要使用这两行代码；
        socket.setDNS(adapter, 1, "223.5.5.5")
        socket.setDNS(adapter, 2, "114.114.114.114")

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



-- 下面这段代码是在PC模拟器上构造一个唯一的ID；不同PC上运行模拟器，这个ID要不一样
-- 因为mqtt client使用的是这个ID做为client id，如果不同PC上的id一样，模拟器在不同PC上同时运行时，mqtt client就会频繁出现被踢下线的问题
-- 目前模拟器上还没有合适的接口获取唯一ID，所以此处先简单的构造一个ID，需要手动保证ID唯一，在此处我简单使用了zhutianhua1做为ID
_G.mobile = {}
function mobile.imei()
    return "zhutianhua1"
    -- log.info("mcu.unique_id()", mcu.unique_id())
    -- return mcu.unique_id().."zhutianhua1"
end
