-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "air8000_gnss"
VERSION = "1.0.0"

log.info("main", PROJECT, VERSION)

-- 引入必要的库文件(lua编写), 内部库不需要require
sys = require("sys")


-- mobile.flymode(0,true)
if wdt then
    --添加硬狗防止程序卡死，在支持的设备上启用这个功能
    wdt.init(9000)--初始化watchdog设置为9s
    sys.timerLoopStart(wdt.feed, 3000)--3s喂一次狗
end
log.info("main", "air8000_gnss")


mcu.hardfault(0)    --死机后停机，一般用于调试状态
pm.ioVol(pm.IOVOL_ALL_GPIO, 3300) -- 所有GPIO高电平输出3.0V
local gps_uart_id = 2 -- 根据实际设备选取不同的uartid
uart.setup(gps_uart_id, 115200)
-- libgnss.bind(gps_uart_id)-- 绑定uart, 马上开始解析GNSS数据
--打开或者关闭GNSS的函数，传1打开，传0关闭


sys.taskInit(function()
    log.info("GPS", "start")
    pm.power(pm.GPS, true)
    -- 绑定uart,底层自动处理GNSS数据
    -- 第二个参数是转发到虚拟UART, 方便上位机分析
    libgnss.bind(gps_uart_id, uart.VUART_0)
    sys.wait(200) -- GPNSS芯片启动需要时间
    -- 调试日志,可选
    libgnss.debug(true)
end)


sys.taskInit(function()
    while 1 do
        sys.wait(5000)
        log.info("RMC", json.encode(libgnss.getRmc(2) or {}, "7f"))         --解析后的rmc数据
        log.info("GGA", libgnss.getGga(3))                                   --解析后的gga数据
        -- log.info("GLL", json.encode(libgnss.getGll(2) or {}, "7f"))
        -- log.info("GSA", json.encode(libgnss.getGsa(1) or {}, "7f"))
        -- log.info("GSV", json.encode(libgnss.getGsv(2) or {}, "7f"))
        -- log.info("VTG", json.encode(libgnss.getVtg(2) or {}, "7f"))
        -- log.info("ZDA", json.encode(libgnss.getZda(2) or {}, "7f"))
        -- log.info("date", os.date())
        -- log.info("sys", rtos.meminfo("sys"))
        -- log.info("lua", rtos.meminfo("lua"))
    end
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
