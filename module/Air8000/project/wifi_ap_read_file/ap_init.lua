--[[
@module  ap_init
@summary ap_init AP启动功能模块
@version 1.0
@date    2025.09.02
@author  拓毅恒
@usage
用法实例：

启动 AP 服务
- 运行 create_ap 任务，来执行开启 AP 的操作，并返回设置的SSID和PASSWD。

本文件在其余文件中用到了其中的变量，可直接在所需文件中 require "ap_init" 来加载运行。
]]

dhcpsrv = require("dhcpsrv")
-- 配置参数
local AP_SSID       = "Air8000_FileHub"
local AP_PASSWORD   = "12345678"

-- 创建AP热点
local function create_ap()
    log.info("WIFI", "创建AP热点: " .. AP_SSID)
    wlan.init()
    sys.wait(100)
    wlan.createAP(AP_SSID, AP_PASSWORD)
    netdrv.ipv4(socket.LWIP_AP, "192.168.4.1", "255.255.255.0", "192.168.4.1")
    while netdrv.ready(socket.LWIP_AP) ~= true do
        sys.wait(100)
    end
    dnsproxy.setup(socket.LWIP_AP, socket.LWIP_GP)
    dhcpsrv.create({adapter=socket.LWIP_AP})
    sys.publish("AP_CREATE_OK")
end

-- 启动AP配置任务
sys.taskInit(create_ap)

return {
    AP_SSID = AP_SSID,
    AP_PASSWORD = AP_PASSWORD,
}
