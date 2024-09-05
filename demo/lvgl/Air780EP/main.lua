--- 模块功能：lcddemo
-- @module lcd
-- @author Dozingfiretruck
-- @release 2021.01.25
-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "lcddemo"
VERSION = "1.0.0"

log.info("main", PROJECT, VERSION)

-- sys库是标配
_G.sys = require("sys")

-- 添加硬狗防止程序卡死
if wdt then
    wdt.init(9000) -- 初始化watchdog设置为9s
    sys.timerLoopStart(wdt.feed, 3000) -- 3s喂一次狗
end

local rtos_bsp = rtos.bsp()

-- 根据不同的BSP返回不同的值
-- spi_id,pin_reset,pin_dc,pin_cs,bl
function lcd_pin()
    if string.find(rtos_bsp,"EC718") then
        return lcd.HWID_0, 36, 0xff, 0xff, 25 -- 注意:EC718P有硬件lcd驱动接口, 无需使用spi,当然spi驱动也支持
    else
        log.info("main", "bsp not support")
        return
    end
end

local spi_id, pin_reset, pin_dc, pin_cs, bl = lcd_pin()

if spi_id ~= lcd.HWID_0 then
    spi_lcd = spi.deviceSetup(spi_id, pin_cs, 0, 0, 8, 20 * 1000 * 1000, spi.MSB, 1, 0)
    port = "device"
else
    port = spi_id
end

--[[ 此为合宙售卖的ec718系列专用硬件双data驱动TFT LCD LCD 分辨率:320x480 屏幕ic:nv3037 购买地址:https://item.taobao.com/item.htm?id=764253232987&skuId=5258482696347&spm=a1z10.1-c-s.w4004-24087038454.8.64961170w5EdoA]]
lcd.init("nv3037", {
    port = port,
    pin_dc = pin_dc,
    pin_pwr = bl,
    pin_rst = pin_reset,
    direction = 0,
    w = 320,
    h = 480,
    xoffset = 0,
    yoffset = 0,
    interface_mode = lcd.DATA_2_LANE
}, spi_lcd)




log.info("lvgl", lvgl.init())

local scr = lvgl.obj_create(nil, nil)
local btn = lvgl.btn_create(scr)
lvgl.obj_align(btn, lvgl.scr_act(), lvgl.ALIGN_CENTER, 0, 0)

local label = lvgl.label_create(btn)
local flag = true

lvgl.label_set_text(label, "LuatOS!")
lvgl.scr_load(scr)
lvgl.indev_drv_register("pointer", "emulator")

local function btn_cb(obj, event)
    if event == lvgl.EVENT_SHORT_CLICKED then
        log.info("short click")
        if flag then
            lvgl.label_set_text(label, "LuatOS!")
            flag = false
        else
            lvgl.label_set_text(label, "hello world!")
            flag = true
        end
    end
end
lvgl.obj_set_event_cb(btn, btn_cb)

local x, y = 0, 0
local i2cid = 1
local ft6336SlaveAddr, ft6336GetFingerNum, ft6336GetLoc0 = 0x38, 0x02, 0x03
local tpRstPin = 24
local tpIntPin = 22
local function ft6336Read(addr, len)
    i2c.send(i2cid, ft6336SlaveAddr, string.char(addr))
    return i2c.recv(1, ft6336SlaveAddr, len)
end

local function ft6336Scan()
    local data = ft6336Read(ft6336GetFingerNum, 1)
    if not data or data:byte() == 0 then
        return 0
    end
    local data = ft6336Read(ft6336GetLoc0, 4)
    if not data or data:len() ~= 4 then
        return 0
    end
    x = ((data:byte(1) & 0x0F) << 8) + data:byte(2)
    y = ((data:byte(3) & 0x0F) << 8) + data:byte(4)
    return 1
end

sys.taskInit(function()
    local rstPin = gpio.setup(tpRstPin, 1)
    local intPin = gpio.setup(tpIntPin, function(val)
        sys.publish("INT_TRIGGER")
    end, gpio.PULLUP, gpio.FALLING)
    rstPin(0)
    sys.wait(10)
    rstPin(1)
    mcu.altfun(mcu.I2C, i2cid, 23, 2, 0)
    mcu.altfun(mcu.I2C, i2cid, 24, 2, 0)
    i2c.setup(i2cid, 1);
    while true do
        sys.waitUntil("INT_TRIGGER")
        if ft6336Scan() > 0 then
            lvgl.indev_point_emulator_update(x, y, 1)
        else
            lvgl.indev_point_emulator_update(x, y, 0)
        end
    end
end)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
