--[[
@module  lcd_drv
@summary LCD显示驱动模块，基于lcd核心库
@version 1.0
@date    2025.12.1
@author  江访
@usage
本模块为LCD显示驱动功能模块，主要功能包括：
1、初始化 LCD屏幕；
2、配置LCD显示参数和显示缓冲区；
3、初始化AirUI;
4、支持多种屏幕方向和分辨率设置；
]]

local function tp_drv_init()
    -- 初始化软件I2C，接口i2c.createSoft(scl, sda, delay)
    -- 参数说明：
    -- 0: SCL引脚编号
    -- 1: SDA引脚编号
    local result = i2c.createSoft(8, 5)

    if type(result) ~= "userdata" then
        log.error("tp_drv.init i2c.createSoft error")
        return false
    end
    -- 此处触摸IC数据读取使用的是软件I2C接口
    -- 参数说明：
    -- "gt911": 触摸控制器型号
    -- port: I2C接口对象
    -- pin_rst: 复位引脚编号
    -- pin_int: 中断引脚编号
    -- w: 触摸面板宽度
    -- h: 触摸面板高度
    result = tp.init("gt911", { port = result, pin_rst = 9, pin_int = 6 })

    log.info("tp.init", result)

    if rtos.bsp() ~= "PC" then
       
        -- 绑定触摸设备到AirUI输入设备
        airui.device_bind_touch(result)

        -- 在PC模拟器上启用系统键盘输入
        airui.keyboard_enable_system(true)
    else
        if not result then
            log.error("ui_main", "触摸初始化失败")
        else
            -- 绑定触摸设备到AirUI输入设备
           airui.device_bind_touch(result)
        end
    end
end

tp_drv_init()