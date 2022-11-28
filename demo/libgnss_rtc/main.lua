
-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "libgnssdemo"
VERSION = "1.0.0"

-- sys库是标配
_G.sys = require("sys")

--[[ 
demo适用于air530z, 演示挂载在uart 2的情况, 如果挂载在其他端口, 修改gps_uart_id
]]

local gps_uart_id = 2

uart.on(gps_uart_id, "recv", function(id, len)
    local data = uart.read(gps_uart_id, 1024)
     if data then
        libgnss.parse(data)
    end
end)

-- Air530Z默认波特率是9600, 主动切换一次
uart.setup(gps_uart_id, 9600)
uart.write(gps_uart_id, "$PCAS01,5*19\r\n")
uart.setup(gps_uart_id, 115200)

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
