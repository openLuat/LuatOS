--[[
@module  tp_drv
@summary 触摸面板驱动模块，基于tp核心库
@version 1.0
@date    2025.12.1
@author  江访
@usage
本模块为触摸面板驱动功能模块，主要功能包括：
1、初始化GT911触摸控制器；
2、配置I2C通信接口和触摸回调函数；
3、发布触摸事件消息供UI系统处理；

对外接口：
1、tp_drv.init()：初始化触摸面板驱动
]]



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

local tp_drv = {}

function tp_drv.init()

    -- 初始化I2C 0，设置为低速模式
i2c.setup(1, i2c.SLOW)
    -- 初始化软件I2C，接口i2c.createSoft(scl, sda, delay)
    -- 参数说明：
    -- 0: SCL引脚编号
    -- 1: SDA引脚编号
    -- local result = i2c.createSoft(0, 1)

    -- if type(result) ~= "userdata" then
    --     log.error("tp_drv.init i2c.createSoft error")
    -- end
    -- 此处触摸IC数据读取使用的是软件I2C接口
    -- 参数说明：
    -- "gt911": 触摸控制器型号
    -- port: I2C接口对象
    -- pin_rst: 复位引脚编号
    -- pin_int: 中断引脚编号
    -- w: 触摸面板宽度
    -- h: 触摸面板高度

    local result = tp.init("gt911", { port = 1, pin_rst = 28, pin_int = 7 , int_type = tp.FALLING })

    log.info("tp.init", result)

    if rtos.bsp() ~= "PC" then
       
        -- 绑定触摸设备到AirUI输入设备
        airui.device_bind_touch(result)

    else
        if not result then
            log.error("ui_main", "触摸初始化失败")
        else
            -- 绑定触摸设备到AirUI输入设备
           airui.device_bind_touch(result)
        end
    end
end

return tp_drv
-- tp_drv_init()