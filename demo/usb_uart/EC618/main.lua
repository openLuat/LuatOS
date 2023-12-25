-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "usb_uart"
VERSION = "1.0.0"

log.info("main", PROJECT, VERSION)

-- 引入必要的库文件(lua编写), 内部库不需要require
sys = require("sys")


--[[
注意: 若使用普通串口调试功能, 需要以下条件之一才能收到数据
1. 把DTR设置为高电平
2. 先发送一次数据

参考用的上位机, 用py演示, 需要pyserial库

import os, sys, serial.tools.list_ports, time

for item in serial.tools.list_ports.comports():
    if not item.pid or not item.location :
        continue
    if item.vid == 0x19d1 and item.pid == 0x0001 and "x.6" in item.location :
        print(dir(item))
        print(item.name)
        with serial.Serial(item.name, 115200, timeout=1) as ser:
            while 1:
                data = ser.read(128)
                if data :
                    print( str(time.time()) + ">> " + str(data))
                else :
                    ser.write("Hi from PC".encode())
]]

log.info("main", "usb uart demo")

local uartid = uart.VUART_0 -- USB虚拟串口的固定id

--初始化
local result = uart.setup(
    uartid,--串口id
    115200,--波特率,其实无所谓, 纯虚拟串口
    8,--数据位
    1--停止位
)


-- 收取数据会触发回调, 这里的"receive" 是固定值
uart.on(uartid, "receive", function(id, len)
    local s = ""
    repeat
        -- s = uart.read(id, 1024)
        s = uart.read(id, len)
        if s and #s > 0 then -- #s 是取字符串的长度
            -- 如果传输二进制/十六进制数据, 部分字符不可见, 不代表没收到
            -- 关于收发hex值,请查阅 https://doc.openluat.com/article/583
            log.info("uart", "receive", id, #s, s)
            uart.write(uart.VUART_0, s)
            -- log.info("uart", "receive", id, #s, s:toHex())
        end
    until s == ""
end)
local tx_buff = zbuff.create(24)
tx_buff:set(0, 0x31)
-- 并非所有设备都支持sent事件
uart.on(uartid, "sent", function(id)
    log.info("uart", "sent", id)
end)

sys.taskInit(function()

    while 1 do
        -- uart.write(uart.VUART_0, "hello test usb-uart\r\n")
        uart.tx(uart.VUART_0, tx_buff,0, tx_buff:len())
        sys.wait(1000)
    end
end)


-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
