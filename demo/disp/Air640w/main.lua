-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "dispdemo"
VERSION = "1.0.0"

-- 引入必要的库文件(lua编写), 内部库不需要require
local sys = require "sys"

-- 日志TAG, 非必须
local TAG = "main"
local last_temp_data = "0"

sys.subscribe("WLAN_READY", function ()
    print("!!! wlan ready event !!!")
    -- 马上进行时间同步
    socket.ntpSync()
end)

----------------------------------------------------------------------
-- 对接SSD1306, 当前显示一行就好了
function display_str(str)
    disp.clear()
    disp.drawStr(str, 1, 18)
    disp.update()
end

function ui_update()
    disp.clear()

    disp.drawStr(os.date(), 1, 12)

    disp.drawStr("Temp: " .. last_temp_data, 1, 24)
    disp.drawStr("rssi: " .. tostring(wlan.rssi()), 1, 36)

    disp.update()
end

-- 初始化显示屏
log.info(TAG, "init ssd1306")
disp.init({mode="i2c_sw", pin0=18, pin1=19})
display_str("Booting ...")

sys.taskInit(function()
    while 1 do
        sys.wait(1000)
        log.info("disp", "hi, ui update now")
        ui_update()
    end
end)


-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
