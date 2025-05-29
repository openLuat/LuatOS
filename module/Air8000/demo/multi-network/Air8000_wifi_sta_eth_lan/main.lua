-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "Air8000_STA_to_ETH"
VERSION = "1.0.0"

--[[
本代码功能：
1. 通过STA模式连接到WiFi网络
2. 初始化以太网模块
3. 将WiFi STA的网络共享给以太网设备
]]

-- 加载必要的模块
_G.sys = require("sys")
dhcpsrv = require("dhcpsrv")
dnsproxy = require("dnsproxy")

-- STA模式连接WiFi配置
local WIFI_SSID = "luatos1234"
local WIFI_PASSWORD = "12341234"

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
        51200000--波特率
    )
    log.info("main", "open spi", result)
    if result ~= 0 then
        log.info("main", "spi open error", result)
        return false
    end

    local success = netdrv.setup(socket.LWIP_ETH, netdrv.CH390, {spi=1, cs=12, irq=255})
    if not success then
        log.error("以太网初始化失败")
        return false
    end

    log.info("以太网初始化完成")
    return true
end

-- STA模式连接WiFi
function connect_sta()
    log.info("初始化WiFi STA")
    wlan.init()
    sys.wait(300)

    log.info("开始连接WiFi:", WIFI_SSID)
    local success = wlan.connect(WIFI_SSID, WIFI_PASSWORD)
    if not success then
        log.error("WiFi连接失败")
        return false
    end

    -- 等待获取IP地址
    while 1 do
        local ip = netdrv.ipv4(socket.LWIP_STA)
        if ip and ip ~= "0.0.0.0" then
            log.info("WiFi STA已连接，IP:", ip)
            break
        end
        sys.wait(100)
    end

    log.info("WiFi STA初始化完成")
    return true
end

-- 配置网络共享（STA到ETH）
function setup_network_sharing()
    log.info("配置网络共享")

    -- 配置以太网的IP
    netdrv.ipv4(socket.LWIP_ETH, "192.168.2.1", "255.255.255.0", "0.0.0.0")
    sys.wait(1000)
    -- 获取以太网网络状态，连接后返回 true，否则返回 false，如果不存在就返回 nil。
    while netdrv.ready(socket.LWIP_ETH) ~= true do
        log.info("netdrv", "等待以太网就绪") -- 若以太网设备没有连上，可打开此处注释排查。
        sys.wait(10000)
    end

    -- 启用以太网的DHCP服务
    dhcpsrv.create({adapter=socket.LWIP_ETH, gw={192,168,2,1}})
    -- 设置DNS代理，将以太网流量通过STA转发
    dnsproxy.setup(socket.LWIP_ETH, socket.LWIP_STA)

    log.info("netdrv", "以太网就绪")

    -- 等待网络就绪
    while 1 do
        if netdrv.ready(socket.LWIP_STA) then
            log.info("设置NAPT")
            netdrv.napt(socket.LWIP_STA)
            break
        end
        sys.wait(1000)
    end

    log.info("网络共享配置完成")
    return true
end

-- 主任务
function main_task()
    -- 初始化WiFi STA
    if not connect_sta() then
        log.error("WiFi STA初始化失败，退出")
        return
    end
    sys.wait(100)

    -- 初始化以太网
    if not init_eth() then
        log.error("以太网初始化失败，退出")
        return
    end
    sys.wait(100)

    -- 配置网络共享
    if not setup_network_sharing() then
        log.error("网络共享配置失败，退出")
        return
    end
    sys.wait(100)

    -- 检查网络连接状态
    local is_wifi_connected = false
    while true do
        local current_wifi_status = netdrv.link(socket.LWIP_STA)
        if current_wifi_status and not is_wifi_connected then
            log.info("WiFi已连接")
            is_wifi_connected = true
        elseif not current_wifi_status and is_wifi_connected then
            log.info("WiFi已断开，尝试重新连接...")
            is_wifi_connected = false
            if not connect_sta() then
                log.error("WiFi重新连接失败")
            end
        end
        sys.wait(5000)
    end
end

-- 启动主任务
sys.taskInit(main_task)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
