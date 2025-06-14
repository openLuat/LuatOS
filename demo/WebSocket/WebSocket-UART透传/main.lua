
PROJECT = "airtun"
VERSION = "1.0.0"

_G.sys = require("sys")

if wdt then
    --添加硬狗防止程序卡死，在支持的设备上启用这个功能
    wdt.init(9000)--初始化watchdog设置为9s
    sys.timerLoopStart(wdt.feed, 3000)--3s喂一次狗
end
-- ----------------------------------------
-- 报错信息自动上报到平台,默认是iot.openluat.com
-- 支持自定义, 详细配置请查阅API手册
-- 开启后会上报开机原因, 这需要消耗流量,请留意
if errDump then
    errDump.config(true, 600)
end
-- ----------------------------------------
local uart_rx_buff = zbuff.create(1024)
local uartid = 1
local Sbuf = 0
local uart_rx_buff_data = ""

-- 初始化UART
uart.setup(uartid, 115200, 8, 1)

local wsc = nil

-- UART接收处理函数
local function uartReceiveHandler(id)
    local len = uart.rx(id, uart_rx_buff)
    if len > 0 then
        uart_rx_buff:seek(0)
        uart_rx_buff_data = uart_rx_buff:read(len)
        -- 去除可能的换行和空白字符
        uart_rx_buff_data = uart_rx_buff_data:gsub("[\r\n]", ""):match("^%s*(.-)%s*$")
        Sbuf = len
        log.info("UART接收的数据包", uart_rx_buff_data)
    end
end

sys.taskInit(function()
    sys.waitUntil("IP_READY")
    -- 这是个测试服务, 当发送的是json,且action=echo,就会回显所发送的内容
    -- 加密TCP链接 wss 表示加密
    -- 注册UART接收回调
    uart.on(uartid, "receive", uartReceiveHandler)

    -- 创建WebSocket连接
    wsc = websocket.create(nil, "wss://echo.airtun.air32.cn/ws/echo")
    
    if wsc.headers then
        wsc:headers({Auth="Basic ABCDEGG"})
    end
    
    wsc:autoreconn(true, 3000)
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
        if event == "conack" then
            log.info("WebSocket连接成功!")
            sys.publish("wsc_conack")
        end
    end)
    
    wsc:connect()
    sys.waitUntil("wsc_conack")
    log.info("websocket链接成功")

    while true do
        if Sbuf > 0 then
            log.info("准备发送数据到服务器，长度", Sbuf)
            log.info("原始数据:", uart_rx_buff_data)
            log.info("UART发送到服务器的数据包类型 ",type(uart_rx_buff_data))
            -- 检查是否是echo命令
            if uart_rx_buff_data == '"echo"'  then-- 连接收到串口发送的echo ，会进行数据发送
                log.info("UART透传成功 进行数据发送")
                log.info("收到echo命令，发送数据")
                local response = json.encode({
                    action = "echo",
                    msg = os.date("%a %Y-%m-%d %H:%M:%S"), -- %a表示星期几缩写
                })
                wsc:send(response)
            else
                -- 其他数据直接转发
                log.info("转发普通数据")
                wsc:send(uart_rx_buff_data)
            end
            
            -- 重置状态
            Sbuf = 0
            uart_rx_buff:del()
        end
        sys.wait(200)  
    end
       wsc:close()
    wsc = nil
end)

sys.run()

-- sys.run()之后后面不要加任何语句!!!!!

 