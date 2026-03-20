--[[
@module  tp_drv
@summary 触摸面板驱动模块，基于tp核心库
@version 1.0
@date    2026.03.17
@usage
本模块为触摸面板驱动功能模块，主要功能包括：
1、初始化GT911触摸控制器；
2、配置I2C通信接口和触摸回调函数；
3、发布触摸事件消息供UI系统处理；
]]

local tp_drv = {}

function tp_drv.init()
    -- 开机I2C供电，触摸、摄像头和音频都是使用I2C0
    -- 初始化硬件I2C
    i2c.setup(1, i2c.SLOW)

    -- 初始化触摸IC
    local result = tp.init("gt911", { port = 1, pin_rst = 0xff, pin_int = gpio.WAKEUP0})

    log.info("tp.init", result)

    if not result then
        log.error("tp_drv", "触摸初始化失败")
        return result
    else
        -- 绑定触摸设备到AirUI输入设备
        return airui.device_bind_touch(result)
    end
end

return tp_drv
