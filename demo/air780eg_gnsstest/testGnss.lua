
-- libgnss库初始化
libgnss.clear() -- 清空数据,兼初始化

-- LED和ADC初始化
LED_GNSS = 24
gpio.setup(LED_GNSS, 0) -- GNSS定位成功灯

local gnss = require("uc6228")

sys.taskInit(function()
    log.debug("提醒", "室内无GNSS信号,定位不会成功, 要到空旷的室外,起码要看得到天空")
    gnss.setup({
        uart_id=2,
        uart_forward = uart.VUART_0, -- 转发到虚拟串口,方便对接GnssToolKit3
        debug=true
    })
    pm.power(pm.GPS, true)
    gnss.start()
    gnss.agps()
end)

sys.taskInit(function()
    while 1 do
        sys.wait(5000)
        -- log.info("RMC", json.encode(libgnss.getRmc(2) or {}, "7f"))
        -- log.info("INT", libgnss.getIntLocation())
        -- log.info("GGA", libgnss.getGga(3))
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
    local onoff = libgnss.isFix() and 1 or 0
    log.info("GNSS", "LED", onoff)
    gpio.set(LED_GNSS, onoff)
end)

