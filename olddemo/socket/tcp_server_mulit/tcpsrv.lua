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
	log.info("netc", netc)
	-- result = libnet.waitLink(dName, 0, netc)
	clients = {}
	local buff = zbuff.create(1024)
	while true do
		log.info("开始监听客户端连接, 无限时长")
		sys.wait(1000)
		result, code = libnet.listen(dName, 0, netc)
		log.info("监听结果", result, code)
		if result then
			log.info("有客户端连接请求到来, 接受连接")
            result, client = socket.accept(netc, function(client, event, param)
				log.info("客户端事件", client, event, params)
				if event == socket.EVENT then
					local result = socket.rx(client, buff)
					log.info("客户端数据到来", result, buff:used())
					buff:seek(0)
				end
			end)
			socket.debug(client, true)
            if result then
				table.insert(clients, client)
			    log.info("客户端连上了", client, "发送个问候")
			    log.info("发送数据", socket.tx(client, "helloworld"))
            end
		end
		sys.wait(1000)
	end
	libnet.close(dName, 5000, netc)
	log.info("服务器关闭了")
end


function SerDemo(port, adapter)
	sysplus.taskInitEx(serTask, dName, netCB, port, adapter)
end

-- sys.taskInit(function()
-- 	while 1 do
-- 		sys.wait(1000)
-- 		log.info("meminfo", rtos.meminfo("sys"))
-- 	end
-- end)
