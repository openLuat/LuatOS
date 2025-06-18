-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "scdemo"
VERSION = "1.0.0"
log.info("main", PROJECT, VERSION)
-- 一定要添加sys.lua !!!!
sys = require("sys")
_G.sysplus = require("sysplus")
local taskName = "UDP_TASK"             -- sysplus库用到的任务名称，也作为任务id
if wdt then
    --添加硬狗防止程序卡死，在支持的设备上启用这个功能
    wdt.init(9000)--初始化watchdog设置为9s
    sys.timerLoopStart(wdt.feed, 3000)--3s喂一次狗
end
local uart_rx_buff = zbuff.create(1024)     -- 串口接收到的数据
----------------------------网络配置---------------------------
local libnet = require "libnet"         -- libnet库，支持tcp、udp协议所用的同步阻塞接口
local ip = "112.125.89.8"               -- 连接UDP服务器的ip地址
local port = 46139                      -- 连接UDP服务器的端口
local netCB = nil                       -- socket服务的回调函数
local connect_state = false             -- 连接状态 true:已连接   false:未连接
local protocol = true                  -- 通讯协议 true:UDP协议  false:TCP协议
local ssl = false                       -- 加密传输 true:加密     false:不加密
local tx_buff = zbuff.create(1024)     -- 发送至UDP服务器的数据
local rx_buff = zbuff.create(1024)     -- 从UDP服务器接收到的数据
--==============================================================
--Uart初始化  
local uartid = 1 -- 根据实际设备选取不同的uartid
uart.setup(
    uartid,--串口id
    115200,--波特率
    8,--数据位
    1--停止位
)
function UDP_TASK()
    -- 打印一下连接的目标ip和端口号
    log.info("connect ip: ", ip, "port:", port)
    sys.waitUntil("IP_READY")                -- 等待联网成功
    netCB = socket.create(nil, taskName)     -- 创建socket对象
    socket.debug(netCB, true)                -- 打开调试日志
    socket.config(netCB, nil, protocol, ssl)      -- 此配置为UDP连接，无SSL加密
    -- 串口和UDP服务器的交互逻辑
    while true do
        -- 连接服务器，返回是否连接成功
        local result = libnet.connect(taskName, 15000, netCB, ip, port)
        -----查询网络状态
        local status = mobile.status()    
        log.info("status", status) 
        
        -- 收取数据会触发回调, 这里的"receive" 是固定值不要修改。
        log.info("connect ip: 等待连接 ",result)
        uart.on(uartid, "receive", function(id, len)
            while true do
                local len = uart.rx(id, uart_rx_buff)   -- 接收串口收到的数据，并赋值到uart_rx_buff
                if len <= 0 then    -- 接收到的字节长度为0 则退出
                    break
                end
                -- 如果已经在线了，则发送socket.EVENT消息来打断任务里的阻塞等待状态，让任务循环继续
                if connect_state then
                    sys_send(taskName, socket.EVENT, 0)
                end
            end
        end)
        -- 如果连接成功，则改变连接状态参数，并且随便发一条数据到服务器，看服务器能不能收到
        if result then
            log.info("connect ip: 连接成功")
            connect_state = true
           libnet.tx(taskName, 0, netCB, "UDP CONNECT")
        end
        -- 连接上服务器后，等待处理接收服务器下行至模块的数据 和 发送串口的数据到服务器
        while result do
            succ, param, _, _ = socket.rx(netCB, rx_buff)   -- 接收数据
            if not succ then
                log.info("服务器断开了", succ, param, ip, port)
                break
            end
            if rx_buff:used() > 0 then
                log.info("收到服务器数据，长度", rx_buff:used())
               uart.tx(uartid, rx_buff)    -- 从服务器收到的数据转发 从串口输出
                rx_buff:del()
            end
            tx_buff:copy(nil, uart_rx_buff)         -- 将串口数据赋值给UDP待发送数据的buff中
            uart_rx_buff:del()                      -- 清除串口buff的数据长度
            if tx_buff:used() > 0 then
                log.info("发送到服务器数据，长度", tx_buff:used())
                local result = libnet.tx(taskName, 0, netCB, tx_buff)   -- 发送数据
                if not result then
                    log.info("发送失败了", result, param)
                    break
                end
            end
            tx_buff:del()
            -- 如果zbuff对象长度超出，需要重新分配下空间
            if uart_rx_buff:len() > 1024 then
                uart_rx_buff:resize(1024)
            end
            if tx_buff:len() > 1024 then
                tx_buff:resize(1024)
            end
            if rx_buff:len() > 1024 then
                rx_buff:resize(1024)
            end
            log.info(rtos.meminfo("sys"))   -- 打印系统内存
            -- 阻塞等待新的消息到来，比如服务器下发，串口接收到数据
            result, param = libnet.wait(taskName, 15000, netCB)
            if not result then
                log.info("服务器断开了", result, param)
                break
            end
        end
        -- 服务器断开后的行动，由于while true的影响，所以会再次重新执行进行 重新连接。
        connect_state = false
        libnet.close(taskName, 5000, netCB)
        tx_buff:clear(0)
        rx_buff:clear(0)
        sys.wait(1000)
    end
end
-- libnet库依赖于sysplus，所以只能通过sysplus.taskInitEx创建的任务函数中运行
sysplus.taskInitEx(UDP_TASK, taskName, netCB)
-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!