--[[
本功能模块演示的内容为：
使用Air8101核心板驱动显示合宙AirLCD_1020配件板全屏显示一个按钮和一个标签
点击按钮一次，标签上的数字增加一
AirLCD_1020是合宙设计生产的一款5寸RGB888接口800*480分辨率的电容触摸显示屏

使用了Air8101核心板右边的两排排针，一共40个引脚
这些引脚的功能说明参考本demo的pins_Air8101.json文件
]]


--加载AirLCD_1020驱动文件
local air_lcd = require "AirLCD_1020"
--TP设备
local tp_device



local function lcd_app_task_func()

    -- 开启缓冲区, 刷屏速度会加快, 但也消耗2倍屏幕分辨率的内存
    lcd.setupBuff(nil, true) -- 使用sys内存, 只需要选一种
    lcd.autoFlush(false)

    log.info("合宙工业引擎Air8101+合宙LCD配件板功能演示")

    while true do
        lcd.clear()        

        log.info("tick1", mcu.ticks(), mcu.hz())
        for i=1,10 do
            lcd.showImage(0, 0, "/luadb/introduction.jpg")
            lcd.flush()
            lcd.showImage(0, 0, "/luadb/bird.jpg")
            lcd.flush()
        end
        log.info("tick2", mcu.ticks())
        
        sys.wait(1000)
    end
end

-- local function tp_callBack(tp_device,tp_data)
--     log.info("tp_callBack")
--     sys.publish("TP",tp_device,tp_data)
-- end

-- local function tp_app_task_func()

--     while true do
--         local result, tp_device, tp_data = sys.waitUntil("TP")
--         if result then
--             lcd.drawPoint(tp_data[1].x, tp_data[1].y, 0xF800)
--             lcd.flush()
--         end
--     end
-- end


--初始化LCD
air_lcd.init_lcd()
--初始化TP触摸面板
tp_device = air_lcd.init_tp()
-- tp_device = air_lcd.init_tp(nil, nil, nil, nil, tp_callBack)
--打开LCD背光
air_lcd.open_backlight()

--创建LCD显示应用的task，并且运行task的主函数lcd_app_task_func
sys.taskInit(lcd_app_task_func)
-- sys.taskInit(tp_app_task_func)

