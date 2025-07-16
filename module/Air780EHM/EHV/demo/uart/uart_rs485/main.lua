-- Luatools需要PROJECT和VERSION这两个信息
PROJECT = "uart_RS485"
VERSION = "1.0.0"

log.info("main", PROJECT, VERSION)

-- 引入必要的库文件(lua编写), 内部库不需要require
sys = require("sys")

if wdt then
    --添加硬狗防止程序卡死，在支持的设备上启用这个功能
    wdt.init(9000)--初始化watchdog设置为9s
    sys.timerLoopStart(wdt.feed, 3000)--3s喂一次狗
end

log.info("main", "uart demo run......")

local uartid = 1        -- 根据实际设备选取不同的uartid
local uart485Pin = 25   -- 用于控制485接收和发送的使能引脚

gpio.setup(1, 1)        --打开电源(开发板485供电脚是gpio1，用开发板测试需要开机初始化拉高gpio1)

--初始化
uart.setup(uartid, 9600, 8, 1, uart.NONE, uart.LSB, 1024, uart485Pin, 0, 2000)

-- 收取数据会触发回调, 这里的"receive" 是固定值
uart.on(uartid, "receive", function(id, len)
    local s = ""
    repeat
        s = uart.read(id, 128)
        if #s > 0 then -- #s 是取字符串的长度
            -- 关于收发hex值,请查阅 https://doc.openluat.com/article/583
            log.info("uart", "receive", id, #s, s)
            -- log.info("uart", "receive", id, #s, s:toHex()) --如果传输二进制/十六进制数据, 部分字符不可见, 不代表没收到
        end
    until s == ""
end)

sys.taskInit(function()
    -- 循环两秒向串口发一次数据
    while true do
        sys.wait(2000)
        uart.write(uartid, "test data.")
    end
end)

-- 用户代码已结束---------------------------------------------
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!