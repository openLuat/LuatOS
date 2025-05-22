-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "rs485_uart"
VERSION = "1.0.0"

-- 打印版本信息
log.info("main", PROJECT, VERSION)

-- 引入必要的库文件(lua编写), 内部库不需要require
sys = require("sys")

if wdt then
    --添加硬狗防止程序卡死，在支持的设备上启用这个功能
    wdt.init(9000)--初始化watchdog设置为9s
    sys.timerLoopStart(wdt.feed, 3000)--3s喂一次狗
end

-- 打印提示信息
log.info("main", "rs485 uart demo")

-- 定义串口ID和485引脚
local uartid = 1        -- 根据实际设备选取不同的uartid
local uart485Pin = 17   -- 用于控制485收发转换的方向转换脚

-- 打开485供电使能脚
gpio.setup(16, 1)       -- 打开电源(开发板485供电脚是gpio16，用开发板测试需要开机初始化拉高gpio16)

-- 初始化串口参数
uart.setup(
    uartid, -- 串口ID
    9600, -- 波特率
    8, -- 数据位
    1, -- 停止位
    uart.NONE, -- 校验位
    uart.LSB, -- 大小端
    1024, -- 缓冲区大小
    uart485Pin, -- 485模式下收发转换脚gpio
    0, -- 485模式下rx方向gpio的电平
    20000 -- 485模式下tx向rx转换的延迟时间
)

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
        -- 写入可见字符串
        uart.write(uartid, "test data.")
        -- 写入十六进制字符串
        -- uart.write(1, string.char(0x55,0xAA,0x4B,0x03,0x86))
    end
end)

-- 用户代码已结束---------------------------------------------
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!