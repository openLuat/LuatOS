--[[
@module  netdrv_wifi
@summary “WIFI STA网卡”驱动模块 
@version 1.0
@date    2025.07.01
@author  朱天华
@usage
本文件为WIFI STA网卡驱动模块，核心业务逻辑为：
1、初始化WIFI网络；
2、连接WIFI路由器；
3、和WIFI路由器之间的连接状态发生变化时，在日志中进行打印；

本文件没有对外接口，直接在其他功能模块中require "netdrv_wifi"就可以加载运行；
]]

local exnetif = require "exnetif"

local function ip_ready_func(ip, adapter)
    if adapter == socket.LWIP_STA then
        log.info("netdrv_wifi.ip_ready_func", "IP_READY", socket.localIP(socket.LWIP_STA))
    end
end

local function ip_lose_func(adapter)    
    if adapter == socket.LWIP_STA then
        log.warn("netdrv_wifi.ip_lose_func", "IP_LOSE")
    end
end


--WIFI联网成功（做为STATION成功连接AP，并且获取到了IP地址）后，内核固件会产生一个"IP_READY"消息
--各个功能模块可以订阅"IP_READY"消息实时处理WIFI联网成功的事件
--也可以在任何时刻调用socket.adapter(socket.LWIP_STA)来获取WIFI网络是否连接成功

--WIFI断网后，内核固件会产生一个"IP_LOSE"消息
--各个功能模块可以订阅"IP_LOSE"消息实时处理WIFI断网的事件
--也可以在任何时刻调用socket.adapter(socket.LWIP_STA)来获取WIFI网络是否连接成功

--此处订阅"IP_READY"和"IP_LOSE"两种消息
--在消息的处理函数中，仅仅打印了一些信息，便于实时观察WIFI的连接状态
--也可以根据自己的项目需求，在消息处理函数中增加自己的业务逻辑控制，例如可以在连网状态发生改变时更新网络图标
sys.subscribe("IP_READY", ip_ready_func)
sys.subscribe("IP_LOSE", ip_lose_func)


-- 配置WiFi设备模式的单网卡，exnetif.set_priority_order使用的网卡编号为socket.LWIP_STA
-- ssid为要连接的WiFi路由器名称；
-- password为要连接的WiFi路由器密码；
-- 注意：仅支持2.4G的WiFi，不支持5G的WiFi；
-- 实际测试时，根据自己要连接的WiFi热点信息修改以下参数
exnetif.set_priority_order({
    {
        WIFI = {
            ssid = "茶室-降功耗,找合宙!", 
            password = "Air123456"
        }
    }
})

