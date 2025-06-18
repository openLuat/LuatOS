
PROJECT = "airtun"
VERSION = "1.0.0"

-- sys库是标配
_G.sys = require("sys")
-- _G.sysplus = require("sysplus")


-- Air780E的AT固件默认会为开机键防抖, 导致部分用户刷机很麻烦
if rtos.bsp() == "EC618" and pm and pm.PWK_MODE then
    pm.power(pm.PWK_MODE, false)
end

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

    sys.waitUntil("IP_READY")                -- 等待联网成功

    -- 这是个测试服务, 当发送的是json,且action=echo,就会回显所发送的内容
    -- 加密TCP链接 wss 表示加密
    wsc = websocket.create(nil, "wss://echo.airtun.air32.cn/ws/echo")
    -- 这是另外一个测试服务, 能响应websocket的二进制帧
    -- wsc = websocket.create(nil, "ws://echo.airtun.air32.cn/ws/echo2")
    -- 以上两个测试服务是Java写的, 源码在 https://gitee.com/openLuat/luatos-airtun/tree/master/server/src/main/java/com/luatos/airtun/ws

    if wsc.headers then
        wsc:headers({Auth="Basic ABCDEGG"})
    end
    wsc:autoreconn(true, 3000) -- 自动重连机制
    wsc:on(function(wsc, event, data, fin, optcode)
        --[[
            event的值有:
            conack 连接服务器成功,已经收到websocket协议头部信息,通信已建立
            recv   收到服务器下发的信息, data, payload 不为nil
            sent   send函数发送的消息,服务器在TCP协议层已确认收到
            disconnect 服务器连接已断开

            其中 sent/disconnect 事件在 2023.04.01 新增
        ]]
        -- data 当事件为recv是有接收到的数据
        -- fin 是否为最后一个数据包, 0代表还有数据, 1代表是最后一个数据包
        -- optcode, 0 - 中间数据包, 1 - 文本数据包, 2 - 二进制数据包
        -- 因为lua并不区分文本和二进制数据, 所以optcode通常可以无视
        -- 若数据不多, 小于1400字节, 那么fid通常也是1, 同样可以忽略
        log.info("wsc", event, data, fin, optcode)
        -- 显示二进制数据
        -- log.info("wsc", event, data and data:toHex() or "", fin, optcode)
        if event == "conack" then -- 连接websocket服务后, 会有这个事件
            log.info("WebSocket connect succeed!")
            sys.publish("wsc_conack")
        end
    end)
    wsc:connect()
    -- 等待conack是可选的
    sys.waitUntil("wsc_conack")
    --local stat = wsc:ready()
    -- 定期发业务ping也是可选的, 但为了保存连接, 也为了继续持有wsc对象, 这里周期性发数据
    while true do
        wsc:send((json.encode({action="echo", msg=os.date()})))
        sys.wait(15000)
        -- 发送二进制帧, 2023.06.21 之后编译的固件支持
        -- wsc:send(string.char(0xA5, 0x5A, 0xAA, 0xF2), 1, 1)
    end
    wsc:close()
    wsc = nil
end)


-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
