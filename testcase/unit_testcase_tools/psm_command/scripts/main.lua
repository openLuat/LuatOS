PROJECT = "psm_command_test"
VERSION = "1.0.0"

-- 修改者的名称, 方便日后维护
AUTHOR = {"auto"}

-- 引入测试套件和测试运行器模块
local testrunner = require("testrunner")
local psm_command_tests = require("psm_command_test")

sys.taskInit(function()
    -- 第一个参数: 整个批次的名称
    -- 第二个参数: 数组, 每个元素包含 testTable(测试函数表) 和 testcase(用例名称)
    testrunner.runBatch("psm_command_suite", {
        { testTable = psm_command_tests, testcase = "PSM+唤醒配置模块测试" }
    })
end)

sys.run()
