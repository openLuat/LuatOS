--[[
@module  open_ecm
@summary ecm 服务启动功能模块
@version 1.0
@date    2025.08.26
@author  拓毅恒
@usage
用法实例

启动 ECM 服务
- 运行 ecm_task 任务，来执行开启 ECM 的操作。
- ECM 需要在飞行模式下开启，所以首先进入飞行模式。
- 进入飞行模式后，使用 mobile.config(mobile.CONF_USB_ETHERNET, 7) 来启用 ECM 功能。

注：由于Windows系统没有测试环境无法测试 ECM 功能，所以本demo没有完整测试。

本文件没有对外接口，直接在 main.lua 中 require "open_ecm" 即可加载运行。
]]

-- 运行 ECM 模式任务
local function ecm_task()
    -- 初始化重试计数器，用于记录进入飞行模式失败的重试次数
    local count = 0
    -- 尝试进入飞行模式，获取操作结果标志
    local fly_sign = mobile.flymode(0, true)
    -- 判断是否成功进入飞行模式
    if fly_sign then
        log.info("进入飞行模式成功,打开ECM模式")
        -- 调用 mobile.config 函数启用 ECM 功能
        -- 传入的第二个参数 7 ，实际为二进制的 0111
        -- 蜂窝网络模块的usb以太网卡控制，bit0开关，1开0关，bit1模式，1NAT0独立IP(在usb以太网卡开启前可以修改，开启过就不行)，bit2协议1 ECM,0 RNDIS，飞行模式里设置。
        log.info("我看看 ECM 是否启动成功：", mobile.config(mobile.CONF_USB_ETHERNET, 7))
        log.info("退出飞行模式")
        mobile.flymode(0, false)
    else
        log.info("进入飞行模式失败")
    end
end

-- 初始化一个系统任务，执行 ecm_task 函数
sys.taskInit(ecm_task)
