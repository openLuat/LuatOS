--- 模块功能：hzfont_demo
-- @module hzfont_demo
-- @author Tuo
-- @release 2025.12.23
-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "hzfont_demo"
VERSION = "1.0.0"

log.info("main", PROJECT, VERSION)

-- 添加硬狗防止程序卡死
if wdt then
    wdt.init(9000) -- 初始化watchdog设置为9s
    sys.timerLoopStart(wdt.feed, 3000) -- 3s喂一次狗
end

local lcd_use_buff = true -- 是否使用缓冲模式, 提升绘图效率，占用更大内存
local port, pin_reset, bl = lcd.RGB, 22, 23

-- Air1101开发板配套LCD屏幕 分辨率1024*600
log.info("lcdinit",lcd.init("custom", {
    port = port,
    hbp = 140,
    hspw = 20,
    hfp = 160,
    vbp = 20,
    vspw = 3,
    vfp = 12,
    bus_speed = 50 * 1000 * 1000,
    pin_pwr = bl,
    pin_rst = pin_reset,
    direction = 0,
    w = 1024,
    h = 600
}))

-- 如果显示颜色相反，请解开下面一行的注释，关闭反色
-- lcd.invoff()

-- 显示任务函数
local function display_task()
    -- 设置颜色，黑底白字，背景色:黑色(0x0000), 前景色:白色(0xFFFF)
    lcd.setColor(0x0000, 0xFFFF)
    
    -- 开启缓冲区, 刷屏速度会加快, 但也消耗2倍屏幕分辨率的内存
    lcd.setupBuff(nil, true) -- 使用sys内存, 只需要选一种
    lcd.autoFlush(false)
    
    -- 初始化hzfont字体
    hzfont.init()
    
    while true do
        -- 清屏（黑色背景）
        lcd.clear(0x0000)
        
        -- 显示项目信息
        log.info("合宙工业引擎 Air1101 - hzfont演示")
        
        -- 使用hzfont显示不同大小的文字
        -- 接口格式: lcd.drawHzfontUtf8(x, y, str, fontSize, [color], [antialias])
        
        -- 大标题 - 第一行下移
        lcd.drawHzfontUtf8(50, 80, "合宙LuatOS汉字字体演示", 48, 0xF800, 1)
        lcd.drawHzfontUtf8(50, 150, "合宙LuatOS汉字字体演示", 36, 0x07E0, 1)
        
        -- 项目信息
        lcd.drawHzfontUtf8(50, 210, "项目: " .. PROJECT, 32, 0xFFFF, 1)
        lcd.drawHzfontUtf8(50, 260, "版本: " .. VERSION, 32, 0xFFFF, 1)
        
        -- 屏幕信息
        lcd.drawHzfontUtf8(50, 320, "屏幕分辨率: 1024×600", 28, 0xFFE0, 1)
        lcd.drawHzfontUtf8(50, 370, "接口类型: RGB", 28, 0xFFE0, 1)
        
        -- 显示不同颜色的文字示例
        lcd.drawHzfontUtf8(50, 430, "红色文字 Red", 32, 0xF800, 1)
        lcd.drawHzfontUtf8(50, 480, "绿色文字 Green", 32, 0x07E0, 1)
        lcd.drawHzfontUtf8(50, 530, "蓝色文字 Blue", 32, 0x001F, 1)
        lcd.drawHzfontUtf8(50, 580, "黄色文字 Yellow", 32, 0xFFE0, 1)
        
        -- 显示当前时间
        local time_str = os.date("%Y-%m-%d %H:%M:%S")
        lcd.drawHzfontUtf8(50, 630, "当前时间: " .. time_str, 24, 0xFFFF, 1)
        
        -- 右侧显示不同大小的测试文字
        lcd.drawHzfontUtf8(600, 160, "字体大小测试", 20, 0xFD20, 1)
        lcd.drawHzfontUtf8(600, 200, "字体大小测试", 24, 0xFD20, 1)
        lcd.drawHzfontUtf8(600, 240, "字体大小测试", 28, 0xFD20, 1)
        lcd.drawHzfontUtf8(600, 290, "字体大小测试", 32, 0xFD20, 1)
        lcd.drawHzfontUtf8(600, 340, "字体大小测试", 36, 0xFD20, 1)
        lcd.drawHzfontUtf8(600, 390, "字体大小测试", 40, 0xFD20, 1)
        
        -- 显示中文长文本示例
        lcd.drawHzfontUtf8(600, 450, "合宙LuatOS是一个", 24, 0xFFFF, 1)
        lcd.drawHzfontUtf8(600, 480, "面向物联网设备的", 24, 0xFFFF, 1)
        lcd.drawHzfontUtf8(600, 510, "嵌入式脚本系统", 24, 0xFFFF, 1)
        lcd.drawHzfontUtf8(600, 540, "支持多种通信模块", 24, 0xFFFF, 1)
        lcd.drawHzfontUtf8(600, 570, "和丰富的API接口", 24, 0xFFFF, 1)
        
        if lcd_use_buff then
            lcd.flush()
        end
        sys.wait(1000)
    end
end

-- 启动显示任务
sys.taskInit(function()
    display_task()
end)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!