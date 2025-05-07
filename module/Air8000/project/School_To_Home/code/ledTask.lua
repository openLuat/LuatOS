-- 蓝灯
local netLed = gpio.setup(1, 0)
sys.taskInit(function()
    while true do
        while not srvs.isConnected() do
            manage.wake("led")
            netLed(1)
            sys.wait(500)
            netLed(0)
            manage.sleep("led")
            sys.wait(500)
        end
        netLed(0)
        while srvs.isConnected() do
            sys.wait(10000)
        end
    end
end)

-- 黄灯  在gnss.lua里面，由当前Air201上CC0257B的1PPS引脚控制，可以给GNSS芯片发指令改变1pps输出周期

-- local gnssLed = gpio.setup(xxx, 0)
-- sys.taskInit(function()
--     while true do
--         if gnss.isFix() then
--             gnssLed(1)
--             sys.wait(1000)
--         else
--             gnssLed(0)
--             sys.wait(500)
--             gnssLed(0)
--             sys.wait(500)
--         end
--     end
-- end)


-- 红灯   红灯直接在manage.lua里控制了

-- local chargeLed = gpio.setup(xxx, 0)
-- sys.taskInit(function()
--     while true do
--         chargeLed(xxx.isCharge() and 1 or 0)
--         (1000)
--     end
-- end)