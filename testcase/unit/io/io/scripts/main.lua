PROJECT = "iotest"
VERSION = "1.0.0"

-- 引入必要的模块
sys = require("sys")

-- 引入测试套件和测试运行器模块
testrunner = require("testrunner")

-- 载入需要测试的模块
io_test = require("io_test")

-- 开启一个task,运行测试
sys.taskInit(function()
    testrunner.runBatch("io", {
        {testTable = io_test, testcase = "io测试"}
    })
end)

sys.run()