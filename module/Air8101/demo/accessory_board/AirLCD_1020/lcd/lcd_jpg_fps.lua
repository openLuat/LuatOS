--加载AirLCD_1020驱动文件
local air_lcd = require "AirLCD_1020"



--lcd刷屏测试task
--每隔10秒进行一次刷屏测试，日志中输出fps数值(每秒可以全屏刷新显示jpg图片的)
local function lcd_app_task_func()
    log.info("lcd_app_task_func enter")
    -- 开启显示缓冲区, 刷屏速度会加快, 但也消耗2倍屏幕分辨率的内存(2*宽*高 字节)
    -- 第一个参数无意义，直接填nil即可
    -- 第二个参数true表示使用sys中的内存
    lcd.setupBuff(nil, true)
    --禁止自动刷新
    --需要刷新时需要主动调用lcd.flush()接口，才能将缓冲区中的数据显示到lcd上
    lcd.autoFlush(false)

    local begin_tick

    while true do
        --清屏
        lcd.clear()        

        log.info("begin_tick", mcu.ticks(), mcu.hz())

        --记录测试开始的系统tick数值
        begin_tick = mcu.ticks()
        
        --循环测试10次，每次全屏刷新显示两张jpg图片
        for i=1,10 do
            lcd.showImage(0, 0, "/luadb/introduction.jpg")
            lcd.flush()
            lcd.showImage(0, 0, "/luadb/bird.jpg")
            lcd.flush()
        end

        --测试结束，计算fps
        local end_tick = mcu.ticks()
        lcd.clear() 
        lcd.drawStr(184,234,"The number of JPG images displayed in full-screen refresh per second: "..math.floor(mcu.hz()/((end_tick-begin_tick)/20)))
        lcd.flush()

        --等待10秒钟
        sys.wait(10000)
    end
end

--初始化LCD
air_lcd.init_lcd()
--打开LCD背光
air_lcd.open_backlight()

--创建并且启动一个task
--task的主函数为lcd_app_task_func
sys.taskInit(lcd_app_task_func)

