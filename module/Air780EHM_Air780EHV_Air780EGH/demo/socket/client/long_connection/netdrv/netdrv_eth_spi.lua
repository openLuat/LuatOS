--[[
@module  netdrv_eth_spi
@summary “通过SPI外挂CH390H芯片的以太网卡”驱动模块
@version 1.0
@date    2025.07.31
@author  mw
@usage
本文件为“通过SPI外挂CH390H芯片的以太网卡”驱动模块 ，核心业务逻辑为：
1、打开AirETH_1000配件板供电开关；
2、初始化spi0，初始化以太网卡，并且在以太网卡上开启DHCP(动态主机配置协议)；
3、以太网卡的连接状态发生变化时，在日志中进行打印；

Air780EXX核心板和AirETH_1000配件板的硬件接线方式为:
Air780EXX核心板通过TYPE-C USB口供电（核心板背面的功耗测试开关拨到OFF一端）；
| Air780EXX核心板  |  AirETH_1000配件板 |
| --------------- | ----------------- |
| 3V3             | 3.3v              |
| gnd             | gnd               |
| 86/SPI0CLK      | SCK               |
| 83/SPI0CS       | CSS               |
| 84/SPI0MISO     | SDO               |
| 85/SPI0MOSI     | SDI               |
| 107/GPIO21      | INT               |


本文件没有对外接口，直接在其他功能模块中require "netdrv_eth_spi"就可以加载运行；
]]

local function ip_ready_func()
    log.info("netdrv_eth_spi.ip_ready_func", "IP_READY", socket.localIP(socket.LWIP_ETH))
    -- 下面这一行代码临时保留，是为了规避内核固件的一个bug，等内核固件修改bug后，demo中删掉这一行代码
    socket.dft(socket.LWIP_ETH)
end

local function ip_lose_func()
    log.warn("netdrv_eth_spi.ip_lose_func", "IP_LOSE")
end



--此处订阅"IP_READY"和"IP_LOSE"两种消息
--在消息的处理函数中，仅仅打印了一些信息，便于实时观察“通过SPI外挂CH390H芯片的以太网卡”的连接状态
--也可以根据自己的项目需求，在消息处理函数中增加自己的业务逻辑控制，例如可以在连网状态发生改变时更新网络图标
sys.subscribe("IP_READY", ip_ready_func)
sys.subscribe("IP_LOSE", ip_lose_func)


-- 设置默认网卡为socket.LWIP_ETH
socket.dft(socket.LWIP_ETH)

--本demo测试使用的是核心板的VDD 3V3引脚对AirETH_1000配件板进行供电
--3V3管脚是核心板LDO，3.3V输出，供测试用的，仅在使用DCDC供电时有输出,默认打开,无需控制


--这个task的核心业务逻辑是：初始化SPI，初始化以太网卡，并在以太网卡上开启动态主机配置协议
local function netdrv_eth_spi_task_func()
    sys.wait(500)
    -- 初始化SPI1
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
    log.info("main", "open",result)
    --返回值为0，表示打开成功
    if result ~= 0 then
        log.info("main", "spi open error",result)
        return
    end

    --以太网联网成功（成功连接路由器，并且获取到了IP地址）后，内核固件会产生一个"IP_READY"消息
    --各个功能模块可以订阅"IP_READY"消息实时处理以太网联网成功的事件
    --也可以在任何时刻调用socket.adapter(socket.LWIP_USER1)来获取以太网是否连接成功

    --以太网断网后，内核固件会产生一个"IP_LOSE"消息
    --各个功能模块可以订阅"IP_LOSE"消息实时处理以太网断网的事件
    --也可以在任何时刻调用socket.adapter(socket.LWIP_USER1)来获取以太网是否连接成功
    -- 初始化指定netdrv设备,
    -- socket.LWIP_ETH 网络适配器编号
    -- netdrv.CH390外挂CH390
    -- SPI ID 0, 片选 GPIO8
    netdrv.setup(socket.LWIP_ETH, netdrv.CH390, {spi=0,cs=8})
    netdrv.dhcp(socket.LWIP_ETH, true)

end

--创建并且启动一个task
--task的处理函数为netdrv_eth_spi_task_func
sys.taskInit(netdrv_eth_spi_task_func)
