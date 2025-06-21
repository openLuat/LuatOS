-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "scdemo"
VERSION = "1.0.0"

log.info("main", PROJECT, VERSION)

libnet = require "libnet"

if wdt then
    --添加硬狗防止程序卡死，在支持的设备上启用这个功能
    wdt.init(9000)--初始化watchdog设置为9s
    sys.timerLoopStart(wdt.feed, 3000)--3s喂一次狗
end

--Uart初始化  
local uartid = 1 -- 根据实际设备选取不同的uartid
uart.setup(
    uartid,--串口id
    115200,--波特率
    8,--数据位
    1--停止位
)

--=============================================================
-- 测试网站 https://netlab.luatos.com/ 点击 打开TCP 获取测试端口号
-- 要按实际情况修改
local host = "112.125.89.8" -- 服务器ip或者域名, 都可以的
local port = 47500          -- 服务器端口号
local is_udp = true         -- 如果是UDP, 要改成true, false就是TCP
local is_tls = false        -- 加密与否, 要看服务器的实际情况
--=============================================================

-- 处理未识别的网络消息
local function netCB(msg)
    log.info("未处理消息", msg[1], msg[2], msg[3], msg[4])
end

-- 统一联网函数
sys.taskInit(function()
    local res,data
    -----------------------------
    -- 统一联网函数, 可自行删减
    ----------------------------
    ----- time 为修复网络时间过长而修订为 while主体，增加网络状态判断
    while true do
        if wlan and wlan.connect then
            -- wifi 联网,要根据实际情况修改ssid和password!!
            local ssid = "kfyy_7890"
            local password = "kfyy123456"
            log.info("wifi", ssid, password)
            -- TODO 改成自动配网
            wlan.init()
            wlan.setMode(wlan.STATION) -- 默认也是这个模式,不调用也可以
            wlan.connect(ssid, password, 1)
            -- 在网络连接成功时，会发布一个系统消息 IP_READY，而
            -- sys.waitUntil 订阅此消息，能在设置的时间内收到此消息
            -- 即表示网络连接成功。
            res, data = sys.waitUntil("IP_READY", 30000)
            log.info("wlan", "IP_READY", result, data)
         else
            -- 其他不认识的bsp, 循环提示一下吧
            while 1 do
                sys.wait(1000)
                log.info("bsp", "本bsp可能未适配网络层, 请查证")
            end
        end

        if res == true then
            log.info("已联网")
            sys.publish("net_ready")
        end
        ----- time 为修复网络时间过长而修订为 while主体，增加网络状态判断
        while wlan and wlan.ready() do
            sys.wait(4000)
        end
    end
end)

-- 演示task
local function sockettest()
    -- 等待联网
    sys.waitUntil("net_ready")
    -- sntp时间同步
    socket.sntp()

    -- 开始正在的逻辑, 发起socket链接,等待数据/上报心跳
    local taskName = "sc"
    local topic = taskName .. "_txrx"
    log.info("topic", topic)
    local txqueue = {}
    sysplus.taskInitEx(sockettask, taskName, netCB, taskName, txqueue, topic)
    while 1 do
        local result, tp, data = sys.waitUntil(topic, 30000)
        log.info("event", result, tp, data)
        if not result then
            -- 等待30秒,没数据上传/下发, 发个日期心跳包吧
            table.insert(txqueue, os.date())
            sys_send(taskName, socket.EVENT, 0)
        elseif tp == "uplink" then
            -- 上行数据, 主动上报的数据,那就发送呀
            table.insert(txqueue, data)
            sys_send(taskName, socket.EVENT, 0)
        elseif tp == "downlink" then
            -- 下行数据,接收的数据
            -- 其他代码可以通过 sys.publish()
            log.info("socket", "收到下发的数据了", #data)
        end
    end
end

function sockettask(d1Name, txqueue, rxtopic)
    -- 打印准备连接的服务器信息
    log.info("socket", host, port, is_udp and "UDP" or "TCP", is_tls and "TLS" or "RAW")

    -- 准备好所需要的接收缓冲区
    local rx_buff = zbuff.create(1024)
    local netc = socket.create(nil, d1Name)
    socket.config(netc, nil, is_udp, is_tls)
    log.info("任务id", d1Name)

    while true do
        -- 连接服务器, 15秒超时
        log.info("socket", "开始连接服务器")
        sysplus.cleanMsg(d1Name)
        local result = libnet.connect(d1Name, 15000, netc, host, port)
        if result then
            log.info("socket", "服务器连上了")
            libnet.tx(d1Name, 0, netc, "helloworld")
        else
            log.info("socket", "服务器没连上了!!!")
        end
        while result do
            -- 连接成功之后, 先尝试接收
            -- log.info("socket", "调用rx接收数据")
            local succ, param = socket.rx(netc, rx_buff)
            if not succ then
                log.info("服务器断开了", succ, param, ip, port)
                break
            end
            -- 如果服务器有下发数据, used()就必然大于0, 进行处理
            if rx_buff:used() > 0 then
                log.info("socket", "收到服务器数据，长度", rx_buff:used())
                local data = rx_buff:query() -- 获取数据
                sys.publish(rxtopic, "downlink", data)
                uart.tx(uartid, rx_buff)    -- 从服务器收到的数据转发 从串口输出
                rx_buff:del()
            end
            -- log.info("libnet", "调用wait开始等待消息")
            -- 等待事件, 例如: 服务器下发数据, 有数据准备上报, 服务器断开连接
            result, param, param2 = libnet.wait(d1Name, 15000, netc)
            log.info("libnet", "wait", result, param, param2)
            if not result then
                -- 网络异常了, 那就断开了, 执行清理工作
                log.info("socket", "服务器断开了", result, param)
                break
            elseif #txqueue > 0 then
                -- 有待上报的数据,处理之
                while #txqueue > 0 do
                    local data = table.remove(txqueue, 1)
                    if not data then
                        break
                    end
                    result,param = libnet.tx(d1Name, 15000, netc,data)
                    -- log.info("libnet", "发送数据的结果", result, param)
                    if not result then
                        log.info("socket", "数据发送异常", result, param)
                        break
                    end
                end
            end
            -- 循环尾部, 继续下一轮循环
        end
        -- 能到这里, 要么服务器断开连接, 要么上报(tx)失败, 或者是主动退出
        libnet.close(d1Name, 5000, netc)
        -- log.info(rtos.meminfo("sys"))
        sys.wait(30000) -- 这是重连时长, 自行调整
    end
end

sys.taskInit(sockettest)

-- -- 演示定时上报数据, 不需要就注释掉
-- sys.taskInit(function()
--     sys.wait(5000)
--     while 1 do
--         sys.publish("sc_txrx", "uplink", os.date())
--         sys.wait(3000)
--     end
-- end)

-- 演示uart数据上报, 不需要就注释掉
    uart.on(uartid, "receive", function(id, len)
        while 1 do
            local s = uart.read(1, 1024)
            if #s == 0 then
                break
            end
            sys.publish("sc_txrx", "uplink", s)
            if #s == len then
                break
            end
        end
    end)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
