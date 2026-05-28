--[[
@module  extp_drv
@summary 扩展触摸面板驱动模块，基于extp扩展库
@version 1.0
@date    2025.11.20
@author  江访
@usage
本模块为扩展触摸面板驱动功能模块，主要功能包括：
1、初始化AirLCD_1010扩展触摸面板；
2、配置I2C通信接口和触摸参数；
3、发布触摸事件消息供UI系统处理；

说明：
成功执行extp_drv.init()之后，在触摸面板上有触摸动作时，在extp扩展库内，默认会发布以下消息：
1、sys.publish("BASE_TOUCH_EVENT", "SINGLE_TAP", x, y) --单击消息，x和y表示坐标
2、sys.publish("BASE_TOUCH_EVENT", "LONG_PRESS", x, y) --长按消息，x和y表示坐标
如果需要发布上下左右滑动、移动、原始数据几种消息，参考extp扩展库中的extp.set_publish_enabled(msg_type, enabled)进行设置

对外接口：
1、extp_drv.init()：初始化扩展触摸面板驱动
]]

local extp = require "extp"

local extp_drv = {}

--[[
初始化扩展触摸面板驱动；



@usage
加载extp_drv模块后，自动进行初始化：
]]

local function extp_drv_init()
    -- 初始化I2C
    local result = i2c.setup(1, i2c.SLOW)

    if result==0 then
        log.error("extp_drv.init i2c.setup error")
        return false
    end

    result = extp.init({tp_model = "AirLCD_1010", i2c_id = 1, pin_rst = 0xFF, pin_int = 24, w = 320, h = 480})

    log.info("extp.init", result)

end

extp_drv_init()
