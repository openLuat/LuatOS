-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "iomux"
VERSION = "1.0.0"

log.info("main", PROJECT, VERSION)

-- 引入必要的库文件(lua编写), 内部库不需要require
sys = require("sys")

log.info("main", "iomux demo")

local uartid = 2 -- 根据实际设备选取不同的uartid

--把air780epm的PIN55脚,做uart2 rx用, 下面2个等价
pins.setup(55, "UART2_RXD")
pins.setup(55, 2)
--把air780epm的PIN56脚,做uart2 tx用, 下面2个等价
pins.setup(56, "UART2_TXD")
pins.setup(56, 2)
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
        s = uart.read(id, 128)
        if #s > 0 then -- #s 是取字符串的长度
            -- 如果传输二进制/十六进制数据, 部分字符不可见, 不代表没收到
            -- 关于收发hex值,请查阅 https://doc.openluat.com/article/583
            log.info("uart", "receive", id, #s, s)
            -- log.info("uart", "receive", id, #s, s:toHex())
        end
        -- 如使用2024.5.13之前编译的ESP32C3/ESP32S3固件, 恢复下面的代码可以正常工作
        -- if #s == len then
        --     break
        -- end
    until s == ""
end)

-- 并非所有设备都支持sent事件
uart.on(uartid, "sent", function(id)
    log.info("uart", "sent", id)
end)

-- sys.taskInit(function()
--     while 1 do
--         sys.wait(500)
--     end
-- end)


-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!