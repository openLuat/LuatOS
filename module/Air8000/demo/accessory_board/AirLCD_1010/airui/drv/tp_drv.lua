--[[
@module  tp_drv
@summary 触摸面板驱动模块，基于tp核心库
@version 1.0
@date    2026.02.05
@author  江访
@usage
本模块为触摸面板驱动功能模块，主要功能包括：
1、初始化GT911触摸控制器；
2、配置I2C通信接口和触摸回调函数；
3、发布触摸事件消息供UI系统处理；

对外接口：
1、tp_drv.init()：初始化触摸面板驱动
]]


local exmux = require "exmux"

--[[
初始化触摸面板驱动；

@api tp_drv.init()
@summary 配置并初始化GT911触摸控制器
@return boolean 初始化成功返回true，失败返回false

@usage
-- 初始化触摸面板
local result = tp_drv.init()
if result then
    log.info("触摸面板初始化成功")
else
    log.error("触摸面板初始化失败")
end
]]


local function tp_drv_init()
    -- 在Air8000A V2.0开发板上，i2c0同时外挂了tp，gsensor，camera，es8311设备；
    -- 在开发调试时，需要把握一个原则：使用其中一个设备时，其余设备必须同时供电，否则i2c0工作不正常
    -- 具体原因详见Air8000硬件部分I2C说明 https://docs.openluat.com/air8000/luatos/hardware/i2c/#i2c_2
    -- 可以使用exmux扩展库来实现统一管理，详细用法参考：https://docs.openluat.com/osapi/ext/exmux/
    -- 当您使用的不是合宙开发板，而是自己设计的板子，请根据自己板子的硬件设计，来决定是否需要exmux库来配置
    --
    -- 初始化外设分组开关状态
    exmux.setup("DEV_BOARD_8000_V2.0")
    -- 打开i2c0外设分组的电源
    exmux.open("i2c0")

    -- 初始化硬件I2C
    i2c.setup(0, i2c.SLOW) -- 初始化I2C 0，设置为低速模式

    -- 此处触摸IC数据读取使用的是软件I2C接口
    -- 参数说明：
    -- "gt911": 触摸控制器型号
    -- port: I2C接口对象
    -- pin_rst: 复位引脚编号
    -- pin_int: 中断引脚编号
    -- w: 触摸面板宽度
    -- h: 触摸面板高度
    local result = tp.init("gt911", { port = 0, pin_rst = 0xff, pin_int = gpio.WAKEUP0})

    log.info("tp.init", result)

    if rtos.bsp() ~= "PC" then
       
        -- 绑定触摸设备到AirUI输入设备
        airui.device_bind_touch(result)

    else
        if not result then
            log.error("ui_main", "触摸初始化失败")
            return result
        else
            -- 绑定触摸设备到AirUI输入设备
            return airui.device_bind_touch(result)
        end
    end
end

sys.taskInit(tp_drv_init)