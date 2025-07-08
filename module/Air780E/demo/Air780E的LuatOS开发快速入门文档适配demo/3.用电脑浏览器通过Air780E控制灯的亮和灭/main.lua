-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "udpsrvdemo"
VERSION = "1.0.0"

-- sys库是标配
_G.sys = require("sys")

sysplus = require("sysplus")
libnet = require "libnet"

-- =============================================================
-- 测试网站 https://netlab.luatos.com/ 点击 打开UDP 获取测试端口号
-- 要按实际情况修改
local host = "netlab.luatos.com" -- 服务器ip或者域名, 都可以的
local port = 47966 -- 服务器端口号
local is_udp = true -- 如果是UDP, 要改成true, false就是TCP
local is_tls = false -- 加密与否, 要看服务器的实际情况
-- =============================================================

-- 设置灯的输出模式
gpio.setup(27, 0, gpio.PULLUP)

sys.taskInit(function()
    while 1 do
        local result, rx_data = sys.waitUntil("sc_txrx", 30000)
        if result then
            log.info("sys.waitUntil接收到数据")
            --[[在接收的数据rx_data中，寻找ledon出现的位置，如果找到
                会返回第一次出现的位置和最后出现的位置。
            ]]
            local s, e = string.find(rx_data, "ledon")
            if s == 1 and e == 5 then
                gpio.set(27, 1)
                log.info("开灯")
            end
            local s2, e2 = string.find(rx_data, "ledoff")
            if s2 == 1 and e2 == 6 then
                gpio.set(27, 0)
                log.info("关灯")
            end
        else
            log.info("发布keepalive,waitUntil的返回值为: ", result)
            -- 发送心跳
            sys.publish("keepalive")
        end
    end
end)

-- 连接函数
-- function socketTask(rxtopic)
sys.taskInit(function()
    sys.waitUntil("IP_READY")
    -- 创建一个用于接收UDP服务器下发数据的数组
    local rx_buff = zbuff.create(1024)

    -- 申请一个socket_ctrl
    local netc = socket.create(nil)
    --[[配置network一些信息
        @param1 socket_ctrl
        @param2 本地端口号，不写会自动分配一个
        @parma3 是否是UDP
        @param4 是否是加密传输
    ]]
    local config_succ = socket.config(netc, nil, is_udp, false)
    if not config_succ then
        log.info("socket.config", "服务器配置失败")
    end

    -- 订阅心跳消息
    sys.subscribe("keepalive", function()
        succ, full, result = socket.tx(netc, "keepalive" .. os.date())
        log.info("socket", "心跳包发送数据的结果", succ, full, result)
    end)

    while config_succ do
        --[[连接服务器，超时时间15秒
            @param1 任务id
            @param2 连接超时时间
            @param3 socket_ctrl
            @param4 ip地址或域名
            @param5 服务器端口号
            @param6 域名解析是否要IPV6，默认false，只有支持IPV6的协议栈才有效果
            return 失败或超时返回false，成功返回true
        ]]
        local succ,result = socket.connect(netc, host, port)
        if succ then
            log.info("socket", "服务器连接成功")
            sys.wait(1000)
            --[[发一个数据试试是否连接成功
                @param1 socket.create()创建的socket_ctrl
                @param2 要发送的数据
            ]]
            socket.tx(netc, "hello world!!!")
        end

        -- 连接服务器成功后，开始进行接收服务器数据操作
        while succ do
            --[[先接收一次数据包，数据已经缓存在底层，使用本函数只是提取出来
                @param1 socket_ctrl
                @param2 存放接收数据的zbuff
            ]]
            local succ, rx_len = socket.rx(netc, rx_buff)
            --[[对接收到的数据进行处理
                rx_buff:used()代表rx_buff内的数据长度
            ]]
            if rx_buff:used() > 0 then
                local rx_data = rx_buff:query()
                log.info("socket", "接收到的数据为:", rx_data)
                sys.publish("sc_txrx", rx_data)
                rx_buff:del()
            end

            -- 等待接收数据处理完成
            sys.wait(500)
        end
        sys.wait(2000)
    end
    socket.close(netc)
end)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
