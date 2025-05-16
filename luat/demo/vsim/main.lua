
-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "vsimdemo"
VERSION = "1.0.0"

log.info("main", PROJECT, VERSION)

-- sys库是标配
_G.sys = require("sys")
mobile.config(mobile.CONF_USB_ETHERNET, 3)
mobile.vsimInit()
mobile.flymode(nil,true)
mobile.vsimOnOff(true)
mobile.flymode(nil,false)

sys.taskInit(function()

	if rtos.bsp() == "UIS8850BM" then
		sys.wait(2000)
	end

	log.info("status", mobile.status())
    local band = zbuff.create(40)
    local band1 = zbuff.create(40)
    mobile.getBand(band)
    log.info("当前使用的band:")
    for i=0,band:used()-1 do
        log.info("band", band[i])
    end

	log.info("status", mobile.status())
    sys.wait(2000)
    while 1 do
        log.info("imei", mobile.imei())
        log.info("imsi", mobile.imsi())
        local sn = mobile.sn()
        if sn then
            log.info("sn",   sn:toHex())
        end
		log.info("status", mobile.status())
        log.info("iccid", mobile.iccid())
        log.info("csq", mobile.csq()) -- 4G模块的CSQ并不能完全代表强度
        log.info("rssi", mobile.rssi()) -- 需要综合rssi/rsrq/rsrp/snr一起判断
        log.info("rsrq", mobile.rsrq())
        log.info("rsrp", mobile.rsrp())
        log.info("snr", mobile.snr())
        log.info("simid", mobile.simid()) -- 这里是获取当前SIM卡槽
        log.info("apn", mobile.apn(0,1))
        log.info("ip", socket.localIP())
		log.info("lua", rtos.meminfo())
        -- sys内存
        log.info("sys", rtos.meminfo("sys"))
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
    sys.wait(15000)
	mobile.config(mobile.CONF_SIM_WC_MODE, 2)
    while 1 do
        mobile.reqCellInfo(10)
        sys.wait(11000)
        log.info("cell", json.encode(mobile.getCellInfo()))
		mobile.config(mobile.CONF_SIM_WC_MODE, 2)
    end
end)

-- 获取sim卡的状态

sys.subscribe("SIM_IND", function(status, value)
    log.info("sim status", status)
    if status == 'GET_NUMBER' then
        log.info("number", mobile.number(0))
    end
	if status == "SIM_WC" then
        log.info("sim", "write counter", value)
    end
end)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
