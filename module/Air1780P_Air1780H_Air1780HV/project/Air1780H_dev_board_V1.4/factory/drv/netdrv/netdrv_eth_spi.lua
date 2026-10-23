--[[
@module  netdrv_eth_spi
@summary 通过 SPI 外挂 CH390H 芯片的以太网卡驱动模块
@version 1.0
@date    2026.10.20
@usage
Air1780H 无 4G 通信能力，联网走开发板板载以太网口（CH390H，SPI0）。

核心业务逻辑：
1、打开 CH390H 芯片供电开关（GPIO20）；
2、初始化 SPI0，初始化以太网卡，并在以太网卡上开启 DHCP；
3、以太网连接状态变化时打印日志。

硬件（Air1780H V1.4 开发板）：
  GPIO20 为 CH390H 以太网芯片的供电使能控制引脚
  使用 SPI0，片选引脚使用 GPIO8

本文件没有对外接口，直接 require "netdrv_eth_spi" 即可加载运行。
]]

local exnetif = require "exnetif"

local function ip_ready_func(ip, adapter)
    if adapter == socket.LWIP_ETH then
        -- 位置1和2设置自定义 DNS：223.5.5.5（阿里云）、114.114.114.114（国内通用）
        -- 自动获取的 DNS 不稳定时，这两个可提升解析可靠性；专网卡/国外网络请去掉
        socket.setDNS(adapter, 1, "223.5.5.5")
        socket.setDNS(adapter, 2, "114.114.114.114")

        log.info("netdrv_eth_spi.ip_ready_func", "IP_READY", socket.localIP(socket.LWIP_ETH))
    end
end

local function ip_lose_func(adapter)
    if adapter == socket.LWIP_ETH then
        log.warn("netdrv_eth_spi.ip_lose_func", "IP_LOSE")
    end
end

-- 以太网联网成功（连上路由器并获取到 IP）后，内核产生 "IP_READY" 消息
-- 断网后产生 "IP_LOSE" 消息；也可随时用 socket.adapter(socket.LWIP_ETH) 查询状态
sys.subscribe("IP_READY", ip_ready_func)
sys.subscribe("IP_LOSE", ip_lose_func)

local function netdrv_eth_spi_task_func()
    -- 配置 SPI 外接以太网芯片 CH390H 的单网卡，网卡编号为 socket.LWIP_ETH
    exnetif.set_priority_order({
        {
            ETHERNET = {
                pwrpin = 20,
                tp = netdrv.CH390,
                opts = {spi = 0, cs = 8}
            }
        }
    })
end

-- exnetif.set_priority_order 必须在 task 中调用
sys.taskInit(netdrv_eth_spi_task_func)
