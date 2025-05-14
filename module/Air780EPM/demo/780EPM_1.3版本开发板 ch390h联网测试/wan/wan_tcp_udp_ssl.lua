-- netlab.luatos.com上打开TCP，然后修改IP和端口号，自动回复netlab下发的数据，自收自发测试
local server_ip = "112.125.89.8"
local server_port = 44072
local UDP_port = 43454
local ssl_port = 46635
local rxbuf = zbuff.create(8192)

sys.taskInit(function()
    sys.wait(3000)
    local result = spi.setup(0, -- 串口id
    nil, 0, -- CPHA
    0, -- CPOL
    8, -- 数据宽度
    25600000 -- ,--频率
    -- spi.MSB,--高低位顺序    可选，默认高位在前
    -- spi.master,--主模式     可选，默认主
    -- spi.full--全双工       可选，默认全双工
    )
    log.info("main", "open", result)
    if result ~= 0 then -- 返回值为0，表示打开成功
        log.info("main", "spi open error", result)
        return
    end

    netdrv.setup(socket.LWIP_ETH, netdrv.CH390, {
        spiid = 0,
        cs = 8
    })
    netdrv.dhcp(socket.LWIP_ETH, true)
    -- sys.wait(3000)
    while 1 do
        local ipv4ip, aaa, bbb = netdrv.ipv4(socket.LWIP_ETH, "", "", "")
        log.info("ipv4地址,掩码,网关为", ipv4ip, aaa, bbb)
        local netdrv_start = netdrv.ready(socket.LWIP_ETH)
        if netdrv_start and ipv4ip and ipv4ip ~= "0.0.0.0" then
            log.info("条件都满足")
            sys.publish("CH390_IP_READY")
            return
        end
        sys.wait(1000)
    end

end)

sys.taskInit(function()

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
            log.info("收到", rxbuf:toStr(0, rxbuf:used()):toHex())
            log.info("发送", rxbuf:used(), "bytes", rxbuf:toStr(0, rxbuf:used()):toHex())
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
  
    local netc = socket.create(nil, netCB)
    socket.debug(netc, true)
    socket.config(netc, nil, nil, nil, 300, 5, 6) -- 开启TCP保活，防止长时间无数据交互被运营商断线
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

    local netc = socket.create(nil, netCB)
    socket.debug(netc, true)
    socket.config(netc, nil, true, nil, 300, 5, 6) -- 开启TCP保活，防止长时间无数据交互被运营商断线
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

    local netc = socket.create(nil, netCB)
    socket.debug(netc, true)
    socket.config(netc, nil, nil, true, 300, 5, 6) -- 开启TCP保活，防止长时间无数据交互被运营商断线
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
    sys.taskInit(socketTask)
end

function UDPDemo()
    sys.taskInit(UDPTask)
end

function SSLDemo()
    sys.taskInit(SSLTask)
end

sys.taskInit(function ()

    sys.waitUntil("CH390_IP_READY")
    log.info("CH390 联网成功，开始测试")
    -- 如果自带的DNS不好用，可以用下面的公用DNS,但是一定是要在CH390联网成功后使用
    -- socket.setDNS(socket.LWIP_ETH,1,"223.5.5.5")	
    -- socket.setDNS(nil,1,"114.114.114.114")
    socket.dft(socket.LWIP_ETH) --设置网卡默认值

-- socketDemo()
-- UDPDemo() 
SSLDemo()
end)
