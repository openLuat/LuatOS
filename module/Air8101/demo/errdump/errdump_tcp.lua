--[[
本功能模块演示的内容为：
使用Air8101开发板来演示errdump日志上报功能
手动读取异常日志上传到自己平台
]]
local taskName = "TCP_TASK"
local libnet = require "libnet"         -- libnet库，支持tcp、udp协议所用的同步阻塞接口
local ip = "112.125.89.8"               -- 连接tcp服务器的ip地址
local port = 47043                -- 连接tcp服务器的端口
local connect_state = false             -- 连接状态 true:已连接   false:未连接
local protocol = false                  -- 通讯协议 true:UDP协议  false:TCP协议
local ssl = false                       -- 加密传输 true:加密     false:不加密
local tx_buff = zbuff.create(1024)      -- 发送至tcp服务器的数据
local rx_buff = zbuff.create(1024)      -- 从tcp服务器接收到的数据
-- 统一联网函数
sys.taskInit(function()
    sys.wait(1000)
    -----------------------------
    ---------wifi 联网-----------
    -----------------------------
    if wlan and wlan.connect then
        -- wifi 联网, ESP32系列均支持
        local ssid = "kfyy123"
        local password = "kfyy123456"
        log.info("wifi", ssid, password)
        -- TODO 改成esptouch配网
        -- LED = gpio.setup(12, 0, gpio.PULLUP)
        wlan.init()
        wlan.setMode(wlan.STATION)
        wlan.connect(ssid, password, 1)
        local result, data = sys.waitUntil("IP_READY")
        log.info("wlan", "IP_READY", result, data)
        device_id = wlan.getMac()
    end
    log.info("已联网")
    sys.publish("net_ready")
end)

-- 处理未识别的消息
local function tcp_client_main_cbfunc(msg)
	log.info("tcp_client_main_cbfunc", msg[1], msg[2], msg[3], msg[4])
end

function TCP_TASK()
    -- 打印一下连接的目标ip和端口号
    log.info("connect ip: ", ip, "port:", port)
    sys.waitUntil("IP_READY")                -- 等待联网成功
    local socket_client
    while true do
        socket_client = socket.create(nil, taskName)     -- 创建socket对象
        socket.debug(socket_client, true)                      -- 打开调试日志
        socket.config(socket_client, nil, protocol, ssl)       -- 此配置为TCP连接，无SSL加密
        -- 连接服务器，返回是否连接成功
        result = libnet.connect(taskName, 15000, socket_client, ip, port)
        -- 如果连接成功，则改变连接状态参数，并且随便发一条数据到服务器，看服务器能不能收到
        if result then
            connect_state = true
            libnet.tx(taskName, 0, socket_client, "TCP  CONNECT")
        end
        while result do
            succ, param, _, _ = socket.rx(socket_client, rx_buff) -- 接收数据
            if not succ then
                log.info("服务器断开了", succ, param, ip, port)
                break
            end
            if rx_buff:used() > 0 then
                log.info("收到服务器数据，长度", rx_buff:used())
                rx_buff:del()
            end
            if tx_buff:used() > 0 then
                log.info("发送到服务器数据，长度", tx_buff:used())
                local result = libnet.tx(taskName, 0, socket_client, tx_buff) -- 发送数据
                if not result then
                    log.info("发送失败了", result, param)
                    break
                end
            end
            tx_buff:del()

            if tx_buff:len() > 1024 then
                tx_buff:resize(1024)
            end
            if rx_buff:len() > 1024 then
                rx_buff:resize(1024)
            end
            result, param = libnet.wait(taskName, 15000, socket_client)
            if not result then
                log.info("服务器断开了", result, param)
                break
            end
        end
        -- 服务器断开后的行动，由于while true的影响，所以会再次重新执行进行 重新连接。
        connect_state = false
        libnet.close(d1Name, 5000, socket_client)
        socket.release(socket_client)
        tx_buff:clear(0)
        rx_buff:clear(0)
        socket_client=nil
        sys.wait(1000)
    end
end

local function test_user_log()
    -- 下面演示手动获取异常日志信息,手动读取到异常日志可以上报到自己服务器
    errDump.config(true, 0) --配置为手动读取，如果配置为自动上报将无法手动读取系统异常日志
    local err_buff = zbuff.create(4096)
    local new_flag = errDump.dump(err_buff, errDump.TYPE_SYS) -- 开机手动读取一次异常日志
    if err_buff:used() > 0 then
        -- log.info(err_buff:toStr(0, err_buff:used())) -- 打印出异常日志
        tx_buff:copy(nil, err_buff)
        err_buff:del()
        if d1Online then	-- 如果已经在线了，则发送socket.EVENT消息来打断任务里的阻塞等待状态，让任务循环继续
	    	sys_send(d1Name, socket.EVENT, 0)
	    end
    end
    new_flag = errDump.dump(err_buff, errDump.TYPE_SYS) --	errDump.dumpf返回值：true表示本次读取前并没有写入数据，false反之，在删除日志前，最好再读一下确保没有新的数据写入了
    if not new_flag then
        log.info("没有新数据了，删除系统错误日志")
        errDump.dump(nil, errDump.TYPE_SYS, true)
    end
    while true do
        sys.wait(15000)
        errDump.record("测试一下用户的记录功能") --写入用户的日志，注意最大只有4KB，超过部分新的覆盖旧的
        local new_flag = errDump.dump(err_buff, errDump.TYPE_USR)
        if new_flag then
            log.info("errBuff", err_buff:toStr(0, err_buff:used()))
            tx_buff:copy(nil, err_buff)
			err_buff:del()
            if d1Online then	-- 如果已经在线了，则发送socket.EVENT消息来打断任务里的阻塞等待状态，让任务循环继续
                sys_send(d1Name, socket.EVENT, 0)
            end
        end
        new_flag = errDump.dump(err_buff, errDump.TYPE_USR)
        if not new_flag then
            log.info("没有新数据了，删除用户错误日志")
            errDump.dump(nil, errDump.TYPE_USR, true)
        end
    end
end

local function test_error_log() --故意写错用来触发系统异常日志记录
	sys.wait(60000)
	lllllllllog.info("测试一下用户的记录功能") --默认写错代码死机
end


-- libnet库依赖于sysplus，所以只能通过sysplus.taskInitEx创建的任务函数中运行
sysplus.taskInitEx(TCP_TASK, taskName, tcp_client_main_cbfunc) --启动tcp task
sys.taskInit(test_user_log) -- 启动errdemp测试任务
sys.taskInit(test_error_log)--启动错误函数任务
