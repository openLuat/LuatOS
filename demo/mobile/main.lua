
-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "mobiledemo"
VERSION = "1.0.0"

log.info("main", PROJECT, VERSION)

-- sys库是标配
_G.sys = require("sys")
-- 对于双卡的设备, 可以设置为自动选sim卡
-- 但是, 这样SIM1所在管脚就强制复用为SIM功能, 不可以再复用为GPIO
-- mobile.simid(2)
mobile.simid(2,true)--优先用SIM0
sys.taskInit(function()
    -- mobile.apn(0,2,"") -- 使用默认APN激活CID2
    mobile.rtime(2) -- 在无数据交互时，RRC2秒后自动释放
    -- 下面是配置自动搜索小区间隔，和轮询搜索冲突，开启1个就可以了
    -- mobile.setAuto(10000,30000, 5) -- SIM暂时脱离后自动恢复，30秒搜索一次周围小区信息
    sys.wait(2000)
    while 1 do
        log.info("imei", mobile.imei())
        log.info("imsi", mobile.imsi())
        local sn = mobile.sn()
        if sn then
            log.info("sn",   sn:toHex())
        end
        log.info("muid", mobile.muid())
        log.info("iccid", mobile.iccid())
        log.info("csq", mobile.csq()) -- 4G模块的CSQ并不能完全代表强度
        log.info("rssi", mobile.rssi()) -- 需要综合rssi/rsrq/rsrp/snr一起判断
        log.info("rsrq", mobile.rsrq())
        log.info("rsrp", mobile.rsrp())
        log.info("snr", mobile.snr())
        log.info("simid", mobile.simid()) -- 这里是获取当前SIM卡槽
        log.info("apn", mobile.apn(0,1))
        log.info("ip", socket.localIP())
        sys.wait(15000)
    end
end)

-- 基站数据的查询

-- 订阅式, 模块本身会周期性查询基站信息,但通常不包含临近小区
sys.subscribe("CELL_INFO_UPDATE", function()
    log.info("cell", json.encode(mobile.getCellInfo()))
end)

-- 轮询式, 包含临近小区信息，这是手动搜索，和上面的自动搜索冲突，开启一个就行
sys.taskInit(function()
    sys.wait(3000)
    while 1 do
        mobile.reqCellInfo(60)
        sys.wait(30000)
        log.info("cell", json.encode(mobile.getCellInfo()))
    end
end)

-- 获取sim卡的状态

sys.subscribe("SIM_IND", function(status)
    log.info("sim status", status)
    if status == 'GET_NUMBER' then
        log.info("number", mobile.number(0))
    end
end)


-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
