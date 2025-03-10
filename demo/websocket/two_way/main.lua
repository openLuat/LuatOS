
PROJECT = "websocket"
VERSION = "1.0.0"

-- sys库是标配
_G.sys = require("sys")

--[[
本示例是2路websocket的示例, 一个连接A, 一个连接B, 均为加密连接, 但同一个服务器
每个连接在100~200毫秒内发送1次数据, 每足够1000次就打印一次日志
]]

sys.taskInit(function()
    if wlan and wlan.connect then
        local ssid = "uiot"
        local password = "12345678"
        log.info("wifi", ssid, password)
        -- TODO 改成esptouch配网
        -- LED = gpio.setup(12, 0, gpio.PULLUP)
        wlan.init()
        -- wlan.setMode(wlan.STATION)
        wlan.connect(ssid, password, 1)
        local result, data = sys.waitUntil("IP_READY", 30000)
        socket.sntp()
        log.info("wlan", "IP_READY", result, data)
        device_id = wlan.getMac()
    elseif rtos.bsp() == "AIR105" then
        w5500.init(spi.HSPI_0, 24000000, pin.PC14, pin.PC01, pin.PC00)
        w5500.config() --默认是DHCP模式
        w5500.bind(socket.ETH0)
        -- LED = gpio.setup(62, 0, gpio.PULLUP)
        sys.wait(1000)
        -- TODO 获取mac地址作为device_id
    elseif mobile then
        --mobile.simid(2)
        -- LED = gpio.setup(27, 0, gpio.PULLUP)
        device_id = mobile.imei()
        sys.waitUntil("IP_READY", 30000)
    end

    -- sys.waitUntil("IP_READY")
    sys.taskInit(ws_task, "A")
    sys.taskInit(ws_task, "B")
end)

function ws_task(my_name)
    local wsc = nil
    -- 这是个测试服务, 当发送的是json,且action=echo,就会回显所发送的内容
    wsc = websocket.create(nil, "wss://echo.airtun.air32.cn/ws/echo")
    -- 这是另外一个测试服务, 能响应websocket的二进制帧
    -- wsc = websocket.create(nil, "ws://echo.airtun.air32.cn/ws/echo2")
    -- 以上两个测试服务是Java写的, 源码在 https://gitee.com/openLuat/luatos-airtun/tree/master/server/src/main/java/com/luatos/airtun/ws

    if wsc.headers then
        wsc:headers({Auth="Basic ABCDEGG"})
    end
    wsc:autoreconn(true, 3000) -- 自动重连机制
    local counter = 0
    wsc:on(function(wsc, event, data, fin, optcode)
        -- event 事件, 当前有conack和recv
        -- data 当事件为recv是有接收到的数据
        -- fin 是否为最后一个数据包, 0代表还有数据, 1代表是最后一个数据包
        -- optcode, 0 - 中间数据包, 1 - 文本数据包, 2 - 二进制数据包
        -- 因为lua并不区分文本和二进制数据, 所以optcode通常可以无视
        -- 若数据不多, 小于1400字节, 那么fid通常也是1, 同样可以忽略
        if counter % 1000 == 0 then
            log.info("wsc."..my_name, event, counter)
        end
        counter = counter + 1
        -- 显示二进制数据
        -- log.info("wsc", event, data and data:toHex() or "", fin, optcode)
        if event == "conack" then -- 连接websocket服务后, 会有这个事件
            log.error("wsc_conack." .. my_name, "CONACK 事件!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!")
            wsc:send((json.encode({action="echo", device_id=device_id})))
            sys.publish("wsc_conack." .. my_name)
        end
    end)
    wsc:connect()
    -- 等待conack是可选的
    --sys.waitUntil("wsc_conack", 15000)
    -- 定期发业务ping也是可选的, 但为了保存连接, 也为了继续持有wsc对象, 这里周期性发数据
    while true do
        sys.wait(math.random(100, 200))
        -- 发送文本帧
        -- wsc:send("{\"room\":\"topic:okfd7qcob2iujp1br83nn7lcg5\",\"action\":\"join\"}")
        wsc:send((json.encode({action="echo", msg=os.date(), lua=rtos.meminfo(), sys=rtos.meminfo("sys"),psram=rtos.meminfo("psram")})))
        -- 发送二进制帧, 2023.06.21 之后编译的固件支持
        -- wsc:send(string.char(0xA5, 0x5A, 0xAA, 0xF2), 1, 1)
    end
    wsc:close()
    wsc = nil
end



-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
