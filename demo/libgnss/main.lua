-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "gnss"
VERSION = "1.0.0"

--[[
本demo是演示定位数据处理的
]]

-- sys库是标配
local sys = require("sys")
require("sysplus")

local gps_uart_id = 2
libgnss.clear() -- 清空数据,兼初始化

sys.taskInit(function()
    -- Air780EG工程样品的GPS的默认波特率是9600, 量产版是115200,以下是临时代码
    log.info("GPS", "start")
    pm.power(pm.GPS, true)
    uart.setup(gps_uart_id, 115200)
    libgnss.bind(gps_uart_id) -- 绑定uart,底层自动处理GNSS数据
    sys.wait(200) -- GPNSS芯片启动需要时间
    -- 调试日志,可选
    libgnss.debug(true)
    -- 增加显示的语句
    uart.write(gps_uart_id, "$CFGMSG,0,1,1\r\n") -- GLL
    sys.wait(10)
    uart.write(gps_uart_id, "$CFGMSG,0,5,1\r\n") -- VTG
    -- 定位成功后,使用GNSS时间设置RTC, 暂不可用
    -- libgnss.rtcAuto(true)
    -- 读取之前的位置信息
    local gnssloc = io.readFile("/gnssloc")
    if gnssloc then
        uart.write(gps_uart_id, "$AIDPOS," .. gnssloc .. "\r\n")
        gnssloc = nil
    end
    sys.wait(100)
    if http then
        -- TODO AGNSS 未调通
        -- while 1 do
        --     local code, headers, body = http.request("GET", "http://download.openluat.com/9501-xingli/HXXT_GPS_BDS_AGNSS_DATA.dat").wait()
        --     -- local code, headers, body = http.request("GET", "http://nutzam.com/6228.bin").wait()
        --     log.info("gnss", "AGNSS", code, body and #body or 0)
        --     if code == 200 and body and #body > 1024 then
        --         for offset=1,#body,1024 do
        --             log.info("gnss", "AGNSS", "write >>>")
        --             uart.write(gps_uart_id, body:sub(offset, 1024))
        --             sys.wait(5)
        --         end
        --         io.writeFile("/6228.bin", body)
        --         break
        --     end
        --     sys.wait(60*1000)
        -- end
    end
end)

sys.timerLoopStart(function()
    -- 6228CI, 查询产品信息, 可选
    -- uart.write(gps_uart_id, "$PDTINFO,*62\r\n")
    -- uart.write(gps_uart_id, "$AIDINFO\r\n")
    -- uart.write(gps_uart_id, "$CFGSYS\r\n")
    -- uart.write(gps_uart_id, "$CFGMSG,6,4\r\n")
    log.info("RMC", json.encode(libgnss.getRmc(2) or {}))
    -- log.info("GGA", json.encode(libgnss.getGga(2) or {}))
    -- log.info("GLL", json.encode(libgnss.getGll(2) or {}))
    -- log.info("GSA", json.encode(libgnss.getGsa(2) or {}))
    -- log.info("GSV", json.encode(libgnss.getGsv(2) or {}))
    -- log.info("VTG", json.encode(libgnss.getVtg(2) or {}))
    -- log.info("date", os.date())
    log.info("sys", rtos.meminfo("sys"))
    log.info("lua", rtos.meminfo("lua"))
end, 5000)

-- 订阅GNSS状态编码
sys.subscribe("GNSS_STATE", function(event, ticks)
    -- event取值有 
    -- FIXED 定位成功
    -- LOSE  定位丢失
    -- ticks是事件发生的时间,一般可以忽略
    log.info("gnss", "state", event, ticks)
    if event == "FIXED" then
        local locStr = libgnss.locStr()
        log.info("gnss", "pre loc", locStr)
        if locStr then
            io.writeFile("/gnssloc", locStr)
        end
    end
end)

sys.subscribe("NTP_UPDATE", function()
    if not libgnss.isFix() then
        -- "$AIDTIME,year,month,day,hour,minute,second,millisecond"
        local date = os.date("!*t")
        local str = string.format("$AIDTIME,%d,%d,%d,%d,%d,%d,000", 
                             date["year"], date["month"], date["day"], date["hour"], date["min"], date["sec"])
        log.info("gnss", str)
        uart.write(gps_uart_id, str .. "\r\n")
    end
end)

if socket and socket.sntp then
    sys.subscribe("IP_READY", function()
    socket.sntp()
    end)
end

-- 定期重启GPS, 测试AGNSS
-- sys.taskInit(function()
--     while 1 do
--         sys.wait(120 * 1000)
--         log.info("GPS", "stop")
--         pm.power(pm.GPS, false)
--         pm.power(pm.GPS_ANT, false)
--         sys.wait(500)
--         log.info("GPS", "start")
--         pm.power(pm.GPS, true)
--         pm.power(pm.GPS_ANT, true)
--         sys.wait(300) -- 输出产品日志大概是150ms左右,这里延时一下
--         -- 写入时间
--         local date = os.date("!*t")
--         if date["year"] > 2021 then
--             local str = string.format("$AIDTIME,%d,%d,%d,%d,%d,%d,000", 
--                              date["year"], date["month"], date["day"], date["hour"], date["min"], date["sec"])
--             log.info("gnss", str)
--             uart.write(gps_uart_id, str .. "\r\n")
--         end
--         -- 读取并写入辅助坐标
--         local gnssloc = io.readFile("/gnssloc")
--         if gnssloc then
--             uart.write(gps_uart_id, "$AIDPOS," .. gnssloc .. "\r\n")
--             gnssloc = nil
--         end
--         -- 写入星历
--         local body = io.readFile("/6228.bin")
--         if body then
--             for offset=1,#body,1024 do
--                 log.info("gnss", "AGNSS", "write >>>")
--                 uart.write(gps_uart_id, body:sub(offset, 1024))
--                 sys.wait(5)
--             end
--         end
--         log.info("AGNSS", "write complete")
--         -- 查询一下辅助定位成功没
--         sys.wait(300)
--         uart.write(gps_uart_id, "$AIDINFO\r\n")
--     end

-- end)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
