sys.taskInit(function()
    log.info("GPS", "start")
    -- gnss的复位
    local gpsRst = gpio.setup(27, 1)

    local uartId = 2
    libgnss.clear() -- 清空数据,兼初始化
    uart.setup(uartId, 115200)

    sys.wait(200) -- GPNSS芯片启动需要时间
    -- 调试日志,可选
    libgnss.debug(true)
    libgnss.bind(2)
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
    elseif event == "LOSE" then
        log.info("gnss", "no fix")
    end
end)


sys.timerLoopStart(function ()
    local isFixed = libgnss.isFix()
    attributes.set("isFixed", isFixed and "已定位" or "获取中")
    if isFixed then
        local loc = libgnss.getRmc(2)
        attributes.set("lat", tostring(loc.lat))
        attributes.set("lng", tostring(loc.lng))
        attributes.set("location", {
            lat = loc.lat,
            lng = loc.lng,
        })
    else
        attributes.set("lat", "无数据")
        attributes.set("lng", "无数据")
    end
end,3000)
