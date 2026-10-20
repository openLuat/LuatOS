--[[
@module  prod_wifi
@summary 产测项 WIFI_TEST#：WiFi 扫描（顺带验证板载天线链路）
@usage   WIFI_TEST#
@return  string —— 成功回扫描到的 AP 数量，失败回 "ERROR"
说明：只判"能扫到 AP"，不判信号强弱、不连接；扫描结果经 "WLAN_SCAN_DONE" 消息返回。
]]

local TIMEOUT_MS = 15000

return function(arg)
    wlan.init()
    sys.wait(500)

    wlan.scan()
    local got = sys.waitUntil("WLAN_SCAN_DONE", TIMEOUT_MS)
    if not got then
        log.error("prod_wifi", "扫描超时，未收到 WLAN_SCAN_DONE")
        return "ERROR"
    end

    local result = wlan.scanResult() or {}
    local count = 0
    for _ in pairs(result) do
        count = count + 1
    end

    log.info("prod_wifi", "扫描到", count, "个 AP")
    if count == 0 then
        log.error("prod_wifi", "未扫描到任何 AP（查板载天线）")
        return "ERROR"
    end
    return tostring(count)
end
