-- Luatools需要PROJECT和VERSION这两个信息
PROJECT = "uart_mux"
VERSION = "1.0.0"

log.info("main", PROJECT, VERSION)

-- 引入必要的库文件(lua编写), 内部库不需要require
sys = require("sys")

if wdt then
    --添加硬狗防止程序卡死，在支持的设备上启用这个功能
    wdt.init(9000)--初始化watchdog设置为9s
    sys.timerLoopStart(wdt.feed, 3000)--3s喂一次狗
end

local uartid = 2 -- 根据实际设备选取不同的uartid

-- mcu.iomux(mcu.UART, 2, 1)       -- Air780E的UART2复用到gpio12(58脚_RX)和gpio13(57脚_TX)
mcu.iomux(mcu.UART, 2, 2)       -- Air780E的UART2复用到gpio6(55脚_RX)和gpio7(56脚_TX)

--初始化
uart.setup(
    uartid,--串口id
    115200,--波特率
    8,--数据位
    1--停止位
)

--循环发数据
sys.timerLoopStart(uart.write,3000, uartid, "test")

-- 收取数据会触发回调, 这里的"receive" 是固定值
uart.on(uartid, "receive", function(id, len)
    local data = ""
    while 1 do
        local tmp = uart.read(uartid)
        if not tmp or #tmp == 0 then
            break
        end
        data = data .. tmp
    end
    log.info("uart", "uart收到数据长度", #data)
end)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!