
local function ip_ready_func()
    log.info("wlan_connect.ip_ready_func", "IP_READY")
end

local function ip_lose_func()
    log.info("wlan_connect.ip_lose_func", "IP_LOSE")
end

-- local function wlan_ip_status_task_func()
--     log.info("wlan_ip_status_task_func wait IP_READY")
--     sys.waitUntil("IP_READY")
--     log.info("wlan_ip_status_task_func receive IP_READY")

--     while true do
--         sys.wait(10000)
--     end
-- end

-- sys.taskInit(wlan_ip_status_task_func)

sys.subscribe("IP_READY", ip_ready_func)
sys.subscribe("IP_LOSE", ip_lose_func)

-- local function wlan_init_task_func()
--     sys.wait(5000)
--     log.info("wlan_init_task_func")
--     sys.wait(5000)
--     if wlan and wlan.connect then
--         wlan.init()
--         wlan.connect("茶室-降功耗,找合宙!", "Air123456", 1)
--         --等待WIFI联网结果，WIFI联网成功后，内核固件会产生一个"IP_READY"消息
--         local result, data = sys.waitUntil("IP_READY")
--         log.info("wlan", "IP_READY", result, data)
--     end
-- end

-- sys.taskInit(wlan_init_task_func)

wlan.init()
wlan.connect("茶室-降功耗,找合宙!", "Air123456", 1)

--WIFI联网成功（做为STATION成功连接AP，并且获取到了IP地址）后，内核固件会产生一个"IP_READY"消息
--各个功能模块可以订阅"IP_READY"消息实时处理WIFI联网成功的事件
--也可以在任何时刻调用wlan.ready()来获取WIFI网络是否连接成功

--WIFI断网后，内核固件会产生一个"IP_LOSE"消息
--各个功能模块可以订阅"IP_LOSE"消息实时处理WIFI断网的事件
--也可以在任何时刻调用wlan.ready()来获取WIFI网络是否连接成功