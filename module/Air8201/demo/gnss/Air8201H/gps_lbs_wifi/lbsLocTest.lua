
local sys = require "sys"
local lbsLoc = require("lbsLoc")

local lbsLocTest = {}
-- **********以下为基站+wifi混合定位*****************

-- 功能:获取基站对应的经纬度后的回调函数
-- 参数:-- result：number类型，0表示成功，1表示网络环境尚未就绪，2表示连接服务器失败，3表示发送数据失败，4表示接收服务器应答超时，5表示服务器返回查询失败；为0时，后面的5个参数才有意义
-- lat：string类型，纬度，整数部分3位，小数部分7位，例如031.2425864
-- lng：string类型，经度，整数部分3位，小数部分7位，例如121.4736522
-- addr：目前无意义
-- time：string类型或者nil，服务器返回的时间，6个字节，年月日时分秒，需要转为十六进制读取
    -- 第一个字节：年减去2000，例如2017年，则为0x11
    -- 第二个字节：月，例如7月则为0x07，12月则为0x0C
    -- 第三个字节：日，例如11日则为0x0B
    -- 第四个字节：时，例如18时则为0x12
    -- 第五个字节：分，例如59分则为0x3B
    -- 第六个字节：秒，例如48秒则为0x30
-- locType：numble类型或者nil，定位类型，0表示基站定位成功，255表示WIFI定位成功
local function getLocCb(result, lat, lng, addr, time, locType)
    log.info("testLbsLoc.getLocCb", result, lat, lng)
    -- 获取经纬度成功
    if result == 0 then
        log.info("服务器返回的时间", time:toHex())
        log.info("定位类型,基站定位成功返回0", locType)
    end
    -- 广播给其他需要定位数据的task
    -- sys.publish("lbsloc_result", result, lat, lng)
end

-- 注意, 免费版的基站+wifi混合定位,大部分情况下只会返回基站定位的结果
-- 收费版本请咨询销售
-- 订阅WLAN扫描成功的消息
sys.subscribe("WLAN_SCAN_DONE", function ()
    -- 获取wlan扫描结果
    local results = wlan.scanResult()
    log.info("scan", "results", #results)
    if #results > 0 then
        local reqWifi = {}
        --wlan扫描成功，打印扫描结果
        for k,v in pairs(results) do
            log.info("scan", v["ssid"], v["rssi"], v["bssid"]:toHex())
            local bssid = v["bssid"]:toHex()
            bssid = string.format ("%s:%s:%s:%s:%s:%s", bssid:sub(1,2), bssid:sub(3,4), bssid:sub(5,6), bssid:sub(7,8), bssid:sub(9,10), bssid:sub(11,12))
            reqWifi[bssid]=v["rssi"]
        end
        -- 发送基站定位请求
        lbsLoc.request(getLocCb,nil,nil,nil,nil,nil,nil,reqWifi)
    else
        -- 没有wifi数据,进行基站定位
        lbsLoc.request(getLocCb) 
    end
end)

sys.taskInit(function()
    sys.waitUntil("IP_READY", 30000)
    wlan.init()
    while 1 do
        --发起基站信息查询,含临近小区
        mobile.reqCellInfo(15)
        -- 等待基站数据已更新的消息，超时时间3秒
        sys.waitUntil("CELL_INFO_UPDATE", 3000)
        -- 扫描wifi频段
        wlan.scan()
        sys.wait(60000)
    end
end)

return lbsLocTest
