--[[
@module  netif_app
@summary netif_app 网络管理模块,开启多网融合功能，wifi提供网络供wifi和以太网设备上网
@version 1.0
@date    2026.07.02
@author  王城钧
@usage
本文件为网络管理模块，核心业务逻辑为：
1.设置多网融合功能，wifi提供网络供wifi和以太网设备上网
2、http测试wifi网络
本文件没有对外接口，直接在main.lua中require "netif_app"就可以加载运行；
]] 
PROJECT = "helloworld"
VERSION = "1.0.0"

local exnetif = require("exnetif")

-- 配置区（请改为实际值）
-- 以太网配置
local ETH_CONFIG = {
    pwrpin = 140,                          -- CH390 供电使能引脚，按实际修改
    tp = netdrv.CH390,                     -- 网卡芯片
    opts = { spi = 1, cs = 12, irq = 19 },-- SPI 配置，irq 可选，按实际修改
    need_ping = true,
}

-- WiFi 凭证 A
local WIFI_A = {
    ssid = "116",
    password = "wangshuai123",
    need_ping = true,
}

-- WiFi 凭证 B
local WIFI_B = {
    ssid = "xiaoshuai",
    password = "2894551470",
    need_ping = true,
}

-- 网络状态变化回调
local function on_network_status(net_type, adapter)
    if net_type then
        log.info("当前使用:", net_type, "adapter:", adapter)
    else
        log.warn("所有网络断开！")
    end
end

-- 主任务：多网融合初始化及 WiFi 凭证切换
function helloworld_app_task_func()
    --阶段1：多网融合初始化（WiFi_A + 以太网）
    log.info("阶段1：多网融合 WiFi_A + 以太网")

    local ok = exnetif.set_priority_order({
        { WIFI = WIFI_A },              -- 高优先级：WiFi
        { ETHERNET = ETH_CONFIG },      -- 低优先级：以太网兜底
    })
    log.warn(ok, "阶段1: 初始化失败")
    log.info("优先级: WiFi > 以太网，等待网络就绪")

    -- 等待任一网络就绪
    local net_type, adapter = sys.waitUntil("EXLIB_NETDRV_NETWORK_STATUS", 60000)
    log.info("阶段1 当前网络:", net_type, adapter)

    --[[
    阶段2：切换 WiFi 凭证（先关 WiFi，再用新凭证重开）

    为什么需要先 close 再 set_priority_order？

    set_priority_order 内部对 WiFi 网卡做了状态保护，避免重复初始化。它在处理 WiFi 配置时
    会先检查当前状态，只有当 WiFi 处于 DISCONNECTED（从未初始化过）才会执行 wlan.init() +
    wlan.connect() 的完整初始化流程，否则直接跳过。

    已连接过的 WiFi 网卡状态是 OPENED、CONNECTING 或 CONNECTED，都不满足这个条件，所以即使
    传入了新凭证也不会生效。

    因此需要先调用 exnetif.close 将 WiFi 网卡状态重置为 DISCONNECTED，此时多网卡中的其他网络
    会自动接管网络流量保证业务不中断，然后再调用 set_priority_order 传入新凭证，让 WiFi 走完整的
    初始化流程重新连接。
    ]]
    log.info("阶段2：切换到 WiFi_B")
    log.info("模拟：已从服务端获取新 WiFi 凭证")

    -- 2a. 关闭 WiFi（使其回到 DISCONNECTED 状态，否则 set_priority_order 会跳过）
    log.info("关闭 WiFi...")
    exnetif.close(false, socket.LWIP_STA)
    sys.wait(2000)  -- 等待断开完成

    -- 2b. 用 WiFi_B 凭证重新调用 set_priority_order
    --     WiFi 关闭期间以太网自动兜底，网络不中断
    ok = exnetif.set_priority_order({
        { WIFI = WIFI_B },
        { ETHERNET = ETH_CONFIG },
    })
    log.warn(ok, "阶段2: 切换失败")
    log.info("WiFi 正在重连...以太网保持在线兜底")

    -- 等待 WiFi_B 连上
    net_type, adapter = sys.waitUntil("EXLIB_NETDRV_NETWORK_STATUS", 45000)
    log.info("阶段2 切换完成，当前网络:", net_type, adapter)

    log.info("测试结束")
end

exnetif.notify_status(on_network_status)

sys.taskInit(helloworld_app_task_func)


sys.run()
