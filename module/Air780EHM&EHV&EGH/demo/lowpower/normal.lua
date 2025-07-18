
-- netlab.luatos.com上打开TCP，然后修改IP和端口号，自动回复netlab下发的数据，自收自发测试

local server_ip = "112.125.89.8"
local server_port = 47523

local rxbuf = zbuff.create(8192)

sys.subscribe("IP_READY", function(ip, adapter)
    log.info("mobile", "IP_READY", ip, (adapter or -1) == socket.LWIP_GP)
    sys.publish("net_ready")
end)

local function netCB(netc, event, param)
    if param ~= 0 then
        sys.publish("socket_disconnect")
        return
    end
	if event == socket.LINK then
	elseif event == socket.ON_LINE then
        socket.tx(netc, "hello,luatos!")
	elseif event == socket.EVENT then
        socket.rx(netc, rxbuf)
        socket.wait(netc)
        if rxbuf:used() > 0 then
            log.info("收到", rxbuf:toStr(0,rxbuf:used()):toHex())
            log.info("发送", rxbuf:used(), "bytes")
            socket.tx(netc, rxbuf)
        end
        rxbuf:del()
	elseif event == socket.TX_OK then
        socket.wait(netc)
        log.info("发送完成")
	elseif event == socket.CLOSED then
        sys.publish("socket_disconnect")
    end
end

local function socketTask()
    sys.waitUntil("net_ready")
    log.info("联网成功，准备链接服务器")
    pm.power(pm.WORK_MODE,0) --进入正常模式
	local netc = socket.create(nil, netCB)
	socket.debug(netc, true)
	socket.config(netc, nil, nil, nil, 300, 5, 6)   --开启TCP保活，防止长时间无数据交互被运营商断线
    while true do
        log.info("开始链接服务器")
        local succ, result = socket.connect(netc, server_ip, server_port)
        if not succ then
            log.info("未知错误，5秒后重连")
        else
            log.info("链接服务器成功")
            local result, msg = sys.waitUntil("socket_disconnect")
        end
        log.info("服务器断开了，5秒后重连")
        socket.close(netc)
        log.info(rtos.meminfo("sys"))
        sys.wait(5000)
    end
end

function socketDemo()
	sys.taskInit(socketTask)
end


socketDemo()