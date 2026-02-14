--[[
@module  tp_drv
@summary 触摸面板驱动模块，基于tp核心库
@version 1.0
@date    2026.02.04
@author  孙志鹏
@usage
本模块为触摸面板驱动功能模块，主要功能包括：
1、初始化GT911触摸控制器；
2、配置I2C通信接口和触摸回调函数；
3、发布触摸事件消息供UI系统处理；

对外接口：
1、tp_drv.init()：初始化触摸面板驱动
]] local tp_drv = {}

--[[
触摸事件回调函数；

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

local rst_pin = 55
local int_pin = 3


local is_soft_i2c = true

local port = 1

if is_soft_i2c then
    port = i2c.createSoft(39, 38) -- scl, sda, delay
else
    i2c.setup(port, i2c.SLOW)
end

function tp_drv.init()
    -- 初始化软件I2C，接口i2c.createSoft(scl, sda, delay)
     -- 初始化复位引脚GPIO4，先拉低再关闭，确保不被拉高
    gpio.setup(rst_pin, 0) -- 设置GPIO4为输出模式，输出低电平
    sys.wait(10) -- 短暂延时确保电平稳定
    gpio.close(rst_pin) -- 关闭GPIO4功能，恢复高阻态
    if not is_soft_i2c then
        i2c.setup(port, i2c.SLOW)
    end
    -- 此处触摸IC数据读取使用的是软件I2C接口
    -- 参数说明：
    -- "gt911": 触摸控制器型号
    -- port: I2C接口对象
    -- pin_rst: 复位引脚编号
    -- pin_int: 中断引脚编号
    -- w: 触摸面板宽度
    -- h: 触摸面板高度
    result = tp.init("gt911", {
        port = port,
        pin_rst = rst_pin,
        pin_int = int_pin,
        int_type = 1,
        w = 1280,
        h = 400
    })

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
