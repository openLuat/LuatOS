--[[
@module  lbs_util
@summary Air8204出厂固件 - 基站/WiFi（airlbs）混合定位模块
@version 1.0
@date    2026.09.28
@usage
本模块基于合宙 airlbs 扩展库，通过扫描周边基站与 WiFi 热点进行网络定位，
用于室内或卫星信号遮挡场景下的定位补充。

本模块从 fota.lua 中拆分而来：原先基站定位与 OTA 升级代码混在 fota.lua 内，
且 fota.lua 需通过 return lbs_util 被 main.lua 以“升级模块”的形式加载定位功能，
职责不清。拆分后 fota.lua 只负责 OTA 升级，本模块只负责基站/WiFi 定位。

对外接口：
    lbs_util.open()    -- 打开基站定位轮询
    lbs_util.close()   -- 关闭基站定位轮询
    lbs_util.getloc()  -- 获取最近一次定位结果，返回 (is_fix, {lat=, lng=})

实现说明：
    1. 定位周期为 70 秒，每次定位前重新扫描一次 WiFi；
    2. 定位结果仅缓存最近一次，供 app.lua 的定位上报任务读取；
    3. GPS 定位优先，本模块作为 GPS 无解时的回退定位手段；
    4. 该服务为收费服务，已联系合宙销售申请并填入 project_id 与 project_key；
       凭据失效、欠费或 QPS 超限时定位请求会失败，
       airlbs 库会打印对应错误码（3=欠费、2=QPS超限、0=查询失败）。
]]

local airlbs = require "airlbs"

local lbs_util = {}

local lbs_state = true             -- 基站定位轮询开关，true=开启，false=暂停
local lbsloc = {lat = 0, lng = 0}  -- 最近一次基站/WiFi 定位结果
local is_fix = false               -- 是否已成功定位

local timeout = 15 -- 扫描基站/wifi 做 基站/wifi定位 的超时时间，最小5S,最大60S；取 15S 与 airlbs 库默认 15000ms 对齐，避免云端数据库查询未返回即超时
-- 此为收费服务，需联系合宙销售申请；project_id 长度固定为 6 位
local airlbs_project_id = "uhgTXu"
local airlbs_project_key = "zZ9XUVilgkww0nMmO9ib6KWozHB5oJZo"

-- 打开基站定位轮询
function lbs_util.open()
    lbs_state = true
end

-- 关闭基站定位轮询
function lbs_util.close()
    lbs_state = false
end

-- 获取最近一次基站/WiFi 定位结果
-- @return boolean 是否定位成功
-- @return table   定位结果 {lat=纬度, lng=经度}
function lbs_util.getloc()
    -- 打印当前缓存的 LBS 基站/WiFi 定位结果，明确标识来源，便于与 GNSS 卫星定位区分
    log.info("[LBS基站定位] is_fix:", is_fix, "lat:", lbsloc.lat, "lng:", lbsloc.lng)
    return is_fix ,lbsloc
end

-- 扫描周边 WiFi 热点并返回扫描结果
-- 如需wifi定位,需要硬件以及固件支持wifi扫描功能
local function scan_wifi()
    local wifi_info = nil
    if wlan then
        sys.wait(3000) -- 网络可用后等待一段时间才再调用wifi扫描功能,否则可能无法获取wifi信息
        wlan.init()
        wlan.scan()
        sys.waitUntil("WLAN_SCAN_DONE", timeout * 1000)
        wifi_info = wlan.scanResult()
        log.info("scan", "wifi_info", #wifi_info)
    end
    return wifi_info
end

-- 基站/WiFi 混合定位主循环
local function lbsloc_airlbs()
    while not socket.adapter(socket.dft()) do
        log.warn("lbs_util", "wait IP_READY", socket.dft())
        sys.waitUntil("IP_READY", 1000)
    end

    local wifi_info = scan_wifi()

    socket.sntp()
    sys.waitUntil("NTP_UPDATE", 1000)

    while 1 do
        sys.wait(70000) -- 循环70S一次wifi定位
        if lbs_state then
            log.info("[LBS基站定位] 开始进行airlbs多基站定位")
            local result, data = airlbs.request({
                project_id = airlbs_project_id,
                project_key = airlbs_project_key,
                wifi_info = wifi_info,
                timeout = timeout * 1000
            })
            if result then
                local data_str = json.encode(data)
                log.info("[LBS基站定位] 请求成功，返回数据:", data_str)
                -- 解析经纬度
                local lat = data_str:match("\"lat\":([0-9.-]+)")
                local lng = data_str:match("\"lng\":([0-9.-]+)")
                log.info("[LBS基站定位] 解析结果 lat:", lat, "lng:", lng)
                lbsloc.lat = lat
                lbsloc.lng = lng
                is_fix = true
            else
                log.warn("[LBS基站定位] 请求失败，请检查project_id和project_key")
                is_fix = false
            end

            -- 每轮定位后重新扫描一次 WiFi，供下一轮使用
            wifi_info = scan_wifi()
        end
    end
end

-- wifi/基站混合定位
sys.taskInit(lbsloc_airlbs)

return lbs_util
