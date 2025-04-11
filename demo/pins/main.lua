-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "pins"
VERSION = "1.0.0"

log.info("main", PROJECT, VERSION)

-- 引入必要的库文件(lua编写), 内部库不需要require
sys = require("sys")

log.info("main", "pins demo")

local uartid = 2 -- 根据实际设备选取不同的uartid

--把air780epm的PIN55脚,做uart2 rx用
--把air780epm的PIN56脚,做uart2 tx用
pins.setup(55, "UART2_RXD")
pins.setup(56, "UART2_TXD")

--初始化
uart.setup(
    uartid,--串口id
    115200,--波特率
    8,--数据位
    1--停止位
)


--循环发数据
sys.timerLoopStart(uart.write,1000, uartid, "test")
-- 收取数据会触发回调, 这里的"receive" 是固定值
uart.on(uartid, "receive", function(id, len)
    local s = ""
    repeat
        s = uart.read(id, 1024)
        if #s > 0 then -- #s 是取字符串的长度
            -- 如果传输二进制/十六进制数据, 部分字符不可见, 不代表没收到
            log.info("uart", "receive", id, #s, s)
            -- 用HEX值打印收到的内容
            -- log.info("uart", "receive", id, #s, s:toHex())
        end
    until s == ""
end)

-- 发送数据会触发回调, 这里的"sent" 是固定值, id是回调参数, 由底层自动传入
uart.on(uartid, "sent", function(id)
    log.info("uart", "sent", id)
end)


-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!