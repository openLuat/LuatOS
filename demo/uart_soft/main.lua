-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "soft uart"
VERSION = "1.0.0"

log.info("main", PROJECT, VERSION)

-- 引入必要的库文件(lua编写), 内部库不需要require
sys = require("sys")

if wdt then
    --添加硬狗防止程序卡死，在支持的设备上启用这个功能
    wdt.init(9000)--初始化watchdog设置为9s
    sys.timerLoopStart(wdt.feed, 3000)--3s喂一次狗
end

log.info("main", "soft uart demo")

local function resouce()     
    local rtos_bsp = rtos.bsp()
    if rtos_bsp == "AIR101" then
        return nil,nil,nil,nil,nil,nil,nil
    elseif rtos_bsp == "AIR103" then
        return nil,nil,nil,nil,nil,nil,nil
    elseif rtos_bsp == "AIR105" then
        return pin.PA07,0,pin.PA06,1,115200,-20,-10
    elseif rtos_bsp == "ESP32C3" then
        return nil,nil,nil,nil,nil,nil,nil
    elseif rtos_bsp == "ESP32S3" then
        return nil,nil,nil,nil,nil,nil,nil
    elseif rtos_bsp == "EC618" then
        return 17,0,1,2,19200,0,-10
    else
        log.info("main", "bsp not support")
        return
    end
end

local tx_pin,tx_timer,rx_pin,rx_timer,br,tx_adjust,rx_adjust = resouce() 

local uartid = uart.createSoft(tx_pin,tx_timer,rx_pin,rx_timer,tx_adjust,rx_adjust)
--初始化
local result = uart.setup(
    uartid,--串口id
    br,--软件串口波特率根据平台的软硬件配置有不同的极限
    8,--数据位
    1,--停止位
    uart.ODD
)


--循环发数据
-- sys.timerLoopStart(uart.write,1000, uartid, "test")
-- 收取数据会触发回调, 这里的"receive" 是固定值
uart.on(uartid, "receive", function(id, len)
    local s = ""
    repeat
        -- 如果是air302, len不可信, 传1024
        -- s = uart.read(id, 1024)
        s = uart.read(id, len)
        if #s > 0 then -- #s 是取字符串的长度
            -- 如果传输二进制/十六进制数据, 部分字符不可见, 不代表没收到
            -- 关于收发hex值,请查阅 https://doc.openluat.com/article/583
            log.info("uart", "receive", id, #s, s:toHex())
            uart.write(id, s)
        end
    until s == ""
end)

-- 并非所有设备都支持sent事件
uart.on(uartid, "sent", function(id)
    log.info("uart", "sent", id)
end)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
