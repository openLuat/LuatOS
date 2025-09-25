--[[
@module  fota
@summary 使用合宙iot平台远程升级功能模块
@version 1.0
@date    2025.09.25
@author  王城钧
@usage
实现远程升级功能
]]

-- 使用合宙iot平台时需要这个参数
PRODUCT_KEY = "SIsRml1ImTsP6XR4lvRAQVuksbZZuUpO" -- 到 iot.openluat.com 创建项目,获取正确的项目id
--加在libfota2扩展库
libfota2 = require "libfota2"

local function fota_cb(ret)
    log.info("fota", ret)
    -- fota结束，无论成功还是失败，都释放fota_running标志
    if ret == 0 then
        log.info("升级包下载成功,重启模块")
        rtos.reboot()
    end
end

local opts = {}

libfota2.request(fota_cb, opts)

sys.timerLoopStart(libfota2.request, 4 * 3600000, fota_cb, opts)