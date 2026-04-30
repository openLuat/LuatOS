--[[
@module  simple_uart
@summary 简易串口功能模块
@version 1.0
@date    2025.09.23
@author  魏健强
@usage
本demo演示的核心功能为：
1.开启串口，配置波特率等参数；
2.设置接收回调函数
3.定时向串口发送数据
]]
local uartid = 1 -- 根据实际设备选取不同的uartid

local function uart_send()
    -- 循环两秒向串口发一次数据
    while true do
        sys.wait(2000)
        uart.write(uartid, "test data.")
    end
end

local function uart_send_cb(id)
    log.info("uart", id , "数据发送完成回调")
end

local function uart_cb(id, len)
  local s = ""
    repeat
        s = uart.read(id, 128) -- 读取缓冲区中的数据，这里设置的一次读最多128字节
        if #s > 0 then -- #s 是取字符串的长度
            -- 关于收发hex值,请查阅 https://doc.openluat.com/article/583
            log.info("uart", "receive", id, #s, s)
            -- log.info("uart", "receive", id, #s, s:toHex()) --如果传输二进制/十六进制数据, 部分字符不可见, 不代表没收到
        end
    until s == ""
end
--初始化
uart.setup(
    uartid,--串口id
    115200,--波特率
    8,--数据位
    1--停止位
)

-- 收取数据会触发回调, 这里的"receive" 是固定值
uart.on(uartid, "receive", uart_cb)

-- 发送数据完成会触发回调, 这里的"sent" 是固定值
uart.on(uartid, "sent", uart_send_cb)

sys.taskInit(uart_send)