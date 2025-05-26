-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "Air8000_wifi_networking_by_eth"
VERSION = "1.0.0"

--[[
本demo演示的功能是:
1. 初始化以太网模块，并通过硬件连接上网。
2. 启用 WiFi 的 AP 模式，使其他设备可以连接。
3. 配置网络共享，将以太网的网络共享给 WiFi。
4. 实现网络状态的监控和维护。
]]

-- 加载必要的模块
_G.sys = require("sys")
dhcpsrv = require("dhcpsrv")
dnsproxy = require("dnsproxy")

-- 以太网初始化
function init_eth()
    log.info("初始化以太网")
    -- 打开CH390供电
    gpio.setup(140, 1, gpio.PULLUP)
    sys.wait(100)

    -- 配置SPI和初始化网络驱动
    local result = spi.setup(
        1,--spi id
        nil,
        0,--CPHA
        0,--CPOL
        8,--数据宽度
        51200000--,--波特率
    )
    log.info("main", "open spi",result)
    if result ~= 0 then--返回值为0，表示打开成功
        log.info("main", "spi open error",result)
        return
    end

    local success = netdrv.setup(socket.LWIP_ETH, netdrv.CH390, {spi=1,cs=12})
    if not success then
        log.error("以太网初始化失败")
        return false
    end
    netdrv.dhcp(socket.LWIP_ETH, true)

    while 1 do
        local ip = netdrv.ipv4(socket.LWIP_ETH)
        if ip and ip ~= "0.0.0.0" then
            break
        end
        sys.wait(100)
    end
    iperf.server(socket.LWIP_ETH)

    log.info("以太网初始化完成")
    return true
end

-- WiFi AP初始化
function init_ap()
    log.info("初始化WiFi AP")
    wlan.init()
    sys.wait(300)

    -- 创建AP
    local success = wlan.createAP("Air8000_AP", "12345678")
    if not success then
        log.error("创建WiFi AP失败")
        return false
    end

    -- 配置AP的IP
    netdrv.ipv4(socket.LWIP_AP, "192.168.4.1", "255.255.255.0", "0.0.0.0")
    sys.wait(5000)

    -- 启用AP的DHCP服务
    dhcpsrv.create({adapter=socket.LWIP_AP})

    -- 设置DNS代理，将AP流量通过以太网转发
    dnsproxy.setup(socket.LWIP_AP, socket.LWIP_ETH)

    log.info("WiFi AP初始化完成")

    while 1 do
        if netdrv.ready(socket.LWIP_ETH) then
            log.info("以太网作为网关")
            netdrv.napt(socket.LWIP_ETH)
            break
        end
        sys.wait(1000)
    end
    icmp.setup(socket.LWIP_ETH)
    while 1 do
        -- 持续ping网关
        local ip,mark,gw = netdrv.ipv4(socket.LWIP_ETH)
        if gw then
            log.info("ping", gw)
            icmp.ping(socket.LWIP_ETH, gw)
        end
        sys.wait(10000)
    end

    return true
end

function ping_handle(id, time, dst)
    log.info("ping.result", id, time, dst);
end

-- wifi的AP相关事件
function ap_event_handle(evt, data)
    -- evt 可能的值有: "CONNECTED", "DISCONNECTED"
    -- 当evt=CONNECTED, data是连接的AP的新STA的MAC地址
    -- 当evt=DISCONNECTED, data是断开与AP连接的STA的MAC地址
    log.info("收到AP事件", evt, data and data:toHex())
end

-- 主任务
function main_task()
    -- 初始化以太网
    if not init_eth() then
        log.error("以太网初始化失败，退出")
        return
    end
    sys.wait(100)

    -- 初始化WiFi AP
    if not init_ap() then
        log.error("WiFi AP初始化失败，退出")
        return
    end
    sys.wait(100)

    -- 检查以太网链路状态
    while true do
        if netdrv.link(socket.LWIP_ETH) then
            log.info("以太网已连接")
            break
        else
            log.info("等待以太网连接...")
            sys.wait(1000)
        end
    end
    sys.wait(100)

    -- 循环保持任务运行
    while true do
        sys.wait(1000)
    end
end

sys.subscribe("PING_RESULT", ping_handle)
sys.subscribe("WLAN_AP_INC", ap_event_handle)
sys.taskInit(main_task)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
