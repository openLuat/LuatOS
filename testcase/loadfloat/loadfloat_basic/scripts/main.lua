PROJECT = "loadfloat_basic"
VERSION = "1.0.0"

AUTHOR = {"auto"}

local testrunner = require("testrunner")
local loadfloat_tests = require("loadfloat_test")

sys.taskInit(function()
    testrunner.runBatch("loadfloat_suite", {
        { testTable = loadfloat_tests, testcase = "load()超长浮点数测试" }
    })
end)

sys.run()
