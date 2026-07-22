
-- 使用合宙iot平台时需要这个参数
PRODUCT_KEY = "YOUR_PRODUCT_KEY_HERE" -- 到 iot.openluat.com 创建项目,获取正确的项目id

sys = require "sys"
libfota2 = require "libfota2"
-- 循环打印版本号, 方便看版本号变化, 非必须
local function version_log()
    while 1 do
        sys.wait(60000)
        log.info("降功耗 找合宙")
        -- log.info("fota", "脚本版本号", VERSION)
        log.info("fota", "脚本版本号", VERSION, "core版本号", rtos.version())
    end
end
sys.taskInit(version_log)

local lbs_util = {}

local lbs_state = true
local lbsloc = {lat = 0, lng = 0}
local is_fix = false
-- 升级结果的回调函数
-- 功能:获取fota的回调函数
-- 参数:
-- result:number类型
--   0表示成功
--   1表示连接失败
--   2表示url错误
--   3表示服务器断开
--   4表示接收报文错误
--   5表示使用iot平台VERSION需要使用 xxx.yyy.zzz形式
local function fota_cb(ret)
    log.info("fota_config.ota_status", ret)
    config.ota_status = false
    led_util.set_led2()
    led_util.set_led1()
    if ret == 0 then
        log.info("升级包下载成功,重启模块")
        rtos.reboot()
    elseif ret == 1 then
        log.info("连接失败", "请检查url拼写或服务器配置(是否为内网)")
    elseif ret == 2 then
        log.info("url错误", "检查url拼写")
    elseif ret == 3 then
        log.info("服务器断开", "检查服务器白名单配置")
    elseif ret == 4 then
        log.info("接收报文错误", "检查模块固件或升级包内文件是否正常")
    elseif ret == 5 then
        log.info("版本号书写错误", "iot平台版本号需要使用xxx.yyy.zzz形式")
    else
        log.info("不是上面几种情况 ret为", ret)
    end
end

local ota_opts = {}

local function fota_start()
    -- 这个判断是提醒要设置PRODUCT_KEY的,实际生产请删除
    while not socket.adapter(socket.dft()) do
        log.warn("mqtt_client_main_task_func", "wait IP_READY", socket.dft())
        sys.waitUntil("IP_READY", 1000)
    end
    log.info("开始检查升级")
    sys.wait(500)
    config.ota_status = true
    led_util.led2_purple()
    led_util.led1_purple()
    libfota2.request(fota_cb, ota_opts)
end
sys.taskInit(fota_start)


local airlbs = require "airlbs"

local timeout = 5 -- 扫描基站/wifi 做 基站/wifi定位 的超时时间，最小5S,最大60S

-- 此为收费服务，需自行联系销售申请
local airlbs_project_id = "YOUR_AIRLBS_PROJECT_ID"
local airlbs_project_key = "YOUR_AIRLBS_PROJECT_KEY"

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

-- 演示定时自动升级, 每隔24小时自动检查一次
sys.timerLoopStart(libfota2.request, 24 * 3600000, fota_cb, ota_opts)

return lbs_util