-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "HZ201P"
VERSION = "0.0.1"
log.info("main", PROJECT, VERSION)
-- 引入必要的库文件(lua编写), 内部库不需要require
_G.sys = require "sys"
pm.ioVol(pm.IOVOL_ALL_GPIO, 1800)

-- gnss的备电和gsensor的供电
local vbackup = gpio.setup(24, 1)
-- gnss的供电
local gpsPower = gpio.setup(26, 1)
-- gnss的复位
local gpsRst = gpio.setup(27, 1)

-- Gsensor
require "da267"
-- 780ep不支持VOLTE，支持CAMERA
-- 780epv固件支持VOLTE，但固件空间放不下CAMERA

-- CAMERA
-- require "camCapture"

-- VOLTE
-- require "ccVolte"

-- LED
sys.taskInit(function()
    local netLed = gpio.setup(1, 0)
    local pwrLed = gpio.setup(16, 0, nil, nil, 4)
    while 1 do
        netLed(1)
        pwrLed(0)
        sys.wait(500)
        netLed(0)
        pwrLed(1)
        sys.wait(500)
    end
end)
-- GNSS
uart.setup(2, 115200)
-- 调试日志,可选
libgnss.debug(true)
libgnss.bind(2)
-- SIM DETECT
local simCheck = gpio.setup(41, function()
    log.info("sim status", gpio.get(41))
end)

sys.subscribe("GNSS_STATE", function(state)
    if state == "FIXED" then
        log.info("定位成功")
    elseif state == "LOSE" then
        log.info("定位丢失")
    end
end)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
