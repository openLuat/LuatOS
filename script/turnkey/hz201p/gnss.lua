sys.taskInit(function()
    log.info("GPS", "start")
    -- gnss的复位
    local gpsRst = gpio.setup(27, 1)

    local uartId = 2
    libgnss.clear() -- 清空数据,兼初始化
    uart.setup(uartId, 115200)

    sys.wait(200) -- GPNSS芯片启动需要时间
    -- 调试日志,可选
    --libgnss.debug(true)
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

--基站定位数据
local latLbs, lngLbs, typeLbs

sys.timerLoopStart(function ()
    local isFixed = libgnss.isFix()
    if isFixed then--优先使用gps数据
        local loc = libgnss.getRmc(2)
        attributes.set("isFixed", "已定位")
        attributes.set("lat", tostring(loc.lat))
        attributes.set("lng", tostring(loc.lng))
        attributes.set("location", {
            lat = loc.lat,
            lng = loc.lng,
        })
    elseif latLbs and lngLbs then
        attributes.set("isFixed", typeLbs)
        attributes.set("lat", tostring(latLbs))
        attributes.set("lng", tostring(lngLbs))
        attributes.set("location", {
            lat = tonumber(latLbs),
            lng = tonumber(lngLbs),
        })
    else
        attributes.set("isFixed", "获取中")
        attributes.set("lat", "无数据")
        attributes.set("lng", "无数据")
    end
end,3000)


local lbsLoc = require("lbsLoc")

local function getLocCb(result, lat, lng, addr, time, locType)
    log.info("testLbsLoc.getLocCb", result, lat, lng)
    -- 基站定位获取经纬度成功
    if result == 0 then
        latLbs, lngLbs = lat, lng
        typeLbs = locType == 0 and "基站定位" or "WIFI定位"
    end
end

sys.taskInit(function()
    sys.waitUntil("IP_READY", 30000)
    while mobile do -- 没有mobile库就没有基站定位
        --基站定位信息
        mobile.reqCellInfo(15)
        sys.waitUntil("CELL_INFO_UPDATE", 3000)
        --wifi定位信息
        wlan.scan()
        local reqWifi
        local r = sys.waitUntil("WLAN_SCAN_DONE", 60000)
        if r then
            local results = wlan.scanResult()
            log.info("wifi scan", "count", #results)
            if #results > 0 then
                local reqWifi = {}
                for k,v in pairs(results) do
                    log.info("scan", v["ssid"], v["rssi"], v["bssid"]:toHex())
                    local bssid = v["bssid"]:toHex()
                    bssid = string.format ("%s:%s:%s:%s:%s:%s", bssid:sub(1,2), bssid:sub(3,4), bssid:sub(5,6), bssid:sub(7,8), bssid:sub(9,10), bssid:sub(11,12))
                    reqWifi[bssid]=v["rssi"]
                end
            end
        end
        if not libgnss.isFix() then--没定位成功再去获取
            lbsLoc.request(getLocCb,nil,nil,nil,nil,nil,nil,reqWifi)
        end
        sys.wait(60000)
    end
end)
