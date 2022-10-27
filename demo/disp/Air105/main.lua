

-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "dispdemo"
VERSION = "1.0.0"

log.info("main", PROJECT, VERSION)

-- sys库是标配
_G.sys = require("sys")

--[[
硬件接线

I2C屏幕                Air105开发板
SCL                    (PE7)
SDA                    (PE6)
VCC                    3.3V
GND                    GND
]]

--添加硬狗防止程序卡死
if wdt then
    wdt.init(9000)--初始化watchdog设置为9s
    sys.timerLoopStart(wdt.feed, 3000)--3s喂一次狗
end

----------------------------------------------------------------------
-- 对接SSD1306
function display_str(str)
    disp.clear()
    disp.drawStr(str, 1, 18)
    disp.update()
end

function ui_update()
    disp.clear() -- 清屏

    disp.drawStr(os.date("%Y-%m-%d %H:%M:%S"), 1, 12) -- 写日期

    disp.drawStr("Luat@Air101" .. " " .. _VERSION, 1, 24) -- 写版本号

    disp.update()
end

-- 初始化显示屏
log.info("disp", "init ssd1306") -- log库是内置库,内置库均不需要require
disp.init({mode="i2c_sw", pin0=1, pin1=4}) -- 通过PA1 SLK/PA4 SDA模拟, 也可以用硬件i2c脚
disp.setFont(1) -- 启用中文字体,文泉驿点阵宋体 12x12
display_str("启动中 ...")

sys.taskInit(function()
    while 1 do
        sys.wait(1000)
        log.info("disp", "ui update", rtos.meminfo()) -- rtos是也是内置库
        ui_update()
    end
end)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
