local sys = require("sys")

-- 项目信息,预留
PROJECT = "playit" -- W600 on LuatOS
VERSION = "1.0.0"
PRODUCT_KEY = "1234567890"

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


-- TODO: 用户按钮(PB7), 用于清除配网信息,重新airkiss

-- TODO: 联网更新脚本和底层(也许)

-- 主循环, 必须加
sys.run()
