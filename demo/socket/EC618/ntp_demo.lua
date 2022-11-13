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
				-- rtc.set(tamp - 0x83aa7e80 + 8 * 3600)
			else
				--2036年后，当前ntp协议会回滚
				log.info("ntp 时间戳回滚")
				-- rtc.set(0x7C558180 + tamp + 8 * 3600)
			end
			log.info(os.date())
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
				log.info("ntp 完成")
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

function ntpDemo()
	sys.taskInit(ntpTask)
end