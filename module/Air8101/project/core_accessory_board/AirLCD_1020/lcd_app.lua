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

--创建LCD显示应用的task，并且运行task的主函数lcd_app_task_func
sys.taskInit(lcd_app_task_func)

