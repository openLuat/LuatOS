
-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "libgnssdemo"
VERSION = "1.0.0"

-- sys库是标配
_G.sys = require("sys")

uart.on(2, "recv", function(id, len)
    local data = uart.read(2, 1024)
    --log.info("uart2", data)
    libgnss.parse(data)
end)
uart.setup(2, 9600)

sys.timerLoopStart(function()
    log.info("GPS", libgnss.getIntLocation())
    local rmc = libgnss.getRmc()
    log.info("rmc", json.encode(rmc))
    --log.info("rmc", rmc.lat, rmc.lng, rmc.year, rmc.month, rmc.day, rmc.hour, rmc.min, rmc.sec)
    rtc.set({year=rmc.year,mon=rmc.month,day=rmc.day,hour=rmc.hour,min=rmc.min,sec=rmc.sec})
end, 3000) -- 两秒打印一次

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
