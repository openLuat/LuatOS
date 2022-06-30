-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "uart_irq"
VERSION = "1.0.0"

log.info("main", PROJECT, VERSION)

-- 引入必要的库文件(lua编写), 内部库不需要require
local sys = require "sys"

mcu.setClk(240)
log.info("main", "uart demo")

sys.subscribe("BLE_STATE_INC", function(state)
    log.info("ble", "ble state changed", state)
    if state == 1 then
        nimble.server_init()
    else
        nimble.server_deinit()
    end
end)

local buff = zbuff.create({8,8,24},0x000000)

-- 监听GATT服务器的WRITE_CHR事件
sys.subscribe("BLE_GATT_WRITE_CHR", function(info, data)
    if data:len() == 0 then
        return
    end
    local cmd = data:split(",")
    if cmd[1]=="ws2812" then
        local rgb = tonumber(cmd[2],16)
        local grb = (rgb&0xff0000)>>8|(rgb&0xff00)<<8|(rgb&0xff)
        buff:setFrameBuffer(8,8,24,grb)
        sensor.ws2812b(pin.PB05,buff,0,300,300,300)
    end
end)

sys.taskInit(function()
    sys.wait(2000) -- 为了能看到日志,休眠2秒
    nimble.debug(6) -- 开启日志
    nimble.init() -- 初始化nimble, 会产生事件BLE_STATE_INC
end)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
