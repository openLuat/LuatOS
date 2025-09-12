--[[
@module  lan
@summary lan 模组连接4G网络通过以太网口传输给其他设备
@version 1.0
@date    2025.09.12
@author  王城钧
@usage
本文件为lan网络模块，核心业务逻辑为：
1.设置模组连接4G网络通过以太网口传输给其他设备
本文件没有对外接口，直接在main.lua中require "lan"就可以加载运行；
]]

dhcps = require "dhcpsrv"
dnsproxy = require "dnsproxy"

-- 启动lan网络初始化
local function lan_init()
    sys.wait(500)   -- 非必须延时
    log.info("ch390", "打开LDO供电")
    gpio.setup(140, 1, gpio.PULLUP)     --打开ch390供电
    sys.wait(6000)
    local result = spi.setup(
        1,--spi_id
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
    if result ~= 0 then--返回值为0，表示打开成功
        log.info("main", "spi open error",result)
        return
    end

    -- 初始化指定netdrv设备,
    -- socket.LWIP_ETH 网络适配器编号
    -- netdrv.CH390外挂CH390
    -- SPI ID 1, 片选 GPIO12
    netdrv.setup(socket.LWIP_ETH, netdrv.CH390, {spi=1,cs=12})
    sys.wait(3000)
    local ipv4,mark, gw = netdrv.ipv4(socket.LWIP_ETH, "192.168.4.1", "255.255.255.0", "192.168.4.1")
    log.info("ipv4", ipv4,mark, gw)
    while netdrv.link(socket.LWIP_ETH) ~= true do
        -- sys.wait(100)   -- 等待以太网口联通
    end
    while netdrv.link(socket.LWIP_GP) ~= true do
        -- sys.wait(100)   -- 等待GP口联通
    end
    sys.wait(2000) --非必须延时
    dhcps.create({adapter=socket.LWIP_ETH})
    dnsproxy.setup(socket.LWIP_ETH, socket.LWIP_GP)
    netdrv.napt(socket.LWIP_GP)
    if iperf then
        log.info("启动iperf服务器端")
        iperf.server(socket.LWIP_ETH)
    end
end

-- 启动lan网络任务
local function lan_task()
    -- sys.waitUntil("IP_READY")
    while 1 do
        sys.wait(3000) -- 非必须延时, 此处为了方便观察日志
        -- log.info("http", http.request("GET", "http://httpbin.air32.cn/bytes/4096", nil, nil, {adapter=socket.LWIP_ETH}).wait())
        log.info("lua", rtos.meminfo())
        log.info("sys", rtos.meminfo("sys"))
        -- log.info("psram", rtos.meminfo("psram"))
    end
end

-- 启动lan网络初始化
sys.taskInit(lan_init)

-- 启动lan网络任务
sys.taskInit(lan_task)