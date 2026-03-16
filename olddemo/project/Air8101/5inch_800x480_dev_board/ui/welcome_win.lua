-- 加载显示屏驱动功能模块
local lcd_device = require "lcd_device"

-- 欢迎窗口的任务处理函数
-- 居中显示两行内容
-- 第一行 欢迎使用
-- 第二行 合宙 LuatOS
-- 每行内容每隔一段时间缩小显示，整个过程形成一幅动画效果
-- 之后延时1秒，然后publish一个消息OPEN_MAIN_MENU_WIN出去，打开主菜单窗口
local function welcome_win_task_func()

    -- 显示屏中心点坐标
    local central_pos_x = math.floor(lcd_device.width/2)
    local central_pos_y = math.floor(lcd_device.height/2)

    local first_line_text = "欢迎使用"
    -- 中心点和上下两行文字之间的垂直间隔
    local vertical_space = 10
    local second_line_text = "合宙LuatOS"

    -- 显示的最大字号
    local font_max_size = 128
    -- 每次缩放减小的字号数值
    local font_sub_size = 2
    -- 缩放显示的次数
    local font_zoom_cnt = 24
    -- 每次缩放显示的间隔，单位毫秒
    local font_zoom_interval = 5

    lcd.setColor(lcd_device.bg_color, lcd_device.fg_color)    
    

    for i=1,font_zoom_cnt do
        -- 清屏
        lcd.clear()

        -- 显示第一行文字
        -- 第一个参数为UTF8格式的文本
        -- 第二个参数为显示的字号
        -- 第三个参数固定为4
        -- 第四个参数为显示的左上角x坐标
        -- 第五个参数为显示的左上角y坐标
        lcd.drawGtfontUtf8Gray(first_line_text,
            font_max_size-(i-1)*font_sub_size,
            4,
            math.floor(central_pos_x-4*(font_max_size-(i-1)*font_sub_size)/2),
            central_pos_y-vertical_space-(font_max_size-(i-1)*font_sub_size))


        -- 显示第二行文字
        -- 第一个参数为UTF8格式的文本
        -- 第二个参数为显示的字号
        -- 第三个参数固定为4
        -- 第四个参数为显示的左上角x坐标
        -- 第五个参数为显示的左上角y坐标
        lcd.drawGtfontUtf8Gray(second_line_text,
            font_max_size-(i-1)*font_sub_size,
            4,
            math.floor(central_pos_x-5*(font_max_size-(i-1)*font_sub_size)/2),
            central_pos_y+vertical_space)


        -- 刷屏，将缓冲区中的数据显示到lcd上
        lcd.flush()

        sys.wait(font_zoom_interval)
    end

    sys.wait(1000)
    sys.publish("OPEN_MAIN_MENU_WIN")
    
end

--创建并且启动一个task
--task的处理函数为welcome_win_task_func
sys.taskInit(welcome_win_task_func)

