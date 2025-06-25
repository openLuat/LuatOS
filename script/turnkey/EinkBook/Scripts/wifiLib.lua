local wifiConnect = {}

function wifiConnect.connect(ssid, passwd)
    local waitRes, data
    if wlan.init() ~= 0 then
        log.error(tag .. ".init", "ERROR")
        return false
    end
    if wlan.setMode(wlan.STATION) ~= 0 then
        log.error(tag .. ".setMode", "ERROR")
        return false
    end

    if USE_SMARTCONFIG == true then
        if wlan.smartconfig() ~= 0 then
            log.error(tag .. ".connect", "ERROR")
            return false
        end
        waitRes, data = sys.waitUntil("WLAN_STA_CONNECTED", 180 * 10000)
        log.info("WLAN_STA_CONNECTED", waitRes, data)
        if waitRes ~= true then
            log.error(tag .. ".wlan ERROR")
            return false
        end
        waitRes, data = sys.waitUntil("IP_READY", 10000)
        if waitRes ~= true then
            log.error(tag .. ".wlan ERROR")
            return false
        end
        log.info("IP_READY", waitRes, data)
        return true
    end

    if wlan.connect(ssid, passwd) ~= 0 then
        log.error(tag .. ".connect", "ERROR")
        return false
    end
    waitRes, data = sys.waitUntil("WLAN_STA_CONNECTED", 10000)
    if waitRes ~= true then
        log.error(tag .. ".wlan ERROR")
        return false
    end
    log.info("WLAN_STA_CONNECTED", waitRes, data)
    waitRes, data = sys.waitUntil("IP_READY", 10000)
    if waitRes ~= true then
        log.error(tag .. ".wlan ERROR")
        return false
    end
    log.info("IP_READY", waitRes, data)
    return true
end

return wifiConnect
