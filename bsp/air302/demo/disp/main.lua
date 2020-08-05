

-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "dispdemo"
VERSION = "1.0.0"

-- sys库是标配
_G.sys = require("sys")

-- 网络灯
local NETLED = gpio.setup(19, 0)

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

    disp.drawStr("Luat@Air302" .. " " .. _VERSION, 1, 24) -- 写版本号
    if socket.isReady() then
        disp.drawStr("网络已经就绪", 1, 36) -- 写网络状态
    else
        disp.drawStr("网络未就绪", 1, 36)
    end
    --disp.drawStr("rssi: " .. tostring(nbiot.rssi()), 1, 36)

    disp.update()
end

-- 初始化显示屏
log.info("disp", "init ssd1306") -- log库是内置库,内置库均不需要require
disp.init({mode="i2c_sw", pin0=17, pin1=18}) -- 通过GPIO17 SLK/GPIO18 SDA模拟, 也可以用硬件i2c脚
disp.setFont(1) -- 启用中文字体,文泉驿点阵宋体 12x12
display_str("启动中 ...")

sys.taskInit(function()
    while 1 do
        sys.wait(1000)
        log.info("disp", "ui update", rtos.meminfo()) -- rtos是也是内置库
        ui_update()
    end
end)

sys.taskInit(function()
    while 1 do
        if socket.isReady() then
            NETLED(1)
            sys.wait(100)
            NETLED(0)
            sys.wait(1900)
        else
            NETLED(1)
            sys.wait(500)
            NETLED(0)
            sys.wait(500)
        end
    end
end)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
