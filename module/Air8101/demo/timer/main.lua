-- main.lua文件
-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "timer_demo"
VERSION = "1.0.0"


-- sys库是标配
sys = require("sys")

sys.taskInit(function()
log.info("------start timer_demo------")
-- 定义一个单次触发的定时器回调函数
local function oneShotCallback(message)
log.info("One-shot timer triggered: " .. message)
end

-- 定义一个周期性触发的定时器回调函数
local function periodicCallback(count)
log.info("Periodic timer triggered (Count: " .. count .. ")")
end

-- 定义一个周期性触发的定时器回调函数
local function periodicCallback1(count)
log.info("Periodic timer triggered1 (Count: " .. count .. ")")
end

-- 初始化计数器，用于周期性定时器
local periodicCount = 0

-- 启动一个单次触发的定时器，延迟3秒后触发
local oneShotTimerId = sys.timerStart(oneShotCallback, 3000, 0, "Hello from one-shot timer!")

-- 启动一个一次性定时器，分别再第7秒触发一次
sys.timerStart(periodicCallback,7000,"first")
-- 启动一个一次性定时器，分别再第6秒触发一次
sys.timerStart(periodicCallback,6000,"second")
-- 启动一个一次性定时器，分别再第5秒触发一次
sys.timerStart(periodicCallback,5000,"third")

-- 启动一个周期性触发的定时器，每2秒触发一次
local periodicTimerId2 = sys.timerLoopStart(function()    periodicCount = periodicCount + 1    periodicCallback1(periodicCount)
end, 2000)

--等待5000ms
sys.wait(5000)

-- 停止周期性定时器
sys.timerStart(function()
sys.timerStop(periodicTimerId2)
log.info("stop 2s loop timer periodicCallback1")
end,5000)

-- 停止所有定时器（仅作为测试，实际应用中应根据需要停止）
sys.timerStart(function()
sys.timerStopAll(periodicCallback)
log.info("stop periodicCallback loop timer ")
end,4000)

end)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!

