
-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "psmtcp"
VERSION = "1.0.0"

-- 本DEMO需要V0003 20200810之后的固件版本

-- sys库是标配
_G.sys = require("sys")

local NETLED = gpio.setup(19, 1) -- 输出模式,休眠后就熄灭了

sys.taskInit(function()
    -- 等待联网
    while not socket.isReady() do sys.wait(1000) end
    -- 建立netclient对象
    local netc = socket.tcp()
    netc:host("39.105.203.30")
    netc:port(19001)
    -- 配置好回调
    netc:on("connect", function(id, re)
        log.info("netc", "connect", id, re)
        local data = json.encode({imei=nbiot.imei(),rssi=nbiot.rssi(),iccid=nbiot.iccid()})
        log.info("netc", "send reg package", data)
        netc:send(data, 2)
        sys.publish("NETC_OK")
    end)
    netc:on("recv", function(id, data)
        -- 注意, 唤醒操作, 调用netc:rebind后, 如果基站有缓存的数据, 这里就会被触发
        log.info("netc", "recv", id, data)
        netc:send(data)
    end)
    -- 检查开机原因
    local flag = false
    log.info("pm", "lastReson", pm.lastReson())
    -- 非普通上电/复位上电,那就是唤醒上电咯
    if pm.lastReson() ~= 0 then
        -- 读取低功耗内存的 0x5A 0xA5 ? ? ? ?
        local data = lpmem.read(0, 6)
        -- 打印内容,方便调试
        log.info("lpmem", data:toHex())
        -- 使用pack库解析之
        local _, t1,t2,sockid = pack.unpack(data, ">bbI")
        -- 头两个字符是我们自定义的0x5A 0xA5,不是的话,就肯定是脏数据了
        if t1 == 0x5A and t2 == 0xA5 then
            netc:rebind(sockid) -- 重建tcp上下文
            netc:send(string.char(0), 2) -- 发送心跳
            flag = true
        else
            -- 脏数据就不管了
            log.info("lpmem", "bad custom lpmem data, skip")
        end
    end
    -- 如果不唤醒流程, 或者数据是脏的,就新建连接
    if not flag then
        -- 启动tcp连接线程
        if netc:start() == 0 then
            sys.waitUntil("NETC_OK", 15000)
            if netc:closed() == 0 then
                -- 启动成功, 那就把sockid放入低功耗内存,在唤醒时重建上下文.
                lpmem.write(0, pack.pack(">bbI", 0x5A, 0xA5, netc:sockid()))
            else
                -- 启动,那就重启吧 or 重试2次?
                log.warn("Start netc FAIL!!!")
                sys.wait(15000)
                rtos.reboot()
            end
        else
            -- socket线程都启动失败?什么情况啊
            log.warn("Start netc FAIL!!!")
            sys.wait(15000)
            rtos.reboot()
        end
    end
    --sys.wait(5000)
    -- 5分钟后唤醒,发个心跳, 顺便看看服务器有没有数据下发
    pm.dtimerStart(0, 300000)
    -- 我要睡了!!! 事实上还会等几秒, 这时候服务器还能下发数据
    pm.request(pm.DEEP)
    --sys.wait(300000)
end)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
