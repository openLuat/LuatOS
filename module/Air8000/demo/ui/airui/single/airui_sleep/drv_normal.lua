--[[
@module  drv_normal
@summary 常规模式pm.power(pm.WORK_MODE, 0)驱动配置功能模块 
@version 1.0
@date    2026.02.09
@author  马梦阳
@usage
本文件为常规模式pm.power(pm.WORK_MODE, 0)驱动配置功能模块，提供了常规模式的配置模板，包括以下几点：
1、在进入常规模式前，根据自己的实际项目需求，配置是否需要退出飞行模式
2、配置最低功耗模式为常规模式；pm.power(pm.WORK_MODE, 0)


Air8000A/Air8000U/Air8000N/Air8000AB/Air8000W模组内部包含有WiFi芯片，GPIO23作为WiFi芯片的使能引脚，
默认状态下，GPIO23为高电平输出，在低功耗模式下,WiFi芯片部分的功耗表现为42uA左右，PSM+模式下，WiFi芯片部分的功耗表现为16uA左右，客户应根据实际项目需求进行配置
在常规模式示例代码中，并未对GPIO23进行额外配置，默认状态下为高电平，以此演示常规模式下的实际功耗表现

Air8000A/Air8000U/Air8000N/Air8000AB/Air8000D/Air8000DB模组内部包含有GNSS和GSensor，GPIO24作为GNSS备电电源开关和GSensor电源开关
默认状态下，GPIO24为高电平，在低功耗模式和PSM+模式下，GNSS备电开启和Gsensor开启后，二者的功耗总和表现为88uA左右，客户应根据实际需求进行配置
在常规模式示例代码中，并未对GPIO24进行配置，默认状态下为高电平，以此演示常规模式下的实际功耗表现


本文件的对外接口只有1个：
1、sys.subscribe("DRV_SET_NORMAL", set_drv_normal)：订阅"DRV_SET_NORMAL"消息；
   其他应用模块如果需要配置DRV_SET_NORMAL模式，直接sys.publish("DRV_SET_NORMAL")这个消息即可；
]]


local module = hmeta.model()

log.info("drv_normal", "当前使用的模组是：", module)


local function normal_task()
    log.info("normal_task enter")

    -- 根据自己的项目需求决定是否需要退出飞行模式
    -- 一般来说，主动切换为常规模式时，如果系统处于飞行模式（例如在低功耗模式下自己主动设置了飞行模式）
    -- 并且切换为常规模式后需要退出飞行模式时，才需要打开下面的一行代码
    -- mobile.flymode(0, false)

    -- Air8000A/Air8000U/Air8000N/Air8000AB/Air8000D/Air8000DB模组内部包含有GNSS和GSensor
    -- GPIO24作为GNSS备电开关和GSensor电源开关，默认状态为高电平
    -- 如果在之前进入低功耗模式或者PSM+模式时关闭/拉低了GPIO24
    -- 则在切换为常规模式后，需要重新拉高GPIO24，使GNSS和GSensor正常工作
    -- 根据自己的项目需求决定是否重新拉高GPIO24，需要时可以打开下面这行代码
    if module == "Air8000A" or module == "Air8000U" or module == "Air8000N" or module == "Air8000AB" or module == "Air8000D" or module == "Air8000DB" then
        gpio.setup(24, 1)
    end

    -- Air8000A/Air8000U/Air8000N/Air8000AB/Air8000W模组内部包含有WiFi芯片
    -- GPIO23作为WiFi芯片的使能脚，默认状态为高电平
    -- 不论在低功耗模式还是PSM+模式下是否有关闭WiFi芯片
    -- 在切换到常规模式后，内核固件都会自动先将GPIO23拉低再拉高，确保WiFi芯片正常工作

    -- 配置最低功耗模式为常规模式
    -- 执行此行代码后，就会立即主动进入常规模式
    pm.power(pm.WORK_MODE, 0)
end


local function set_drv_normal()
    sys.taskInit(normal_task)
end


-- 系统启动之后，最低功耗模式默认就是常规模式
-- 如果项目需求是一直工作在常规模式，则不需要做任何设置
-- 如果项目需求是在常规模式，低功耗模式，PSM+模式之间主动灵活切换，根据自己的业务逻辑，在合适的位置sys.publish("DRV_SET_NORMAL")即可配置为最低功耗模式为常规模式
-- 此处订阅"DRV_SET_NORMAL"消息，在消息处理函数中主动切换为常规模式；
-- 此处并不会因为异步消息处理机制导致sys.publish("DRV_SET_NORMAL")下一行代码运行在其他功耗模式，因为代码只要在运行，自动就是常规模式
sys.subscribe("DRV_SET_NORMAL", set_drv_normal)