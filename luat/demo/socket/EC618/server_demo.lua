local libnet = require "libnet"

--下面演示用阻塞方式做自动应答服务器，只适合W5500
local dName = "D2_TASK"
local d1Name = "D1_TASK"
local function netCB(msg)
	log.info("未处理消息", msg[1], msg[2], msg[3], msg[4])
end

local function serTask(port)
	local tx_buff = zbuff.create(1024)
	local rx_buff = zbuff.create(1024)
	local netc 
	local result, param, succ, rIP, rPort, cnt
	netc = socket.create(nil, dName)
	socket.debug(netc, true)
	socket.config(netc, port)
	result = libnet.waitLink(dName, 0, netc)
	ip, mask, gw, ipv6 = socket.localIP()
	if not ipv6 then
		log.info("没有IPV6地址，无法演示")
		libnet.close(dName, 5000, netc)
		socket.release(netc)
		sysplus.taskDel(dName)
		return
	else
		log.info("本地IPV6地址", ipv6)
	end
	while true do
		log.info("start server!")
		log.info(rtos.meminfo("sys"))
		result = libnet.listen(dName, 0, netc)
		log.info(result)
		if result then
            result,_ = socket.accept(netc, nil)    --只支持1对1
            if result then
			    log.info("客户端连上了")
            end
		end
		cnt = 0
		while result do
			succ, param, rIP, rPort = socket.rx(netc, rx_buff)
			if not succ then
				log.info("客户端断开了", succ, param, ip, port)
				break
			end
			if rx_buff:used() > 0 then
				log.info("收到客户端数据，长度", rx_buff:used(), cnt)
				tx_buff:copy(nil,rx_buff)   --把接收的数据返回给客户端
				rx_buff:del()
				cnt = cnt + 1
			end 

			if tx_buff:used() > 0 then
				result, param = libnet.tx(dName, 5000, netc, tx_buff)
			end
			if not result then
				log.info("发送失败了", result, param)
				break
			end
			tx_buff:del()
			if tx_buff:len() > 1024 then
				tx_buff:resize(1024)
			end
			if rx_buff:len() > 1024 then
				rx_buff:resize(1024)
			end
			if cnt < 20 then
				log.info(rtos.meminfo("sys"))
				result, param = libnet.wait(dName, 30000, netc)
				if not result then
					log.info("客户端断开了", result, param)
					break
				end
			else
				log.info("接收数据20次以上，演示主动断开连接")
				result = false
			end
			log.info(rtos.meminfo("sys"))
		end
		libnet.close(dName, 5000, netc)
		log.info(rtos.meminfo("sys"))
	end
end

-- local function UDPTask(port)
-- 	local tx_buff = zbuff.create(1024)
-- 	local rx_buff = zbuff.create(1024)
-- 	local remote_ip = zbuff.create(18)
-- 	local netc 
-- 	local result, param, succ, rIP, rPort
-- 	netc = socket.create(socket.ETH0, dName)
-- 	socket.debug(netc, true)
-- 	socket.config(netc, port, true)
	
-- 	while true do

-- 		log.info(rtos.meminfo("sys"))
-- 		result = libnet.waitLink(dName, 0, netc)
-- 		if result then
--             result,_ = libnet.connect(dName, 5000, netc,"::",0) 
-- 		end:
-- 		while result do
-- 			result, param = libnet.wait(dName, 5000, netc)
-- 			if not result then
-- 				log.info("客户端断开了", result, param)
-- 				break
-- 			end
-- 			succ, param, rIP, rPort = socket.rx(netc, rx_buff)
-- 			if not succ then
-- 				log.info("客户端断开了", succ, paramt)
-- 				break
-- 			end
-- 			if rx_buff:used() > 0 then
-- 				remote_ip:copy(0, rIP)	--用于后续处理，必须的
-- 				if remote_ip[0] == 0 then
-- 					rIP = remote_ip[1] .. "." .. remote_ip[2] .. "." .. remote_ip[3] .. "." .. remote_ip[4] --不是必须的，只是打印一下方便看看
-- 					log.info("收到客户端数据，长度", rx_buff:used(), rIP, rPort)
-- 				else
-- 					log.info("收到客户端数据，长度", rx_buff:used()) --w5500暂时支持IPV4，就不处理IPV6的情况了
-- 				end
-- 				tx_buff:copy(nil,rx_buff)   --把接收的数据返回给客户端
-- 				rx_buff:del()
-- 			end 

-- 			if tx_buff:used() > 0 then
-- 				if remote_ip[0] == 0 then
-- 					result, param = libnet.tx(dName, 5000, netc, tx_buff, remote_ip:query(1,4,false), rPort)
-- 				else
-- 					result = true	--w5500暂时支持IPV4，就不处理IPV6的情况了
-- 				end
-- 			end
-- 			if not result then
-- 				log.info("发送失败了", result, param)
-- 				break
-- 			end
-- 			tx_buff:del()
-- 			if tx_buff:len() > 1024 then
-- 				tx_buff:resize(1024)
-- 			end
-- 			if rx_buff:len() > 1024 then
-- 				rx_buff:resize(1024)
-- 			end
-- 			log.info(rtos.meminfo("sys"))

-- 		end
-- 		libnet.close(dName, 5000, netc)
-- 		log.info(rtos.meminfo("sys"))
-- 		sys.wait(1000)
-- 	end
-- end

local function clientTask(port)
	d1Online = false
	local rx_buff = zbuff.create(1024)
	local netc 
	local result, param, is_err, ip, mask, gw, ipv6

	netc = socket.create(nil, d1Name)
	socket.debug(netc, true)
	socket.config(netc)
	-- socket.config(netc, nil, true)
	while true do
		result = libnet.waitLink(d1Name, 0, netc)
		ip, mask, gw, ipv6 = socket.localIP()
		if not ipv6 then
			log.info("没有IPV6地址，无法演示")
			libnet.close(d1Name, 5000, netc)
			socket.release(netc)
			sysplus.taskDel(d1Name)
			return
		end
		log.info("start client")
		result = libnet.connect(d1Name, 15000, netc, ipv6, port)
		d1Online = result
		if result then
			log.info("服务器连上了")
			libnet.tx(d1Name, 15000, netc, "helloworld")
		end
		cnt = 1
		while result do
			succ, param, _, _ = socket.rx(netc, rx_buff)
			if not succ then
				log.info("服务器断开了", succ, param, ip, port)
				break
			end
			if rx_buff:used() > 0 then
				log.info("收到服务器数据，长度", rx_buff:used())
				rx_buff:del()
			end

			if rx_buff:len() > 1024 then
				rx_buff:resize(1024)
			end
			result, param = libnet.wait(d1Name, 5000, netc)
			if not result then
				log.info("服务器断开了", result, param)
				break
			end
			if not param then
				result, param = libnet.tx(d1Name, 15000, netc, "helloworld")
				if not result then
					log.info("服务器断开了", result, param)
					break
				end
			end
		end
		d1Online = false
		libnet.close(d1Name, 5000, netc)
		log.info(rtos.meminfo("sys"))
		sys.wait(1000)
	end
end



function SerDemo(port)
	mobile.ipv6(true)
	sysplus.taskInitEx(serTask, dName, netCB, port)
	-- sysplus.taskInitEx(clientTask, d1Name, netCB, port)	--回环测试，如果不需要，可以注释掉
end

-- function UDPSerDemo(port)
-- 	sysplus.taskInitEx(UDPTask, dName, netCB, port)
-- end