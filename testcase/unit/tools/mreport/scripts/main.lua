PROJECT = "mreporttest"
VERSION = "1.0.0"

AUTHOR = {"copilot"}

testrunner = require("testrunner")

local mreport_tests = require("mreport_test")

sys.taskInit(function()
    testrunner.runBatch("mreport_suite", {
        { testTable = mreport_tests, testcase = "netdrv.mreport测试" }
    })
end)

sys.run()
