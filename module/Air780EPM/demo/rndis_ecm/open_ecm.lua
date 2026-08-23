--[[
@module  open_ecm
@summary ecm 服务启动功能模块
@version 1.2
@date    2026.08.03
@author  拓毅恒
@usage
用法实例

启动 ECM 服务
- 运行 ecm_task 任务，来执行开启 ECM 的操作。
- 使用 mobile.config(mobile.CONF_USB_ETHERNET, 3) 来启用 ECM 功能。
- ECM 设置完毕后需要主动进出飞行模式一次才能生效。

注：由于Windows系统没有测试环境无法测试 ECM 功能，所以本demo没有完整测试。

特别注意：
1. USB默认是ECM配置，设置完毕后还需要开关USB电源将USB协议重置为ecm配置


本文件没有对外接口，直接在 main.lua 中 require "open_ecm" 即可加载运行。
]]

local function ip_ready_func(ip, adapter)
    if adapter == socket.LWIP_GP then
        -- IP_READY后打印IP地址
        log.info("IP_READY", socket.localIP(socket.LWIP_GP))
    end
end

--订阅"IP_READY"消息
sys.subscribe("IP_READY", ip_ready_func)

-- 运行 ECM 模式任务
local function ecm_task()
    -- 调用 mobile.config 函数启用 ECM 功能
    -- 传入的第二个参数 7 ，实际为二进制的 0111
    -- 蜂窝网络模块的usb以太网卡控制，bit0开关：1开0关，bit1模式：1-NAT 0-独立IP(在usb以太网卡开启前可以修改，开启过就不行)，bit2协议：1 ECM,0 ECM(需在飞行模式下设置)
    log.info("我看看 ECM 是否启动成功：", mobile.config(mobile.CONF_USB_ETHERNET, 7))
    -- 设置完毕后，需要进出一次飞行模式，才能生效
    log.info("进入飞行模式")
    mobile.flymode(0, true)
    log.info("退出飞行模式")
    mobile.flymode(0, false)
    -- 设置网卡需要开关USB电源将USB协议重置为ECM配置
    pm.power(pm.USB ,false)
    pm.power(pm.USB ,true)
end

-- 初始化一个系统任务，执行 ecm_task 函数
sys.taskInit(ecm_task)
