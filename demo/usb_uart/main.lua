-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "usb_uart"
VERSION = "1.0.0"

log.info("main", PROJECT, VERSION)

-- 引入必要的库文件(lua编写), 内部库不需要require
sys = require("sys")

if wdt then
    --添加硬狗防止程序卡死，在支持的设备上启用这个功能
    wdt.init(9000)--初始化watchdog设置为9s
    sys.timerLoopStart(wdt.feed, 3000)--3s喂一次狗
end

log.info("main", "usb uart demo")

-- Air105 的虚拟串口需要安装驱动, Air780E/Air600E不需要
-- USB驱动下载 https://doc.openluat.com/wiki/21?wiki_page_id=2070
-- USB驱动与 合宙Cat.1的USB驱动是一致的

-- 当前仅Air105/Air780E/Air600E能运行本demo

if usbapp then -- Air105需要初始化usb虚拟串口
    usbapp.start(0)
end


local uartid = uart.VUART_0 -- USB虚拟串口的固定id

--初始化
local result = uart.setup(
    uartid,--串口id
    115200,--波特率
    8,--数据位
    1--停止位
)


-- 收取数据会触发回调, 这里的"receive" 是固定值
uart.on(uartid, "receive", function(id, len)
    local s = ""
    repeat
        -- 如果是air302, len不可信, 传1024
        -- s = uart.read(id, 1024)
        s = uart.read(id, len)
        if s and #s > 0 then -- #s 是取字符串的长度
            -- 如果传输二进制/十六进制数据, 部分字符不可见, 不代表没收到
            -- 关于收发hex值,请查阅 https://doc.openluat.com/article/583
            log.info("uart", "receive", id, #s, s)
            -- log.info("uart", "receive", id, #s, s:toHex())
        end
    until s == ""
end)

-- 并非所有设备都支持sent事件
uart.on(uartid, "sent", function(id)
    log.info("uart", "sent", id)
end)

sys.taskInit(function()
    local timer
    while 1 do
        local result, uart_id,data = sys.waitUntil("USB_UART_INC", 30000)
        if result and uart_id == uart.VUART_0 and data == 1 then
            --循环发数据
            timer = sys.timerLoopStart(uart.write,1000, uartid, "test")
            while 1 do
                local result, uart_id,data = sys.waitUntil("USB_UART_INC", 30000)
                if result and uart_id == uart.VUART_0 and data == 2 then
                    sys.timerStop(timer)
                    break
                end
            end
        end
    end
end)


-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
