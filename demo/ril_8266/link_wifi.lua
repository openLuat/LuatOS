local link = {}

local connected, connecting, stopConfig, recvId

function link.isReady()
    return connected
end

function link.shut()
    log.info("link_wifi", "shut")
end

link.getRecvId = function() return recvId end

local errorNum = 0
local function wifiUrc(data, prefix)
    log.info("urc上报", data, prefix)
    if prefix == "STATUS" then
        if not connecting or not connected then
            local state = data:sub(8, -1)
            if state == "0" or state == "1" or state == "5" then
                errorNum = errorNum + 1
                if errorNum > 5 then
                    ril_wifi.request("AT+CWMODE=1")
                    ril_wifi.request("AT+CWSTARTSMART=3")
                else
                    point("later")
                    sys.timerStart(ril_wifi.request, 5000, "AT+CIPSTATUS")
                end
            elseif state == "2" then
                errorNum = 0
                connected = true
                sys.publish("IP_READY_IND")
                return
            end
        end
    elseif prefix == "WIFI GOT IP" then
        connecting = false
        connected = true
        sys.publish("IP_READY_IND")
        return
    elseif prefix == "WIFI CONNECTED" then
        connecting = true
        return
    elseif prefix == "Smart get wifi info" then
        stopConfig = sys.timerStart(ril_wifi.request, 20000, "AT+CWSTOPSMART")
        return
    elseif prefix == "smartconfig connected wifi" then
        connecting = true
        if sys.timerIsActive(stopConfig) then sys.timerStop(stopConfig) end
        ril_wifi.request("AT+CWSTOPSMART", nil, nil, 6000)
    elseif prefix == "+IPD" then
        log.info("rcv data", data)
        local lid, dataLen = string.match(data, "%+IPD,(%d),(%d+)")
        recvId = lid
        ril_wifi.request(string.format("AT+CIPRECVDATA=%d,%d", lid, dataLen))
    elseif prefix == "+CIPRECVLEN" then
        log.info("rcv test", prefix, data)
        local lid = {string.match(data, "%+CIPRECVLEN:(.+),(.+),(.+),(.+),(.+)")}
        for k, v in pairs(lid) do
            if v ~= "-1" and v ~= "0" then
                ril_wifi.request(string.format("AT+CIPRECVDATA=%d,%d", k - 1, 2147483647))
            end
        end
    end
end

local function wifiRsp(cmd, success, response, intermediate)
    log.info("wifi", cmd, success, response, intermediate)
    if cmd == "AT+CWSTARTSMART=3" then
        if success then smartConfig = true end
    elseif cmd == "AT+CWSTOPSMART" then
        if connecting then
            connecting = false
            connected = true
            sys.publish("IP_READY_IND")
        else
            sys.timerStart(ril_wifi.request, 2000, "AT+CWSTARTSMART=3")
        end
    end
end

ril_wifi.regUrc("+IPD", wifiUrc)
ril_wifi.regUrc("STATUS", wifiUrc)
ril_wifi.regUrc("WIFI GOT IP", wifiUrc)
ril_wifi.regUrc("WIFI CONNECTED", wifiUrc)
ril_wifi.regUrc("smartconfig connected wifi", wifiUrc)
ril_wifi.regUrc("Smart get wifi info", wifiUrc)
ril_wifi.regRsp("+CWSTARTSMART", wifiRsp)
ril_wifi.regRsp("+CWSTOPSMART", wifiRsp)
ril_wifi.regUrc("+CIPRECVLEN", wifiUrc)

ril_wifi.request("AT+CIPRECVMODE=1")
ril_wifi.request("AT+CIPMODE=0")
ril_wifi.request("AT+CIPMUX=1")
ril_wifi.request("AT+CIPSTATUS")

return link
