--加载AirLCD_1020驱动文件
local air_lcd = require "AirLCD_1020"
--TP设备
local tp_device


--lcd显示和TP触摸控制task
--显示一个button控件和一个label控件
--点击button一次，label上的数字加一
local function lcd_app_task_func()

    -- 开启缓冲区, 刷屏速度会加快, 但也消耗2倍屏幕分辨率的内存
    lcd.setupBuff(nil, true) -- 使用sys内存, 只需要选一种
    lcd.autoFlush(false)

    lvgl.init()
    lvgl.indev_drv_register("pointer", "touch", tp_device)

    local scr = lvgl.obj_create(nil, nil)

    -- 创建一个按钮
    local btn = lvgl.btn_create(scr)  -- 在屏幕上创建一个按钮
    lvgl.obj_set_size(btn, 100, 50)  -- 设置按钮大小为100x50
    lvgl.obj_align(btn, nil, lvgl.ALIGN_CENTER, 0, 0)  -- 将按钮居中，并向上偏移50像素

    -- 在按钮上添加一个标签
    local btn_label = lvgl.label_create(btn)  -- 在按钮上创建一个标签
    lvgl.label_set_text(btn_label, "Press Me")  -- 设置按钮标签的文本为“Press Me”
    lvgl.obj_align(btn_label, nil, lvgl.ALIGN_CENTER, 0, 0)  -- 将标签居中显示在按钮上

    -- 创建一个标签用于显示数字
    local counter_label = lvgl.label_create(scr)  -- 在屏幕上创建一个标签
    lvgl.label_set_text(counter_label, "0")  -- 设置标签的初始文本为“0”
    lvgl.obj_align(counter_label, nil, lvgl.ALIGN_CENTER, 0, 50)  -- 将标签居中，并向下偏移50像素

    -- 定义一个计数器变量
    local counter = 0

    -- 按钮点击事件回调函数
    local function btn_event_cb(obj, event)
        if event == lvgl.EVENT_CLICKED then  -- 如果按钮被点击
            log.info("button clicked")
            counter = counter + 1  -- 计数器加1
            lvgl.label_set_text(counter_label, tostring(counter))  -- 更新标签上的数字
        end
    end
    

    -- 将回调函数绑定到按钮的点击事件
    lvgl.obj_set_event_cb(btn, btn_event_cb, lvgl.EVENT_CLICKED, nil)
    
    
    lvgl.scr_load(scr)
end


--初始化LCD
air_lcd.init_lcd()
--初始化TP触摸面板
tp_device = air_lcd.init_tp()
--打开LCD背光
air_lcd.open_backlight()

--创建并且启动一个task
--task的主函数为lcd_app_task_func
sys.taskInit(lcd_app_task_func)

