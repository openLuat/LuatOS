
sys.taskInit(function()
    -----------------------------
    -- 统一联网函数, 可自行删减
    ----------------------------
    if wlan and wlan.connect then
        -- wifi 联网, 带 wlan 模块的模组均支持
        local ssid = "luatos1234"
        local password = "12341234"
        log.info("wifi", ssid, password)
        -- TODO 改成esptouch配网
        -- LED = gpio.setup(12, 0, gpio.PULLUP)
        wlan.init()
        wlan.setMode(wlan.STATION)
        wlan.connect(ssid, password, 1)
        local result, data = sys.waitUntil("IP_READY", 30000)
        log.info("wlan", "IP_READY", result, data)
        device_id = wlan.getMac()
    elseif mobile then
        -- Air780E/Air600E系列
        --mobile.simid(2)
        -- LED = gpio.setup(27, 0, gpio.PULLUP)
        device_id = mobile.imei()
        log.info("ipv6", mobile.ipv6(true))
        sys.waitUntil("IP_READY", 30000)
    elseif http then
        sys.waitUntil("IP_READY")
    else
        while 1 do
            sys.wait(1000)
            log.info("http", "当前固件未包含http库")
        end
    end
    log.info("已联网")
    sys.publish("net_ready")
end)