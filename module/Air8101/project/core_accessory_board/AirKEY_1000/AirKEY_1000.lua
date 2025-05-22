--本文件中的主机是指Air8101核心板
--AirKEY_1000是合宙设计生产的一款8路独立按键的配件板

local AirKEY_1000 = {}




--配置主机和AirKEY_1000之间的控制参数；

--key_id：number类型；
--        AirKEY_1000的按键ID；
--        取值范围：1到8；
--        必须传入，不允许为空；
--gpio_id：number类型；
--         主机使用的中断引脚GPIO ID；
--         AirKEY_1000上的一个按键引脚，和主机上的一个GPIO中断引脚相连；
--         AirKEY_1000上的按键按下或者弹起，主机上的GPIO中断引脚输入电平发生变化，从而产生中断；
--         取值范围：Air8101上只能使用0到9，或者12到55，注意不要使用已经复用为其他功能的引脚；
--int_mode：number类型；
--          表示主机GPIO中断触发类型；
--          取值范围：gpio.RISING表示上升沿触发，gpio.FALLING表示下降沿触发，Air8101不支持gpio.BOTH；
--          如果没有传入此参数，则默认为gpio.FALLING；
--int_cbfunc：function类型；
--          表示中断处理函数，函数的定义格式如下：
--                           function cb_func(level, gpio_id)
--                               --level：表示触发中断类型，上升沿触发为gpio.RISING，下降沿触发为gpio.FALLING
--                               --gpio_id：表示触发中断的主机中断引脚的GPIO ID；
--                           end
--          中断函数中不要直接执行耗时较长的动作，例如写fskv，写文件，延时等，可以publish消息给其他协程或者给订阅消息的处理函数去执行耗时动作
--          必须传入，不允许为空；

--返回值：成功返回true，失败返回false
function AirKEY_1000.setup(key_id, gpio_id, int_mode, int_cbfunc)
    if not (key_id>=1 and key_id<=8) then
        log.error("AirKEY_1000.setup error", "invalid key_id", key_id)
        return false
    end

    if not (gpio_id>=0 and gpio_id<=9 or gpio_id>=12 and gpio_id<=55) then
        log.error("AirKEY_1000.setup error", "invalid gpio_id", gpio_id)
        return false
    end

    if not (int_mode==gpio.RISING or int_mode==gpio.FALLING) then
        log.error("AirKEY_1000.setup error", "invalid int_mode", int_mode)
        return false
    end

    if type(int_cbfunc)~="function" then
        log.error("AirKEY_1000.setup error", "invalid int_cbfunc", type(int_cbfunc))
        return false
    end

    -- gpio.setup(gpio_id, int_cbfunc, int_mode==gpio.RISING and gpio.PULLDOWN or gpio.PULLUP, int_mode)
    gpio.setup(gpio_id, int_cbfunc, gpio.PULLUP, int_mode)

    return true
end


return AirKEY_1000
