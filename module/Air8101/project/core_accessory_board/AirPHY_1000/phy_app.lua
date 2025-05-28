
local function ip_ready_func()
    log.info("phy connect.ip_ready_func", "IP_READY")
end

local function ip_lose_func()
    log.info("phy connect.ip_lose_func", "IP_LOSE")
end



--此处订阅"IP_READY"和"IP_LOSE"两种消息
--在消息的处理函数中，仅仅打印了一些信息，便于实时观察以太网的连接状态
--也可以根据自己的项目需求，在消息处理函数中增加自己的业务逻辑控制，例如可以在连网状态发生改变时更新网络图标
sys.subscribe("IP_READY", ip_ready_func)
sys.subscribe("IP_LOSE", ip_lose_func)




--本demo测试使用的是核心板的VDD 3V3引脚对AirPHY_1000配件板进行供电
--VDD 3V3引脚是Air8101内部的LDO输出引脚，最大输出电流300mA
--GPIO13在Air8101内部使能控制这个LDO的输出
--所以在此处GPIO13输出高电平打开这个LDO
gpio.setup(13, 1, gpio.PULLUP) 



--初始化以太网卡

--以太网联网成功（成功连接路由器，并且获取到了IP地址）后，内核固件会产生一个"IP_READY"消息
--各个功能模块可以订阅"IP_READY"消息实时处理以太网联网成功的事件
--也可以在任何时刻调用socket.adapter(socket.LWIP_ETH)来获取以太网是否连接成功

--以太网断网后，内核固件会产生一个"IP_LOSE"消息
--各个功能模块可以订阅"IP_LOSE"消息实时处理以太网断网的事件
--也可以在任何时刻调用socket.adapter(socket.LWIP_ETH)来获取以太网是否连接成功
netdrv.setup(socket.LWIP_ETH)

--在以太网上开启动态主机配置协议
netdrv.dhcp(socket.LWIP_ETH, true)

