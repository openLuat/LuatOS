--加载AirFONTS_1000驱动文件
local air_vetor_fonts = require "AirFONTS_1000"
--加载AirLCD_1020驱动文件
local air_lcd = require "AirLCD_1020"
--TP设备
local tp_device


--lcd显示矢量字体的task
--自动刷新显示不同字号矢量字体以及不同bit的灰度显示效果
local function lcd_vector_font_app_task_func()
    log.info("lcd_vector_font_app_task_func enter")
    -- 开启显示缓冲区, 刷屏速度会加快, 但也消耗2倍屏幕分辨率的内存(2*宽*高 字节)
    -- 第一个参数无意义，直接填nil即可
    -- 第二个参数true表示使用sys中的内存
    lcd.setupBuff(nil, true)
    --禁止自动刷新
    --需要刷新时需要主动调用lcd.flush()接口，才能将缓冲区中的数据显示到lcd上
    lcd.autoFlush(false)

    lvgl.init()
    lvgl.indev_drv_register("pointer", "touch", tp_device)

    local scr = lvgl.obj_create(nil, nil)

    -- 加载16号和32号矢量字体
    local counter_label_font_size = 16
    local font_counter_label = lvgl.font_load(air_vetor_fonts.spi_gtfont, counter_label_font_size)
    local font32 = lvgl.font_load(air_vetor_fonts.spi_gtfont, 32)

    -- 创建一个按钮
    local btn = lvgl.btn_create(scr)  -- 在屏幕上创建一个按钮
    lvgl.obj_set_size(btn, 240, 50)  -- 设置按钮大小为240x50
    lvgl.obj_align(btn, nil, lvgl.ALIGN_CENTER, 0, 200)  -- 将按钮左右居中，向下偏移200像素

    -- 在按钮上添加一个标签
    local btn_label = lvgl.label_create(btn)  -- 在按钮上创建一个标签
    lvgl.obj_set_style_local_text_font(btn_label, lvgl.LABEL_PART_MAIN, lvgl.STATE_DEFAULT, font32)  -- 设置为32号矢量字体
    lvgl.label_set_text(btn_label, "点我")  -- 设置按钮标签的文本为“点我”
    lvgl.obj_align(btn_label, nil, lvgl.ALIGN_CENTER, 0, 0)  -- 将标签居中显示在按钮上

    -- 创建一个标签用于显示数字
    local counter_label = lvgl.label_create(scr)  -- 在屏幕上创建一个标签
    lvgl.obj_set_style_local_text_font(counter_label, lvgl.LABEL_PART_MAIN, lvgl.STATE_DEFAULT, font_counter_label) -- 初始设置为16号矢量字体
    lvgl.label_set_text(counter_label, counter_label_font_size.."号字体")  -- 设置标签的初始文本为“16号字体”
    lvgl.obj_align(counter_label, nil, lvgl.ALIGN_CENTER, 0, -100)  -- 将标签左右居中，向上偏移100像素

    -- 按钮点击事件回调函数
    local function btn_event_cb(obj, event)
        --颜色表，依次是黑色，红色，绿色，蓝色
        local color_table = {lvgl.color_hex(0x000000), lvgl.color_hex(0xFF0000), lvgl.color_hex(0x00FF00), lvgl.color_hex(0x0000FF)}
        if event == lvgl.EVENT_CLICKED then  -- 如果按钮被点击
            log.info("button clicked")
  
            -- 要显示的矢量字体字号加一
            counter_label_font_size = counter_label_font_size+1
            -- 如果大于32，复位到默认值16
            if counter_label_font_size>32 then counter_label_font_size = 16 end

            -- 加载counter_label_font_size字号大小的矢量字体
            font_counter_label = lvgl.font_load(air_vetor_fonts.spi_gtfont, counter_label_font_size)
            -- 设置标签的显示字体为counter_label_font_size字号大小的矢量字体
            lvgl.obj_set_style_local_text_font(counter_label, lvgl.LABEL_PART_MAIN, lvgl.STATE_DEFAULT, font_counter_label) 
            -- 设置标签上显示内容的颜色，依次在黑，红，绿，蓝之间循环
            lvgl.obj_set_style_local_text_color(counter_label, lvgl.LABEL_PART_MAIN, lvgl.STATE_DEFAULT, color_table[counter_label_font_size%4+1])

            -- 更新标签上显示的内容
            lvgl.label_set_text(counter_label, counter_label_font_size .. "号字体")
        end
    end
    

    -- 将回调函数绑定到按钮的点击事件
    lvgl.obj_set_event_cb(btn, btn_event_cb, lvgl.EVENT_CLICKED, nil)
    
    
    lvgl.scr_load(scr)
end


-- 整机开发板上矢量字库供电使能控制引脚为GPIO32
-- 需要GPIO32输出高电平，打开使能控制
gpio.setup(32, 1)
mcu.altfun(mcu.SPI, 0, 33)
mcu.altfun(mcu.SPI, 0, 34)
mcu.altfun(mcu.SPI, 0, 35)
mcu.altfun(mcu.SPI, 0, 36)
--初始化矢量字库，使用GPIO33到GPIO36四个引脚
air_vetor_fonts.init(0, 34)


-- 整机开发板上LCD供电使能控制引脚为GPIO5
-- 需要GPIO5输出高电平，打开使能控制
gpio.setup(5, 1)
-- 初始化LCD
air_lcd.init_lcd()
-- 初始化TP触摸面板
tp_device = air_lcd.init_tp()
-- 打开LCD背光
air_lcd.open_backlight()

-- 创建并且启动一个task
-- task的主函数为lcd_vector_font_app_task_func
sys.taskInit(lcd_vector_font_app_task_func)

