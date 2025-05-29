--[[
本功能模块演示的内容为：
1. 软件配置 Air8000 的 WiFi AP 功能，然后烧录到 Air8000 模块中，最后使用 WiFi 设备连接对应热点，最终实现 4G 上网。
2. 软件配置 Air8000 的 Ethernet LAN功能，然后烧录到 Air8000 模块中，最后使用以太网设备通过网线与 Air8000 模块连接，最终实现 4G 上网。

功能演示使用 Air8000 整机开发板进行。
]]


-- 加载三个用到的库：dnsproxy 用于 DNS 代理服务，dhcpsrv 用于 DHCP 服务器服务，httpplus 用于 HTTP 请求相关的操作。
dnsproxy = require("dnsproxy")
dhcpsrv = require("dhcpsrv")
httpplus = require("httpplus")

-- 打开 CH390 供电
gpio.setup(140, 1, gpio.PULLUP)

-- 通过 BOOT 按键方便刷 Air8000S
-- 定义函数 PWR8000S，用于控制 Air8000S 的 LDO 供电引脚
function PWR8000S(val)
    gpio.set(23, val)
end

-- 加个防抖，中断后马上上报，但 1s 内只上报一次
gpio.debounce(0, 1000)

-- 配置 GPIO0 为中断，默认双向触发，且启用内部下拉
function resetAir8000S()
    sys.taskInit(function()
        log.info("复位Air8000S")
        PWR8000S(0)
        sys.wait(20)
        PWR8000S(1)
    end)
end
gpio.setup(0, resetAir8000S, gpio.PULLDOWN)

-- 配置 WiFi AP 功能，使得 WiFi 设备实现 4G上网
function test_ap()
    log.info("执行AP创建操作", airlink.ready() , "正常吗?")
    -- 设置 WiFi 热点的名称和密码
    wlan.createAP("uiot5678", "12345678")
    -- 设置 AP 的 IP 地址、子网掩码、网关地址
    netdrv.ipv4(socket.LWIP_AP, "192.168.4.1", "255.255.255.0", "0.0.0.0")
    -- 获取 WiFi AP 网络状态，连接后返回 true，否则返回 false，如果不存在就返回 nil。
    log.info("netdrv", "等待AP就绪")
    while netdrv.ready(socket.LWIP_AP) ~= true do
        log.info("netdrv", "等待AP就绪")
        sys.wait(10000)
    end
    -- 创建 DHCP 服务器，为连接到 WiFi AP 的设备分配 IP 地址。
    log.info("netdrv", "创建dhcp服务器, 供AP使用")
    dhcpsrv.create({adapter=socket.LWIP_AP})
    -- 获取 4G 网络状态，连接后返回 true，否则返回 false，如果不存在就返回 nil。
    log.info("netdrv", "等待4G就绪")
    while netdrv.ready(socket.LWIP_GP) ~= true do
        log.info("netdrv", "等待4G就绪")
        sys.wait(100)
    end
    -- 创建 DNS 代理服务，使得 WiFi AP 上的设备可以通过 4G 网络访问互联网。
    log.info("netdrv", "创建dns代理服务, 供AP使用")
    dnsproxy.setup(socket.LWIP_AP, socket.LWIP_GP)
end

-- 订阅系统事件"PING_RESULT"，当系统执行 PING 命令时，会触发此事件并将 PING 的结果打印出来。
function handlePingResult(id, time, dst)
    log.info("ping.result", id, time, dst);
end
sys.subscribe("PING_RESULT", handlePingResult)

-- WiFi AP 相关事件
-- 订阅系统事件"WLAN_AP_INC"，当有设备连接或断开连接到 WiFi AP 时，会触发此事件并将连接状态和对应 MAC 地址打印出来。
function handleWlanApInc(evt, data)
    -- evt 可能的值有: "CONNECTED", "DISCONNECTED"
    -- 当 evt=CONNECTED, data 是连接的 AP 的新 STA 的 MAC 地址
    -- 当 evt=DISCONNECTED, data 是断开与 AP 连接的 STA 的 MAC 地址
    log.info("收到AP事件", evt, data and data:toHex())
end
sys.subscribe("WLAN_AP_INC", handleWlanApInc)

--  每隔6秒打印一次 airlink 统计数据,调试用
-- sys.taskInit(function()
--     while 1 do
--         sys.wait(6000)
--         airlink.statistics()
--     end
-- end)

-- 配置 Ethernet LAN 功能，为以太网设备实现 4G 上网
function eth_lan()
    -- sys.wait(3000)
    -- 配置 SPI 参数，Air8000 使用 SPI 接口与以太网模块进行通信。
    local result = spi.setup(
        1,--spi id
        nil,
        0,--CPHA
        0,--CPOL
        8,--数据宽度
        51200000--,--波特率
    )
    log.info("main", "open spi",result)
    if result ~= 0 then--返回值为 0，表示打开成功
        log.info("main", "spi open error",result)
        return
    end
    -- 初始化以太网，Air8000 指定使用 CH390 芯片。
    log.info("netdrv", "初始化以太网")
    netdrv.setup(socket.LWIP_ETH, netdrv.CH390, {spi=1,cs=12,irq=255})
    log.info("netdrv", "等待以太网就绪")
    sys.wait(1000)
    -- 设置以太网的 IP 地址、子网掩码、网关地址
    netdrv.ipv4(socket.LWIP_ETH, "192.168.5.1", "255.255.255.0", "0.0.0.0")
    -- 获取以太网网络状态，连接后返回 true，否则返回 false，如果不存在就返回 nil。
    while netdrv.ready(socket.LWIP_ETH) ~= true do
        log.info("netdrv", "等待以太网就绪") -- 若以太网设备没有连上，可打开此处注释排查。
        sys.wait(10000)
    end
    log.info("netdrv", "以太网就绪")
    -- 创建 DHCP 服务器，为连接到以太网的设备分配 IP 地址。
    log.info("netdrv", "创建dhcp服务器, 供以太网使用")
    dhcpsrv.create({adapter=socket.LWIP_ETH, gw={192,168,5,1}})
    -- 创建 DNS 代理服务，使得以太网接口上的设备可以通过 4G 网络访问互联网。
    log.info("netdrv", "创建dns代理服务, 供以太网使用")
    dnsproxy.setup(socket.LWIP_ETH, socket.LWIP_GP)
end

-- 初始化 Ethernet LAN 和 WiFi AP。
function wifi_ap_eth_lan()
    while airlink.ready() ~= true do
        sys.wait(100)
    end
    wlan.init()
    sys.taskInit(eth_lan)
    sys.taskInit(test_ap)

    while 1 do
        -- 当 4G 网络就绪后，开启 NAPT （网络端口地址转换）功能，使 4G 网络作为 WiFi AP 上设备的网关。
        if netdrv.ready(socket.LWIP_GP) then
            log.info("netdrv", "4G作为网关")
            netdrv.napt(socket.LWIP_GP)
            break
        end
        sys.wait(1000)
    end
end

sys.taskInit(wifi_ap_eth_lan)
