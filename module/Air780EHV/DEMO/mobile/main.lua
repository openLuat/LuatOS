
-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "mobiledemo"
VERSION = "1.0.0"

log.info("main", PROJECT, VERSION)

-- sys库是标配
_G.sys = require("sys")



-- Air780E的AT固件默认会为开机键防抖, 导致部分用户刷机很麻烦
if rtos.bsp() == "EC618" and pm and pm.PWK_MODE then
    pm.power(pm.PWK_MODE, false)
end


-- 对于双卡的设备, 可以设置为自动选sim卡
-- 但是, 这样SIM1所在管脚就强制复用为SIM功能, 不可以再复用为GPIO
-- mobile.simid(2)
mobile.simid(2,true)--优先用SIM0


sys.taskInit(function()

	log.info("status", mobile.status())
    local band = zbuff.create(40)
    local band1 = zbuff.create(40)
    mobile.getBand(band)
    log.info("当前使用的band:")
    for i=0,band:used()-1 do
        log.info("band", band[i])
    end
    band1[0] = 38
    band1[1] = 39
    band1[2] = 40
    mobile.setBand(band1, 3)    --改成使用38,39,40
    band1:clear()
    mobile.getBand(band1)
    log.info("修改后使用的band:")
    for i=0,band1:used()-1 do
        log.info("band", band1[i])
    end
    mobile.setBand(band, band:used())    --改回原先使用的band，也可以下载的时候选择清除fs

    mobile.getBand(band1)
    log.info("修改回默认使用的band:")
    for i=0,band1:used()-1 do
        log.info("band", band1[i])
    end
	-- mobile.vsimInit()
	-- mobile.flymode(nil,true)
	-- mobile.vsimOnOff(true)
	-- mobile.flymode(nil,false)
    -- mobile.apn(0,2,"") -- 使用默认APN激活CID2
    -- mobile.rtime(3) -- 在无数据交互时，RRC 3秒后自动释放
    -- 下面是配置自动搜索小区间隔，和轮询搜索冲突，开启1个就可以了
    -- mobile.setAuto(10000,30000, 5) -- SIM暂时脱离后自动恢复，30秒搜索一次周围小区信息
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
    sys.wait(5000)
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
