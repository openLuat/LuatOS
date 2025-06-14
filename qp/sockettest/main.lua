-- 必要全局定义
PROJECT = "LuatOS_Socket_Demo"
VERSION = "1.0.0"

log.info(PROJECT, VERSION, "start")

-- 定义socket id
local socket_tcp1,socket_tcp1
local socket_id_udp

local tcpserver = "netlab.luatos.com"
local tcpport = 45431
local udpserver = "netlab.luatos.com"
local udpport = 46011

local is_udp = false        -- 如果是UDP, 要改成true, false就是TCP
local is_tls = false        -- 加密与否, 要看服务器的实际情况

local tcpdata = "tcp data test...."
local udpdata = "udp data test...."

local tcptaskname = "TcpTask"
local Udptaskname = "UdpTask"

function tcp_event_handler1(id, event)
    if event == socket.EVENT then
        log.info("Socket event", "connect success", id)
        socket.send(id, "Hello, TCP Server!")
    elseif event == socket.RECV then
        local data = socket.recv(id, 1024)
        log.info("Socket event", "data received", data)
        -- 演示recv后主动关闭连接
        socket.close(id)
    elseif event == socket.SENT then
        log.info("Socket event", "data sent success", id)
    elseif event == socket.CLOSE then
        log.info("Socket event", "connection closed", id)
        socket.release(id)
    elseif event == socket.ERROR then
        log.info("Socket event", "error occured", id)
        socket.release(id)
    end
end

function tcp_event_handler2(id, event)
    sysplus.waitMsg()
    
    if event == socket.EVENT then
        log.info("Socket event", "connect success", id)
        socket.send(id, "Hello, TCP Server!")
    elseif event == socket.RECV then
        local data = socket.recv(id, 1024)
        log.info("Socket event", "data received", data)
        -- 演示recv后主动关闭连接
        socket.close(id)
    elseif event == socket.SENT then
        log.info("Socket event", "data sent success", id)
    elseif event == socket.CLOSE then
        log.info("Socket event", "connection closed", id)
        socket.release(id)
    elseif event == socket.ERROR then
        log.info("Socket event", "error occured", id)
        socket.release(id)
    end
end

local function tcpevent1(ctrl,msg,para)
    local s = string.format("value:%X,%X,%X,%X", socket.ON_LINE, socket.TX_OK, socket.CLOSED, socket.EVENT)
    log.info("event received:",msg,para)
    log.info(s)
    -- log.info("value:%X", socket.ON_LINE, socket.TX_OK, socket.CLOSED, socket.EVENT)
    if msg == socket.ON_LINE then
        log.info("connect sucess! ")
    elseif msg == socket.TX_OK then
        log.info("Up link success!")
    elseif msg == socket.CLOSD then
        log.info("socket close success!")
    elseif msg == socket.EVENT then
        if para == 0 then
            log.info("new downlink arrived, pls receive data using socket.rx()")
        elseif para == -1 then
            log.info("socket error!, maybe server down!")
        end
    end
end

function tcp_socket1()
    local succ, rlt
    local ipready, adapter
    -- 创建TCP socket
    sys.wait(2000)
    log.info("begin socket .....")
    -- socket_tcp1 = socket.create(nil, tcptaskname)
    socket_tcp1 = socket.create(nil, tcpevent)

    -- 配置TCP选项
    socket.debug(socket_tcp1, true)               -- 开启调试模式
    socket.config(socket_tcp1, nil, false, false) 
    --socket.keepalive(socket_tcp1, true)           -- 开启TCP Keepalive

    -- 连接TCP服务器
    succ, rlt = socket.connect(socket_tcp1, tcpserver, tcpport)
    log.info("connect rlt1:", succ,rlt)
    if not succ then
        log.info("connect error")
    end

    if not rlt then
        rlt = sysplus.waitMsg(tcptaskname, socket.ON_LINE, 10000)
        log.info("connect rlt2:", rlt)
        if rlt then
            log.info("tcp connect ok")
        end
    else
        log.info("tcp connect ok fast")
    end

    log.info("tcp test begin")

    while true do
        sys.wait(3000)
        ipready, adapter = socket.adapter()
        if ipready then
          socket.tx(socket_tcp1, tcpdata)
          log.info("send:", tcpdata)
        else
          log.info("netword not ready")
        end
    end
end

function tcp_socket2()
    local succ, rlt
    local ipready, adapter
    -- 创建TCP socket
    sys.wait(2000)
    log.info("begin socket .....")
    -- socket_tcp2 = socket.create(nil, tcptaskname)
    socket_tcp2 = socket.create(nil, tcptaskname)

    -- 配置TCP选项
    socket.debug(socket_tcp2, true)               -- 开启调试模式
    socket.config(socket_tcp2, nil, false, false) 
    --socket.keepalive(socket_tcp[]= true)           -- 开启TCP Keepalive

    -- 连接TCP服务器
    succ, rlt = socket.connect(socket_tcp2, tcpserver, tcpport)
    log.info("connect rlt1:", succ,rlt)
    if not succ then
        log.info("connect error")
    end

    if not rlt then
        rlt = sysplus.waitMsg(tcptaskname, socket.ON_LINE, 10000)
        log.info("connect rlt2:", rlt)
        if rlt then
            log.info("tcp connect ok")
        end
    else
        log.info("tcp connect ok fast")
    end

    log.info("tcp test begin")

    while true do
        sys.wait(3000)
        ipready, adapter = socket.adapter()
        if ipready then
          socket.tx(socket_socket_tcp2id_tcp, tcpdata)
          log.info("send:", tcpdata)
        else
          log.info("netword not ready")
        end
    end
end

-- UDP客户端示例（包含所有UDP相关接口）
function udp_socket_demo()
    -- 创建UDP socket
    socket_id_udp = socket.create()
    socket.config(socket_id_udp, nil, true, false) 
    -- 绑定UDP端口 (可选，接收数据用)
    -- socket.bind(socket_id_udp, "0.0.0.0", 5678)

    -- 设置UDP目标地址（重要）
    socket.connect(socket_id_udp, udpserver, udpport)



    while true do
      -- 发送UDP数据
      sys.wait(3000)
      socket.tx(socket_id_udp, udpdata)
      log.info("udp sent:", udpdata)
    end
end

-- DNS解析功能演示
function dns_resolve_demo()
    socket.dns("example.com", function(result, ip)
        if result then
            log.info("DNS sucess", ip)
        else
            log.info("DNS fail")
        end
    end)
end


local function socketinfo()
    while true do
        sys.wait(5000)
        --local info = socket.info()
        log.info("socket info:", info)
    end
end

-- 主任务入口，启动socket示例演示
sysplus.taskInitEx(tcp_socket1, tcptaskname1, tcp_event_handler1)
sysplus.taskInitEx(tcp_socket2, tcptaskname2, tcp_event_handler2)

-- sysplus.taskInitEx(udp_socket_demo, Udptaskname)

--sys.taskInit(dns_resolve_demo)

-- sys.taskInit(socketinfo)

-- 系统启动
sys.run()
