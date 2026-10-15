-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "prof_basic"
VERSION = "1.0.0"

-- 修改者的名称, 方便日后维护
AUTHOR = {"wendal"}

-- 引入测试套件和测试运行器模块
testrunner = require("testrunner")

-- 载入需要测试的模块
prof_test = require("prof_test")

-- 真机契约: 长用例必须有WDT喂狗任务
if wdt and wdt.init then
    wdt.init(9000)
    sys.taskInit(function()
        while true do
            sys.wait(1000)
            if wdt.feed then wdt.feed() end
        end
    end)
end

-- 开启一个task,运行测试
sys.taskInit(function()
    testrunner.runBatch("prof", {
        {testTable = prof_test, testcase = "cycle profiler基础"}
    })
end)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
