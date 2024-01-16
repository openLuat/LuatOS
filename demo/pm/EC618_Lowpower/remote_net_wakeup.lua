-- netlab.luatos.com上打开TCP，然后修改IP和端口号，自动回复netlab下发的数据，自收自发测试

local server_ip = "112.125.89.8"
local server_port = 45471
local rxbuf = zbuff.create(8192)

local socketIsConnected = false

local socketTxCycle = 5 * 1000
local socketWaitTxSuccess = 15 * 1000
local socketTxQueue = {}

local function insertData(data)
    if #socketTxQueue >= 10 then -- 缓存10条消息
        return
    end

    table.insert(socketTxQueue , data)
    if #socketTxQueue == 1 then
        sys.publish("SOCKET_APP_NEW_SOCKET")
    end
end

local function heartTimerCb()
    insertData("heart")
end  

local function netCB(netc, event, param)
    log.info("netc", netc, event, param)
    if param ~= 0 then
        socketIsConnected = false
        sys.timerStop(heartTimerCb)
        sys.publish("socket_disconnect")
        return
    end
	if event == socket.LINK then
	elseif event == socket.ON_LINE then
        socketIsConnected = true
        sys.timerLoopStart(heartTimerCb, 60000)
        sys.publish("SOCKET_APP_IS_READY")
        insertData("hello,luatos!")
	elseif event == socket.EVENT then
        socket.rx(netc, rxbuf)
        socket.wait(netc)
        if rxbuf:used() > 0 then
            insertData("recv ok")
        end
        rxbuf:del()
	elseif event == socket.TX_OK then
        socket.wait(netc)
        log.info("发送完成")
        sys.publish("SOCKET_TX_OK")
	elseif event == socket.CLOSED then
        socketIsConnected = false
        sys.timerStop(heartTimerCb)
        sys.publish("socket_disconnect")
    end
end

local netc = socket.create(nil, netCB)

local function socketTask()
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

sys.taskInit(function ()
    local needWait
    while true do
        if socketIsConnected then
            if #socketTxQueue >= 1 then
                local txData = table.remove(socketTxQueue, 1)
                local succ, full, result = socket.tx(netc, txData)
                if succ then
                    local result = sys.waitUntil("SOCKET_TX_OK", socketWaitTxSuccess)
                    log.info("result", result)
                else
                    socketIsConnected = false
                    sys.publish("socket_disconnect")
                end
            else
                sys.waitUntil("SOCKET_APP_NEW_SOCKET")
            end
        else
            sys.waitUntil("SOCKET_APP_IS_READY") 
        end
    end
end)


function socketDemo()
    gpio.setup(23,nil)
    gpio.setup(32, function()
        insertData("wakeup data")
    end, gpio.PULLUP, gpio.FALLING)
    pm.power(pm.WORK_MODE, 1)
	sys.taskInit(socketTask)
end
socketDemo()