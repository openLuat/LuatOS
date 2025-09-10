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

local function ip_ready_func()
    log.info("netdrv_wifi.ip_ready_func", "IP_READY", json.encode(wlan.getInfo()))
end

local function ip_lose_func()
    log.warn("netdrv_wifi.ip_lose_func", "IP_LOSE")
end



--此处订阅"IP_READY"和"IP_LOSE"两种消息
--在消息的处理函数中，仅仅打印了一些信息，便于实时观察WIFI的连接状态
--也可以根据自己的项目需求，在消息处理函数中增加自己的业务逻辑控制，例如可以在连网状态发生改变时更新网络图标
sys.subscribe("IP_READY", ip_ready_func)
sys.subscribe("IP_LOSE", ip_lose_func)


-- 设置默认网卡为socket.LWIP_STA
socket.dft(socket.LWIP_STA)


wlan.init()
--连接WIFI热点，连接结果会通过"IP_READY"或者"IP_LOSE"消息通知
--Air8000仅支持2.4G的WIFI，不支持5G的WIFI
--此处前两个参数表示WIFI热点名称以及密码，更换为自己测试时的真实参数即可
--第三个参数1表示WIFI连接异常时，内核固件会自动重连
wlan.connect("茶室-降功耗,找合宙!", "Air123456", 1)

--WIFI联网成功（做为STATION成功连接AP，并且获取到了IP地址）后，内核固件会产生一个"IP_READY"消息
--各个功能模块可以订阅"IP_READY"消息实时处理WIFI联网成功的事件
--也可以在任何时刻调用socket.adapter(socket.LWIP_STA)来获取WIFI网络是否连接成功

--WIFI断网后，内核固件会产生一个"IP_LOSE"消息
--各个功能模块可以订阅"IP_LOSE"消息实时处理WIFI断网的事件
--也可以在任何时刻调用socket.adapter(socket.LWIP_STA)来获取WIFI网络是否连接成功