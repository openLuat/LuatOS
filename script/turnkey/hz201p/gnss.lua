local uartId = 2
libgnss.clear() -- 清空数据,兼初始化
uart.setup(uartId, 115200)



sys.taskInit(function()
    log.info("GPS", "start")
    gpio.setup(27, 1)
    libgnss.bind(uartId)
    sys.wait(200) -- GPNSS芯片启动需要时间
    -- 调试日志,可选
    libgnss.debug(true)
end)

sys.taskInit(function()
    while 1 do
        sys.wait(5000)
        -- uart.write(uartId, "$CFGSYS\r\n")
        -- uart.write(uartId, "$CFGMSG,6,4\r\n")
        log.info("RMC", json.encode(libgnss.getRmc(2) or {}))
        -- log.info("GGA", libgnss.getGga(3))
        -- log.info("GLL", json.encode(libgnss.getGll(2) or {}))
        -- log.info("GSA", json.encode(libgnss.getGsa(2) or {}))
        -- log.info("GSV", json.encode(libgnss.getGsv(2) or {}))
        -- log.info("VTG", json.encode(libgnss.getVtg(2) or {}))
        -- log.info("ZDA", json.encode(libgnss.getZda(2) or {}))
        -- log.info("date", os.date())
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
        if locStr then
            io.writeFile("/gnssloc", locStr)
        end
    end
end)

