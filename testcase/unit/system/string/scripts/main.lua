PROJECT = "stringtest"
VERSION = "1.0.0"

-- 修改者的名称, 方便日后维护
AUTHOR = {"auto"}

-- 引入测试套件和测试运行器模块
local testrunner = require("testrunner")
local string_tests = require("string_test")

sys.taskInit(function()
    -- 第一个参数: 整个批次的名称
    -- 第二个参数: 数组, 每个元素包含 testTable(测试函数表) 和 testcase(用例名称)
    testrunner.runBatch("string_suite", {
        { testTable = string_tests, testcase = "String库测试" }
    })
end)

sys.run()
