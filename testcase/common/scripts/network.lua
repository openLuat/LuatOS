local ctx_path = "/luadb/ctx.json"


if mobile then
    -- 什么都不做
elseif wlan and wlan.init then
    local data = io.readFile(ctx_path)
    local t_data = json.decode(data)
    local ssid = t_data.wifi_ssid
    local password = t_data.wifi_password
    wlan.init()
    wlan.setMode(wlan.STATION) -- 默认也是这个模式,不调用也可以
    wlan.connect(ssid, password, 1)
elseif w5500 then
    w5500.init(spi.HSPI_0, 24000000, pin.PC14, pin.PC01, pin.PC00)
    w5500.config() -- 默认是DHCP模式
    w5500.bind(socket.ETH0)
elseif socket then
    -- 适配了socket库也OK, 就当1秒联网吧
    sys.timerStart(sys.publish, 1000, "IP_READY")
end
