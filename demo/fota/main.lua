
-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "fotademo"
VERSION = "1.0.0"

--[[
本demo 适用于 Air780E/Air780EG/Air600E
1. 需要 V1103及以上的固件
2. 需要 LuaTools 2.1.89 及以上的升级文件生成
]]

-- 使用合宙iot平台时需要这个参数
PRODUCT_KEY = "123" -- 到 iot.openluat.com 创建项目,获取正确的项目id

sys = require "sys"
libnet = require "libnet"
libfota = require "libfota"

sys.taskInit(function()
    while 1 do
        sys.wait(1000)
        log.info("fota", "version", VERSION)
    end
end)


function fota_cb(ret)
    log.info("fota", ret)
    if ret == 0 then
        rtos.reboot()
    end
end

-- 使用合宙iot平台进行升级
libfota.request(fota_cb)
sys.timerLoopStart(libfota.request, 3600000, fota_cb)

-- 使用自建服务器进行升级
-- local ota_url = "http://myserv.com/myapi/version=" .. _G.VERSION .. "&imei=" .. mobile.imei()
-- libfota.request(fota_cb, ota_url)
-- sys.timerLoopStart(libfota.request, 3600000, fota_cb, ota_url)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
