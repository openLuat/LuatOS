local ctx_path = "/luadb/ctx.json"

local netready = {}

function netready.exec(ctx, timeout)
    -- 应该 根据 型号和上下文, 进行联网操作
    if mobile then
        -- 什么都不做
        log.info("netready", "使用移动网络，无需初始化")
    elseif wlan and wlan.init then
        log.info("netready", "使用 WiFi 网络，开始初始化")
        local ssid = ctx.wifi_ssid
        local password = ctx.wifi_password
        wlan.init()
        wlan.setMode(wlan.STATION) -- 默认也是这个模式,不调用也可以
        wlan.connect(ssid, password, 1)
    elseif socket then
        -- 适配了socket库也OK, 就当1秒联网吧
        sys.timerStart(sys.publish, 1000, "IP_READY")
    end
end

function netready.deinit()
    if mobile then
        mobile.flymode(0, true)
        log.info("netready", "使用移动网络，进入飞行模式")
    elseif wlan and wlan.disconnect then
        log.info("netready", "断开 WiFi 连接")
        wlan.disconnect()
    end
end

return netready
