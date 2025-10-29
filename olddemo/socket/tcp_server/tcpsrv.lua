local libnet = require "libnet"

--下面演示用阻塞方式做自动应答服务器，只适合W5500
local dName = "D2_TASK"
local function netCB(msg)
	log.info("未处理消息", msg[1], msg[2], msg[3], msg[4])
end

local function serTask(port, adapter)
	log.info("tcpsrv", "准备监听端口", socket.localIP(adapter), port)
	local tx_buff = zbuff.create(1024)
	local rx_buff = zbuff.create(1024)
	local netc 
	local result, param, succ, rIP, rPort
	netc = socket.create(adapter, dName)
	socket.debug(netc, true)
	socket.config(netc, port)
	while true do

		log.info(rtos.meminfo("sys"))
		result = libnet.waitLink(dName, 0, netc)
		result = libnet.listen(dName, 0, netc)
		if result then
            result,_ = socket.accept(netc, nil)    --W5500的硬件协议栈不支持一对多
            if result then
			    log.info("客户端连上了")
			    libnet.tx(dName, 0, netc, "helloworld")
            end
		end
		while result do
			succ, param, rIP, rPort = socket.rx(netc, rx_buff)
			if not succ then
				log.info("客户端断开了", succ, param, rIP, port)
				break
			end
			if rx_buff:used() > 0 then
				log.info("收到客户端数据，长度", rx_buff:used())
				tx_buff:copy(nil,rx_buff)   --把接收的数据返回给客户端
				rx_buff:del()
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
			log.info(rtos.meminfo("sys"))
			result, param = libnet.wait(dName, 5000, netc)
			if not result then
				log.info("客户端断开了", result, param)
				break
			end
		end
		libnet.close(dName, 5000, netc)
		log.info(rtos.meminfo("sys"))
		sys.wait(1000)
	end
end


function SerDemo(port, adapter)
	sysplus.taskInitEx(serTask, dName, netCB, port, adapter)
end
