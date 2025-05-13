--- 模块功能：lcddemo
-- @module lcd
-- @author Tuo
-- @release 2021.02.12
-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "lcddemo"
VERSION = "1.0.0"

log.info("main", PROJECT, VERSION)

-- sys库是标配
_G.sys = require("sys")

-- 添加硬狗防止程序卡死
if wdt then
    wdt.init(9000) -- 初始化watchdog设置为9s
    sys.timerLoopStart(wdt.feed, 3000) -- 3s喂一次狗
end

local lcd_use_buff = true -- 是否使用缓冲模式, 提升绘图效率，占用更大内存
local port, pin_reset, bl = lcd.RGB, 36, 25

-- Air8101开发板配套LCD屏幕 分辨率800*480 
lcd.init("h050iwv", {
    port = port,
    pin_dc = 0xff,
    pin_pwr = bl,
    pin_rst = pin_reset,
    direction = 0,
    w = 800,
    h = 480,
    xoffset = 0,
    yoffset = 0
})

-- Air8101开发板配套LCD屏幕 分辨率1024*600 
-- lcd.init("hx8282",
--         {port = port,pin_pwr = bl, pin_rst = pin_reset,
--         direction = 0,w = 1024,h = 600,xoffset = 0,yoffset = 0})

-- Air8101开发板配套LCD屏幕 分辨率720*1280
-- lcd.init("nv3052c",
--         {port = port,pin_pwr = bl, pin_rst = pin_reset,
--         direction = 0,w = 720,h = 1280,xoffset = 0,yoffset = 0})

-- Air8101开发板配套LCD屏幕 分辨率480*854
-- lcd.init("st7701sn",
--         {port = port,pin_pwr = bl, pin_rst = pin_reset,
--         direction = 0,w = 480,h = 854,xoffset = 0,yoffset = 0})

-- 如果显示颜色相反，请解开下面一行的注释，关闭反色
-- lcd.invoff()

sys.taskInit(function()
    -- 开启缓冲区, 刷屏速度会加快, 但也消耗2倍屏幕分辨率的内存
    lcd.setupBuff(nil, true) -- 使用sys内存, 只需要选一种
    lcd.autoFlush(false)
    while 1 do
        lcd.clear()
        log.info("合宙工业引擎 Air8101")
        if lcd.showImage then
            -- 注意, jpg需要是常规格式, 不能是渐进式JPG
            -- 如果无法解码, 可以用画图工具另存为,新文件就能解码了
            lcd.showImage(0, 0, "/luadb/picture1.jpg") --lcd屏幕分辨率800*480
            -- lcd.showImage(0, 0, "/luadb/picture2.jpg") --lcd屏幕分辨率1024*600
            -- lcd.showImage(0, 0, "/luadb/picture3.jpg") --lcd屏幕分辨率720*1280
            -- lcd.showImage(0, 0, "/luadb/picture4.jpg") --lcd屏幕分辨率480*854
            sys.wait(100)
        end
        -- log.info("lcd.drawLine", lcd.drawLine(20, 20, 150, 20, 0x001F)) --在屏幕两点之间画一条线
        -- log.info("lcd.drawRectangle", lcd.drawRectangle(20, 40, 120, 70, 0xF800)) --从屏幕左上边缘开始绘制一个框
        -- log.info("lcd.drawCircle", lcd.drawCircle(50, 50, 20, 0x0CE0)) --从圆心开始绘制一个圆

        if lcd_use_buff then
            lcd.flush()
        end
        sys.wait(1000)
    end
end)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
