
-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "mobiledemo"
VERSION = "1.0.0"

log.info("main", PROJECT, VERSION)

-- sys库是标配
_G.sys = require("sys")


sys.taskInit(function()
    sys.wait(2000)
    while 1 do
        log.info("imei", mobile.imei():toHex())
        log.info("imsi", mobile.imsi():toHex())
        local sn = mobile.sn()
        if sn then
            log.info("sn",   sn:toHex())
        end
        log.info("muid", mobile.muid():toHex())
        log.info("iccid", mobile.iccid())
        log.info("csq", mobile.csq())
        log.info("rssi", mobile.rssi())
        log.info("rsrq", mobile.rsrq())
        log.info("rsrp", mobile.rsrp())
        log.info("snr", mobile.snr())
        log.info("simid", mobile.simid())
        sys.wait(15000)
    end
end)

-- 基站数据的查询

-- 订阅式, 模块本身会周期性查询基站信息,但通常不包含临近小区
sys.subscribe("CELL_INFO_UPDATE", function()
    log.info("cell", json.encode(mobile.getCellInfo()))
end)

-- 轮训式, 包含临近小区信息
sys.taskInit(function()
    sys.wait(3000)
    while 1 do
        mobile.reqCellInfo(60)
        sys.wait(30000)
        log.info("cell", json.encode(mobile.getCellInfo()))
    end
end)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
