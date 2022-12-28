-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "gnss"
VERSION = "1.0.0"

--[[
本demo是演示定位数据处理的
]]

-- sys库是标配
local sys = require("sys")
require("sysplus")

local gps_uart_id = 2
-- uart.on(gps_uart_id, "recv", function(id, len)
--     while 1 do
--         local data = uart.read(id, 1024)
--         if data and #data > 0 then
--             log.info("GPS", data)
--         else
--             break
--         end
--     end
-- end)
libgnss.clear()

sys.taskInit(function()
    -- Air780EG工程样品的GPS的默认波特率是9600, 量产版是115200,以下是临时代码
    if rtos.bsp():startsWith("EC618") then
        uart.setup(gps_uart_id, 9600)
        log.info("GPS", "start")
        pm.power(pm.GPS, true)
        pm.power(pm.GPS_ANT, true)
        sys.wait(100)
        uart.write(gps_uart_id, "$CFGPRT,,h0,115200,,\r\n")
        sys.wait(50)
    end
    -- 下列是正式代码
    uart.setup(gps_uart_id, 115200)
    libgnss.bind(gps_uart_id)
    -- 调试日志
    libgnss.debug(true)
    -- 定位成功后,使用GNSS时间设置RTC, 暂不可用
    -- libgnss.rtcAuto(true)
    -- 读取之前的位置信息
    local gnssloc = io.readFile("/gnssloc")
    if gnssloc then
        uart.write(gps_uart_id, "$AIDPOS," .. gnssloc .. "\r\n")
        gnssloc = nil
    end
    sys.wait(100)
    if http then
        while 1 do
            local code, headers, body = http.request("GET", "http://download.openluat.com/9501-xingli/HXXT_GPS_BDS_AGNSS_DATA.dat").wait()
            log.info("gnss", "AGNSS", code, body and #body or 0)
            if code == 200 and body and #body > 1024 then
                for offset=1,#body,1024 do
                    log.info("gnss", "AGNSS", "write >>>")
                    uart.write(gps_uart_id, body:sub(offset, 1024))
                    sys.wait(20)
                end 
                break
            end
            sys.wait(60*1000)
        end
    end
end)

sys.timerLoopStart(function()
    -- 6228CI, 查询产品信息, 可选
    -- uart.write(gps_uart_id, "$PDTINFO,*62\r\n")
    uart.write(gps_uart_id, "$AIDINFO\r\n")
    log.info("RMC", json.encode(libgnss.getRmc(2) or {}))
    log.info("GGA", json.encode(libgnss.getGga(2) or {}))
    log.info("GLL", json.encode(libgnss.getGll(2) or {}))
    log.info("GSA", json.encode(libgnss.getGsa(2) or {}))
    log.info("GSV", json.encode(libgnss.getGsv(2) or {}))
    log.info("VTG", json.encode(libgnss.getVtg(2) or {}))
    log.info("date", os.date())
end, 5000)

-- 订阅GNSS状态编码
sys.subscribe("GNSS_STATE", function(event, ticks)
    -- event取值有 
    -- FIXED 定位成功
    -- LOSE  定位丢失
    -- ticks是事件发生的时间,一般可以忽略
    log.info("gnss", "state", event, ticks)
    if event == "FIXED" then
        local locStr = libgnss.locStr()
        log.info("gnss", "pre loc", locStr)
        if locStr then
            io.writeFile("/gnssloc", locStr)
        end
    end
end)

sys.subscribe("NTP_UPDATE", function()
    if not libgnss.isFix() then
        -- "$AIDTIME,year,month,day,hour,minute,second,millisecond"
        local date = os.date("!*t")
        local str = string.format("$AIDTIME,%d,%d,%d,%d,%d,%d,000", 
                             date["year"], date["month"], date["day"], date["hour"], date["min"], date["sec"])
        log.info("gnss", str)
        uart.write(gps_uart_id, str .. "\r\n")
    end
end)

-- NTP任务
-- 实现ntp校准时间
-- 通过回调的方式进行演示
local function netCB(netc, event, param)
	if event == socket.LINK and param == 0 then
		sys.publish("NTP_ENABLE_LINK")
	elseif event == socket.ON_LINE and param == 0 then
		socket.tx(netc, "\xE3\x00\x06\xEC" .. string.rep("\x00", 44))
		socket.wait(netc)	-- 这样才会有接收消息的回调
	elseif event == socket.EVENT and param == 0 then
		local rbuf = zbuff.create(512)
		socket.rx(netc, rbuf)
		if rbuf:used() >= 48 then
			local tamp = rbuf:query(40,4,true) 
			if tamp - 0x83aa7e80 > 0 then
				rtc.set(tamp - 0x83aa7e80)
			else
				--2036年后，当前ntp协议会回滚
				log.info("ntp", "时间戳回滚")
				rtc.set(0x7C558180 + tamp)
			end
			log.info("date", os.date())
			sys.publish("NTP_UPDATE")
            sys.publish("NTP_FINISH")
			rbuf:resize(4)
		end
	end
end

local function ntpTask()
	local server = {
		"ntp1.aliyun.com",
		"ntp2.aliyun.com",
		"ntp3.aliyun.com",
		"ntp4.aliyun.com",
		"ntp5.aliyun.com",
		"ntp6.aliyun.com",
		"ntp7.aliyun.com",
		"194.109.22.18",
		"210.72.145.44",}
	local msg
	local netc = socket.create(nil, netCB)
	socket.debug(netc, true)
	socket.config(netc, nil, true)	-- 配置成UDP，自动分配本地端口
	local isError, result = socket.linkup(netc)
	if isError then
		log.info("unkown error")
		return false
	end
	if not result then
		result, msg = sys.waitUntil("NTP_ENABLE_LINK")
	else
		log.info("already online")
	end
	for k,v in pairs(server) do
		log.info("尝试", v)
		isError, result = socket.connect(netc, v, 123)
		if isError then
			log.info("unkown error")
		else
			result, msg = sys.waitUntil("NTP_FINISH", 5000)
			if result then
				log.info("ntp", "完成")
				socket.close(netc)
				socket.release(netc)
				return
			end
		end
		socket.close(netc)
	end
	log.info("ntp 失败")
	socket.release(netc)
	return
end

sys.taskInit(ntpTask)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
