-- Luatools需要PROJECT和VERSION这两个信息
PROJECT = "uart_two"
VERSION = "1.0.0"

log.info("main", PROJECT, VERSION)

if wdt then
    --添加硬狗防止程序卡死，在支持的设备上启用这个功能
    wdt.init(9000)--初始化watchdog设置为9s
    sys.timerLoopStart(wdt.feed, 3000)--3s喂一次狗
end

log.info("main", "uart_two demo run......")

-- 根据实际设备选取不同的uartid
local uartid1 = 1 -- 第一个串口id
local uartid2 = 2 -- 第二个串口id

-- 初始化第一个串口
uart.setup(
    uartid1,--串口id
    115200,--波特率
    8,--数据位
    1--停止位
)

-- 初始化第一个串口
uart.setup(
    uartid2,--串口id
    115200,--波特率
    8,--数据位
    1--停止位
)

-- 第一个串口接收数据回调函数
-- 收取数据会触发回调, 这里的"receive" 是固定值
uart.on(uartid1, "receive", function(id, len)
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

-- 第二个串口接收数据回调函数
-- 收取数据会触发回调, 这里的"receive" 是固定值
uart.on(uartid2, "receive", function(id, len)
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
    -- 循环两秒分别向两个串口发一次数据
    while true do
        sys.wait(2000)
        uart.write(uartid1, "uart1 test data.")
        uart.write(uartid2, "uart2 test data.")
    end
end)

-- 用户代码已结束---------------------------------------------
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!