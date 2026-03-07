

----------------------------------------
-- 报错信息自动上报到平台,默认是iot.openluat.com
-- 支持自定义, 详细配置请查阅API手册
-- 开启后会上报开机原因, 这需要消耗流量,请留意
if errDump then
    errDump.config(true, 600)
end
----------------------------------------

local wsc = nil

sys.taskInit(function()
    sys.waitUntil("CH390_IP_READY")
    log.info("CH390 联网成功，开始测试")
    socket.dft(socket.LWIP_ETH)
    -- 如果自带的DNS不好用，可以用下面的公用DNS,但是一定是要在CH390联网成功后使用
    -- socket.setDNS(socket.LWIP_ETH,1,"223.5.5.5")	
    -- socket.setDNS(nil,1,"114.114.114.114")


    -- 这是个测试服务, 当发送的是json,且action=echo,就会回显所发送的内容
    -- wsc = websocket.create(nil, "ws://echo.airtun.air32.cn/ws/echo")
    -- 这是另外一个回环测试服务, 能响应websocket的二进制帧
    wsc = websocket.create(nil, "ws://airtest.openluat.com:2900/websocket")
    -- 以上两个测试服务是Java写的, 源码在 https://gitee.com/openLuat/luatos-airtun/tree/master/server/src/main/java/com/luatos/airtun/ws

    if wsc.headers then
        wsc:headers({Auth="Basic ABCDEGG"})
    end
    wsc:autoreconn(true, 3000) -- 自动重连机制
    wsc:on(function(wsc, event, data, fin, optcode)
        -- event 事件, 当前有conack和recv
        -- data 当事件为recv是有接收到的数据
        -- fin 是否为最后一个数据包, 0代表还有数据, 1代表是最后一个数据包
        -- optcode, 0 - 中间数据包, 1 - 文本数据包, 2 - 二进制数据包
        -- 因为lua并不区分文本和二进制数据, 所以optcode通常可以无视
        -- 若数据不多, 小于1400字节, 那么fid通常也是1, 同样可以忽略
        log.info("wsc", event, data, fin, optcode)
        -- 显示二进制数据
        -- log.info("wsc", event, data and data:toHex() or "", fin, optcode)
        if event == "conack" then -- 连接websocket服务后, 会有这个事件
            wsc:send((json.encode({action="echo", device_id=device_id})))
            sys.publish("wsc_conack")
        end
    end)
    wsc:connect()
    -- 等待conack是可选的
    --sys.waitUntil("wsc_conack", 15000)
    -- 定期发业务ping也是可选的, 但为了保存连接, 也为了继续持有wsc对象, 这里周期性发数据
    while true do
        sys.wait(15000)
        -- 发送文本帧
        wsc:send("{\"room\":\"topic:okfd7qcob2iujp1br83nn7lcg5\",\"action\":\"join\"}")
        sys.wait(2000)
        wsc:send((json.encode({action="echo", msg=os.date()})))
        sys.wait(2000)
        -- 发送二进制帧, 2023.06.21 之后编译的固件支持
        wsc:send(string.char(0xA5, 0x5A, 0xAA, 0xF2), 1, 1)
    end
    wsc:close()
    wsc = nil
end)
