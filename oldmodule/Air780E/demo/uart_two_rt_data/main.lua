-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "uart_irq"
VERSION = "1.0.0"

log.info("main", PROJECT, VERSION)

-- 引入必要的库文件(lua编写), 内部库不需要require
sys = require("sys")

if wdt then
    --添加硬狗防止程序卡死，在支持的设备上启用这个功能
    wdt.init(9000)--初始化watchdog设置为9s
    sys.timerLoopStart(wdt.feed, 3000)--3s喂一次狗
end

log.info("main", "uart demo")

local uart_id = 1

local uartid = 2 -- 根据实际设备选取不同的uartid
local _uart485Pin = 18
gpio.setup(_uart485Pin, 0, nil, nil, 4) 
-- --gpio.setup(18, 0, nil, nil, 4)
--初始化
-- 485自动切换, 选取GPIO10作为收发转换脚

uart.setup(uart_id, 9600, 8, 1, uart.NONE)
uart.setup(uartid, 9600, 8, 1, uart.NONE, uart.LSB, 1024, _uart485Pin, 0, 2000)
-- uart.setup(uartid, 9600, 8, 1, uart.NONE)
  
--循环发数据
sys.timerLoopStart(uart.write,1000, uart_id, "test")
sys.timerLoopStart(uart.write,1000, uartid, "test")
-- 收取数据会触发回调, 这里的"receive" 是固定值



sys.taskInit(function ()
    uart.on(uart_id, "receive", function(id, len)
        -- if uart_id ~= id then
        --     return
        -- end
        local s = ""
        repeat
            -- s = uart.read(id, 1024)
            s = uart.read(id, len)
            if #s > 0 then -- #s 是取字符串的长度
                -- 如果传输二进制/十六进制数据, 部分字符不可见, 不代表没收到
                -- 关于收发hex值,请查阅 https://doc.openluat.com/article/583
                log.info("uart", "receive", id, #s, s)
                -- log.info("uart", "receive", id, #s, s:toHex())
            end
            if #s == len then
                break
            end
            
        until s == ""
    end)
end)

sys.taskInit(function ()
    
    uart.on(uartid, "receive", function(id, len)
        -- if uartid ~= id then
        --     return
        -- end
        local s = ""
        repeat
            -- s = uart.read(id, 1024)
            s = uart.read(id, len)
            if #s > 0 then -- #s 是取字符串的长度
                -- 如果传输二进制/十六进制数据, 部分字符不可见, 不代表没收到
                -- 关于收发hex值,请查阅 https://doc.openluat.com/article/583
                log.info("uart", "receive", id, #s, s)
                -- log.info("uart", "receive", id, #s, s:toHex())
            end
            if #s == len then
                break
            end
            
        until s == ""
    end)
end)


-- 并非所有设备都支持sent事件
uart.on(uart_id, "sent", function(id)
    log.info("uart", "sent", id)
end)
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
