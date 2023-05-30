
-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "socket_low_power"
VERSION = "1.0"
PRODUCT_KEY = "123" --换成自己的
-- sys库是标配
_G.sys = require("sys")
_G.sysplus = require("sysplus")
log.style(1)
local server_ip = "112.125.89.8"    --换成自己的
local server_port = 34352 --换成自己的
local period = 1800000 --默认30分钟变化一次模式

local reason, slp_state = pm.lastReson()
log.info("wakeup state", pm.lastReson())
if reason > 0 then
    log.info("已经从深度休眠唤醒")
    pm.power(pm.WORK_MODE,3)
else
    sys.taskInit(function()
        log.info("High Performance")
        pm.power(pm.WORK_MODE,1)
        sys.wait(period)
        log.info("Balanced")
        pm.power(pm.WORK_MODE,2)
        sys.wait(period)
        log.info("no low power")
        pm.power(pm.WORK_MODE,0)
        sys.wait(period)
        log.info("power save")
        pm.power(pm.WORK_MODE,3)
        pm.dtimerStart(3, period)
        gpio.setup(23,nil)
        gpio.close(35)
        sys.wait(period)
    end)
end

local libnet = require "libnet"

local d1Name = "D1_TASK"
local function netCB(msg)
	log.info("未处理消息", msg[1], msg[2], msg[3], msg[4])
end

local function testTask(ip, port)
	d1Online = false
	local tx_buff = zbuff.create(1024)
	local rx_buff = zbuff.create(1024)
	local netc 
	local result, param, is_err
	netc = socket.create(nil, d1Name)
	socket.debug(netc, false)
	socket.config(netc, nil, nil, nil)
	-- socket.config(netc, nil, true)
	while true do

		log.info(rtos.meminfo("sys"))
		result = libnet.waitLink(d1Name, 0, netc)
		result = libnet.connect(d1Name, 15000, netc, ip, port)
		-- result = libnet.connect(d1Name, 5000, netc, "112.125.89.8",34607)
		d1Online = result
		if result then
			log.info("服务器连上了")
			libnet.tx(d1Name, 0, netc, "helloworld")
            if reason > 0 then
                pm.dtimerStart(3, period)
                gpio.setup(23,nil)
                gpio.close(35)
                sys.wait(period) 
            end
		end
		while result do
			succ, param, _, _ = socket.rx(netc, rx_buff)
			if not succ then
				log.info("服务器断开了", succ, param, ip, port)
				break
			end
			if rx_buff:used() > 0 then
				log.info("收到服务器数据，长度", rx_buff:used())
				uart.tx(uart_id, rx_buff)
				rx_buff:del()
			end
			if tx_buff:len() > 1024 then
				tx_buff:resize(1024)
			end
			if rx_buff:len() > 1024 then
				rx_buff:resize(1024)
			end
			log.info(rtos.meminfo("sys"))
			-- 阻塞等待新的消息到来，比如服务器下发，串口接收到数据
			result, param = libnet.wait(d1Name, 300000, netc)
			if not result then
				log.info("服务器断开了", result, param)
				break
			end
		end
		d1Online = false
		libnet.close(d1Name, 5000, netc)
		log.info(rtos.meminfo("sys"))
		sys.wait(1000)
	end
end
sysplus.taskInitEx(testTask, d1Name, netCB, server_ip, server_port)
-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!