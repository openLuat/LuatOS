
-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "netdrv"
VERSION = "1.0.4"


-- sys库是标配
_G.sys = require("sys")

wdt.init(3000)
sys.timerLoopStart(function()
    wdt.feed()
    log.info("喂狗")
end, 1000)

sys.taskInit(function()
    sys.wait(100)
    -- 初始化airlink
    airlink.init()

    if rtos.bsp() == "Air8101" then
        airlink.start(0)
    else
        airlink.start(1)
    end
    sys.wait(100)

    while 1 do
        -- 发送给对端设备
        local data = rtos.bsp() .. " " .. os.date()
        log.info("发送数据给对端设备", data, "当前airlink状态", airlink.ready())
        airlink.sdata(data)
        sys.wait(1000)
    end
end)

sys.subscribe("AIRLINK_SDATA", function(data)
    log.info("收到AIRLINK_SDATA!!", data)
end)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
