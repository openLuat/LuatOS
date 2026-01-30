--[[
@module  tp_drv
@summary 触摸面板驱动模块，基于tp核心库
@version 1.0
@date    2026.01.29
@author  江访
@usage
本模块为触摸面板驱动功能模块，主要功能包括：
1、初始化GT911触摸控制器；
2、配置I2C通信接口和触摸回调函数；
3、发布触摸事件消息供UI系统处理；

对外接口：
1、tp_drv.init()：初始化触摸面板驱动
]]

local tp_drv = {}

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

function tp_drv.init()

    -- 初始化硬件I2C
    i2c.setup(1, i2c.SLOW) -- 初始化I2C 1，设置为低速模式

    -- 此处触摸IC数据读取使用的是硬件I2C接口
    -- 参数说明：
    -- "gt911": 触摸控制器型号
    -- port: I2C接口
    -- pin_rst: 复位引脚编号
    -- pin_int: 中断引脚编号
    -- w: 触摸面板宽度
    -- h: 触摸面板高度
    local result = tp.init("gt911", { port = 1, pin_rst = 0xff, pin_int = gpio.WAKEUP0, w = 320, h = 480 })

    log.info("tp.init", result)

    if not result then
        log.error("ui_main", "触摸初始化失败")
        return result
    else
        -- 绑定触摸设备到AirUI输入设备
        return airui.indev_bind_touch(result)
    end
end

return tp_drv