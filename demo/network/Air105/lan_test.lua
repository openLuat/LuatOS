local libnet = require "libnet"


--下面演示用阻塞方式做串口透传远程服务器，简单的串口DTU
local d1Online = false
local com_buff = zbuff.create(4096)
local d1Name = "D1_TASK"
local function dtu_cb(msg)
	sys.info("未处理消息", msg[1], msg[2], msg[3], msg[4])
end

local function demo_dtu(uart_id)
	d1Online = false
	local tx_buff = zbuff.create(10240)
	local rx_buff = zbuff.create(10240)
	local netc = network.create(network.ETH0, d1Name)
	network.config(netc)	--默认配置就是普通的TCP应用
	network.debug(netc, true)
	local result, param, ip, port, is_err
	result = uart.setup(uart_id,115200,8,1)
	uart.on(uart_id, "receive", function(id, len)
	    uart.rx(id, com_buff)
	    if d1Online then
	    	sys_send(d1Name, network.EVENT, 0)
	    end
	end)
	while true do
		result = libnet.waitLink(d1Name, 0, netc)
		result = libnet.connect(d1Name, 5000, netc, "10.0.0.3", 12000)
		sys.info(rtos.meminfo("sys"))
		d1Online = result
		if result then
			sys.info("服务器连上了")
		end
		while result do
			is_err, param, ip, port = network.rx(netc, rx_buff)
			if is_err then
				sys.info("服务器断开了", is_err, param, ip, port)
				break
			end
			if rx_buff:used() > 0 then
				uart.tx(uart_id, rx_buff)
				rx_buff:del()
			end 
			tx_buff:copy(nil, com_buff)
			com_buff:del()
			if tx_buff:used() > 0 then
				result, param = libnet.tx(d1Name, 5000, netc, tx_buff)
			end
			if not result then
				sys.info("发送失败了", result, param)
				break
			end
			tx_buff:del()
			if com_buff:len() > 8192 then
				com_buff:resize(4096)
			end
			if tx_buff:len() > 10240 then
				tx_buff:resize(10240)
			end
			if rx_buff:len() > 10240 then
				rx_buff:resize(10240)
			end
			sys.info(rtos.meminfo("sys"))
			result, param = libnet.wait(d1Name, 5000, netc)
			if not result then
				sys.info("服务器断开了", result, param)
				break
			end
		end
		d1Online = false
		libnet.close(d1Name, 5000, netc)
		sys.info(rtos.meminfo("sys"))
		sys.wait(1000)
	end
end

function demo1(uart_id)
	sys.taskInitV2(demo_dtu, d1Name, dtu_cb, uart_id)
end
