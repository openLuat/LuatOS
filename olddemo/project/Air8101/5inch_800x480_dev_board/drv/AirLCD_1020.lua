local AirLCD_1020 = 
{
    -- i2c_soft_device = , --触摸面板使用的软件I2C对象，必须使用全局变量存储，不能使用local类型的局部变量
    -- tp_device = , --触摸面板设备
}

--AirLCD_1020显示屏的分辨率为800*480
local WIDTH, HEIGHT = 800, 480


--初始化AirLCD_1020的LCD配置

--返回值：nil
function AirLCD_1020.init_lcd()
    -- st7265
    lcd.init("custom",
        {port = lcd.RGB, hbp = 8, hspw = 4, hfp = 8, vbp = 16, vspw = 4, vfp = 16,
        bus_speed = 30*1000*1000, direction = 0, w = WIDTH, h = HEIGHT, xoffset = 0, yoffset = 0})
end

--关闭AirLCD_1020的LCD

--返回值：nil
function AirLCD_1020.close_lcd()
    lcd.close()
end


--初始化AirLCD_1020的TP配置
--无论使用硬件i2c还是软件io模拟i2c，都是传入引脚的GPIO ID

--int：number类型；
--     表示中断引脚GPIO ID；
--     取值范围：主控产品(例如Air8101)上有效的GPIO ID值；
--     如果没有传入此参数或者传入了nil，则使用默认值7；
--rst：number类型；
--     表示复位控制引脚GPIO ID；
--     取值范围：主控产品(例如Air8101)上有效的GPIO ID值；
--     如果没有传入此参数或者传入了nil，则使用默认值28；
--sda：number类型；
--     表示数据引脚GPIO ID；
--     取值范围：主控产品(例如Air8101)上有效的GPIO ID值；
--     如果没有传入此参数或者传入了nil，则使用默认值1；
--scl：number类型；
--     表示时钟引脚脚GPIO ID；
--     取值范围：主控产品(例如Air8101)上有效的GPIO ID值；
--     如果没有传入此参数或者传入了nil，则使用默认值0；
--cb： function类型；
--     表示触摸事件的回调函数，回调函数的定义格式如下：
--     function cb_func(tp_device, tp_data)
--         --tp_device：产生触摸事件的触摸设备，和AirLCD_1020.init_tp函数的返回值一致
--         --tp_data：触摸事件的数据结构
--                  tp_data[1].event：触摸事件，number类型，tp.EVENT_DOWN(按下事件，值为1)，tp.EVENT_UP(弹起事件，值为2)，tp.EVENT_MOVE(移动事件，值为3)
--                  tp_data[1].x：触摸的x坐标，number类型
--                  tp_data[1].y：触摸的y坐标，number类型
--                  tp_data[1].timestamp：触摸时的系统tick数；每秒钟包含的tick数量可以通过mcu.hz()获取，例如Air8101上，每秒的tick数量是500
--     end
--     允许为空，没有默认值；

--返回值：成功返回触摸设备对象(非nil)，失败返回nil
function AirLCD_1020.init_tp(int, rst, sda, scl, cb)
    AirLCD_1020.i2c_soft_device = i2c.createSoft(scl or 0, sda or 1)  

    AirLCD_1020.tp_device = tp.init("gt911",{port=AirLCD_1020.i2c_soft_device, pin_rst = rst or 28, pin_int = int or 7, w = WIDTH, h = HEIGHT}, cb)

    return AirLCD_1020.tp_device
end


--打开AirLCD_1020的背光

--gpio_id：number类型；
--         表示控制LCD背光的GPIO ID；
--         取值范围：主控产品(例如Air8101)上有效的GPIO ID值；
--         如果没有传入此参数或者传入了nil，则使用默认值8；

--返回值：nil
function AirLCD_1020.open_backlight(gpio_id)
    gpio.setup(gpio_id or 8, 1)
end

--关闭AirLCD_1020的背光

--gpio_id：number类型；
--         表示控制LCD背光的GPIO ID；
--         取值范围：主控产品(例如Air8101)上有效的GPIO ID值；
--         如果没有传入此参数或者传入了nil，则使用默认值8；

--返回值：nil
function AirLCD_1020.close_backlight(gpio_id)
    gpio.setup(gpio_id or 8, 0)
end


return AirLCD_1020
