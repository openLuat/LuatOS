-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "HZ201P"
VERSION = "1.0.4"
log.info("main", PROJECT, VERSION)
-- 引入必要的库文件(lua编写), 内部库不需要require
sys = require "sys"
sysplus = require("sysplus")

--mcu.hardfault(0)

--运营商给的dns经常抽风，手动指定
socket.setDNS(nil, 1, "223.5.5.5")
socket.setDNS(nil, 2, "119.29.29.29")

pm.ioVol(pm.IOVOL_ALL_GPIO, 1800)
-- gnss的备电和gsensor的供电
local vbackup = gpio.setup(24, 1)
-- gnss的供电
local gpsPower = gpio.setup(26, 1)

-- 使用合宙iot平台时需要这个参数
PRODUCT_KEY = "YXdzIDo5QawWCIRywShMAKjmJsInXtsb" -- 到 iot.openluat.com 创建项目,获取正确的项目id
libfota = require "libfota"
function fota_cb(ret)
    log.info("fota", ret)
    if ret == 0 then
        rtos.reboot()
    end
end
-- 使用合宙iot平台进行升级
sys.subscribe("IP_READY",function()
    libfota.request(fota_cb)
    sys.timerLoopStart(libfota.request, 3600000, fota_cb)
end)

--云平台逻辑
require "cloud"

--获取所有参数
attributes = require "attributes"
attributes.initial()--初始化

--gnss
require "gnss"

-- Gsensor
require "da267"
sys.subscribe("STEP_COUNTER", function(step)
    log.info("STEP_COUNTER", step)
    if step > 0 then
        attributes.set("step", step)
    end
end)

-- LED
--全局状态变量
_G_CONNECTED = false
local blueLed = gpio.setup(1, 0)
local redLed = gpio.setup(16, 0, nil, nil, 4)
sys.taskInit(function()
    while true do
        if attributes.get("ledControl") then
            blueLed(attributes.get("blueLed") and 1 or 0)
            redLed(attributes.get("redLed") and 1 or 0)
            sys.wait(500)
        else
            redLed(attributes.get("isCharging") and 1 or 0)
            blueLed(1)
            sys.wait(_G_CONNECTED and 100 or 1000)
            blueLed(0)
            sys.wait(_G_CONNECTED and 100 or 1000)
        end
    end
end)

--关机键
local powerTimer
local powerKey = gpio.setup(46, function()
    log.info("powerKey", gpio.get(46))
    if gpio.get(46) == 0 then
        sys.publish("POWERKEY_PRESSED")
        powerTimer = sys.timerStart(function()
            log.info("powerKey", "long press")
            --把灯关都掉，让用户以为已经关机了
            blueLed(0) redLed(0)
            blueLed = function() end
            redLed = blueLed
            --两秒后真正关机
            sys.timerStart(pm.shutdown, 2000)
        end, 3000)
    else
        if powerTimer then
            sys.timerStop(powerTimer)
            log.info("powerKey", "stop press")
        end
    end
end,gpio.PULLUP)

--电量检测与上报
require "battery"

--信号值检测与上报
sys.taskInit(function ()
    while true do
        attributes.set("rsrp", mobile.rsrp())
        attributes.set("rsrq", mobile.rsrq())
        sys.wait(60000)
    end
end)


--拨打电话与音频
require "ccVolte"

-- SIM DETECT
local simCheck = gpio.setup(41, function()
    log.info("sim status", gpio.get(41))
end)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
