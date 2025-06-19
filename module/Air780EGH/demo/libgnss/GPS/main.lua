-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "Air780EGH_gnss"
VERSION = "1.0.0"

log.info("main", PROJECT, VERSION)

-- 引入必要的库文件(lua编写), 内部库不需要require
sys = require("sys")

if wdt then
    --添加硬狗防止程序卡死，在支持的设备上启用这个功能
    wdt.init(9000)--初始化watchdog设置为9s
    sys.timerLoopStart(wdt.feed, 3000)--3s喂一次狗
end
log.info("main", "Air780EGH_gnss")

mcu.hardfault(0)    --死机后停机，一般用于调试状态
local gps_uart_id = 2 -- 根据实际设备选取不同的uartid
uart.setup(gps_uart_id, 115200)

sys.taskInit(function()
    log.debug("提醒", "室内无GNSS信号,定位不会成功, 要到空旷的室外,起码要看得到天空")
    pm.power(pm.GPS, true) --打开GPS
    uart.setup(2,115200) --配置模组内部主芯片与GNSS芯片通信用UART的相关参数
    libgnss.bind(2) --马上开始解析NMEA格式数据
    libgnss.debug(true) --开发调试期可打开调试日志
end)


-- 订阅GNSS状态编码
sys.subscribe("GNSS_STATE", function(event, ticks)
    -- event取值有
    -- FIXED 定位成功
    -- LOSE  定位丢失
    -- ticks是事件发生的时间,一般可以忽略
    log.info("gnss", "state", event, ticks)
    if event == "FIXED" then
        local locStr = libgnss.locStr()
        log.info("gnss", "locStr", locStr)
        -- if locStr then
        --     -- 存入文件,方便下次AGNSS快速定位
        --     io.writeFile("/gnssloc", locStr)
        -- end
    end
end)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!