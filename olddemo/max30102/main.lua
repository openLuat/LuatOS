-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "max30102demo"
VERSION = "1.0.0"

-- log.info("main", PROJECT, VERSION)

-- 引入必要的库文件(lua编写), 内部库不需要require
local sys = require "sys"

-- sys.timerLoopStart(function ()
--     log.info("mem.lua", rtos.meminfo())
--     log.info("mem.sys", rtos.meminfo("sys"))
-- end, 3000)


_G.sysplus = require("sysplus")

function pinx()
    local bsp = rtos.bsp()
    if bsp:startsWith("ESP32") then
        return 0, 2
    elseif bsp == "AIR105" then
        return 0, pin.PC05
    elseif bsp == "AIR101" or bsp == "AIR103" or bsp == "AIR601" then
        return 0, 10
    else
        return 0, 1
    end
end

local i2cid, irq_pin = pinx()
local i2c_speed = i2c.FAST
sys.taskInit(function()
    log.info("初始化i2c")
    i2c.setup(i2cid, i2c_speed)
    log.info("初始化max30102")
    max30102.init(i2cid, irq_pin)
    -- max30102.get().wait()
    -- max30102.shutdown()
    while 1 do
        log.info("尝试读取")
        local ret,HR,SpO2 = max30102.get().wait()
        if ret then
            log.info("max30102", HR,SpO2)
        else
            log.info("max30102", "false")
        end
        sys.wait(5000)
    end
end)




-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
