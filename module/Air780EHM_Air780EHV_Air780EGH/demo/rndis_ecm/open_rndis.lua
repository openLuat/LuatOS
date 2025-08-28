--[[
@module  open_rndis
@summary rndis 服务启动功能模块
@version 1.0
@date    2025.08.25
@author  拓毅恒
@usage
用法实例

启动 RNDIS 服务
- 运行 rndis_task 任务，来执行开启 RNDIS 的操作。
- RNDIS 需要在飞行模式下开启，所以首先进入飞行模式。
- 进入飞行模式后，使用 mobile.config(mobile.CONF_USB_ETHERNET, 3) 来启用 RNDIS 功能。

注：在v2013以下固件使用mobile.config()的返回值有bug，无论是否开启成功，返回值均为false，需要烧录V2013及以上固件才能完整验证此功能。

本文件没有对外接口，直接在 main.lua 中 require "open_rndis" 即可加载运行。
]]

-- 运行 RNDIS 模式任务
local function rndis_task()
    -- 初始化重试计数器，用于记录进入飞行模式失败的重试次数
    local count = 0
    -- 尝试进入飞行模式，获取操作结果标志
    local fly_sign = mobile.flymode(0, true)
    -- 判断是否成功进入飞行模式
    if fly_sign then
        log.info("进入飞行模式成功,打开RNDIS模式")
        -- 调用 mobile.config 函数启用 RNDIS 功能
        log.info("我看看 RNDIS 是否启动成功：", mobile.config(mobile.CONF_USB_ETHERNET, 3))
        log.info("退出飞行模式")
        mobile.flymode(0, false)
    else
        log.info("进入飞行模式失败")
    end
end

-- 初始化一个系统任务，执行 rndis_task 函数
sys.taskInit(rndis_task)
