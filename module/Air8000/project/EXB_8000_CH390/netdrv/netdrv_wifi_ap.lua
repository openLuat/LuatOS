--[[
@module  wifi_ap
@summary wifi_ap模块 
@version 1.0
@date    2025.10.20
@author  魏健强
@usage 本文为wifi_ap功能模块,核心逻辑为
1、开启wifi_ap热点；
2、开启tcp客户端

本文件没有对外接口，直接在其他功能模块中require "wifi_ap"就可以加载运行；
]] 
dhcpsrv = require("dhcpsrv")

local function test_ap()
    log.info("开始AP 测试...")
    wlan.init()
    log.info("执行AP创建操作")
    wlan.createAP("test2", "HZ88888888") 
    netdrv.ipv4(socket.LWIP_AP, "192.168.4.1", "255.255.255.0", "192.168.4.1")
    -- 创建一个dhcp服务器, 最简单的版本
    dhcpsrv.create({adapter=socket.LWIP_AP})
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

-- -- 局域网内tcp客户端测试
-- local function tcp_client_test()
--     local tcp_client_main = require "tcp_client_main"
--     -- 传入网卡，ip,端口号参数
--     tcp_client_main.set_tcp_client_params(socket.LWIP_AP, "192.168.4.100", 2333)
-- end
-- sys.taskInit(eth_lan_setup)