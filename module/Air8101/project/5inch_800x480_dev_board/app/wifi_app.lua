
-- 开发板上GPIO9控制网络指示灯
local WIFI_NET_LED_GPIO_ID = 9

local function ip_ready_func()
    log.info("wifi_app.ip_ready_func", "IP_READY", json.encode(wlan.getInfo()))
end

local function ip_lose_func()
    log.info("wifi_app.ip_lose_func", "IP_LOSE")
end


--WIFI网络指示灯显示任务函数
--连接上WIFI AP之后，指示灯常亮
--没有连接上WIFI AP时，指示灯亮1秒，灭1秒
local function wifi_net_led_task_func()
    local led_set_func = gpio.setup(WIFI_NET_LED_GPIO_ID, 0)
    while true do
        if socket.adapter(socket.LWIP_STA) then
            led_set_func(1)
            sys.wait(1000)
        else
            led_set_func(1)
            sys.wait(1000)
            led_set_func(0)
            sys.wait(1000)
        end
    end
end


-- sys.taskInit(wifi_net_led_task_func)




--此处订阅"IP_READY"和"IP_LOSE"两种消息
--在消息的处理函数中，仅仅打印了一些信息，便于实时观察WIFI的连接状态
--也可以根据自己的项目需求，在消息处理函数中增加自己的业务逻辑控制，例如可以在连网状态发生改变时更新网络图标
sys.subscribe("IP_READY", ip_ready_func)
sys.subscribe("IP_LOSE", ip_lose_func)


--初始化WIFI STATION
wlan.init()

--连接WIFI热点，连接结果会通过"IP_READY"或者"IP_LOSE"消息通知
--Air8101仅支持2.4G的WIFI，不支持5G的WIFI
--此处前两个参数表示WIFI热点名称以及密码，更换为自己测试时的真实参数即可
--第三个参数1表示WIFI连接异常时，内核固件会自动重连

--WIFI联网成功（做为STATION成功连接AP，并且获取到了IP地址）后，内核固件会产生一个"IP_READY"消息
--各个功能模块可以订阅"IP_READY"消息实时处理WIFI联网成功的事件
--也可以在任何时刻调用socket.adapter(socket.LWIP_STA)来获取WIFI网络是否连接成功

--WIFI断网后，内核固件会产生一个"IP_LOSE"消息
--各个功能模块可以订阅"IP_LOSE"消息实时处理WIFI断网的事件
--也可以在任何时刻调用socket.adapter(socket.LWIP_STA)来获取WIFI网络是否连接成功
wlan.connect("茶室-降功耗,找合宙!", "Air123456", 1)
-- wlan.connect("ChinaNet-2aWX", "zzij6udd", 1)


