
-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "fotademo"
VERSION = "1.0.0"

-- 使用合宙iot平台时需要这个参数
PRODUCT_KEY = "qubOK4pUnggHYGye1L7GNAdsPXTcDLbb" -- 到 iot.openluat.com 创建项目,获取正确的项目id

sys = require "sys"
libfota = require "libfota"

-- Air780E的AT固件默认会为开机键防抖, 导致部分用户刷机很麻烦
if rtos.bsp() == "EC618" and pm and pm.PWK_MODE then
    pm.power(pm.PWK_MODE, false)
end

-- 统一联网函数
sys.taskInit(function()
    -- 默认都等到联网成功
    sys.waitUntil("IP_READY")
    sys.publish("net_ready")
end)

sys.taskInit(function()
    while 1 do
        sys.wait(5000)
        log.info("fota", "version", VERSION)
        local bsp_version = rtos.version()
        log.info("当前core版本:",bsp_version)
    end
end)


function fota_cb(ret)
    log.info("fota", ret)
    if ret == 0 then
        rtos.reboot()
    end
end

-- 使用合宙iot平台进行升级
sys.taskInit(function()
    sys.waitUntil("net_ready")
    libfota.request(fota_cb)
end)
sys.timerLoopStart(libfota.request, 3600000, fota_cb)



-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
