-- netlab.luatos.com上打开TCP，然后修改IP和端口号，自动回复netlab下发的数据，自收自发测试
local server_ip = "112.125.89.8"
local server_port = 35257
local function netCB(netc, event, param)
    if param ~= 0 then
        sys.publish("socket_disconnect")
        return
    end
	if event == socket.LINK then

	elseif event == socket.ON_LINE then
        socket.tx(netc, "hello,luatos!")
	elseif event == socket.EVENT then
        local rbuf = zbuff.create(8192)
        socket.rx(netc, rbuf)
        if rbuf:used() > 0 then
            socket.tx(netc, rbuf)
        end
        rbuf:del()
        rbuf = nil
	elseif event == socket.TX_OK then
        log.info("发送完成")
	elseif event == socket.CLOSE then
        sys.publish("socket_disconnect")
    end
end

local function socketTask()
	local netc = socket.create(nil, netCB)
	-- socket.debug(netc, true)
	socket.config(netc, nil, nil, nil, 300, 5, 6)   --开启TCP保活，防止长时间无数据交互被运营商断线
    while true do
        local isError, result = socket.connect(netc, server_ip, server_port)
        if isError then
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
	sys.taskInit(socketTask)
end