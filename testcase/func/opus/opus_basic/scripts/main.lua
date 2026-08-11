-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "opus_test"
VERSION = "1.0.0"

AUTHOR = {"luatos"}

-- 引入测试套件和测试运行器模块
testrunner = require("testrunner")

-- 载入需要测试的模块
opus_test = require("opus_test")

-- 开启一个task,运行测试
sys.taskInit(function()
    testrunner.runBatch("opus", {
        {testTable = opus_test, testcase = "opus编解码测试"}
    })
end)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
