
-- netlab.luatos.com上打开TCP 有测试服务器
local server_ip = "112.125.89.8"
local server_port = 47523
local is_udp = false --用户根据自己实际情况选择

--是UDP服务器就赋值为true，是TCP服务器就赋值为flase
--UDP服务器比TCP服务器功耗低
--如果用户对数据的丢包率有极为苛刻的要求，最好选择TCP

local Heartbeat_interval = 5 -- 发送数据的间隔时间，单位分钟

-- 数据内容  
local heart_data = string.rep("1234567890", 10)
local rxbuf = zbuff.create(8192)

local function netCB(netc, event, param)
    if param ~= 0 then
        sys.publish("socket_disconnect")
        return
    end
    if event == socket.LINK then
    elseif event == socket.ON_LINE then
        -- 链接上服务器以后发送的第一包数据是 hello,luatos
        socket.tx(netc, "hello,luatos!")

    elseif event == socket.EVENT then
        socket.rx(netc, rxbuf)
        socket.wait(netc)
        if rxbuf:used() > 0 then
            log.info("收到", rxbuf:toStr(0, rxbuf:used()), "数据长度", rxbuf:used())
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
    local netc = socket.create(nil, netCB) --创建一个链接
    socket.debug(netc, true)--开启socket层的debug日志，方便寻找问题
    socket.config(netc, nil, is_udp, nil, 300, 5, 6)  --配置TCP链接的参数，开启保活，防止长时间无数据交互服务器踢掉模块
    while true do
        --真正去链接服务器
        local succ, result = socket.connect(netc, server_ip, server_port)
        --链接成功后循环发送数据
        while succ do
            local Heartbeat_interval = Heartbeat_interval * 60 * 1000
            sys.wait(Heartbeat_interval)
            socket.tx(netc, heart_data)
        end
        --链接不成功5S重连一次
        if not succ then
            log.info("未知错误，5秒后重连")
            uart.write(1, "未知错误，5秒后重连")
        else
            local result, msg = sys.waitUntil("socket_disconnect")
        end
        log.info("服务器断开了，5秒后重连")
        uart.write(1, "服务器断开了，5秒后重连")
        socket.close(netc)
        sys.wait(5000)
    end
end

function socketDemo()

    --配置GPIO以达到最低功耗的目的
    gpio.setup(23, nil)
    gpio.close(33) -- 如果功耗偏高，开始尝试关闭WAKEUPPAD1
    gpio.close(35) -- 这里pwrkey接地才需要，不接地通过按键控制的不需要

    --关闭USB以后可以降低约150ua左右的功耗，如果不需要USB可以关闭
    pm.power(pm.USB, false)

     --进入低功耗长连接模式
    pm.power(pm.WORK_MODE, 1)

    sys.taskInit(socketTask)

end

sys.taskInit(socketDemo)

