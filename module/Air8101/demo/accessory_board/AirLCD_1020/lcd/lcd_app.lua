--加载AirLCD_1020驱动文件
local air_lcd = require "AirLCD_1020"
--TP设备
local tp_device


--lcd显示task
--每隔10秒清屏并且全屏刷新显示一张图片
local function lcd_app_task_func()
    log.info("lcd_app_task_func enter")
    -- 开启显示缓冲区, 刷屏速度会加快, 但也消耗2倍屏幕分辨率的内存(2*宽*高 字节)
    -- 第一个参数无意义，直接填nil即可
    -- 第二个参数true表示使用sys中的内存
    lcd.setupBuff(nil, true)
    --禁止自动刷新
    --需要刷新时需要主动调用lcd.flush()接口，才能将缓冲区中的数据显示到lcd上
    lcd.autoFlush(false)

    --每隔10秒清屏并且全屏刷新显示一张图片
    while true do
        --清屏
        lcd.clear()
        --显示图片
        lcd.showImage(0, 0, "/luadb/introduction.jpg")
        --刷屏，将缓冲区中的数据显示到lcd上
        lcd.flush()
        --等待10秒钟
        sys.wait(10000)
    end
end

local function tp_callback(tp_device,tp_data)
    log.info("tp_callback", tp_data[1].event, tp_data[1].x, tp_data[1].y, tp_data[1].timestamp, mcu.hz())
    sys.publish("TP",tp_device,tp_data)
end


--tp处理task
--检测到触摸按下和移动的时间后，以触摸的中心点画一个半径为10的实心圆
local function tp_app_task_func()
    while true do
        --阻塞等待触摸事件
        local result, tp_device, tp_data = sys.waitUntil("TP")
        log.info("tp_app_task_func", result)
        if result then
            --触摸按下或者移动的事件
            if tp_data[1].event == tp.EVENT_DOWN or tp_data[1].event == tp.EVENT_MOVE then
                --以触摸的中心点画一个半径为10的实心圆
                --lcd.drawCircle设计本身，并不支持画纯粹的实心圆，会有一些点画不到
                for i=1,10 do
                    lcd.drawCircle(tp_data[1].x, tp_data[1].y, i, 0xF800)
                end
                --刷屏，将缓冲区中的数据显示到lcd上
                lcd.flush()
            end
        end
    end
end


--初始化LCD
air_lcd.init_lcd()
--初始化TP触摸面板，触摸事件的回调函数为tp_callback
air_lcd.init_tp(nil, nil, nil, nil, tp_callback)
--打开LCD背光
air_lcd.open_backlight()

--创建并且启动一个task
--task的主函数为lcd_app_task_func
sys.taskInit(lcd_app_task_func)
--创建并且启动一个task
--task的主函数为tp_app_task_func
sys.taskInit(tp_app_task_func)

