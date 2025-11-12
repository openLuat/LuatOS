--[[
@module  netdrv_wifi_ap
@summary "WIFI AP网卡"驱动模块
@version 1.0
@date    2025.10.16
@author  王世豪
@usage
本文件为WIFI AP网卡驱动模块，核心业务逻辑为：
1、初始化WiFi AP功能；
2、配置热点名称、密码等参数；
3、启动接入点供其他设备连接；

本文件没有对外接口，直接在其他功能模块中require "netdrv_wifi_ap"就可以加载运行；
]]

dnsproxy = require("dnsproxy")
dhcpsrv = require("dhcpsrv")


local function ip_ready_func(ip,adapter)
    if adapter == socket.LWIP_AP then
        log.info("netdrv_wifi.ip_ready_func", "IP_READY: ", ip)
    end
end

local function ip_lose_func(ip,adapter)
    if adapter == socket.LWIP_AP then
        log.warn("netdrv_wifi.ip_lose_func", "IP_LOSE")
        sys.publish(SERVER_TOPIC, "SOCKET_CLOSED")
    end
end

-- 监听WLAN_AP_INC消息，处理WiFi接入点相关事件
local function ap_ready_func(evt, data)
    -- evt 可能的值有: "CONNECTED", "DISCONNECTED"
    -- 当evt=CONNECTED, data是连接的AP的新STA的MAC地址
    -- 当evt=DISCONNECTED, data是断开与AP连接的STA的MAC地址
    log.info("收到AP事件", evt, data and data:toHex())
end

-- 订阅系统网络相关消息，实现事件驱动的网络状态管理
sys.subscribe("IP_READY", ip_ready_func)
sys.subscribe("IP_LOSE", ip_lose_func)
sys.subscribe("WLAN_AP_INC", ap_ready_func)


-- 设置默认网卡为socket.LWIP_AP
socket.dft(socket.LWIP_AP)

--这个task的核心业务逻辑是：执行WiFi AP初始化和配置流程
local function netdrv_wifi_ap_task_func()
    -- wlan初始化
    wlan.init()
    -- 创建热点，SSID=LuatOS+IMEI，密码=12345678
    wlan.createAP("LuatOS" .. mobile.imei(), "12345678")
    -- 为AP网卡分配静态IPv4地址、子网掩码、网关
    netdrv.ipv4(socket.LWIP_AP, "192.168.4.1", "255.255.255.0", "0.0.0.0")

    -- 等待AP接口就绪
    while netdrv.ready(socket.LWIP_AP) ~= true do
        sys.wait(100)
    end
    -- 配置DNS代理
    dnsproxy.setup(socket.LWIP_AP, socket.LWIP_GP)
    -- 在AP接口上创建DHCP服务器，为连接到热点的设备自动分配IP地址
    dhcpsrv.create({adapter=socket.LWIP_AP})
    -- 配置网络共享（NAPT）,使用4G网络作为主网关出口
    while 1 do
        if netdrv.ready(socket.LWIP_GP) then
            netdrv.napt(socket.LWIP_GP)
            log.info("AP 创建成功，如果无法连接，需要将按照https://docs.openluat.com/air8000/luatos/app/updatwifi/update/ 升级固件")
            log.info("AP 创建成功，如果无法连接，请升级本仓库的最新core")
            break
        end
        sys.wait(1000)
    end
end

--创建并且启动一个task
--task的处理函数为netdrv_wifi_ap_task_func
sys.taskInit(netdrv_wifi_ap_task_func)