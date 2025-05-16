-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "paid_lbs"
VERSION = "1.0.0"

-- 使用合宙iot平台时需要这个参数
PRODUCT_KEY = "xxx" -- 到 iot.openluat.com 创建项目,获取正确的项目id

-- 引入必要的库文件(lua编写), 内部库不需要require
sys = require("sys")
sysplus = require("sysplus")
libnet = require "libnet"

log.info("main", PROJECT, VERSION)

if wdt then
    -- 添加硬狗防止程序卡死，在支持的设备上启用这个功能
    wdt.init(20000) -- 初始化watchdog设置为9s
    sys.timerLoopStart(wdt.feed, 3000) -- 3s喂一次狗
end

local airlbs = require "airlbs"

local timeout = 60 -- 扫描基站/wifi 做 基站/wifi定位 的超时时间，最小5S,最大60S

-- 此为收费服务，需自行联系销售申请
local airlbs_project_id = ""
local airlbs_project_key = ""

-- --多基站定位
-- sys.taskInit(function()
--     sys.waitUntil("IP_READY") -- 等待底层上报联网成功
--     socket.sntp() -- 进行NTP授时，放置部分联通卡没有基站授时
--     sys.waitUntil("NTP_UPDATE", 1000)
--     while 1 do
--         if airlbs_project_id and airlbs_project_key then
--             local result, data = airlbs.request({
--                 project_id = airlbs_project_id,
--                 project_key = airlbs_project_key,
--                 timeout = timeout * 1000 -- 实际的超时时间(单位：ms)
--             })
--             if result then
--                 log.info("airlbs多基站定位返回的经纬度数据为", json.encode(data))
--             end
--         else
--             log.warn("请检查project_id和project_key")
--         end
--         sys.wait(20000)
--     end

-- end)

-- wifi/基站混合定位
sys.taskInit(function()
    sys.waitUntil("IP_READY")
    -- 如需wifi定位,需要硬件以及固件支持wifi扫描功能
    local wifi_info = nil
    if wlan then
        sys.wait(3000) -- 网络可用后等待一段时间才再调用wifi扫描功能,否则可能无法获取wifi信息
        wlan.init()
        wlan.scan()
        sys.waitUntil("WLAN_SCAN_DONE", timeout * 1000)
        wifi_info = wlan.scanResult()
        log.info("scan", "wifi_info", #wifi_info)
    end

    socket.sntp()
    sys.waitUntil("NTP_UPDATE", 1000)

    while 1 do
        local result, data = airlbs.request({
            project_id = airlbs_project_id,
            project_key = airlbs_project_key,
            wifi_info = wifi_info,
            timeout = timeout * 1000
        })
        if result then
                log.info("airlbs多基站定位返回的经纬度数据为", json.encode(data))
        else
            log.warn("请检查project_id和project_key")
        end
        sys.wait(20000) -- 循环20S一次wifi定位
    end

end)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!

