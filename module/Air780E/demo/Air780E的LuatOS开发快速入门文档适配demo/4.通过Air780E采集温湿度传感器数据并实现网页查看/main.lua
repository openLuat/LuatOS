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

--设置dht11传感器的out引脚与780E开发板的连接引脚
local dht11_pin = 7

sys.taskInit(function()
    while 1 do
        local result, rx_data = sys.waitUntil("sc_txrx", 30000)
        if not result then
            log.info("发布keepalive,waitUntil的返回值为: ", result)
            -- 如果sys.waitUntil30秒内没收到消息sc_txrx，则发送一次心跳
            sys.publish("keepalive")
        end
    end
end)

-- 连接函数
sys.taskInit(function()
    sys.waitUntil("IP_READY")

    -- 申请一个socket_ctrl
    local netc = socket.create(nil,"MySocket")
    --[[配置network一些信息
        @param1 socket_ctrl
        @param2 本地端口号，不写会自动分配一个
        @parma3 是否是UDP
        @param4 是否是加密传输
    ]]
    local config_succ = socket.config(netc, nil, is_udp, is_tls)
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
        else
            log.info("socket", "服务器连接失败")
        end

        -- 连接服务器成功后，开始进行向服务器发送温湿度数据操作
        while succ do
            --[[读取dht11传感器的数值
                @param1  dht11的out引脚连接780E开发板的引脚号
                @param2  是否校验读取到的值，true为校验
                @return1 湿度值，单位为0.01%
                @return2 温度值 单位为0.01%
                @return  成功返回true，失败返回false
            ]]
            local h,t,r = sensor.dht1x(dht11_pin, true)
            if r then
                --[[
                    ..为字符串的连接符，
                    例如log.info("hello".."world")打印出来就是helloworld
                ]]
                local data = "湿度:".. (h/100) .. "\r\n".. "温度:".. (t/100)
                log.info("dht1x",data)
                --将温湿度的数据上传到web服务器
                local succ,full,result = socket.tx(netc,data)
                if not succ then
                    log.info("socket","温湿度数据上传失败")
                end
                --[[如果成功向web服务器上传了数据，则发布消息"sc_txrx"
                    如果在30秒内没发送过消息，则会发一个心跳指令
                ]]
                sys.publish("sc_txrx")
            else
                log.info("温湿度值校验失败")
            end
            sys.wait(3000)
        end
        sys.wait(2000)
    end
    socket.close(netc)
end)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
