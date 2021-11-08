
-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "nimbledemo"
VERSION = "1.0.0"

log.info("main", PROJECT, VERSION)

-- 一定要添加sys.lua !!!!
local sys = require "sys"

--添加硬狗防止程序卡死
if wdt then
    wdt.init(15000)--初始化watchdog设置为15s
    sys.timerLoopStart(wdt.feed, 10000)--10s喂一次狗
end

local spi_lcd = spi.deviceSetup(0,20,0,0,8,20*1000*1000,spi.MSB,1,1)
lcd.setColor(0x0000,0xFFFF)
log.info("lcd.init",
lcd.init("st7735s",{port = "device",pin_dc = 17, pin_pwr = 7,pin_rst = 19,direction = 2,w = 160,h = 80,xoffset = 1,yoffset = 26},spi_lcd))
lcd.clear()
lcd.setFont(lcd.font_opposansm12_chinese)
lcd.drawStr(30,15,"nimbledemo",0X07FF)
lcd.drawStr(50,35,"监听中",0x001F)

-- 监听BLE主适配的状态变化
sys.subscribe("BLE_STATE_INC", function(state)
    log.info("ble", "ble state changed", state)
    if state == 1 then
        nimble.server_init()
    else
        nimble.server_deinit()
    end
end)

-- 监听GATT服务器的WRITE_CHR
sys.subscribe("BLE_GATT_WRITE_CHR", function(info, data)
    -- info 是个table, 但当前没有数据
    log.info("ble", "data got!!", data:toHex())
    lcd.fill(0,40,160,80)
    lcd.drawStr(10,60,"接收数据:"..data:toHex(),0x07E0)
end)

-- TODO 支持传数据(read)和推送数据(notify)

-- 配合微信小程序 "BLE蓝牙开发助手"
-- 1. 若开发板无天线, 将手机尽量靠近芯片也能搜到
-- 2. 该小程序是开源的, 每次write会自动分包为16字节

sys.taskInit(function()
    sys.wait(2000)
    nimble.debug(6)
    nimble.init()
end)


-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
