
local function ip_ready_func()
    log.info("wlan_connect.ip_ready_func", "IP_READY")
end

local function ip_lose_func()
    log.info("wlan_connect.ip_lose_func", "IP_LOSE")
end



sys.subscribe("IP_READY", ip_ready_func)
sys.subscribe("IP_LOSE", ip_lose_func)



wlan.init()
wlan.connect("茶室-降功耗,找合宙!", "Air123456", 1)

--WIFI联网成功（做为STATION成功连接AP，并且获取到了IP地址）后，内核固件会产生一个"IP_READY"消息
--各个功能模块可以订阅"IP_READY"消息实时处理WIFI联网成功的事件
--也可以在任何时刻调用wlan.ready()来获取WIFI网络是否连接成功

--WIFI断网后，内核固件会产生一个"IP_LOSE"消息
--各个功能模块可以订阅"IP_LOSE"消息实时处理WIFI断网的事件
--也可以在任何时刻调用wlan.ready()来获取WIFI网络是否连接成功