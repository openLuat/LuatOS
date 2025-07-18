
local function ip_ready_func()
    log.info("eth connect.ip_ready_func", "IP_READY")
end

local function ip_lose_func()
    log.info("eth connect.ip_lose_func", "IP_LOSE")
end


--此处订阅"IP_READY"和"IP_LOSE"两种消息
--在消息的处理函数中，仅仅打印了一些信息，便于实时观察以太网的连接状态
--也可以根据自己的项目需求，在消息处理函数中增加自己的业务逻辑控制，例如可以在连网状态发生改变时更新网络图标
sys.subscribe("IP_READY", ip_ready_func)
sys.subscribe("IP_LOSE", ip_lose_func)


--本demo测试使用的是核心板的VDD 3V3引脚对AirETH_1000配件板进行供电
--VDD 3V3引脚是Air8101内部的LDO输出引脚，最大输出电流300mA
--GPIO13在Air8101内部使能控制这个LDO的输出
--所以在此处GPIO13输出高电平打开这个LDO
gpio.setup(13, 1, gpio.PULLUP)


--这个task的核心业务逻辑是：初始化SPI，初始化以太网卡，并在以太网上开启动态主机配置协议
local function spi_eth_init_task_func()

    sys.wait(6000)
    -- 初始化SPI
    local result = spi.setup(
        0,--spi_id
        nil,
        0,--CPHA
        0,--CPOL
        8,--数据宽度
        25600000--,--频率
        -- spi.MSB,--高低位顺序    可选，默认高位在前
        -- spi.master,--主模式     可选，默认主
        -- spi.full--全双工       可选，默认全双工
    )
    log.info("main", "spi open status", result)
    if result ~= 0 then--返回值为0，表示打开成功
        log.info("main", "spi open error",result)
        return
    end

    --初始化以太网卡

    --以太网联网成功（成功连接路由器，并且获取到了IP地址）后，内核固件会产生一个"IP_READY"消息
    --各个功能模块可以订阅"IP_READY"消息实时处理以太网联网成功的事件
    --也可以在任何时刻调用socket.adapter(socket.LWIP_USER1)来获取以太网是否连接成功

    --以太网断网后，内核固件会产生一个"IP_LOSE"消息
    --各个功能模块可以订阅"IP_LOSE"消息实时处理以太网断网的事件
    --也可以在任何时刻调用socket.adapter(socket.LWIP_USER1)来获取以太网是否连接成功

    -- socket.LWIP_USER1 指定网络适配器编号
    -- netdrv.CH390外挂CH390
    -- SPI ID 0, 片选 GPIO15
    netdrv.setup(socket.LWIP_USER1, netdrv.CH390, {spi= 0,cs= 15})

    --在以太网上开启动态主机配置协议
    netdrv.dhcp(socket.LWIP_USER1, true)

end


--创建并且启动一个task
--task的主函数为spi_eth_init_task_func
sys.taskInit(spi_eth_init_task_func)
