--[[
@module  wifi_ap
@summary wifi_ap模块 
@version 1.0
@date    2025.10.20
@author  魏健强
@usage 本文为wifi_ap功能模块,核心逻辑为
1、开启wifi_ap热点；
2、4G作为数据出口,其他需要联网的设备连接模块热点上网；
直接使用Air8000开发板硬件测试即可；

本文件没有对外接口，直接在其他功能模块中require "wifi_ap"就可以加载运行；
]] 
dnsproxy = require("dnsproxy")
dhcpsrv = require("dhcpsrv")

-- 如果无法使用AP功能，可以开启此功能升级WiFi固件版本后再次尝试
-- 升级完毕后最好取消调用，防止后期版本升级过高导致程序使用不稳定
-- require "check_wifi" 

local function test_ap()
    log.info("开始AP 测试...")
    wlan.init()
    log.info("执行AP创建操作")
    wlan.createAP("test2", "HZ88888888") 
    netdrv.ipv4(socket.LWIP_AP, "192.168.4.1", "255.255.255.0", "192.168.4.1")
    while not socket.adapter(socket.LWIP_GP) do
        -- 在此处阻塞等待wifi连接成功的消息"IP_READY"
        -- 或者等待1秒超时退出阻塞等待状态;
        -- 注意：此处的1000毫秒超时不要修改的更长；
        sys.waitUntil("IP_READY", 1000)
    end
    dnsproxy.setup(socket.LWIP_AP, socket.LWIP_GP)
    -- 创建一个dhcp服务器, 最简单的版本
    dhcpsrv.create({adapter=socket.LWIP_AP})
    netdrv.napt(socket.LWIP_GP)
end

local function ap_event(evt, data)
    -- evt 可能的值有: "CONNECTED", "DISCONNECTED"
    -- 当evt=CONNECTED, data是连接的AP的新STA的MAC地址
    -- 当evt=DISCONNECTED, data是断开与AP连接的STA的MAC地址
    log.info("收到AP事件", evt, data and data:toHex())
end

-- wifi的AP相关事件
sys.subscribe("WLAN_AP_INC", ap_event)

sys.taskInit(test_ap)
