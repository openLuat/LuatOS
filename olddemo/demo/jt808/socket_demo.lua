local libnet = require "libnet"
local JT808Prot = require "JT808Prot"
local gpsMng = require "gpsMng"


local d1Online = false
local d1Name = "D1_TASK"
local tx_buff = zbuff.create(1024)
local rx_buff = zbuff.create(1024)
local ip, port="112.125.89.8", 40042

local function netCB(msg)
	log.info("未处理消息", msg[1], msg[2], msg[3], msg[4])
end

--数据发送的消息队列
local msgQuene = {}
function insertMsg(data,user)
    table.insert(msgQuene,{data=data,user=user})
    return true
end
 --终端通用应答
function T_commonRsp(seq,id,result,cbFnc)
    local data = JT808Prot.encode(JT808Prot.T_COMMON_RSP,seq,id,result and 0 or 1)
    if not insertMsg(data,{cb=function(r) log.info("socketOutMsg.commonRsp","send result",r) cbFnc(r) end}) then
        if cbFnc then cbFnc(false) end
    end
end

--位置上报task
local coLocRpt
function createLocRptTask()
	return sys.taskInit(function()
		log.info("libgnss.isFix()", libgnss.isFix())
		while true do
			if libgnss.isFix() then
				local tLocation = libgnss.getRmc(2)
				local lat = tLocation.lat*1000000
				local lng = tLocation.lng*1000000
				local spd = tLocation.speed
				local speed = (spd*1852 - (spd*1852 %1000))/1000
				local Course = tLocation.course
				local gga = libgnss.getGga(2)
				local altitude=gga.altitude
				-- log.info("发送位置信息.locRpt", lat, lng)
				local data, seq = JT808Prot.encode(JT808Prot.T_LOC_RPT,
					0,
					0,
					tonumber(lat),
					tonumber(lng),
					altitude, --海拔
					speed,            --速度
					Course,  --方向
					gpsMng.getTime(),
					"")
				log.info(" 打包后的字符串和流水号LocRpt", data, seq)
				if insertMsg(data, { cb = function(r)
						log.info("socketOutMsg.locRpt位置上报", "send result", r)
						sys.publish("SEND_LOC_RPT_CNF", r)
					end }) then
					sys.waitUntil("SEND_LOC_RPT_CNF")
				end
			else
				log.info("定位失败，位置上报失败")
			end
			sys.wait(fskv.get("wakeLocRptFreq") * 1000)
		end
	end)
end

--心跳上报task
local coHeartRpt
function createHeartRptTask()
	return sys.taskInit(function()
		while true do
			local data, seq = JT808Prot.encode(JT808Prot.T_HEART_RPT)
			log.info(" 打包后的字符串和流水号Heart", data, seq)
			if insertMsg(data, { cb = function(r)
					log.info("发送心跳信息.heartRpt", "send result", r)
					sys.publish("SEND_HEART_RPT_CNF", r)
				end }) then
				sys.waitUntil("SEND_HEART_RPT_CNF")
			end
			sys.wait(fskv.get("heartFreq") * 1000)
		end
	end)
end

--平台通用应答
local function s_commonRsp(packet)
    log.info("s_commonRsp",packet.tmnlSeq,packet.tmnlId,packet.rspResult)
    coroutine.resume(socketTask.coMonitor,'feed monitor')
end
--设置终端参数
local function s_setPara(packet)
    log.info("s_setPara",packet.result,packet.msgSeq,packet.msgId)
    T_commonRsp(packet.msgSeq,packet.msgId,packet.result)
end
--终端控制
local function s_control(packet)
    log.info("s_control",packet.controlCmd,packet.result,packet.msgSeq,packet.msgId)
    T_commonRsp(packet.msgSeq,packet.msgId,packet.result,function(r)
        if packet.controlCmd==JT808Prot.CONTROL_RESET then
            sys.timerStart(sys.restart,2000,"server control reset")
        end
    end)
end
local cmds =
{
    [JT808Prot.S_COMMON_RSP] = s_commonRsp,  --平台通用应答
    [JT808Prot.S_SET_PARA] = s_setPara,   --设置终端参数
    [JT808Prot.S_CONTROL] = s_control,     --终端控制
}

local tCache = {}
--tcp接收数据处理函数
function inproc(data)
	table.insert(tCache, data)
	local cacheData = table.concat(tCache) --连接字符串
	tCache = {}
	while cacheData:len() > 0 do
		local unProcData, packet = JT808Prot.decode(cacheData)
		cacheData = unProcData or ""
		if packet then
			if packet.msgId and cmds[packet.msgId] and packet.result then
				cmds[packet.msgId](packet)
			else
				log.warn("inproc", "invalid packet")
			end
		else
			if cacheData:len() > 0 then
				table.insert(tCache, 1, cacheData)
				sys.timerStart(function() tCache = {} end, 10000)
			end
			break
		end
	end
end



local function socketTask(ip, port)
	local netc
	local result, param, is_err

	netc = socket.create(nil, d1Name)
	-- socket.debug(netc, true)
	socket.config(netc, nil, nil, nil)
	-- socket.config(netc, nil, true)
	while true do
		-- log.info(rtos.meminfo("sys"))
		--result = libnet.waitLink(d1Name, 0, netc)
		result = libnet.connect(d1Name, 15000, netc, ip, port)
		-- result = libnet.connect(d1Name, 5000, netc, "112.125.89.8",34607)
		d1Online = result
		if result then
			log.info("服务器连上了")
			createLocRptTask()
			createHeartRptTask()
		end
		while result do
			succ, param, _, _ = socket.rx(netc, rx_buff)
			if not succ then
				log.info("服务器断开了", succ, param, ip, port)
				break
			end
			if rx_buff:used() > 0 then
				log.info("收到服务器数据，长度", rx_buff:used())
				inproc(rx_buff:toStr(0, rx_buff:used()))  --读出接收数据并处理
				rx_buff:del()
			end
			while #msgQuene>0 do
				local outMsg = table.remove(msgQuene,1)
				tx_buff:write(outMsg.data)
				if tx_buff:used() > 0 then
					result, param = libnet.tx(d1Name, 15000, netc, tx_buff)
					log.info("发送结果", result)
				end
				if not result then
					log.info("发送失败了", result )
					break
				end
				if outMsg.user and outMsg.user.cb then outMsg.user.cb(result,outMsg.data,outMsg.user.para) end
				if not result then return end
				tx_buff:del()
			end
			if tx_buff:len() > 1024 then
				tx_buff:resize(1024)
			end
			if rx_buff:len() > 1024 then
				rx_buff:resize(1024)
			end
			-- 阻塞等待新的消息到来，比如服务器下发，串口接收到数据
			result, param = libnet.wait(d1Name, 1000, netc)
			if not result then
				log.info("服务器断开了", result, param)
				break
			end
		end
		d1Online = false
		libnet.close(d1Name, 5000, netc)
		tx_buff:clear(0)
		rx_buff:clear(0)
		sys.wait(1000)
	end
end


sysplus.taskInitEx(socketTask, d1Name, netCB, ip, port)


