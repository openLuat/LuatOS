

local rxbuf = zbuff.create(8192)
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
	elseif event == socket.CLOSE then
        sys.publish("socket_disconnect")
    end
end

local function socketTask()
	local netc = socket.create(socket.ETH0, netCB)
	socket.debug(netc, true)
	socket.config(netc, nil, nil, nil, 300, 5, 6)   --开启TCP保活，防止长时间无数据交互被运营商断线
    while true do
        local succ, result = socket.connect(netc, server_ip, server_port)
        if not succ then
            log.info("未知错误，5秒后重连")
        else
            local result, msg = sys.waitUntil("socket_disconnect")
        end
        log.info("服务器断开了，5秒后重连")
        socket.close(netc)
        log.info(rtos.meminfo("sys"))
        sys.wait(5000)
    end
end

local function UDPTask()
    local netc = socket.create(socket.ETH0, netCB)
    socket.debug(netc, true)
    socket.config(netc, nil, true, nil, 300, 5, 6)   --开启TCP保活，防止长时间无数据交互被运营商断线
    while true do
        local succ, result = socket.connect(netc, server_ip, UDP_port)
        if not succ then
            log.info("未知错误，5秒后重连")
        else
            local result, msg = sys.waitUntil("socket_disconnect")
        end
        log.info("服务器断开了，5秒后重连")
        socket.close(netc)
        log.info(rtos.meminfo("sys"))
        sys.wait(5000)
    end
end


local function SSLTask()
    local netc = socket.create(socket.ETH0, netCB)
    socket.debug(netc, true)
    socket.config(netc, nil, nil, true, 300, 5, 6)   --开启TCP保活，防止长时间无数据交互被运营商断线
    while true do
        local succ, result = socket.connect(netc, server_ip, ssl_port)
        if not succ then
            log.info("未知错误，5秒后重连")
        else
            local result, msg = sys.waitUntil("socket_disconnect")
        end
        log.info("服务器断开了，5秒后重连")
        socket.close(netc)
        log.info(rtos.meminfo("sys"))
        sys.wait(5000)
    end
end

function socketDemo()
    mobile.rtime(1)
	sys.taskInit(socketTask)
end

function UDPDemo()
    mobile.rtime(1)
    sys.taskInit(UDPTask)
end

function SSLDemo()
    mobile.rtime(1)
    sys.taskInit(SSLTask)
end