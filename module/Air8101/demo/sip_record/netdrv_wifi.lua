local exnetif = require "exnetif"

local netdrv_wifi = {}
local started = false

local function validate(config)
    if type(config) ~= "table" or type(config.ssid) ~= "string" or config.ssid == "" or
        config.ssid == "replace-with-your-2.4g-ssid" then
        return false, "请在 config.lua 中填写2.4GHz Wi-Fi名称"
    end
    if type(config.password) ~= "string" or config.password == "replace-with-your-wifi-password" then
        return false, "请在 config.lua 中填写Wi-Fi密码"
    end
    return true
end

function netdrv_wifi.start(config)
    local ok, err = validate(config)
    if not ok then
        log.error("sip_record.net", err)
        return false
    end
    if started then
        return true
    end
    started = true

    sys.subscribe("IP_READY", function(ip, adapter)
        if adapter == socket.LWIP_STA then
            if config.dns1 then socket.setDNS(adapter, 1, config.dns1) end
            if config.dns2 then socket.setDNS(adapter, 2, config.dns2) end
            log.info("sip_record.net", "IP_READY", ip or socket.localIP(adapter))
        end
    end)
    sys.subscribe("IP_LOSE", function(adapter)
        if adapter == socket.LWIP_STA then
            log.warn("sip_record.net", "IP_LOSE")
        end
    end)
    sys.subscribe("WLAN_STA_INC", function(event, data)
        log.info("sip_record.net", "WLAN_STA_INC", event, data)
    end)

    sys.taskInit(function()
        exnetif.set_priority_order({{
            WIFI = {
                ssid = config.ssid,
                password = config.password
            }
        }})
    end)
    return true
end

return netdrv_wifi
