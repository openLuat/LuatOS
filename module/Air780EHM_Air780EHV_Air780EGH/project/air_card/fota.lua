
PRODUCT_KEY = "1if3rgrNXMY4KvhaIEtcgaclywx552CG"

local libfota3 = require "libfota3"

local function version_log()
    while 1 do
        sys.wait(60000)
        log.info("降功耗 找合宙")
        log.info("fota", "脚本版本号", VERSION, "core版本号", rtos.version())
    end
end
sys.taskInit(version_log)

local lbs_util = {}

local lbs_state = true
local lbsloc = {lat = 0, lng = 0}
local is_fix = false

libfota3.request({
    project_key = PRODUCT_KEY,
    script_name = PROJECT,
    script_version = VERSION,
    auto = true,
    interval = 60,
    on_status = function(status, msg, percent)
        log.info("fota3", status, msg or "", percent or "")
        if status == "checking" or status == "download_start" or status == "downloading" then
            if config then config.ota_status = true end
            if led_util then
                led_util.led1_purple()
                led_util.led2_purple()
            end
        elseif status == "download_done" or status == "upgrade_success" or status == "upgrade_fail"
            or status == "check_fail" or status == "no_new_version" or status == "network_fail" then
            if config then config.ota_status = false end
            if led_util then
                led_util.set_led1()
                led_util.set_led2()
            end
        end
    end,
    on_confirm = function(action, info, callback)
        callback(true)
    end,
})


local airlbs = require "airlbs"

local timeout = 5 -- 扫描基站/wifi 做 基站/wifi定位 的超时时间，最小5S,最大60S

-- 此为收费服务，需自行联系销售申请
-- local airlbs_project_id = "uhgTXu"
-- local airlbs_project_key = "zZ9XUVilgkww0nMmO9ib6KWozHB5oJZo"

local airlbs_project_id = "123456"
local airlbs_project_key = "123456"

function lbs_util.open()
    lbs_state = true
end
function lbs_util.close()
    lbs_state = false
end
function lbs_util.getloc()
    return is_fix ,lbsloc
end
local function lbsloc_airlbs()
    while not socket.adapter(socket.dft()) do
        log.warn("mqtt_client_main_task_func", "wait IP_READY", socket.dft())
        sys.waitUntil("IP_READY", 1000)
    end
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
        sys.wait(70000) -- 循环70S一次wifi定位
        if lbs_state then
            log.info("开始进行airlbs多基站定位")
            local result, data = airlbs.request({
                project_id = airlbs_project_id,
                project_key = airlbs_project_key,
                wifi_info = wifi_info,
                timeout = timeout * 1000
            })
            if result then
                local data_str = json.encode(data)
                log.info("airlbs多基站定位返回的经纬度数据为", data_str)
                -- 解析经纬度
                local lat = data_str:match("\"lat\":([0-9.-]+)")
                log.info("airlbs", "lat", lat)
                local lng = data_str:match("\"lng\":([0-9.-]+)")
                log.info("airlbs", "lng", lng)
                lbsloc.lat = lat
                lbsloc.lng = lng
                is_fix = true
            else
                log.warn("请检查project_id和project_key")
                is_fix = false
            end
        
            wifi_info = nil
            if wlan then
                sys.wait(3000) -- 网络可用后等待一段时间才再调用wifi扫描功能,否则可能无法获取wifi信息
                wlan.init()
                wlan.scan()
                sys.waitUntil("WLAN_SCAN_DONE", timeout * 1000)
                wifi_info = wlan.scanResult()
                log.info("scan", "wifi_info", #wifi_info)
            end
        end
    end

end

-- wifi/基站混合定位
sys.taskInit(lbsloc_airlbs)

return lbs_util