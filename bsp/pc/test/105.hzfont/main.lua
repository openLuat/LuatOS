PROJECT = "lcddemo"
VERSION = "1.0.0"

log.info("main", PROJECT, VERSION)

taskName = "lcd"
local airlcd = require "airlcd"


show_picture = "/luadb/picture.jpg"

local function lcd_setup()
    sys.wait(500)
    gpio.setup(141, 1, gpio.PULLUP)              -- 如果是整机开发板则需要GPIO141打开给lcd电源供电，如果是核心板，可以自行选择供电管脚，或者直接选择vdd_ext管脚
    sys.wait(1000)
    airlcd.lcd_init("AirLCD_1000")
end

-- 定义字体文件路径
local FONT_PATHS = {
    "/sd/simhei.ttf",      -- SD卡路径
    "/sd/MiSans-regular_mini.ttf",       -- SD卡路径
    "/luadb/MiSans-regular-gb2312.ttf",        -- 当前目录
    "./arial.ttf",         -- 当前目录
    "C:/Windows/Fonts/simhei.ttf",  -- Windows系统字体
    "C:/Windows/Fonts/arial.ttf",   -- Windows系统字体
    "/System/Library/Fonts/PingFang.ttc",  -- macOS系统字体
    "/usr/share/fonts/truetype/noto/NotoSansCJK-Regular.ttc"  -- Linux系统字体
}

-- 查找可用的字体文件
local function find_font_file()
    for _, path in ipairs(FONT_PATHS) do
        local f = io.open(path, "rb")
        if f then
            f:close()
            log.info("main", "Found font file:", path)
            return path
        end
    end
    return nil
end


local function lcd_task()
    lcd_setup()                     -- 初始化LCD
    lcd.setupBuff(nil, true)        -- 设置缓冲区大小，使用系统内存
    lcd.autoFlush(false)            -- 自动刷新LCD

    -- -- 查找字体文件
    -- local font_path = find_font_file()
    -- if not font_path then
    --     log.error("main", "No font file found! Please place a TTF file in /sd/ or current directory")
    --     -- 显示错误信息
    --     lcd.clear(0x0000)
    --     lcd.setFont(lcd.font_opposansm12_chinese)
    --     lcd.drawStr(10, 30, "错误：未找到字体文件")
    --     lcd.drawStr(10, 50, "请将TTF字体文件放在:")
    --     lcd.drawStr(10, 70, "/sd/simhei.ttf")
    --     lcd.drawStr(10, 90, "或 ./simhei.ttf")
    --     lcd.flush()
    --     sys.wait(5000)
    --     return
    -- end
    
    -- -- 初始化HzFont
    -- log.info("main", "Initializing HzFont with:", font_path)
    -- if not hzfont.init(font_path) then
    --     log.error("main", "Failed to initialize HzFont")
    --     lcd.clear(0x0000)
    --     lcd.setFont(lcd.font_opposansm12_chinese)
    --     lcd.drawStr(10, 30, "错误：HzFont初始化失败")
    --     lcd.drawStr(10, 50, "字体文件: " .. font_path)
    --     lcd.flush()
    --     sys.wait(5000)
    --     return
    -- end

    log.info("main", "hzfont.init()")
    hzfont.init()
    hzfont.debug(false)
    
    log.info("main", "HzFont initialized successfully!")
    
    -- 测试用例
    local test_strings = {
        "Hello World!",
        "你好，世界！",
        "HzFont测试",
        "1234567890",
        "!@#$%^&*()",
        "中英文混合Mixed Text",
        "字体大小测试 Size Test"
    }
    
    local test_sizes = {12, 16, 20, 24, 32, 48}
    local colors = {0xFFFFFF, 0xFF0000, 0x00FF00, 0x0000FF, 0xFFFF00, 0xFF00FF, 0x00FFFF}
    
    local line_y = 20
    
    while true do
        lcd.clear()

        -- 设置背景色为白色，文字前景色为黑色
        lcd.setColor(0xFFFFFF, 0x0000)
        -- log.info("main", "hzfont.drawUtf8(10, 40, '字体测试', 32, 0x000000, 1)")
        lcd.drawHzfontUtf8(10, 40, "字体测试", 32, nil, 2)

        -- INSERT_YOUR_CODE
        -- local x = 10
        -- local y = 80
        -- for size = 12, 48, 2 do
        --     antialias = -1
        --     -- log.info("main", "hzfont.drawUtf8(x, y, string.format('大小：%d号 ABab', size), size, 0x000000, 4)")
        --     lcd.drawHzfontUtf8(x, y, string.format("大小：%d号 ABab", size), size, 0x000000, antialias)
        --     y = y + size + 4
        -- end
        
        lcd.drawHzfontUtf8(10, 80, "支持TTF, 各种语言 ", 24, 0x007700)

        lcd.drawHzfontUtf8(10, 110, "Hello, 世界! ごじゅうおん", 24, 0x000077)

        lcd.drawHzfontUtf8(10, 150, "大小演示: 16 32 48px", 16, 0x770000)

        lcd.drawHzfontUtf8(10, 180, "可以混合中文English!", 20, 0x880088)

        lcd.drawHzfontUtf8(10, 210, "Another Line Example", 20, 0x008888,4 )

        -- 各种符号
        lcd.drawHzfontUtf8(10, 260, "@#$%^&*()+-☆", 20, 0x008888,4 )

        lcd.flush()
        sys.wait(100)
    end
end


sysplus.taskInitEx(lcd_task, taskName)   




-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
