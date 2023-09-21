
-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "bletest"
VERSION = "1.0.0"

--[[
这是使用BLE功能模拟KT6368A的demo, 从机模式, UART1透传

支持的模块:
1. Air601
2. ESP32系列, 包括ESP32C3/ESP32S3
3. Air101/Air103 开发板天线未引出, 天线未校准, 能用但功耗高
]]

log.info("main", PROJECT, VERSION)

-- 一定要添加sys.lua !!!!
sys = require("sys")

--添加硬狗防止程序卡死
if wdt then
    wdt.init(9000)--初始化watchdog设置为9s
    sys.timerLoopStart(wdt.feed, 3000)--3s喂一次狗
end

function pinx() -- 根据不同开发板，给LED赋值不同的gpio引脚编号
    local rtos_bsp = rtos.bsp()
    if rtos_bsp == "AIR101" then -- Air101开发板LED引脚编号
        mcu.setClk(240)
        return pin.PB08, 1
    elseif rtos_bsp == "AIR103" then -- Air103开发板LED引脚编号
        mcu.setClk(240)
        return pin.PB26, 1
    elseif rtos_bsp == "AIR601" then -- Air601开发板LED引脚编号
        return pin.PB26, 1
    elseif rtos_bsp == "ESP32C3" then -- ESP32C3开发板的引脚
        return 12, 0
    elseif rtos_bsp == "ESP32S3" then -- ESP32C3开发板的引脚
        return 10, 0
    else
        log.info("main", "define led pin in main.lua")
        return 0, 1
    end
end
local ledpin, uart_id = pinx()
LED = gpio.setup(ledpin, 0, gpio.PULLUP)
uart.setup(uart_id, 9600)
uart.on(uart_id, "receive", function(id, len)
    gpio.toggle(ledpin)
    local s = ""
    repeat
        s = uart.read(uart_id, 128)
        if #s > 0 then -- #s 是取字符串的长度
            -- 如果传输二进制/十六进制数据, 部分字符不可见, 不代表没收到
            -- 关于收发hex值,请查阅 https://doc.openluat.com/article/583
            log.info("uart", "receive", id, #s, s)
            -- TODO 判断是否为AT指令, 如果是的话还需要解析
            if nimble.connok() then
                -- nimble.send_msg(1, 0, s)
                -- nimble.sendNotify(nil, string.fromHex("FF01"), string.char(0x31, 0x32, 0x33, 0x34, 0x35))
                nimble.sendNotify(nil, string.fromHex("FF01"), s)
            end
        end
    until s == ""
    gpio.toggle(ledpin)
end)

-- 监听GATT服务器的WRITE_CHR, 也就是收取数据的回调
sys.subscribe("BLE_GATT_WRITE_CHR", function(info, data)
    -- info 是个table, 但当前没有数据
    log.info("ble", "data got!!", data:toHex())
    uart.write(uart_id, data)
end)

sys.subscribe("BLE_SERVER_STATE_UPD", function(state)
    log.info("ble", "连接状态", nimble.connok() and "已连接" or "已断开")
    LED(nimble.connok() and 1 or 0)
end)

sys.taskInit(function()
    sys.wait(500)

    nimble.config(nimble.CFG_ADDR_ORDER, 1)

    nimble.setUUID("srv", string.fromHex("FF00"))      -- 服务主UUID
    nimble.setChr(0, string.fromHex("FF01"), nimble.CHR_F_WRITE_NO_RSP | nimble.CHR_F_NOTIFY)
    nimble.setChr(1, string.fromHex("FF02"), nimble.CHR_F_READ | nimble.CHR_F_NOTIFY)
    nimble.setChr(2, string.fromHex("FF03"), nimble.CHR_F_WRITE_NO_RSP)

    nimble.init("KT6368A-BLE-1.9", 1)
end)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
