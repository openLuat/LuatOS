--[[
@module  wifi_scan
@summary wifi_scan模块 
@version 1.0
@date    2025.10.20
@author  魏健强
@usage 本文为wifi扫描功能模块,核心逻辑为
1、开启WiFi扫描；
2、打印扫描结果；

本文件没有对外接口，直接在其他功能模块中require "wifi_scan"就可以加载运行；
]] 
local scan_result = {}

wlan.init()
function test_scan()
    while true do
        log.info("10秒后执行wifi扫描")
        sys.wait(10 * 1000)
        wlan.scan()
    end
end

function scan_done_handle()
    local result = wlan.scanResult()
    for k,v in pairs(result) do
        log.info("scan", (v["ssid"] and #v["ssid"] > 0) and v["ssid"] or "[隐藏SSID]", v["rssi"], (v["bssid"]:toHex()))
        if v["ssid"] and #v["ssid"] > 0 then
            table.insert(scan_result, v["ssid"])
        end
    end
    log.info("scan", "aplist", json.encode(scan_result))
end


sys.subscribe("WLAN_SCAN_DONE", scan_done_handle)

sys.taskInit(test_scan)