-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "HZ201P"
VERSION = "0.0.1"

log.info("main", PROJECT, VERSION)

-- 引入必要的库文件(lua编写), 内部库不需要require
_G.sys = require "sys"

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
        pwrLed(1)
        sys.wait(5000)
        netLed(0)
        pwrLed(0)
        sys.wait(5000)
    end
end)

-- 默认是IDLE模式，可替换为pm.LIGHT
pm.request(pm.IDLE)

sys.taskInit(function()
    while 1 do
        log.info("lua", rtos.meminfo())
        log.info("lua", rtos.meminfo("sys"))
        collectgarbage("collect")
        collectgarbage("collect")
        sys.wait(1000)
    end
end)


-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
