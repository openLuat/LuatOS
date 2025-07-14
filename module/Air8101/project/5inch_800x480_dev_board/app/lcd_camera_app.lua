--加载AirLCD_1020驱动文件
local air_lcd = require "AirLCD_1020"
--加载AirCAMERA_1030驱动文件
local air_camera = require "AirCAMERA_1030"
--TP设备
local tp_device


--lcd显示task
--每隔10秒清屏并且全屏刷新显示一张图片
local function lcd_app_task_func()
    log.info("lcd_app_task_func enter")

    -- 整机开发板上USB摄像头供电使能控制引脚为GPIO6
    -- 需要GPIO6输出高电平，打开使能控制
    gpio.setup(6, 1)

    -- 开启摄像头画面预览
    camera.config(camera.USB, camera.CONF_PREVIEW_ENABLE, 1)
    -- 假如预览画面方向有问题，配置下画面旋转
    -- camera.config(camera.USB, camera.CONF_PREVIEW_ROTATE, camera.ROTATE_90)

    --打开摄像头
    local result = air_camera.open()
    --如果打开失败，直接退出这个函数
    if not result then
        log.error("http_upload_photo_task_func error", "air_camera.open fail")
        return
    end

    -- 开启显示缓冲区, 刷屏速度会加快, 但也消耗2倍屏幕分辨率的内存(2*宽*高 字节)
    -- 第一个参数无意义，直接填nil即可
    -- 第二个参数true表示使用sys中的内存
    lcd.setupBuff(nil, true)
    --禁止自动刷新
    --需要刷新时需要主动调用lcd.flush()接口，才能将缓冲区中的数据显示到lcd上
    lcd.autoFlush(false)

    --清屏
    lcd.clear()

    --每隔10秒清屏并且全屏刷新显示一张图片
    while true do
        -- --清屏
        -- lcd.clear()
        -- --显示图片
        -- lcd.showImage(0, 0, "/luadb/introduction.jpg")
        -- --刷屏，将缓冲区中的数据显示到lcd上
        -- lcd.flush()
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
                -- --以触摸的中心点画一个半径为10的实心圆
                -- --lcd.drawCircle设计本身，并不支持画纯粹的实心圆，会有一些点画不到
                -- for i=1,10 do
                --     lcd.drawCircle(tp_data[1].x, tp_data[1].y, i, 0xF800)
                -- end
                --拍摄一张1280*720分辨率的照片
                --如果拍摄成功，result中存储是照片数据
                --如果拍摄失败，result为false
                result = air_camera.capture()
                --如果拍摄失败，关闭摄像头，并且直接退出这个函数
                if not result then
                    log.error("http_upload_photo_task_func error", "air_camera.capture fail")
                end
                air_camera.close()
                --刷屏，将缓冲区中的数据显示到lcd上
                lcd.flush()
            end
        end
    end
end

-- 整机开发板上LCD供电使能控制引脚为GPIO5
-- 需要GPIO5输出高电平，打开使能控制
gpio.setup(5, 1)
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

