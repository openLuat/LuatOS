-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "HZ201P"
VERSION = "0.0.1"
log.info("main", PROJECT, VERSION)
-- 引入必要的库文件(lua编写), 内部库不需要require
_G.sys = require "sys"
_G.sysplus = require("sysplus")

--运营商给的dns经常抽风，手动指定
socket.setDNS(nil, 1, "223.5.5.5")
socket.setDNS(nil, 2, "119.29.29.29")


pm.ioVol(pm.IOVOL_ALL_GPIO, 1800)
-- gnss的备电和gsensor的供电
local vbackup = gpio.setup(24, 1)
-- gnss的供电
local gpsPower = gpio.setup(26, 1)

--云平台逻辑
require "cloud"

--获取所有参数
_G.attributes = require "attributes"
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
local chargeState = gpio.setup(20, nil, 0)
sys.taskInit(function()
    while true do
        if attributes.get("ledControl") then
            blueLed(attributes.get("blueLed") and 1 or 0)
            redLed(attributes.get("redLed") and 1 or 0)
            sys.wait(500)
        else
            redLed(chargeState() == 0 and 1 or 0)
            blueLed(1)
            sys.wait(_G_CONNECTED and 100 or 1000)
            blueLed(0)
            sys.wait(_G_CONNECTED and 100 or 1000)
        end
    end
end)

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
