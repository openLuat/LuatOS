libfota2 = require "libfota2"
local PRODUCT_KEY = "<KEY>"
-- 联网函数, 可自行删减
sys.taskInit(function()
    -- 默认都等到联网成功
    sys.waitUntil("IP_READY")
    log.info("4G网络链接成功")
    sys.publish("net_ready")
end)

local function fota_cb(ret)
    log.info("fota", ret)
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

local function air_update()
    if "123" == PRODUCT_KEY and not ota_opts.url then

        log.info("fota", "请修改正确的PRODUCT_KEY")

    end
    log.info("开始检查升级")
    log.info("fota", "脚本版本号", VERSION, "core版本号", rtos.version())

        libfota2.request(fota_cb, ota_opts)
end

-- 演示定时自动升级, 每隔4小时自动检查一次
sys.timerLoopStart(libfota2.request, 4 * 3600000, fota_cb, ota_opts)
