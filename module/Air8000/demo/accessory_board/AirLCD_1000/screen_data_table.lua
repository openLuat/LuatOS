-- screen_data_table.lua )
-- 此文件只包含屏幕相关配置数据
local screen_data_table = {
    -- 显示屏相关配置
    lcd = {
        model = "AirLCD_1000",  -- LCD型号
        pin_dc = 29,            -- 显示屏供电引脚GPIO端口号，使用VDDEXT供电可填255
        pin_rst = 36,           -- 显示屏复位引脚GPIO端口号，
        pin_pwr = 1,            -- 显示屏背光控制引脚GPIO端口号，，
        pwm_id = 0              -- 显示屏背光引脚对应的PWM ID端口号，
                                -- 如果背光引脚既是GPIO也是PWM引脚，则可以实现通过PWM调节背光亮度
    },

    -- 触摸相关配置
    touch = {
        model = "none",         -- 触摸芯片型号支持型号：AirLCD_1001
        i2c_id = 0,             -- I2C总线端口ID号
        pin_rst = 20,           -- 触摸芯片复位引脚GPIO端口号(若与显示接到一起可以填255)
        pin_int = gpio.WAKEUP0  -- 触摸芯片中断引脚
    },

    -- LCD型号与参数映射表
    -- 每种LCD型号对应的宽度、高度和驱动芯片
    lcd_models = {
        -- 这是竖屏显示参数，横屏显示width和height需要反过来，同时修改ui_disply内lcd_param{}的direction参数
        AirLCD_1000 = {
            width = 320,        -- 屏幕宽度(分辨率)，
            height = 480,       -- 屏幕高度(分辨率)
            lcd_ic = "st7796"   -- 驱动芯片型号
        },
        AirLCD_1001 = {
            width = 320,
            height = 480,
            lcd_ic = "st7796"
        },
        AirLCD_1002 = {
            width = 480,
            height = 480,
            lcd_ic = "R395435T01"
        },
        co5300 = {
            width = 480,
            height = 466,
            lcd_ic = "co5300"
        }
        ,
        st7789 = {
            width = 240,
            height = 320,
            lcd_ic = "st7789"
        }
    },

    -- 触摸相关参数
    default = {
        width = 480,                    -- 触摸屏宽度
        height = 320,                   -- 触摸屏宽度
        slide_threshold = 30,           -- 滑动阈值比例(屏幕最小尺寸的8%)
        click_time_threshold = 200,     -- 点击和长按的时间阈值(毫秒)
        max_event_queue = 3             -- 事件队列最大长度
    }

}

return screen_data_table