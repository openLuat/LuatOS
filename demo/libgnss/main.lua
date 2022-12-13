
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

-- sys.timerLoopStart(function()
--     log.info("GPS", libgnss.getIntLocation())
--     local rmc = libgnss.getRmc()
--     log.info("rmc", json.encode(rmc))
--     --log.info("rmc", rmc.lat, rmc.lng, rmc.year, rmc.month, rmc.day, rmc.hour, rmc.min, rmc.sec)
--     rtc.set({year=rmc.year,mon=rmc.month,day=rmc.day,hour=rmc.hour,min=rmc.min,sec=rmc.sec})
-- end, 3000) -- 两秒打印一次

sys.taskInit(function()
    sys.wait(3000)
    -- libgnss.parse("$GNGGA,220134.000,2232.12578,N,11356.85838,E,1,08,1.7,33.1,M,-3.4,M,,*67\r\n")
    -- libgnss.parse("$GNGLL,2232.12578,N,11356.85838,E,220134.000,A,A*47\r\n")
    -- libgnss.parse("$GNGSA,A,3,10,22,31,32,194,,,,,,,,2.7,1.7,2.1,1*0F\r\n")
    -- libgnss.parse("$GNGSA,A,3,06,21,36,,,,,,,,,,2.7,1.7,2.1,4*34\r\n")
    libgnss.parse("$GPGSV,2,1,07,03,,,31,10,28,174,18,22,62,017,33,25,,,29,0*6E\r\n")
    libgnss.parse("$GPGSV,2,2,07,31,51,343,38,32,63,069,42,194,65,061,37,0*6A\r\n")
    -- libgnss.parse("$BDGSV,2,1,07,04,,,33,06,55,003,34,19,05,147,09,21,66,307,42,0*41\r\n")
    -- libgnss.parse("$BDGSV,2,2,07,22,55,157,,36,16,045,30,39,,,40,0*7E\r\n")
    -- libgnss.parse("$GNRMC,220134.000,A,2232.12578,N,11356.85838,E,0.06,0.00,120422,,,A,V*0B\r\n")
    -- libgnss.parse("$GNVTG,0.00,T,,M,0.06,N,0.12,K,A*26\r\n")
    -- libgnss.parse("$GNZDA,220134.000,12,04,2022,00,00*4B\r\n")
    -- libgnss.parse("$GPTXT,01,01,01,ANTENNA OK*35\r\n")
    -----------------------------------------------------------------------------------------
    local gsv = libgnss.getGsv()
    log.info("---gsv", json.encode(gsv))
end)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
