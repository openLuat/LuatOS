-- 用于检查当前模组中WiFi是否是最新版本，如果不是最新版本则启动升级。
local fota_wifi = require("fota_wifi")

local function wifi_fota_task_func()
    local result = fota_wifi.request()
    if result then
        log.info("fota_wifi", "升级任务执行成功")
    else
        log.info("fota_wifi", "升级任务执行失败")
    end
end

-- 判断网络是否正常
local function wait_ip_ready()
    local result, ip, adapter = sys.waitUntil("IP_READY", 30000)
    if result then
        log.info("fota_wifi", "开始执行升级任务")
        sys.taskInit(wifi_fota_task_func)
    else
        log.error("当前正在升级WIFI&蓝牙固件，请插入可以上网的SIM卡")
    end
end

-- 在设备启动时检查网络状态
sys.taskInit(wait_ip_ready)
