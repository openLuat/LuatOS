
local taskName = "TCP_TASK" -- sysplus库用到的任务名称，也作为任务id

local uartid = 1                        -- 根据实际设备选取不同的uartid
local uart_rx_buff = zbuff.create(1024) -- 串口接收到的数据
local libnet = require "libnet"         -- libnet库，支持tcp、udp协议所用的同步阻塞接口
local ip = "112.125.89.8"               -- 连接tcp服务器的ip地址
local port = 43231                      -- 连接tcp服务器的端口
local netCB = nil                       -- socket服务的回调函数
local connect_state = false             -- 连接状态 true:已连接   false:未连接
local protocol = false                  -- 通讯协议 true:UDP协议  false:TCP协议
local ssl = false                       -- 加密传输 true:加密     false:不加密
local tx_buff = zbuff.create(1024)      -- 发送至tcp服务器的数据
local rx_buff = zbuff.create(1024)      -- 从tcp服务器接收到的数据


exnetif.notifyStatus(function(net_type)
    log.info("可以使用优先级更高的网络:", net_type)
    connect_state = false
end)


--初始化
uart.setup(
    uartid, --串口id
    115200, --波特率
    8,      --数据位
    1       --停止位
)
function TCP_TASK()
    -- 打印一下连接的目标ip和端口号
    log.info("connect ip: ", ip, "port:", port)

    sys.waitUntil("IP_READY")                -- 等待联网成功
    netCB = socket.create(nil, taskName)     -- 创建socket对象，设置为4G上网方式，如果是wifi 上网，需要设置为socket.LWIP_STA
    socket.debug(netCB, true)                -- 打开调试日志
    socket.config(netCB, nil, protocol, ssl) -- 此配置为TCP连接，无SSL加密

    -- 串口和TCP服务器的交互逻辑
    while true do
        -- 连接服务器，返回是否连接成功
        result = libnet.connect(taskName, 15000, netCB, ip, port)



        -- 如果连接成功，则改变连接状态参数，并且随便发一条数据到服务器，看服务器能不能收到
        if result then
            connect_state = true
            libnet.tx(taskName, 0, netCB, "TCP  CONNECT")
        end

        -- 连接上服务器后，等待处理接收服务器下行至模块的数据 和 发送串口的数据到服务器
        while result do
            succ, param, _, _ = socket.rx(netCB, rx_buff) -- 接收数据
            if not succ then
                log.info("服务器断开了", succ, param, ip, port)
                break
            end

            if rx_buff:used() > 0 then
                log.info("收到服务器数据，长度", rx_buff:used())

                uart.tx(uartid, rx_buff) -- 从服务器收到的数据转发 从串口输出
                rx_buff:del()
            end

            log.info(rtos.meminfo("sys")) -- 打印系统内存
            log.info("connect_state", connect_state)
            -- 阻塞等待新的消息到来，比如服务器下发，串口接收到数据
            result, param = libnet.wait(taskName, 15000, netCB)
            if not result then
                log.info("服务器断开了", result, param)
                break
            end
            if connect_state == false then
                log.info("断开连接")
                break
            end
        end

        -- 服务器断开后的行动，由于while true的影响，所以会再次重新执行进行 重新连接。
        connect_state = false
        libnet.close(taskName, 5000, netCB)
        socket.release(netCB)
        netCB = socket.create(nil, taskName)     -- 创建socket对象，设置为4G上网方式，如果是wifi 上网，需要设置为socket.LWIP_STA
        socket.debug(netCB, true)                -- 打开调试日志
        socket.config(netCB, nil, protocol, ssl) -- 此配置为TCP连接，无SSL加密
        tx_buff:clear(0)
        rx_buff:clear(0)
        sys.wait(1000)
    end
end

-- libnet库依赖于sysplus，所以只能通过sysplus.taskInitEx创建的任务函数中运行
sysplus.taskInitEx(TCP_TASK, taskName, netCB)