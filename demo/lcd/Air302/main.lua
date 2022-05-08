--- 模块功能：lcddemo
-- @module lcd
-- @author Dozingfiretruck
-- @release 2021.01.25

-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "lcddemo"
VERSION = "1.0.0"

log.info("main", PROJECT, VERSION)

-- sys库是标配
_G.sys = require("sys")

--添加硬狗防止程序卡死
if wdt then
    wdt.init(15000)--初始化watchdog设置为15s
    sys.timerLoopStart(wdt.feed, 10000)--10s喂一次狗
end

local result = spi.setup(
    0,--串口id
    16,
    0,--CPHA
    0,--CPOL
    8,--数据宽度
    10*1000*1000--,--频率
)

lcd.init("st7735",{port = 0,pin_dc = 17,pin_rst = 18,direction = 0,w = 128,h = 160,xoffset = 0,yoffset = 0})

sys.taskInit(function()
    sys.wait(1000)
    -- API 文档 https://wiki.luatos.com/api/lcd.html
        log.info("lcd.drawLine", lcd.drawLine(20,20,150,20,0x001F))
        log.info("lcd.drawRectangle", lcd.drawRectangle(20,40,120,70,0xF800))
        log.info("lcd.drawCircle", lcd.drawCircle(50,50,20,0x0CE0))
    -- end
end)


-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
