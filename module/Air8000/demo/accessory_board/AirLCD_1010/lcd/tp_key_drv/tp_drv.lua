--[[
@module  tp_drv
@summary 触摸面板驱动模块，基于tp核心库
@version 1.0
@date    2025.12.2
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
触摸事件回调函数；

@local
@function tp_callback(tp_device, tp_data)
@userdata tp_device 触摸设备对象
@table tp_data 触摸数据数组
@return nil
]]

local function tp_callback(tp_device, tp_data)
    if tp_data[1].event == tp.EVENT_DOWN then
        -- log.info("tp_drv tp_callback", tp_data[1].event, tp_data[1].x, tp_data[1].y)
        sys.publish("BASE_TOUCH_EVENT", tp_data[1].event, tp_data[1].x, tp_data[1].y)
    end
end

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
    -- 初始化I2C
    local result = i2c.setup(1, i2c.SLOW)

    if result==0 then
        log.error("tp_drv.init i2c.setup error")
        return false
    end

    result = tp.init("gt911", {port = 1, pin_rst = 0xFF, pin_int = gpio.WAKEUP0, w = 320, h = 480}, tp_callback)

    log.info("tp.init", result)

    return result
end

return tp_drv
