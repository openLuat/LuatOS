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

本文件没有对外接口，直接在 main.lua 中 require "ap_init" 即可加载运行。
]]

-- 配置参数
local AP_SSID       = "Air8000_FileHub"
local AP_PASSWORD   = "12345678"

-- 创建AP热点
function create_ap()
    log.info("WIFI", "创建AP热点: " .. AP_SSID)
    local exnetif = require("exnetif")
    exnetif.setproxy(socket.LWIP_AP, socket.LWIP_GP, {
        ssid = AP_SSID,
        password = AP_PASSWORD,
        adapter_addr = "192.168.4.1",
        adapter_gw = { 192, 168, 4, 1 },
        ap_opts = {
            hidden = false,
            max_conn = 4,
            channel = 6
        }
    })
end

-- 启动AP配置任务
sys.taskInit(create_ap)

return {
    create_ap = create_ap,
    AP_SSID = AP_SSID,
    AP_PASSWORD = AP_PASSWORD,
}
